#!/usr/bin/env python3
"""Track 1: Automated Ingestion & Metadata Enrichment from Mock Metadata.xlsx.

Loads ACSM Mock Datasets (T1–T8 CSVs) into BigQuery `acsm_bronze`, then parses
all 8 worksheets of `Mock Metadata.xlsx` (~220 columns) to automatically populate
table descriptions and column-level descriptions in BigQuery / Dataplex Catalog.

Fulfils ACSM RFP Clauses:
- C1.1.1.2 (Diverse ingestion)
- C1.1.1.8 (Enterprise Unified Governance)
- C1.1.1.10 (Metadata Management & Business Glossary enrichment)
- C1.1.2.7 (Data Trust — business definitions visible on every table/column)
- C1.1.6.8 (Automated Metadata Migration)
"""

import argparse
import io
import os
import pathlib
import xml.etree.ElementTree as ET
import zipfile
from typing import Dict, List, Tuple
from google.cloud import bigquery

TABLE_FILE_MAP: Dict[str, Tuple[str, str]] = {
    "t1_fact_ep_judge": (
        "T1_Fact_EP_Judge.csv",
        "T1 - Fact_EP_Judge",
    ),
    "t2_fact_ep_sales": (
        "T2_Fact_EP_Sales.csv",
        "T2 - Fact_EP_Sales",
    ),
    "t3_fact_ep_collection": (
        "T3_Fact_EP_Collection.csv",
        "T3 - Fact_EP_Collection",
    ),
    "t4_fact_cc_judge": (
        "T4_Fact_CC_Judge.csv",
        "T4 - Fact_CC_Judge",
    ),
    "t4_fact_cc_judge_v2": (
        "T4_Fact_CC_Judge_v2.csv",
        "T4 - Fact_CC_Judge",
    ),
    "t5_fact_cc_sales": (
        "T5_Fact_CC_Sales.csv",
        "T5 - Fact_CC_Sales",
    ),
    "t6_fact_cc_collection": (
        "T6_Fact_CC_Collection.csv",
        "T6 - Fact_CC_Collection",
    ),
    "t7_m3cif": (
        "T7_m3CIF.csv",
        "T7 - m3CIF",
    ),
    "t8_dim_product": (
        "T8_dimProduct.csv",
        "T8 - dimProduct",
    ),
}


def parse_mock_metadata_xlsx(
    xlsx_path: pathlib.Path,
) -> Dict[str, Tuple[str, Dict[str, str]]]:
  """Parses Mock Metadata.xlsx into {sheet_name: (table_desc, {col_name_lower: col_desc})}."""
  metadata: Dict[str, Tuple[str, Dict[str, str]]] = {}
  ns = {
      "main": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
      "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
  }
  with zipfile.ZipFile(xlsx_path, "r") as z:
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
    rel_map = {r.attrib["Id"]: r.attrib["Target"] for r in rels}
    shared: List[str] = []
    if "xl/sharedStrings.xml" in z.namelist():
      sst = ET.fromstring(z.read("xl/sharedStrings.xml"))
      for si in sst.findall("main:si", ns):
        shared.append(
            "".join(t.text or "" for t in si.findall(".//main:t", ns))
        )

    for sheet in wb.findall(".//main:sheet", ns):
      sheet_name = sheet.attrib["name"].strip()
      rid = sheet.attrib[
          "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"
      ]
      target = "xl/" + rel_map[rid].lstrip("/")
      sxml = ET.fromstring(z.read(target))
      table_desc = ""
      col_map: Dict[str, str] = {}

      for row in sxml.findall(".//main:row", ns):
        vals: List[str] = []
        for c in row.findall("main:c", ns):
          t = c.attrib.get("t")
          v = c.find("main:v", ns)
          if v is not None and v.text is not None:
            val = shared[int(v.text)] if t == "s" else v.text
          else:
            is_el = c.find(".//main:t", ns)
            val = is_el.text if is_el is not None else ""
          vals.append(val.replace("\n", " ").strip())

        non_empty = [x for x in vals if x]
        if not non_empty:
          continue
        if non_empty[0].lower().startswith("description:") and len(non_empty) >= 2:
          table_desc = non_empty[1]
        elif len(non_empty) >= 3 and non_empty[0].isdigit():
          col_name = non_empty[1].strip()
          col_desc = non_empty[2].strip()
          col_type = non_empty[3].strip() if len(non_empty) >= 4 else ""
          col_map[col_name.lower()] = (
              f"{col_desc} [Source Type: {col_type}]" if col_type else col_desc
          )

      metadata[sheet_name] = (table_desc, col_map)
  return metadata


def main() -> None:
  parser = argparse.ArgumentParser(
      description="Load ACSM T1-T8 CSVs and apply Mock Metadata.xlsx glossary."
  )
  parser.add_argument(
      "--project_id",
      default=os.environ.get("GOOGLE_CLOUD_PROJECT", ""),
      required=False,
  )
  parser.add_argument(
      "--location",
      default=os.environ.get("GOOGLE_CLOUD_LOCATION", "asia-southeast1"),
  )
  parser.add_argument("--data_dir", required=True)
  args = parser.parse_args()

  data_dir = pathlib.Path(args.data_dir)
  xlsx_path = data_dir / "Mock Metadata.xlsx"
  parsed_meta = (
      parse_mock_metadata_xlsx(xlsx_path) if xlsx_path.exists() else {}
  )

  client = bigquery.Client(project=args.project_id or None, location=args.location)
  for ds_name, ds_desc in [
      ("acsm_bronze", "ACSM Bronze Layer — Raw landing tables from LMS, DMS, AS400, and m3CIF"),
      ("acsm_silver", "ACSM Silver Layer — Standardized, typed, deduplicated & reconciled models"),
      ("acsm_gold", "ACSM Gold Layer — AEON360 Customer 360, Underwriting, Collections, ML & Vector RAG"),
  ]:
    ds_id = f"{client.project}.{ds_name}"
    ds = bigquery.Dataset(ds_id)
    ds.location = args.location
    ds.description = ds_desc
    client.create_dataset(ds, exists_ok=True)
    print(f"[OK] Verified dataset {ds_id} ({args.location})")

  for table_name, (csv_file, sheet_key) in TABLE_FILE_MAP.items():
    csv_path = data_dir / csv_file
    if not csv_path.exists():
      print(f"[SKIP] {csv_path} not found locally.")
      continue

    table_id = f"{client.project}.acsm_bronze.{table_name}"
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,
        autodetect=True,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )
    with open(csv_path, "rb") as f:
      job = client.load_table_from_file(f, table_id, job_config=job_config)
    job.result()

    table = client.get_table(table_id)
    if sheet_key in parsed_meta:
      table_desc, col_map = parsed_meta[sheet_key]
      table.description = (
          f"{table_desc} (Governed via Mock Metadata.xlsx | Source: {csv_file})"
      )
      new_schema = []
      for field in table.schema:
        desc = col_map.get(field.name.lower(), field.description)
        new_schema.append(
            bigquery.SchemaField(
                name=field.name,
                field_type=field.field_type,
                mode=field.mode,
                description=desc,
                fields=field.fields,
            )
        )
      table.schema = new_schema
      client.update_table(table, ["description", "schema"])
    print(
        f"[LOADED & ENRICHED] {table_id}: {table.num_rows:,} rows, "
        f"{len(table.schema)} governed columns"
    )


if __name__ == "__main__":
  main()
