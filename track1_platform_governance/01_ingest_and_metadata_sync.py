#!/usr/bin/env python3
"""Track 1: Pure BigQuery REST API v2 Ingestion & Metadata Sync (`Mock Metadata.xlsx`).

Creates the 8 ACSM tables (`T1_Fact_EP_Judge` .. `T8_dimProduct`) in GCP project
`trustedtesterarvind` using pure BigQuery REST API v2 Resumable Upload (`urllib.request`)
with the active `gcloud auth application-default print-access-token` token (never
invoking legacy `bq` CLI credentials), then populates 100% of table descriptions
and column descriptions (~223 columns) from `./data/Mock Metadata.xlsx`.
"""

import argparse
import gzip
import json
import os
import pathlib
import shutil
import subprocess
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from typing import Any, Dict, List, Optional, Tuple

TABLES_SPEC: List[Tuple[str, str, str, str]] = [
    ("T1_Fact_EP_Judge", "Fact_EP_Judge", "T1_Fact_EP_Judge.csv.gz", "T1 - Fact_EP_Judge"),
    ("T2_Fact_EP_Sales", "Fact_EP_Sales", "T2_Fact_EP_Sales.csv.gz", "T2 - Fact_EP_Sales"),
    ("T3_Fact_EP_Collection", "Fact_EP_Collection", "T3_Fact_EP_Collection.csv.gz", "T3 - Fact_EP_Collection"),
    ("T4_Fact_CC_Judge", "Fact_CC_Judge", "T4_Fact_CC_Judge_v2.csv.gz", "T4 - Fact_CC_Judge"),
    ("T5_Fact_CC_Sales", "Fact_CC_Sales", "T5_Fact_CC_Sales.csv.gz", "T5 - Fact_CC_Sales"),
    ("T6_Fact_CC_Collection", "Fact_CC_Collection", "T6_Fact_CC_Collection.csv.gz", "T6 - Fact_CC_Collection"),
    ("T7_m3CIF", "m3CIF", "T7_m3CIF.csv.gz", "T7 - m3CIF"),
    ("T8_dimProduct", "dimProduct", "T8_dimProduct.csv.gz", "T8 - dimProduct"),
]


def find_cli(name: str) -> str:
  found = shutil.which(name)
  if found:
    return found
  fallback = pathlib.Path.home() / "google-cloud-sdk" / "bin" / name
  if fallback.exists():
    return str(fallback)
  return name


def get_oauth_token() -> str:
  gcloud_bin = find_cli("gcloud")
  for cmd in [
      [gcloud_bin, "auth", "application-default", "print-access-token"],
      [gcloud_bin, "auth", "print-access-token"],
  ]:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode == 0 and proc.stdout.strip():
      return proc.stdout.strip()
  raise RuntimeError(
      "Unable to obtain Google Cloud access token. Run `gcloud auth application-default login`."
  )


