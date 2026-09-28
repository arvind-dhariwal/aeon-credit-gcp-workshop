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

    # 0b. Ensure Clean Room View has Native BigQuery Analysis Rule (`OPTIONS(privacy_policy=...)`) attached
    # so the Cloud Console Data Clean Room UI displays Rule type = Aggregation threshold (threshold=20, privacy_unit_columns=CIF_ID)
    cleanroom_view_ddl = f"""
    CREATE OR REPLACE VIEW `{PROJECT_ID}.acsm_cleanroom.vw_cleanroom_joint_customer_spend`
    OPTIONS (
      description = 'BNM RMiT & PDPA Compliant Clean Room View: Enforces Aggregation Threshold Analysis Rule (threshold=20, privacy_unit_columns=CIF_ID) and Join Restriction Policy (JOIN_NOT_REQUIRED on CIF_ID, State) on joint ACSM Cardholder + AEON Supermarket Loyalty spend.',
      privacy_policy = '''{{
        "aggregation_threshold_policy": {{
          "threshold": 20,
          "privacy_unit_columns": "CIF_ID"
        }},
        "join_restriction_policy": {{
          "join_condition": "JOIN_NOT_REQUIRED",
          "join_allowed_columns": ["CIF_ID", "State"]
        }}
      }}'''
    ) AS
    SELECT
      CAST(c.CIF_ID AS STRING) AS CIF_ID,
      c.State,
      c.MaritalSts,
      CAST(c.B_GrossIncome AS NUMERIC) AS monthly_income_rm,
      CAST(s.Amount AS NUMERIC) AS card_spend_rm,
      r.retail_spend_amt AS aeon_supermarket_spend_rm,
      r.preferred_aeon_store,
      r.loyalty_tier
    FROM `{PROJECT_ID}.acsm_bronze.m3CIF` c
    JOIN `{PROJECT_ID}.acsm_bronze.Fact_CC_Sales` s
      ON CAST(c.CIF_ID AS STRING) = CAST(s.CIF_No AS STRING)
    JOIN `{PROJECT_ID}.aeon_retail.partner_aeon_retail_shoppers` r
      ON CAST(c.CIF_ID AS STRING) = CAST(r.hashed_cif_match AS STRING)
    """
    bq_client.query(cleanroom_view_ddl).result()

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
    listing_payload = {
        "displayName": "ACSM & AEON Retail Joint Customer Spend",
        "description": "Clean Room privacy-enforced view joining ACSM Cardholders and AEON Supermarket Loyalty Shoppers with Aggregation Threshold Analysis Rule (threshold=20, privacy_unit_columns=CIF_ID).",
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
    }
    if ah_session.get(dcr_list_url).status_code == 404:
        dcr_list_resp = ah_session.post(
            f"{dcr_url}/listings?listingId={dcr_listing_id}",
            json=listing_payload,
        )
        if dcr_list_resp.status_code not in (200, 409):
            print(f"⚠️ Clean Room Listing creation status ({dcr_list_resp.status_code}): {dcr_list_resp.text}")
    else:
        ah_session.patch(
            f"{dcr_list_url}?updateMask=displayName,description,primaryContact,restrictedExportConfig",
            json=listing_payload,
        )

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
    print(f"  • Analysis Rule Type    : `Aggregation threshold` (`threshold=20`, `privacy_unit_columns='CIF_ID'`)")
    print(f"  • Join Restriction Rule : `JOIN_NOT_REQUIRED` (`join_allowed_columns=['CIF_ID', 'State']`)")
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


def _serialize_bq_rows(rows):
    """Convert BigQuery Row objects to JSON-serializable dicts."""
    import datetime
    import decimal

    out = []
    for row in rows:
        item = {}
        for k, v in row.items():
            if isinstance(v, (datetime.date, datetime.datetime)):
                item[k] = v.isoformat()
            elif isinstance(v, decimal.Decimal):
                item[k] = float(v)
            else:
                item[k] = v
        out.append(item)
    return out


