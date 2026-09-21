#!/usr/bin/env python3
"""Track 1: Automated Ingestion & Metadata Enrichment from Mock Metadata.xlsx.

Creates the 8 ACSM tables (`T1_Fact_EP_Judge` .. `T8_dimProduct`, plus canonical
table aliases `Fact_EP_Judge` .. `dimProduct`) in GCP project `trsutedtesterarvind`
and populates every table description and column description (~220 columns)
from `./data/Mock Metadata.xlsx`.
"""

import argparse
import os
import pathlib
import xml.etree.ElementTree as ET
import zipfile
from typing import Dict, List, Tuple
from google.cloud import bigquery

# Maps (t_prefixed_table_name, canonical_table_name, csv_filename, metadata_sheet_name)
TABLES_SPEC: List[Tuple[str, str, str, str]] = [
    ("T1_Fact_EP_Judge", "Fact_EP_Judge", "T1_Fact_EP_Judge.csv", "T1 - Fact_EP_Judge"),
    ("T2_Fact_EP_Sales", "Fact_EP_Sales", "T2_Fact_EP_Sales.csv", "T2 - Fact_EP_Sales"),
    ("T3_Fact_EP_Collection", "Fact_EP_Collection", "T3_Fact_EP_Collection.csv", "T3 - Fact_EP_Collection"),
    ("T4_Fact_CC_Judge", "Fact_CC_Judge", "T4_Fact_CC_Judge_v2.csv", "T4 - Fact_CC_Judge"),
    ("T5_Fact_CC_Sales", "Fact_CC_Sales", "T5_Fact_CC_Sales.csv", "T5 - Fact_CC_Sales"),
    ("T6_Fact_CC_Collection", "Fact_CC_Collection", "T6_Fact_CC_Collection.csv", "T6 - Fact_CC_Collection"),
    ("T7_m3CIF", "m3CIF", "T7_m3CIF.csv", "T7 - m3CIF"),
    ("T8_dimProduct", "dimProduct", "T8_dimProduct.csv", "T8 - dimProduct"),
]


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
      sxml = ET.fromstring(z.read("xl/" + rel_map[rid].lstrip("/")))
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
              f"{col_desc} (Source Data Type: {col_type})" if col_type else col_desc
          )

      metadata[sheet_name] = (table_desc, col_map)
  return metadata


def main() -> None:
  repo_root = pathlib.Path(__file__).resolve().parent.parent
  parser = argparse.ArgumentParser(
      description="Create 8 ACSM tables with full table & column descriptions in BigQuery."
  )
  parser.add_argument(
      "--project_id",
      default=os.environ.get("GOOGLE_CLOUD_PROJECT", "trsutedtesterarvind"),
  )
  parser.add_argument(
      "--dataset_id",
      default="acsm_bronze",
      help="Target BigQuery dataset name (default: acsm_bronze)",
  )
  parser.add_argument(
      "--location",
      default=os.environ.get("GOOGLE_CLOUD_LOCATION", "US"),
  )
  parser.add_argument("--data_dir", default=str(repo_root / "data"))
  args = parser.parse_args()

  data_dir = pathlib.Path(args.data_dir)
  xlsx_path = data_dir / "Mock Metadata.xlsx"
  parsed_meta = (
      parse_mock_metadata_xlsx(xlsx_path) if xlsx_path.exists() else {}
  )

  client = bigquery.Client(project=args.project_id, location=args.location)
  for ds_name, ds_desc in [
      (args.dataset_id, "AEON Credit Service Malaysia (ACSM) — 8 Core Tables with Governed Table & Column Descriptions from Mock Metadata.xlsx"),
      ("acsm_silver", "ACSM Silver Layer — Standardized, typed, deduplicated & reconciled models"),
      ("acsm_gold", "ACSM Gold Layer — AEON360 Customer 360, Underwriting, Collections, ML & Vector RAG"),
  ]:
    ds_ref = f"{args.project_id}.{ds_name}"
    ds = bigquery.Dataset(ds_ref)
    ds.location = args.location
    ds.description = ds_desc
    client.create_dataset(ds, exists_ok=True)
    print(f"[DATASET READY] {ds_ref} (location={args.location})")

  for t_name, short_name, csv_file, sheet_key in TABLES_SPEC:
    gz_candidate = data_dir / "full_compressed" / f"{csv_file}.gz"
    raw_candidate = data_dir / csv_file
    sample_candidate = data_dir / "samples" / csv_file

    if gz_candidate.exists():
      target_file = gz_candidate
    elif raw_candidate.exists():
      target_file = raw_candidate
    elif sample_candidate.exists():
      target_file = sample_candidate
    else:
      print(f"[SKIP] {csv_file} not found in {data_dir}")
      continue

    table_id = f"{args.project_id}.{args.dataset_id}.{t_name}"
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,
        autodetect=True,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )
    with open(target_file, "rb") as f:
      job = client.load_table_from_file(f, table_id, job_config=job_config)
    job.result()

    table = client.get_table(table_id)
    enriched_cols = 0
    if sheet_key in parsed_meta:
      table_desc, col_map = parsed_meta[sheet_key]
      table.description = f"{table_desc} [Sheet: {sheet_key} | Source: {csv_file}]"
      new_schema = []
      for field in table.schema:
        desc = col_map.get(field.name.lower(), field.description)
        if desc:
          enriched_cols += 1
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

    # Also create/replace the exact canonical table name from Mock Metadata.xlsx (e.g. Fact_EP_Judge, m3CIF, dimProduct)
    canonical_id = f"{args.project_id}.{args.dataset_id}.{short_name}"
    copy_job = client.copy_table(
        table_id,
        canonical_id,
        job_config=bigquery.CopyJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE
        ),
    )
    copy_job.result()

    print(
        f"[CREATED & ENRICHED] {table_id} (& {short_name}) -> "
        f"{table.num_rows:,} rows | {enriched_cols}/{len(table.schema)} columns described"
    )


if __name__ == "__main__":
  main()