def bq_rest_api(
    method: str,
    url: str,
    token: str,
    project_id: str,
    body: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
  data = json.dumps(body).encode("utf-8") if body is not None else None
  req = urllib.request.Request(
      url,
      data=data,
      method=method,
      headers={
          "Authorization": f"Bearer {token}",
          "Content-Type": "application/json",
          "x-goog-user-project": project_id,
      },
  )
  try:
    with urllib.request.urlopen(req) as resp:
      return json.loads(resp.read().decode("utf-8"))
  except urllib.error.HTTPError as e:
    err_txt = e.read().decode("utf-8", errors="ignore")
    if e.code == 409:
      return {"status": "ALREADY_EXISTS"}
    raise RuntimeError(f"HTTP {e.code} on {method} {url}: {err_txt}") from e


def bq_upload_csv_gz(
    project_id: str,
    dataset_id: str,
    table_id: str,
    gz_path: pathlib.Path,
    token: str,
) -> None:
  """Uploads a .csv.gz file via BigQuery v2 REST API Resumable Upload and waits for completion."""
  init_url = (
      f"https://bigquery.googleapis.com/upload/bigquery/v2/projects/{project_id}"
      "/jobs?uploadType=resumable"
  )
  job_meta = {
      "configuration": {
          "load": {
              "destinationTable": {
                  "projectId": project_id,
                  "datasetId": dataset_id,
                  "tableId": table_id,
              },
              "sourceFormat": "CSV",
              "skipLeadingRows": 1,
              "autodetect": True,
              "writeDisposition": "WRITE_TRUNCATE",
              "allowQuotedNewlines": True,
          }
      }
  }
  init_req = urllib.request.Request(
      init_url,
      data=json.dumps(job_meta).encode("utf-8"),
      method="POST",
      headers={
          "Authorization": f"Bearer {token}",
          "Content-Type": "application/json; charset=UTF-8",
          "x-goog-user-project": project_id,
          "X-Upload-Content-Type": "application/octet-stream",
      },
  )
  with urllib.request.urlopen(init_req) as init_resp:
    upload_url = init_resp.headers.get("Location")

  if not upload_url:
    raise RuntimeError("Did not receive resumable upload Location header from BigQuery.")

  # Decompress CSV in-memory so BigQuery CSV parser processes raw bytes cleanly
  with gzip.open(gz_path, "rb") as f_in:
    raw_csv_bytes = f_in.read()

  put_req = urllib.request.Request(
      upload_url,
      data=raw_csv_bytes,
      method="PUT",
      headers={
          "Content-Type": "application/octet-stream",
          "Content-Length": str(len(raw_csv_bytes)),
      },
  )
  with urllib.request.urlopen(put_req) as put_resp:
    job_info = json.loads(put_resp.read().decode("utf-8"))

  job_id = job_info["jobReference"]["jobId"]
  loc = job_info["jobReference"].get("location", "US")
  status_url = (
      f"https://bigquery.googleapis.com/bigquery/v2/projects/{project_id}"
      f"/jobs/{job_id}?location={loc}"
  )
  while True:
    j = bq_rest_api("GET", status_url, token, project_id)
    state = j.get("status", {}).get("state")
    if state == "DONE":
      err = j.get("status", {}).get("errorResult")
      if err:
        raise RuntimeError(f"BigQuery load job failed for {table_id}: {err}")
      break
    time.sleep(1.5)


def parse_mock_metadata_xlsx(
    xlsx_path: pathlib.Path,
) -> Dict[str, Tuple[str, Dict[str, str]]]:
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
              f"{col_desc} [Source Data Type: {col_type}]"
              if col_type
              else col_desc
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
      default=os.environ.get("GOOGLE_CLOUD_PROJECT", "trustedtesterarvind"),
  )
  parser.add_argument(
      "--dataset_id",
      default="acsm_bronze",
  )
  parser.add_argument(
      "--location",
      default=os.environ.get("GOOGLE_CLOUD_LOCATION", "asia-southeast1"),
  )
  parser.add_argument("--data_dir", default=str(repo_root / "data"))
  args = parser.parse_args()

  token = get_oauth_token()
  data_dir = pathlib.Path(args.data_dir)
  parsed_meta = parse_mock_metadata_xlsx(data_dir / "Mock Metadata.xlsx")

  for ds_id, desc in [
      (
          args.dataset_id,
          "AEON Credit Service Malaysia (ACSM) — 8 Core Tables (T1–T8) with Governed Metadata from Mock Metadata.xlsx",
      ),
      (
          "acsm_silver",
          "ACSM Silver Layer — Standardized, typed, deduplicated & reconciled models",
      ),
      (
          "acsm_gold",
          "ACSM Gold Layer — AEON360 Customer 360, Underwriting, Collections, ML & Vector RAG",
      ),
  ]:
    bq_rest_api(
        "POST",
        f"https://bigquery.googleapis.com/bigquery/v2/projects/{args.project_id}/datasets",
        token,
        args.project_id,
        {
            "datasetReference": {
                "projectId": args.project_id,
                "datasetId": ds_id,
            },
            "location": args.location,
            "description": desc,
        },
    )
    print(f"[DATASET READY] {args.project_id}.{ds_id}", flush=True)

  import concurrent.futures

  def process_one_table(spec: Tuple[str, str, str, str]) -> str:
    t_name, short_name, gz_file, sheet_key = spec
    gz_path = data_dir / "full_compressed" / gz_file
    print(f"Uploading {args.project_id}.{args.dataset_id}.{t_name} from {gz_file} ...", flush=True)
    bq_upload_csv_gz(args.project_id, args.dataset_id, t_name, gz_path, token)

    t_url = (
        f"https://bigquery.googleapis.com/bigquery/v2/projects/{args.project_id}"
        f"/datasets/{args.dataset_id}/tables/{t_name}"
    )
    tbl = bq_rest_api("GET", t_url, token, args.project_id)
    tdesc, cmap = parsed_meta[sheet_key]
    fields = tbl.get("schema", {}).get("fields", [])
    matched = 0
    for f in fields:
      col_desc = cmap.get(f["name"].lower())
      if col_desc:
        f["description"] = col_desc
        matched += 1
    bq_rest_api(
        "PATCH",
        t_url,
        token,
        args.project_id,
        {
            "description": (
                f"{tdesc} (Governed via Mock Metadata.xlsx | Sheet: {sheet_key})"
            ),
            "schema": {"fields": fields},
        },
    )
    num_rows = int(tbl.get("numRows", "0"))
    msg = (
        f"[CREATED & ENRICHED] {args.project_id}.{args.dataset_id}.{t_name} -> "
        f"{num_rows:,} rows | {matched}/{len(fields)} columns described"
    )
    print(msg, flush=True)
    return msg

  with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(process_one_table, TABLES_SPEC))
  print("\n=== SUMMARY OF 8 ACSM TABLES IN BIGQUERY ===", flush=True)
  for r in results:
    print(r, flush=True)


if __name__ == "__main__":
  main()