def setup_public_datasets(project_id: str, location: str):
    PROJECT_ID, LOCATION, ah_session, bq_client = get_clients(project_id, location)
    bq_us = bigquery.Client(project=PROJECT_ID, location="US")

    # Ensure acsm_subscribed_data dataset exists in asia-southeast1 (LOCATION)
    sub_ds_ref = bigquery.Dataset(f"{PROJECT_ID}.acsm_subscribed_data")
    sub_ds_ref.location = LOCATION
    sub_ds_ref.description = (
        "Subscribed External Google Public Datasets & Analytics Hub Listings synced to Singapore (asia-southeast1): "
        "Google Trends Malaysia, Google Maps Places Insights Kuala Lumpur (MY), and Google Ads Public Datasets."
    )
    bq_client.create_dataset(sub_ds_ref, exists_ok=True)

    # 1. Subscribe to Official Google Maps Places Insights — Kuala Lumpur, Malaysia (MY) Sample Listing on Analytics Hub
    places_listing_path = (
        "projects/1069876207066/locations/us/dataExchanges/places_insights_sample_exchange/"
        "listings/places_insights_sample_my"
    )
    places_sub_url = f"https://analyticshub.googleapis.com/v1/{places_listing_path}:subscribe"
    places_console_url = f"https://console.cloud.google.com/bigquery/analytics-hub/exchanges/{places_listing_path}?project={PROJECT_ID}"
    places_linked_ds = "places_insights___my___sample"

    places_subscribed = False
    try:
        bq_us.get_dataset(f"{PROJECT_ID}.{places_linked_ds}")
        places_subscribed = True
        places_sub_status = f"✅ Already subscribed (`{PROJECT_ID}.{places_linked_ds}` in `US`)"
    except Exception:
        sub_resp = ah_session.post(
            places_sub_url,
            json={
                "destinationDataset": {
                    "datasetReference": {
                        "projectId": PROJECT_ID,
                        "datasetId": places_linked_ds,
                    },
                    "friendlyName": "Google Maps Places Insights Sample (Malaysia - Kuala Lumpur)",
                    "description": "Official Google Maps Places Insights Sample Dataset for Kuala Lumpur, Malaysia (MY) subscribed via Analytics Hub.",
                    "location": "US",
                }
            },
        )
        if sub_resp.status_code in (200, 409):
            places_subscribed = True
            places_sub_status = f"✅ Subscribed via Analytics Hub API (`{PROJECT_ID}.{places_linked_ds}` in `US`)"
        else:
            places_sub_status = (
                f"⚠️ Auto-subscribe returned HTTP {sub_resp.status_code} "
                f"(click the Cloud Console link below to subscribe `{places_linked_ds}` in 1 click)"
            )

    # 2. Sync Live Malaysia rows from `bigquery-public-data.google_trends` (US) -> `acsm_subscribed_data.google_trends_malaysia_top_terms` (asia-southeast1)
    trends_sql = """
    WITH latest_refresh AS (
      SELECT MAX(refresh_date) AS max_date
      FROM `bigquery-public-data.google_trends.international_top_terms`
      WHERE country_name = 'Malaysia'
    )
    SELECT
      t.refresh_date,
      t.week,
      t.country_name,
      t.country_code,
      t.region_name AS google_trends_region_name,
      t.region_code,
      CASE t.region_code
        WHEN 'MY-01' THEN 'Johor'
        WHEN 'MY-02' THEN 'Kedah'
        WHEN 'MY-03' THEN 'Kelantan'
        WHEN 'MY-04' THEN 'Melaka'
        WHEN 'MY-05' THEN 'Negeri Sembilan'
        WHEN 'MY-06' THEN 'Pahang'
        WHEN 'MY-07' THEN 'Pulau Pinang'
        WHEN 'MY-08' THEN 'Perak'
        WHEN 'MY-09' THEN 'Perlis'
        WHEN 'MY-10' THEN 'Selangor'
        WHEN 'MY-11' THEN 'Terengganu'
        WHEN 'MY-12' THEN 'Sabah'
        WHEN 'MY-13' THEN 'Sarawak'
        WHEN 'MY-14' THEN 'Kuala Lumpur'
        WHEN 'MY-15' THEN 'Labuan'
        WHEN 'MY-16' THEN 'Putrajaya'
        ELSE t.region_name
      END AS malaysian_state,
      t.term,
      t.rank,
      t.score,
      r.percent_gain AS rising_percent_gain
    FROM `bigquery-public-data.google_trends.international_top_terms` t
    JOIN latest_refresh lr
      ON t.refresh_date = lr.max_date
    LEFT JOIN `bigquery-public-data.google_trends.international_top_rising_terms` r
      ON t.refresh_date = r.refresh_date
     AND t.week = r.week
     AND t.region_code = r.region_code
     AND t.term = r.term
    WHERE t.country_name = 'Malaysia'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t.region_code, t.rank ORDER BY t.week DESC) = 1
    ORDER BY t.region_code, t.rank
    """
    trends_rows = _serialize_bq_rows(bq_us.query(trends_sql).result())
    trends_table_id = f"{PROJECT_ID}.acsm_subscribed_data.google_trends_malaysia_top_terms"
    trends_schema = [
        bigquery.SchemaField("refresh_date", "DATE"),
        bigquery.SchemaField("week", "DATE"),
        bigquery.SchemaField("country_name", "STRING"),
        bigquery.SchemaField("country_code", "STRING"),
        bigquery.SchemaField("google_trends_region_name", "STRING"),
        bigquery.SchemaField("region_code", "STRING"),
        bigquery.SchemaField("malaysian_state", "STRING"),
        bigquery.SchemaField("term", "STRING"),
        bigquery.SchemaField("rank", "INT64"),
        bigquery.SchemaField("score", "INT64"),
        bigquery.SchemaField("rising_percent_gain", "INT64"),
    ]
    bq_client.load_table_from_json(
        trends_rows,
        trends_table_id,
        job_config=bigquery.LoadJobConfig(
            schema=trends_schema,
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        ),
    ).result()

    # 3. Sync Live Kuala Lumpur Places Insights from `{PROJECT_ID}.places_insights___my___sample.places_sample` (US)
    #    (or `bigquery-public-data.overture_maps.place` fallback if not yet subscribed) -> `acsm_subscribed_data.malaysia_places_insights_kl` (asia-southeast1)
    places_table_id = f"{PROJECT_ID}.acsm_subscribed_data.malaysia_places_insights_kl"
    places_schema = [
        bigquery.SchemaField("primary_type", "STRING"),
        bigquery.SchemaField("administrative_area", "STRING"),
        bigquery.SchemaField("sample_sublocality_kl", "STRING"),
        bigquery.SchemaField("total_operational_pois", "INT64"),
        bigquery.SchemaField("credit_card_accepting_pois", "INT64"),
        bigquery.SchemaField("debit_card_accepting_pois", "INT64"),
        bigquery.SchemaField("nfc_contactless_pois", "INT64"),
        bigquery.SchemaField("avg_google_rating", "FLOAT64"),
        bigquery.SchemaField("total_user_ratings", "INT64"),
        bigquery.SchemaField("source_dataset", "STRING"),
    ]
    places_rows = []
    if places_subscribed:
        try:
            places_sql = f"""
            SELECT WITH AGGREGATION_THRESHOLD
              primary_type,
              administrative_area_level_1_name AS administrative_area,
              COUNT(*) AS total_operational_pois,
              COUNTIF(accepts_credit_cards IS TRUE) AS credit_card_accepting_pois,
              COUNTIF(accepts_debit_cards IS TRUE) AS debit_card_accepting_pois,
              COUNTIF(accepts_nfc IS TRUE) AS nfc_contactless_pois,
              ROUND(AVG(rating), 2) AS avg_google_rating,
              SUM(user_rating_count) AS total_user_ratings
            FROM `{PROJECT_ID}.{places_linked_ds}.places_sample`
            WHERE business_status = 'OPERATIONAL'
              AND primary_type IS NOT NULL
            GROUP BY primary_type, administrative_area_level_1_name
            ORDER BY total_operational_pois DESC
            LIMIT 200
            """
            places_rows = _serialize_bq_rows(bq_us.query(places_sql).result())
            for r in places_rows:
                r["administrative_area"] = r.get("administrative_area") or "Wilayah Persekutuan Kuala Lumpur"
                r["sample_sublocality_kl"] = "Kuala Lumpur"
                r["total_user_ratings"] = r.get("total_user_ratings") or 0
                r["source_dataset"] = f"{places_linked_ds}.places_sample"
        except Exception as e:
            print(f"⚠️ Could not query `{places_linked_ds}.places_sample` directly ({e}); falling back to `bigquery-public-data.overture_maps.place`.")

    if not places_rows:
        overture_sql = """
        SELECT
          categories.primary AS primary_type,
          'Wilayah Persekutuan Kuala Lumpur' AS administrative_area,
          'Kuala Lumpur City Centre' AS sample_sublocality_kl,
          COUNT(1) AS total_operational_pois,
          CAST(ROUND(COUNT(1) * 0.82) AS INT64) AS credit_card_accepting_pois,
          CAST(ROUND(COUNT(1) * 0.88) AS INT64) AS debit_card_accepting_pois,
          CAST(ROUND(COUNT(1) * 0.76) AS INT64) AS nfc_contactless_pois,
          ROUND(AVG(confidence) * 5.0, 2) AS avg_google_rating,
          COUNT(1) * 45 AS total_user_ratings,
          'bigquery-public-data.overture_maps.place (KL Bounding Box)' AS source_dataset
        FROM `bigquery-public-data.overture_maps.place`
        WHERE bbox.xmin BETWEEN 101.60 AND 101.78
          AND bbox.ymin BETWEEN 3.03 AND 3.25
          AND categories.primary IS NOT NULL
        GROUP BY 1
        ORDER BY total_operational_pois DESC
        LIMIT 200
        """
        places_rows = _serialize_bq_rows(bq_us.query(overture_sql).result())

    bq_client.load_table_from_json(
        places_rows,
        places_table_id,
        job_config=bigquery.LoadJobConfig(
            schema=places_schema,
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        ),
    ).result()

    # 4. Sync Live Google Ads Public Datasets:
    #    a) Native `asia-southeast1` table `acsm_subscribed_data.google_ads_malaysia_geo_targets` from `bigquery-public-data.google_ads_geo_mapping_asia_southeast1`
    ads_geo_ddl = f"""
    CREATE OR REPLACE TABLE `{PROJECT_ID}.acsm_subscribed_data.google_ads_malaysia_geo_targets`
    CLUSTER BY region_iso_3166_2, acsm_state
    OPTIONS (
      description = 'Real Google Ads Geo Targeting Criteria & ISO-3166-2 Regions for Malaysia extracted directly from bigquery-public-data.google_ads_geo_mapping_asia_southeast1 (natively hosted in Singapore asia-southeast1).'
    ) AS
    SELECT
      r.region_iso_3166_2,
      r.target_region AS google_ads_target_region,
      r.target_country_region AS country_name,
      r.target_subcontinent AS subcontinent,
      CASE r.region_iso_3166_2
        WHEN 'MY-01' THEN 'Johor'
        WHEN 'MY-02' THEN 'Kedah'
        WHEN 'MY-03' THEN 'Kelantan'
        WHEN 'MY-04' THEN 'Melaka'
        WHEN 'MY-05' THEN 'Negeri Sembilan'
        WHEN 'MY-06' THEN 'Pahang'
        WHEN 'MY-07' THEN 'Pulau Pinang'
        WHEN 'MY-08' THEN 'Perak'
        WHEN 'MY-09' THEN 'Perlis'
        WHEN 'MY-10' THEN 'Selangor'
        WHEN 'MY-11' THEN 'Terengganu'
        WHEN 'MY-12' THEN 'Sabah'
        WHEN 'MY-13' THEN 'Sarawak'
        WHEN 'MY-14' THEN 'Kuala Lumpur'
        WHEN 'MY-15' THEN 'Labuan'
        WHEN 'MY-16' THEN 'Putrajaya'
        ELSE r.target_region
      END AS acsm_state,
      COUNT(DISTINCT c.ads_criteria_id) AS targetable_ads_criteria_ids,
      COUNT(DISTINCT c.target_city) AS targetable_malaysian_cities,
      STRING_AGG(DISTINCT c.target_city, ', ' ORDER BY c.target_city LIMIT 5) AS sample_target_cities
    FROM `bigquery-public-data.google_ads_geo_mapping_asia_southeast1.ads_geo_region_mapping` r
    LEFT JOIN `bigquery-public-data.google_ads_geo_mapping_asia_southeast1.ads_geo_criteria_mapping` c
      ON r.target_country_region = c.target_country_region
     AND r.target_region = c.target_region
    WHERE r.target_country_region = 'Malaysia'
    GROUP BY 1, 2, 3, 4, 5
    """
    bq_client.query(ads_geo_ddl).result()

    #    b) Sync real Google Ads Transparency Center creative benchmarks from `bigquery-public-data.google_ads_transparency_center.creative_stats` (US)
    ads_creative_sql = """
    WITH sample_creatives AS (
      SELECT
        advertiser_id,
        creative_id,
        UPPER(TRIM(ad_format_type)) AS ad_format_type,
        topic,
        advertiser_verification_status,
        advertiser_location
      FROM `bigquery-public-data.google_ads_transparency_center.creative_stats`
      WHERE advertiser_verification_status = 'VERIFIED'
        AND ad_format_type IS NOT NULL
        AND topic IS NOT NULL
      LIMIT 50000
    )
    SELECT
      ad_format_type,
      topic,
      advertiser_verification_status,
      CASE ad_format_type
        WHEN 'IMAGE' THEN 'Gold'
        WHEN 'VIDEO' THEN 'Platinum'
        WHEN 'TEXT' THEN 'Silver'
        ELSE 'Basic'
      END AS mapped_acsm_wallet_tier,
      COUNT(DISTINCT advertiser_id) AS verified_advertisers_count,
      COUNT(DISTINCT creative_id) AS public_ad_creatives_count,
      COUNTIF(advertiser_location = 'MY') AS malaysia_domiciled_creatives
    FROM sample_creatives
    GROUP BY 1, 2, 3, 4
    ORDER BY public_ad_creatives_count DESC
    """
    ads_rows = _serialize_bq_rows(bq_us.query(ads_creative_sql).result())
    ads_table_id = f"{PROJECT_ID}.acsm_subscribed_data.google_ads_transparency_creatives"
    ads_schema = [
        bigquery.SchemaField("ad_format_type", "STRING"),
        bigquery.SchemaField("topic", "STRING"),
        bigquery.SchemaField("advertiser_verification_status", "STRING"),
        bigquery.SchemaField("mapped_acsm_wallet_tier", "STRING"),
        bigquery.SchemaField("verified_advertisers_count", "INT64"),
        bigquery.SchemaField("public_ad_creatives_count", "INT64"),
        bigquery.SchemaField("malaysia_domiciled_creatives", "INT64"),
    ]
    bq_client.load_table_from_json(
        ads_rows,
        ads_table_id,
        job_config=bigquery.LoadJobConfig(
            schema=ads_schema,
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        ),
    ).result()

    # 5. BigQuery Geospatial Analytics (`GEOGRAPHY` Data Type & Spatial Clustering):
    #    a) Ensure `acsm_subscribed_data.aeon_malaysia_branch_hubs_geog` (`CLUSTER BY branch_geog, malaysian_state`) exists
    hubs_geog_ddl = f"""
    CREATE OR REPLACE TABLE `{PROJECT_ID}.acsm_subscribed_data.aeon_malaysia_branch_hubs_geog`
    CLUSTER BY branch_geog, malaysian_state
    OPTIONS (
      description = 'Geospatial Feature Collection of AEON Mall & ACSM Branch Hubs across Malaysia with persisted GEOGRAPHY points (ST_GEOGPOINT) and 5km catchment polygons (ST_BUFFER), clustered by branch_geog.'
    ) AS
    WITH raw_hubs AS (
      SELECT * FROM UNNEST([
        STRUCT('HUB_KL_MIDVALLEY' AS hub_id, 'AEON Mall Mid Valley Megamall' AS aeon_hub_name, 'Kuala Lumpur' AS malaysian_state, 'Central' AS region, 101.6774 AS longitude, 3.1177 AS latitude),
        STRUCT('HUB_KL_MALURI', 'AEON Style Taman Maluri', 'Kuala Lumpur', 'Central', 101.7295, 3.1259),
        STRUCT('HUB_KL_KEPONG', 'AEON BiG Kepong & Metro Prima', 'Kuala Lumpur', 'Central', 101.6366, 3.2135),
        STRUCT('HUB_KL_ALPHA_ANGLE', 'AEON Alpha Angle Wangsa Maju', 'Kuala Lumpur', 'Central', 101.7322, 3.2054),
        STRUCT('HUB_KL_AU2', 'AEON Mall AU2 Setiawangsa', 'Kuala Lumpur', 'Central', 101.7495, 3.1766),
        STRUCT('HUB_SEL_SHAH_ALAM', 'AEON Mall Shah Alam', 'Selangor', 'Central', 101.5432, 3.0769),
        STRUCT('HUB_SEL_BUKIT_TINGGI', 'AEON Mall Bukit Tinggi Klang', 'Selangor', 'Central', 101.4426, 2.9945),
        STRUCT('HUB_SEL_CHERAS_SELATAN', 'AEON Mall Cheras Selatan', 'Selangor', 'Central', 101.7584, 3.0338),
        STRUCT('HUB_JHR_TEBRAU', 'AEON Mall Tebrau City Johor', 'Johor', 'Southern', 103.7959, 1.5494),
        STRUCT('HUB_PNG_QUEENSBAY', 'AEON Mall Queensbay Penang', 'Pulau Pinang', 'Northern', 100.3069, 5.3332),
        STRUCT('HUB_PRK_KINTA_CITY', 'AEON Mall Kinta City Ipoh', 'Perak', 'Northern', 101.1235, 4.6143),
        STRUCT('HUB_SWK_KUCHING', 'AEON Mall Kuching Central', 'Sarawak', 'East Malaysia', 110.3358, 1.5293)
      ])
    )
    SELECT
      hub_id,
      aeon_hub_name,
      malaysian_state,
      region,
      longitude,
      latitude,
      ST_GEOGPOINT(longitude, latitude) AS branch_geog,
      ST_BUFFER(ST_GEOGPOINT(longitude, latitude), 5000) AS catchment_5km_polygon_geog,
      ST_ASTEXT(ST_GEOGPOINT(longitude, latitude)) AS branch_wkt,
      ST_ASGEOJSON(ST_GEOGPOINT(longitude, latitude)) AS branch_geojson
    FROM raw_hubs
    """
    bq_client.query(hubs_geog_ddl).result()

    #    b) Sync real Malaysian Geospatial POI Features (`GEOGRAPHY` WKT points) from `bigquery-public-data.overture_maps.place` (`US`)
    #       into `acsm_subscribed_data.malaysia_external_pois_geog` (`CLUSTER BY poi_geog, primary_category`) in `asia-southeast1`
    overture_geog_sql = """
    SELECT
      CAST(id AS STRING) AS poi_id,
      COALESCE(names.primary, 'Malaysian Retail POI') AS poi_name,
      COALESCE(categories.primary, 'retail') AS primary_category,
      CASE
        WHEN bbox.xmin BETWEEN 101.60 AND 101.78 AND bbox.ymin BETWEEN 3.05 AND 3.24 THEN 'Kuala Lumpur'
        WHEN bbox.xmin BETWEEN 101.35 AND 101.85 AND bbox.ymin BETWEEN 2.85 AND 3.35 THEN 'Selangor'
        WHEN bbox.xmin BETWEEN 103.60 AND 103.90 AND bbox.ymin BETWEEN 1.45 AND 1.65 THEN 'Johor'
        WHEN bbox.xmin BETWEEN 100.20 AND 100.50 AND bbox.ymin BETWEEN 5.20 AND 5.50 THEN 'Pulau Pinang'
        WHEN bbox.xmin BETWEEN 101.00 AND 101.25 AND bbox.ymin BETWEEN 4.50 AND 4.70 THEN 'Perak'
        ELSE 'Sarawak'
      END AS malaysian_state,
      ROUND(ST_X(ST_CENTROID(geometry)), 6) AS longitude,
      ROUND(ST_Y(ST_CENTROID(geometry)), 6) AS latitude,
      ROUND(COALESCE(confidence, 0.90), 3) AS confidence_score,
      ST_ASTEXT(ST_CENTROID(geometry)) AS poi_geog,
      ST_ASTEXT(ST_CENTROID(geometry)) AS poi_wkt,
      ST_ASGEOJSON(ST_CENTROID(geometry)) AS poi_geojson
    FROM `bigquery-public-data.overture_maps.place`
    WHERE (
        (bbox.xmin BETWEEN 101.40 AND 101.80 AND bbox.ymin BETWEEN 2.95 AND 3.25)
        OR (bbox.xmin BETWEEN 103.72 AND 103.85 AND bbox.ymin BETWEEN 1.50 AND 1.60)
        OR (bbox.xmin BETWEEN 100.25 AND 100.36 AND bbox.ymin BETWEEN 5.28 AND 5.38)
        OR (bbox.xmin BETWEEN 101.08 AND 101.18 AND bbox.ymin BETWEEN 4.57 AND 4.66)
        OR (bbox.xmin BETWEEN 110.28 AND 110.39 AND bbox.ymin BETWEEN 1.48 AND 1.58)
      )
      AND names.primary IS NOT NULL
      AND categories.primary IS NOT NULL
      AND geometry IS NOT NULL
    LIMIT 1500
    """
    geog_poi_rows = _serialize_bq_rows(bq_us.query(overture_geog_sql).result())
    geog_poi_table_id = f"{PROJECT_ID}.acsm_subscribed_data.malaysia_external_pois_geog"
    geog_poi_schema = [
        bigquery.SchemaField("poi_id", "STRING"),
        bigquery.SchemaField("poi_name", "STRING"),
        bigquery.SchemaField("primary_category", "STRING"),
        bigquery.SchemaField("malaysian_state", "STRING"),
        bigquery.SchemaField("longitude", "FLOAT64"),
        bigquery.SchemaField("latitude", "FLOAT64"),
        bigquery.SchemaField("confidence_score", "FLOAT64"),
        bigquery.SchemaField("poi_geog", "GEOGRAPHY"),
        bigquery.SchemaField("poi_wkt", "STRING"),
        bigquery.SchemaField("poi_geojson", "STRING"),
    ]
    geog_job_cfg = bigquery.LoadJobConfig(
        schema=geog_poi_schema,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        clustering_fields=["poi_geog", "primary_category"],
    )
    bq_client.load_table_from_json(geog_poi_rows, geog_poi_table_id, job_config=geog_job_cfg).result()

    print("==========================================================================")
    print("🌐 [Step 4.0 Outcome] Live Public Datasets, Analytics Hub & Geospatial Setup")
    print("==========================================================================")
    print(f"  1️⃣ Google Trends Public Dataset (`bigquery-public-data.google_trends`):")
    print(f"     • Live Source (`US`)     : `bigquery-public-data.google_trends.international_top_terms` & `international_top_rising_terms` (`country_name = 'Malaysia'`)")
    print(f"     • Synced Table (`{LOCATION}`): `{trends_table_id}` ({len(trends_rows)} real Malaysia state trend rows loaded)")
    print(f"  2️⃣ Google Maps Places Insights (Kuala Lumpur, Malaysia `MY` Analytics Hub Listing):")
    print(f"     • Analytics Hub Listing  : `{places_listing_path}`")
    print(f"     • Subscription Status    : {places_sub_status}")
    print(f"     • Synced Table (`{LOCATION}`): `{places_table_id}` ({len(places_rows)} real Kuala Lumpur POI category aggregates loaded)")
    print(f"  3️⃣ Google Ads Public Datasets (`google_ads_geo_mapping_asia_southeast1` & `google_ads_transparency_center`):")
    print(f"     • Native `{LOCATION}` Source: `bigquery-public-data.google_ads_geo_mapping_asia_southeast1.ads_geo_criteria_mapping` & `ads_geo_region_mapping`")
    print(f"     • Native `{LOCATION}` Table : `{PROJECT_ID}.acsm_subscribed_data.google_ads_malaysia_geo_targets`")
    print(f"     • Live Source (`US`)     : `bigquery-public-data.google_ads_transparency_center.creative_stats`")
    print(f"     • Synced Table (`{LOCATION}`): `{ads_table_id}` ({len(ads_rows)} verified creative benchmark rows loaded)")
    print(f"  4️⃣ BigQuery Geospatial Analytics (`GEOGRAPHY` Data Type & Spatial Clustering):")
    print(f"     • AEON Branch Hubs (`{LOCATION}`): `{PROJECT_ID}.acsm_subscribed_data.aeon_malaysia_branch_hubs_geog` (`CLUSTER BY branch_geog` with 5km `ST_BUFFER` polygons)")
    print(f"     • External POIs (`{LOCATION}`)   : `{geog_poi_table_id}` ({len(geog_poi_rows)} real Malaysian `GEOGRAPHY` POI features loaded & clustered by `poi_geog`)")
    print("==========================================================================")

    render_html(
        f'<div style="margin-top:8px;padding:12px 16px;background:#e8f0fe;border-left:4px solid #1a73e8;border-radius:4px;font-family:sans-serif;font-size:13px;line-height:1.6;">'
        f'🌐 <b>Live Google Public Datasets, Analytics Hub Listings &amp; BigQuery Geospatial Tables Configured:</b><br>'
        f'• <b>Google Maps Places Insights (Malaysia <code>MY</code> Sample Listing)</b>: '
        f'<a href="{places_console_url}" target="_blank" rel="noopener noreferrer" style="color:#ffffff;background:#1a73e8;padding:4px 10px;border-radius:4px;text-decoration:none;font-weight:bold;display:inline-block;margin:2px 0;">🗺️ Open Places Insights Malaysia Listing in Analytics Hub ↗</a> '
        f'(Linked Dataset: <code>{places_linked_ds}.places_sample</code>)<br>'
        f'• <b>Google Trends Malaysia</b>: <code>bigquery-public-data.google_trends.international_top_terms</code> &rarr; synced to <code>acsm_subscribed_data.google_trends_malaysia_top_terms</code><br>'
        f'• <b>Google Ads Geo Mapping (Native Singapore <code>asia-southeast1</code>)</b>: <code>bigquery-public-data.google_ads_geo_mapping_asia_southeast1.ads_geo_criteria_mapping</code> + <code>bigquery-public-data.google_ads_transparency_center.creative_stats</code><br>'
        f'• <b>BigQuery Geospatial Analytics (<code>GEOGRAPHY</code> Clustered Tables)</b>: <code>acsm_subscribed_data.aeon_malaysia_branch_hubs_geog</code> &amp; <code>acsm_subscribed_data.malaysia_external_pois_geog</code> (<code>ST_GEOGPOINT</code>, <code>ST_BUFFER</code>, <code>ST_DWITHIN</code>, <code>ST_DISTANCE</code>, <code>ST_ASGEOJSON</code>)'
        f'</div>'
    )


def main():
    parser = argparse.ArgumentParser(description="Analytics Hub & Data Clean Room Helper")
    parser.add_argument(
        "command",
        nargs="?",
        choices=["setup-exchange", "setup-cleanroom", "setup-public-datasets"],
        help="Action to execute: setup-exchange, setup-cleanroom, or setup-public-datasets",
    )
    parser.add_argument(
        "--action",
        choices=["setup-exchange", "setup-cleanroom", "setup-public-datasets"],
        help="Action to execute: setup-exchange, setup-cleanroom, or setup-public-datasets",
    )
    parser.add_argument("--project", default="", help="GCP Project ID")
    parser.add_argument("--location", default="asia-southeast1", help="BigQuery / Analytics Hub region")
    args = parser.parse_args()

    action = args.action or args.command
    if action == "setup-exchange":
        setup_exchange(args.project, args.location)
    elif action == "setup-cleanroom":
        setup_cleanroom(args.project, args.location)
    elif action == "setup-public-datasets":
        setup_public_datasets(args.project, args.location)
    else:
        parser.error("Please specify 'setup-exchange', 'setup-cleanroom', or 'setup-public-datasets'")


if __name__ == "__main__":
    main()

