#!/usr/bin/env python3
"""CLI helper for Track 1 Notebook 03 (Step 1.5a): Sync business_glossary_acsm.yaml to Dataplex Business Glossary & BigQuery."""

import argparse
import os
import re
import time
import urllib.request
import yaml
import google.auth
from google.auth.transport.requests import AuthorizedSession
from google.cloud import bigquery


YAML_URL = "https://raw.githubusercontent.com/arvind-dhariwal/aeon-credit-gcp-workshop/main/track1_platform_governance/scripts/business_glossary_acsm.yaml"


def resolve_yaml_path() -> str:
    candidates = [
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "business_glossary_acsm.yaml"),
        "aeon-credit-gcp-workshop/track1_platform_governance/scripts/business_glossary_acsm.yaml",
        "../scripts/business_glossary_acsm.yaml",
        "business_glossary_acsm.yaml",
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    urllib.request.urlretrieve(YAML_URL, "business_glossary_acsm.yaml")
    return "business_glossary_acsm.yaml"


def render_html(html_str: str):
    try:
        from IPython import get_ipython
        from IPython.display import HTML, display

        if get_ipython() is not None:
            display(HTML(html_str))
    except Exception:
        pass


def sync_glossary(project_id: str = "", location: str = "asia-southeast1"):
    credentials, default_proj = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    PROJECT_ID = (
        project_id
        or os.environ.get("PROJECT_ID", "").strip()
        or os.environ.get("GOOGLE_CLOUD_PROJECT", "").strip()
        or default_proj
    )
    LOCATION = location or os.environ.get("LOCATION", "asia-southeast1").strip()

    local_yaml = resolve_yaml_path()
    with open(local_yaml, "r") as f:
        cfg = yaml.safe_load(f)

    authed_session = AuthorizedSession(credentials)
    bq_client = bigquery.Client(project=PROJECT_ID, location=LOCATION)

    glossary = cfg["glossary"]
    glossary_id = glossary["id"]
    base_url = f"https://dataplex.googleapis.com/v1/projects/{PROJECT_ID}/locations/{LOCATION}"
    glossary_parent = f"projects/{PROJECT_ID}/locations/{LOCATION}/glossaries/{glossary_id}"

    def wait_for_dataplex_lro(resp):
        """Polls a Dataplex Long-Running Operation (LRO) until completion."""
        if resp.status_code not in (200, 201):
            return
        body = resp.json()
        op_name = body.get("name", "")
        if op_name and "/operations/" in op_name:
            for _ in range(30):
                op_r = authed_session.get(f"https://dataplex.googleapis.com/v1/{op_name}")
                if op_r.status_code == 200 and op_r.json().get("done"):
                    break
                time.sleep(1)

    # 1. Create or Update Top-Level Dataplex Business Glossary (and wait for LRO to finish!)
    g_resp = authed_session.get(f"{base_url}/glossaries/{glossary_id}")
    if g_resp.status_code == 404:
        op_resp = authed_session.post(
            f"{base_url}/glossaries?glossary_id={glossary_id}",
            json={"displayName": glossary["display_name"], "description": glossary["description"]},
        )
        wait_for_dataplex_lro(op_resp)
    else:
        op_resp = authed_session.patch(
            f"{base_url}/glossaries/{glossary_id}?update_mask=displayName,description",
            json={"displayName": glossary["display_name"], "description": glossary["description"]},
        )
        wait_for_dataplex_lro(op_resp)

    # Ensure Glossary is ready before creating Categories
    for _ in range(15):
        g_check = authed_session.get(f"{base_url}/glossaries/{glossary_id}")
        if g_check.status_code == 200:
            break
        time.sleep(1)

    # 2. Create or Update the 4 Domain Categories
    cat_map = {}
    for cat in cfg["categories"]:
        cat_id = cat["id"]
        cat_map[cat_id] = cat["display_name"]
        c_url = f"{base_url}/glossaries/{glossary_id}/categories/{cat_id}"
        cat_payload = {
            "displayName": cat["display_name"],
            "description": cat["description"],
            "parent": glossary_parent,
        }
        if authed_session.get(c_url).status_code == 404:
            c_r = authed_session.post(
                f"{base_url}/glossaries/{glossary_id}/categories?category_id={cat_id}",
                json=cat_payload,
            )
            print(f"  📁 Created Category: {cat['display_name']} ({cat_id}) [HTTP {c_r.status_code}]")
        else:
            c_r = authed_session.patch(
                f"{c_url}?update_mask=displayName,description,parent",
                json=cat_payload,
            )
            print(f"  📁 Verified Category: {cat['display_name']} ({cat_id}) [HTTP {c_r.status_code}]")

    # 3. Create or Update the 10 Standardized ACSM Business Terms under their Categories
    rows_to_insert = []
    for term in cfg["terms"]:
        term_id = term["id"]
        cat_id = term["category"]
        t_url = f"{base_url}/glossaries/{glossary_id}/terms/{term_id}"
        term_payload = {
            "displayName": term["display_name"],
            "description": term["definition"],
            "parent": f"{glossary_parent}/categories/{cat_id}",
        }
        if authed_session.get(t_url).status_code == 404:
            t_r = authed_session.post(
                f"{base_url}/glossaries/{glossary_id}/terms?term_id={term_id}",
                json=term_payload,
            )
            print(f"    🏷️ Created Term: {term['display_name']} -> {cat_id} [HTTP {t_r.status_code}]")
        else:
            t_r = authed_session.patch(
                f"{t_url}?update_mask=displayName,description,parent",
                json=term_payload,
            )
            print(f"    🏷️ Verified Term: {term['display_name']} -> {cat_id} [HTTP {t_r.status_code}]")
        rows_to_insert.append({
            "glossary_id": glossary_id,
            "category_id": cat_id,
            "category_name": cat_map.get(cat_id, cat_id),
            "term_id": term_id,
            "term_display_name": term["display_name"],
            "business_definition": term["definition"],
            "synonyms": ", ".join(term.get("synonyms", [])),
            "related_terms": ", ".join(term.get("related_terms", [])),
            "linked_bigquery_columns": ", ".join(term.get("linked_columns", [])),
            "data_steward": term.get("steward", ""),
        })

    # 4. Populate Glossary Overview Aspect & Link Terms to BigQuery Columns (entryLinkTypes/definition)
    proj_r = authed_session.get(f"https://cloudresourcemanager.googleapis.com/v1/projects/{PROJECT_ID}")
    project_number = str(proj_r.json().get("projectNumber", "")) if proj_r.status_code == 200 else ""
    if project_number:
        glossary_entry = (
            f"projects/{PROJECT_ID}/locations/{LOCATION}/entryGroups/@dataplex/entries/"
            f"projects/{project_number}/locations/{LOCATION}/glossaries/{glossary_id}"
        )
        overview_html = (
            "<p><strong>AEON Credit Service Malaysia (ACSM) — Enterprise Consumer Finance &amp; Regulatory Glossary</strong></p>"
            "<p>Provides standardized business definitions, Bank Negara Malaysia (BNM) Responsible Financing thresholds, "
            "and Malaysian PDPA 2010 privacy classifications across 4 domain categories and 10 core business terms "
            "linked to <code>acsm_gold.gold_aeon_customer360_profile</code> and <code>acsm_bronze</code> tables.</p>"
        )
        authed_session.patch(
            f"https://dataplex.googleapis.com/v1/{glossary_entry}?update_mask=aspects&deleteMissingAspects=false&aspect_keys=dataplex-types.global.overview",
            json={
                "aspects": {
                    "dataplex-types.global.overview": {
                        "aspectType": "projects/dataplex-types/locations/global/aspectTypes/overview",
                        "data": {"content": overview_html},
                    }
                }
            },
        )

        linked_count = 0
        bq_eg_url = f"{base_url}/entryGroups/@bigquery/entryLinks"
        for term in cfg["terms"]:
            term_id = term["id"]
            target_term_entry = (
                f"projects/{project_number}/locations/{LOCATION}/entryGroups/@dataplex/entries/"
                f"projects/{project_number}/locations/{LOCATION}/glossaries/{glossary_id}/terms/{term_id}"
            )
            for col_spec in term.get("linked_columns", []):
                parts = col_spec.split(".")
                if len(parts) == 3:
                    ds_name, tbl_name, col_name = parts
                    link_id = re.sub(r"[^a-z0-9-]", "-", f"acsm-{tbl_name[:12]}-{col_name[:12]}-{term_id[:20]}".lower()).strip("-")[:60]
                    src_table_entry = (
                        f"projects/{project_number}/locations/{LOCATION}/entryGroups/@bigquery/entries/"
                        f"bigquery.googleapis.com/projects/{PROJECT_ID}/datasets/{ds_name}/tables/{tbl_name}"
                    )
                    l_r = authed_session.post(
                        f"{bq_eg_url}?entryLinkId={link_id}",
                        json={
                            "entryLinkType": "projects/dataplex-types/locations/global/entryLinkTypes/definition",
                            "entryReferences": [
                                {"name": src_table_entry, "type": "SOURCE", "path": f"Schema.{col_name}"},
                                {"name": target_term_entry, "type": "TARGET"},
                            ],
                        },
                    )
                    if l_r.status_code in (200, 201, 409):
                        linked_count += 1
        print(f"  🔗 Linked {linked_count} BigQuery Table Columns to Business Glossary Terms (entryLinkTypes/definition)")

    table_id = f"{PROJECT_ID}.acsm_gold.business_glossary_catalog"
    job_config = bigquery.LoadJobConfig(write_disposition="WRITE_TRUNCATE")
    bq_client.load_table_from_json(rows_to_insert, table_id, job_config=job_config).result()
    print(f"\n✅ Synced {len(cfg['categories'])} Categories and {len(rows_to_insert)} Business Glossary Terms from `{local_yaml}` to Dataplex (`{glossary_id}`) & `{table_id}`")

    # 5. Render Clickable Project-Specific Knowledge Catalog Deep Links for Instant Verification
    console_base = f"https://console.cloud.google.com/dataplex/dp-glossaries/projects/{PROJECT_ID}/locations/{LOCATION}/glossaries/{glossary_id}"
    all_glossaries_url = f"https://console.cloud.google.com/dataplex/dp-glossaries?project={PROJECT_ID}"
    glossary_direct_url = f"{console_base}?project={PROJECT_ID}"
    bq_table_url = f"https://console.cloud.google.com/bigquery?project={PROJECT_ID}&ws=!1m5!1m4!4m3!1s{PROJECT_ID}!2sacsm_gold!3sgold_aeon_customer360_profile"

    cat_links_html = "".join([
        f'<li>📁 <a href="{console_base}/categories/{c["id"]}?project={PROJECT_ID}" target="_blank" style="color:#1a73e8;font-weight:600;">{c["display_name"]}</a> <code>({c["id"]})</code></li>'
        for c in cfg["categories"]
    ])
    term_links_html = "".join([
        f'<li>🏷️ <a href="{console_base}/terms/{t["id"]}?project={PROJECT_ID}" target="_blank" style="color:#188038;font-weight:600;">{t["display_name"]}</a> &rarr; <code>{t["category"]}</code></li>'
        for t in cfg["terms"]
    ])

    render_html(f"""
<div style="border: 1px solid #dadce0; border-left: 5px solid #1a73e8; border-radius: 8px; padding: 16px; margin-top: 14px; background-color: #f8f9fa; font-family: Google Sans, Roboto, sans-serif;">
  <h3 style="margin: 0 0 8px 0; color: #202124;">🔍 Click Below to Verify Business Glossary, Categories &amp; Terms in Knowledge Catalog (<code>{PROJECT_ID}</code>)</h3>
  <p style="margin: 6px 0 12px 0;">
    👉 <strong><a href="{glossary_direct_url}" target="_blank" style="color: #ffffff; background-color: #1a73e8; padding: 8px 14px; border-radius: 4px; text-decoration: none; display: inline-block;">📘 Open ACSM Business Glossary ({glossary_id}) ↗</a></strong>
    &nbsp;&nbsp;
    <a href="{all_glossaries_url}" target="_blank" style="color: #1a73e8; font-weight: 600;">View All Glossaries in {PROJECT_ID} ↗</a>
    &nbsp;|&nbsp;
    <a href="{bq_table_url}" target="_blank" style="color: #1a73e8; font-weight: 600;">Open gold_aeon_customer360_profile in BigQuery ↗</a>
  </p>
  <div style="display: flex; gap: 28px; flex-wrap: wrap;">
    <div style="flex: 1; min-width: 280px;">
      <h4 style="margin: 4px 0;">🗂️ 4 Domain Categories (Direct Links):</h4>
      <ul style="margin: 4px 0; padding-left: 20px; line-height: 1.7;">{cat_links_html}</ul>
    </div>
    <div style="flex: 1.3; min-width: 340px;">
      <h4 style="margin: 4px 0;">🏷️ 10 ACSM Business Terms (Direct Links):</h4>
      <ul style="margin: 4px 0; padding-left: 20px; line-height: 1.6;">{term_links_html}</ul>
    </div>
  </div>
</div>
""")


def main():
    parser = argparse.ArgumentParser(description="Sync ACSM Business Glossary YAML to Dataplex & BigQuery")
    parser.add_argument("--project", default="", help="GCP Project ID")
    parser.add_argument("--location", default="asia-southeast1", help="Dataplex / BigQuery region")
    args = parser.parse_args()
    sync_glossary(args.project, args.location)


if __name__ == "__main__":
    main()
