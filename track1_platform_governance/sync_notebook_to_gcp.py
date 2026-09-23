#!/usr/bin/env python3
"""Automatically syncs ACSM_Track1_Serverless_Seamless_Data_Ingestion.ipynb directly to BigQuery Studio & GCS in project `decoded-effect-509506-m5`."""

import argparse
import base64
import json
import pathlib
import subprocess
import urllib.error
import urllib.parse
import urllib.request


def get_token() -> str:
  gcloud = "/usr/local/google/home/dhariwal/google-cloud-sdk/bin/gcloud"
  for cmd in [
      [gcloud, "auth", "application-default", "print-access-token"],
      [gcloud, "auth", "print-access-token"],
  ]:
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode == 0 and p.stdout.strip():
      return p.stdout.strip()
  raise RuntimeError(
      "GCP token expired. Run `gcloud auth application-default login` in your terminal."
  )


def api_call(method: str, url: str, token: str, project_id: str, body=None, content_type="application/json"):
  headers = {
      "Authorization": f"Bearer {token}",
      "x-goog-user-project": project_id,
      "Content-Type": content_type,
  }
  data = body if isinstance(body, bytes) else (json.dumps(body).encode("utf-8") if body is not None else None)
  req = urllib.request.Request(url, data=data, method=method, headers=headers)
  try:
    with urllib.request.urlopen(req) as resp:
      raw = resp.read()
      return json.loads(raw.decode("utf-8")) if raw else {}
  except urllib.error.HTTPError as e:
    err = e.read().decode("utf-8", errors="ignore")
    if e.code in (404, 409):
      return {"status_code": e.code, "error": err}
    raise RuntimeError(f"HTTP {e.code} on {method} {url}: {err}") from e


def sync_notebook(project_id: str, location: str, nb_path: pathlib.Path) -> None:
  token = get_token()

  # 1. Ensure required APIs are enabled in decoded-effect-509506-m5
  for svc in ["bigquery.googleapis.com", "dataform.googleapis.com", "aiplatform.googleapis.com", "storage.googleapis.com"]:
    api_call(
        "POST",
        f"https://serviceusage.googleapis.com/v1/projects/{project_id}/services/{svc}:enable",
        token,
        project_id,
        {},
    )

  # 2. Ensure notebook has PROJECT_ID defaulted to target project_id
  nb_json = json.loads(nb_path.read_text())
  for cell in nb_json.get("cells", []):
    cell["source"] = [
        line.replace('PROJECT_ID = "trustedtesterarvind"', f'PROJECT_ID = "{project_id}"')
        for line in cell.get("source", [])
    ]
  nb_bytes = json.dumps(nb_json, indent=2).encode("utf-8")
  nb_path.write_bytes(nb_bytes)

  # 3. Upload to BigQuery Studio Notebook Repository (Dataform v1beta1 single-file asset)
  repo_id = "acsm-track1-serverless-seamless-data-ingestion"
  ws_id = "default"
  base_df = f"https://dataform.googleapis.com/v1beta1/projects/{project_id}/locations/{location}"

  api_call(
      "POST",
      f"{base_df}/repositories?repositoryId={repo_id}",
      token,
      project_id,
      {
          "displayName": "ACSM_Track1_Serverless_Seamless_Data_Ingestion",
          "labels": {"single-file-asset-type": "notebook"},
      },
  )
  api_call(
      "POST",
      f"{base_df}/repositories/{repo_id}/workspaces?workspaceId={ws_id}",
      token,
      project_id,
      {},
  )
  api_call(
      "POST",
      f"{base_df}/repositories/{repo_id}/workspaces/{ws_id}:writeFile",
      token,
      project_id,
      {
          "path": "ACSM_Track1_Serverless_Seamless_Data_Ingestion.ipynb",
          "contents": base64.b64encode(nb_bytes).decode("ascii"),
      },
  )
  # Commit the workspace change so BigQuery Studio UI shows the latest version immediately
  api_call(
      "POST",
      f"{base_df}/repositories/{repo_id}/workspaces/{ws_id}:commit",
      token,
      project_id,
      {
          "author": {"name": "Arvind Dhariwal", "emailAddress": "dhariwal@google.com"},
          "commitMessage": "Auto-sync ACSM_Track1_Serverless_Seamless_Data_Ingestion.ipynb to BigQuery Studio",
      },
  )
  print(
      f"✅ [BIGQUERY STUDIO NOTEBOOK SYNCED] Project: {project_id} | Region: {location} | "
      f"Asset: {repo_id} (ACSM_Track1_Serverless_Seamless_Data_Ingestion.ipynb)"
  )

  # 4. Also upload to Regional Cloud Storage Bucket in Singapore (asia-southeast1)
  bucket = f"acsm-workshop-landing-{project_id}"
  api_call(
      "POST",
      f"https://storage.googleapis.com/storage/v1/b?project={project_id}",
      token,
      project_id,
      {"name": bucket, "location": location},
  )
  obj_name = urllib.parse.quote("notebooks/ACSM_Track1_Serverless_Seamless_Data_Ingestion.ipynb", safe="")
  api_call(
      "POST",
      f"https://storage.googleapis.com/upload/storage/v1/b/{bucket}/o?uploadType=media&name={obj_name}",
      token,
      project_id,
      nb_bytes,
      content_type="application/x-ipynb+json",
  )
  print(f"✅ [GCS NOTEBOOK SYNCED] gs://{bucket}/notebooks/ACSM_Track1_Serverless_Seamless_Data_Ingestion.ipynb")


if __name__ == "__main__":
  parser = argparse.ArgumentParser()
  parser.add_argument("--project_id", default="decoded-effect-509506-m5")
  parser.add_argument("--location", default="asia-southeast1")
  parser.add_argument(
      "--notebook",
      default=str(
          pathlib.Path(__file__).resolve().parent
          / "ACSM_Track1_Serverless_Seamless_Data_Ingestion.ipynb"
      ),
  )
  args = parser.parse_args()
  sync_notebook(args.project_id, args.location, pathlib.Path(args.notebook))
