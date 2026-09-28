#!/usr/bin/env python3
"""CLI helper for Track 1 Notebook 04: Analytics Hub Data Exchange & BigQuery Data Clean Room setup."""

import argparse
import os
import subprocess
import google.auth
from google.auth.transport.requests import AuthorizedSession
from google.cloud import bigquery


def get_clients(project_id: str = "", location: str = "asia-southeast1"):
    creds, default_proj = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    proj = (
        project_id
        or os.environ.get("PROJECT_ID", "").strip()
        or os.environ.get("GOOGLE_CLOUD_PROJECT", "").strip()
        or default_proj
    )
    ah_session = AuthorizedSession(creds)
    ah_session.headers.update({"x-goog-user-project": proj})
    bq_client = bigquery.Client(project=proj, location=location)
    return proj, location, ah_session, bq_client


def render_html(html_str: str):
    try:
        from IPython import get_ipython
        from IPython.display import HTML, display

        if get_ipython() is not None:
            display(HTML(html_str))
    except Exception:
        pass


def setup_exchange(project_id: str, location: str):
    PROJECT_ID, LOCATION, ah_session, bq_client = get_clients(project_id, location)
    base_ah_url = f"https://analyticshub.googleapis.com/v1/projects/{PROJECT_ID}/locations/{LOCATION}/dataExchanges"

    # 0. Authorize dedicated shared dataset `acsm_analyticshub_shared` (Authorized Views) on source dataset `acsm_bronze`
    src_ds = bq_client.get_dataset(f"{PROJECT_ID}.acsm_bronze")
    auth_entry = bigquery.AccessEntry(
        role=None,
        entity_type="dataset",
        entity_id={
            "dataset": {"projectId": PROJECT_ID, "datasetId": "acsm_analyticshub_shared"},
            "targetTypes": ["VIEWS"],
        },
    )
    if auth_entry not in src_ds.access_entries:
        entries = list(src_ds.access_entries)
        entries.append(auth_entry)
        src_ds.access_entries = entries
        bq_client.update_dataset(src_ds, ["access_entries"])

    # 1. Create or Verify Analytics Hub Data Exchange in Singapore (asia-southeast1)
    exchange_id = "acsm_aeon_exchange"
    ex_url = f"{base_ah_url}/{exchange_id}"
    if ah_session.get(ex_url).status_code == 404:
        ex_resp = ah_session.post(
            f"{base_ah_url}?dataExchangeId={exchange_id}",
            json={
                "displayName": "ACSM_AEON_Ecosystem_Exchange",
                "description": "One-AEON Zero-Copy Cross-Entity Data Exchange in Singapore (asia-southeast1) sharing curated ACSM credit & merchant spend with AEON Retail.",
                "primaryContact": "data-governance@aeoncredit.com.my",
            },
        )
        if ex_resp.status_code not in (200, 409):
            print(f"⚠️ Data Exchange creation status ({ex_resp.status_code}): {ex_resp.text}")

    # 2. Publish or Verify Curated Zero-Copy Listing sharing dedicated dataset `acsm_analyticshub_shared` (NOT `acsm_gold`)
    listing_id = "acsm_merchant_spend_listing"
    list_url = f"{ex_url}/listings/{listing_id}"
    target_shared_ds = f"projects/{PROJECT_ID}/datasets/acsm_analyticshub_shared"

    existing_list_resp = ah_session.get(list_url)
    if existing_list_resp.status_code == 200:
        current_ds = existing_list_resp.json().get("bigqueryDataset", {}).get("dataset", "")
        if current_ds != target_shared_ds:
            print(f"🔄 Updating listing `{listing_id}` from `{current_ds}` to dedicated shared dataset `{target_shared_ds}`...")
            ah_session.delete(list_url)
            existing_list_resp = ah_session.get(list_url)

    if existing_list_resp.status_code == 404:
        list_resp = ah_session.post(
            f"{ex_url}/listings?listingId={listing_id}",
            json={
                "displayName": "ACSM_Merchant_Spend_Zero_Copy_Listing",
                "description": "Curated ACSM Credit Card Merchant Spend Aggregations shared zero-copy from dedicated shared dataset acsm_analyticshub_shared without exposing internal gold tables or cardholder PII.",
                "primaryContact": "data-governance@aeoncredit.com.my",
                "bigqueryDataset": {
                    "dataset": target_shared_ds,
                },
            },
        )
        if list_resp.status_code not in (200, 409):
            print(f"⚠️ Listing creation status ({list_resp.status_code}): {list_resp.text}")

    # 3. List active Data Exchanges & Listings in the project
    exchanges = ah_session.get(base_ah_url).json().get("dataExchanges", [])
    listings = ah_session.get(f"{ex_url}/listings").json().get("listings", [])

    search_url = (
        f"https://console.cloud.google.com/bigquery/analytics-hub/exchanges"
        f";cameo=analyticshub;pageName=search;pageResource="
        f"?project={PROJECT_ID}&visibility=&queryText=AEON"
    )
    publisher_view_url = (
        f"https://console.cloud.google.com/bigquery?project={PROJECT_ID}"
        f"&ws=!1m5!1m4!4m3!1s{PROJECT_ID}!2sacsm_analyticshub_shared!3svw_analyticshub_merchant_spend_aggregations"
    )

    print("==========================================================================")
    print(f"🤝 [Step 2.1 Outcome] Analytics Hub Data Exchange & Listing (`{LOCATION}`)")
    print("==========================================================================")
    for ex in exchanges:
        if ex.get("name", "").endswith(f"/{exchange_id}"):
            print(f"  • Data Exchange Resource: `{ex.get('name')}`")
            print(f"  • Display Name          : {ex.get('displayName')}")
            print(f"  • Listing Count         : {ex.get('listingCount', len(listings))}")
    for lst in listings:
        print(f"  • Published Listing     : `{lst.get('name', '').split('/')[-1]}` -> {lst.get('displayName')}")
        print(f"  • Shared Publisher DS   : `{lst.get('bigqueryDataset', {}).get('dataset')}` (Authorized View: `vw_analyticshub_merchant_spend_aggregations`)")
        print(f"  • Listing State         : ✅ {lst.get('state', 'ACTIVE')}")
    print(f"  • Subscriber Search URL : {search_url}")
    print("==========================================================================")

    render_html(
        f'<div style="margin-top:8px;padding:12px 16px;background:#e8f0fe;border-left:4px solid #1a73e8;border-radius:4px;font-family:sans-serif;font-size:13px;line-height:1.6;">'
        f'🔗 <b>Action Required Before Running Step 2.2 — Subscribe to Listing to Create Linked Dataset:</b><br>'
        f'1. Open <a href="{search_url}" target="_blank" rel="noopener noreferrer" style="color:#ffffff;background:#1a73e8;padding:5px 12px;border-radius:4px;text-decoration:none;font-weight:bold;display:inline-block;margin:4px 0;">🔍 Open Published Listings (queryText=AEON) ↗</a> &nbsp;|&nbsp; '
        f'<a href="{publisher_view_url}" target="_blank" rel="noopener noreferrer" style="color:#1a73e8;font-weight:bold;">Inspect Shared Publisher View (acsm_analyticshub_shared) ↗</a><br>'
        f'2. In the Published Listings results, click the card <b><code>ACSM_Merchant_Spend_Zero_Copy_Listing</code></b>.<br>'
        f'3. Click <b>+ Subscribe</b>, keep the default Linked Dataset name <b><code>acsm_merchant_spend_zero_copy_listing</code></b> in project <code>{PROJECT_ID}</code>, and click <b>Save</b>.<br>'
        f'4. Verify the new Linked Dataset (🔗 <code>acsm_merchant_spend_zero_copy_listing</code>) appears in BigQuery Studio (containing ONLY <code>vw_analyticshub_merchant_spend_aggregations</code>), then run <b>Step 2.2</b> below!'
        f'</div>'
    )


def setup_cleanroom(project_id: str, location: str):
    PROJECT_ID, LOCATION, ah_session, bq_client = get_clients(project_id, location)
    base_ah_url = f"https://analyticshub.googleapis.com/v1/projects/{PROJECT_ID}/locations/{LOCATION}/dataExchanges"

    # 0. Authorize `acsm_cleanroom` (targetTypes: ["VIEWS"]) on Party 1 (`acsm_bronze`) and Party 2 (`aeon_retail`)
    dcr_auth_entry = bigquery.AccessEntry(
        role=None,
        entity_type="dataset",
        entity_id={
            "dataset": {"projectId": PROJECT_ID, "datasetId": "acsm_cleanroom"},
            "targetTypes": ["VIEWS"],
        },
    )
    for src_ds_id in ("acsm_bronze", "aeon_retail"):
        src_ds = bq_client.get_dataset(f"{PROJECT_ID}.{src_ds_id}")
        entries = list(src_ds.access_entries)
        if not any(
            e.entity_type == "dataset"
            and isinstance(e.entity_id, dict)
            and e.entity_id.get("dataset", {}).get("datasetId") == "acsm_cleanroom"
            for e in entries
        ):
            entries.append(dcr_auth_entry)
            src_ds.access_entries = entries
            bq_client.update_dataset(src_ds, ["access_entries"])

    # 1. Create or Verify BigQuery Data Clean Room (`dcrExchangeConfig`) in Singapore (asia-southeast1)
    dcr_id = "acsm_aeon_cleanroom_exchange"
    dcr_url = f"{base_ah_url}/{dcr_id}"
    if ah_session.get(dcr_url).status_code == 404:
        dcr_resp = ah_session.post(
            f"{base_ah_url}?dataExchangeId={dcr_id}",
            json={
                "displayName": "ACSM_AEON_Retail_Data_Clean_Room",
                "description": "BNM RMiT & Malaysian PDPA-compliant Data Clean Room between ACSM and AEON Supermarket Loyalty in Singapore (asia-southeast1).",
                "primaryContact": "data-governance@aeoncredit.com.my",
                "sharingEnvironmentConfig": {"dcrExchangeConfig": {}},
            },
        )
        if dcr_resp.status_code not in (200, 409):
            print(f"⚠️ Data Clean Room creation status ({dcr_resp.status_code}): {dcr_resp.text}")

    # 2. Publish or Verify Privacy-Restricted Clean Room Listing (`restrictedExportConfig.enabled=True`)
    dcr_listing_id = "acsm_aeon_joint_customer_cleanroom_listing"
    dcr_list_url = f"{dcr_url}/listings/{dcr_listing_id}"
    if ah_session.get(dcr_list_url).status_code == 404:
        dcr_list_resp = ah_session.post(
            f"{dcr_url}/listings?listingId={dcr_listing_id}",
            json={
                "displayName": "ACSM & AEON Retail Joint Customer Spend",
                "description": "Clean Room privacy-enforced view joining ACSM Cardholders and AEON Supermarket Loyalty Shoppers with k>=20 aggregation threshold.",
                "primaryContact": "data-governance@aeoncredit.com.my",
                "bigqueryDataset": {
                    "dataset": f"projects/{PROJECT_ID}/datasets/acsm_cleanroom",
                    "selectedResources": [
                        {"table": f"projects/{PROJECT_ID}/datasets/acsm_cleanroom/tables/vw_cleanroom_joint_customer_spend"}
                    ],
                },
                "restrictedExportConfig": {
                    "enabled": True,
                    "restrictQueryResult": False,
                },
            },
        )
        if dcr_list_resp.status_code not in (200, 409):
            print(f"⚠️ Clean Room Listing creation status ({dcr_list_resp.status_code}): {dcr_list_resp.text}")

    dcr_info = ah_session.get(dcr_url).json()
    dcr_listings = ah_session.get(f"{dcr_url}/listings").json().get("listings", [])

    search_url = (
        f"https://console.cloud.google.com/bigquery/analytics-hub/exchanges"
        f";cameo=analyticshub;pageName=search;pageResource="
        f"?project={PROJECT_ID}&visibility=&queryText=AEON"
    )
    dcr_console_url = f"https://console.cloud.google.com/bigquery/analytics-hub/clean-rooms?project={PROJECT_ID}"

    print("==========================================================================")
    print(f"🛡️ [Step 3.1 Outcome] BigQuery Data Clean Room (`{dcr_id}`)")
    print("==========================================================================")
    print(f"  • Clean Room Resource   : `{dcr_info.get('name')}`")
    print(f"  • Display Name          : {dcr_info.get('displayName')}")
    print(f"  • Environment Config    : `dcrExchangeConfig` (Data Clean Room Mode Enabled)")
    print(f"  • Party 1 Source (ACSM) : `acsm_bronze.m3CIF` + `acsm_bronze.Fact_CC_Sales`")
    print(f"  • Party 2 Source (AEON) : `aeon_retail.partner_aeon_retail_shoppers`")
    for lst in dcr_listings:
        print(f"  • Clean Room Listing    : `{lst.get('name', '').split('/')[-1]}` -> {lst.get('displayName')}")
        print(f"  • Egress / Direct Access: `restrictDirectTableAccess={lst.get('restrictedExportConfig', {}).get('restrictDirectTableAccess', True)}`")
    print(f"  • Subscriber Search URL : {search_url}")
    print("--------------------------------------------------------------------------")
    print("📦 Clean Room View in `acsm_cleanroom` & Partner Table in `aeon_retail`:")
    subprocess.run(["bq", "ls", f"--location={LOCATION}", f"{PROJECT_ID}:acsm_cleanroom"], check=False)
    subprocess.run(["bq", "ls", f"--location={LOCATION}", f"{PROJECT_ID}:aeon_retail"], check=False)

    render_html(
        f'<div style="margin-top:8px;padding:12px 16px;background:#e8f0fe;border-left:4px solid #1a73e8;border-radius:4px;font-family:sans-serif;font-size:13px;line-height:1.6;">'
        f'🔗 <b>Action Required Before Running Step 3.2 — Subscribe to Clean Room to Create Linked Dataset:</b><br>'
        f'1. Open <a href="{search_url}" target="_blank" rel="noopener noreferrer" style="color:#ffffff;background:#1a73e8;padding:5px 12px;border-radius:4px;text-decoration:none;font-weight:bold;display:inline-block;margin:4px 0;">🔍 Open Published Listings (queryText=AEON) ↗</a> &nbsp;|&nbsp; '
        f'<a href="{dcr_console_url}" target="_blank" rel="noopener noreferrer" style="color:#1a73e8;font-weight:bold;">Data Clean Rooms Console ↗</a><br>'
        f'2. In the Published Listings results, click the Clean Room card <b><code>ACSM_AEON_Retail_Data_Clean_Room</code></b> &rarr; click <b>+ Subscribe</b> (top bar).<br>'
        f'3. Keep the default Linked Dataset name <b><code>acsm_aeon_retail_data_clean_room</code></b> in project <code>{PROJECT_ID}</code> (enter any Subscription Name, e.g. <code>acsm_aeon_cleanroom_sub</code>) and click <b>Save</b>.<br>'
        f'4. Verify the Clean Room Linked Dataset (🔗 <code>acsm_aeon_retail_data_clean_room</code>) appears in BigQuery Studio, then run <b>Step 3.2</b> below!'
        f'</div>'
    )


def main():
    parser = argparse.ArgumentParser(description="Analytics Hub & Data Clean Room Helper")
    parser.add_argument(
        "command",
        nargs="?",
        choices=["setup-exchange", "setup-cleanroom"],
        help="Action to execute: setup-exchange or setup-cleanroom",
    )
    parser.add_argument(
        "--action",
        choices=["setup-exchange", "setup-cleanroom"],
        help="Action to execute: setup-exchange or setup-cleanroom",
    )
    parser.add_argument("--project", default="", help="GCP Project ID")
    parser.add_argument("--location", default="asia-southeast1", help="BigQuery / Analytics Hub region")
    args = parser.parse_args()

    action = args.action or args.command
    if action == "setup-exchange":
        setup_exchange(args.project, args.location)
    elif action == "setup-cleanroom":
        setup_cleanroom(args.project, args.location)
    else:
        parser.error("Please specify either 'setup-exchange' or 'setup-cleanroom'")


if __name__ == "__main__":
    main()
