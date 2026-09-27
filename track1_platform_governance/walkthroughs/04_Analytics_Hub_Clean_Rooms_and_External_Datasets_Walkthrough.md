# Track 1 (Notebook 04) Walkthrough: Analytics Hub, Data Clean Rooms & External Datasets

**Notebook**: [`04_Analytics_Hub_Clean_Rooms_and_External_Datasets.ipynb`](../notebook/04_Analytics_Hub_Clean_Rooms_and_External_Datasets.ipynb)
**Target Region**: `asia-southeast1` (Singapore)
**ACSM RFP Clauses**: `C1.1.1.11`–`C1.1.1.13`, `C1.1.5.4`, `C1.2.2.2`

---

## 1. Executive Summary & Customer Context

As part of the **One-AEON Malaysia** ecosystem, ACSM collaborates with sister operating companies (**AEON Retail Malaysia / AEON BiG**) to drive cross-entity loyalty and merchant co-marketing while strictly complying with **Malaysian PDPA 2010** (which prohibits sharing raw customer PII across separate legal entities without consent).

This notebook demonstrates 3 zero-copy data sharing and external enrichment patterns in BigQuery:
1. **Part A — Analytics Hub Zero-Copy Cross-Entity Data Sharing**: Publishing curated merchant spend aggregations from ACSM to AEON Retail with zero data duplication.
2. **Part B — BigQuery Data Clean Room (`k >= 20` Aggregation Threshold)**: Privacy-preserving overlap analysis between `acsm_cleanroom.aeon_credit_cardholders` and `acsm_cleanroom.aeon_retail_loyalty_members` using `SELECT WITH AGGREGATION_THRESHOLD` so cohorts with fewer than 20 customers are automatically suppressed.
3. **Part C — Subscribing to External Google Datasets**: Enriching ACSM internal credit & card data with **Google Search Trends**, **Google Maps / Places POI**, and **Google Ads Campaign Telemetry**.

---

## 2. Step-by-Step Walkthrough

### Step 0 & Step 1: Enable Analytics Hub API & Bootstrap Clean Room / External Datasets
- **What Happens**: Auto-detects `PROJECT_ID` in `asia-southeast1`, enables `analyticshub.googleapis.com`, and executes [`04_analytics_hub_cleanroom_and_external_datasets.sql`](../sql/04_analytics_hub_cleanroom_and_external_datasets.sql) to provision `acsm_cleanroom` and `acsm_subscribed_datasets`.

### Step 2 (Part A): Analytics Hub Zero-Copy Exchange (`acsm_one_aeon_exchange`)
- **What Happens**:
  1. Uses `bq mk --data_exchange` to create the `acsm_one_aeon_exchange` Data Exchange in `asia-southeast1`.
  2. Queries the curated merchant category spend summary (`vw_curated_merchant_spend_listing`) shared with AEON Retail without exposing individual cardholder identities.

### Step 3 (Part B): BigQuery Data Clean Room with Privacy-Preserving Thresholds (`k >= 20`)
- **What Happens**:
  1. Creates the Data Clean Room exchange (`acsm_aeon_retail_clean_room`) and verifies the Clean Room view `acsm_cleanroom.vw_cleanroom_one_aeon_overlap` configured with `OPTIONS (privacy_policy = '{"aggregation_threshold_policy": {"threshold": 20, "privacy_unit_columns": "email_sha256"}}')`.
  2. Executes a `SELECT WITH AGGREGATION_THRESHOLDOPTIONS(threshold=20, privacy_unit_column=email_sha256)` query joining ACSM cardholders and AEON Retail loyalty members by `email_sha256`, returning only cohorts with **>= 20 matched customers** (`Malaysian PDPA Safe`).

### Step 4 (Part C): External Dataset Enrichment (Google Trends, Places POI & Google Ads)
- **What Happens**:
  1. **Google Search Trends**: Correlates Malaysian state-level search interest for consumer financing terms (`"Easy Payment Motorcycle"`, `"AEON Credit Card"`, `"Gold Financing"`) with ACSM application volume.
  2. **Google Maps / Places POI**: Geospatially enriches ACSM merchant transactions (`Fact_CC_Sales`) with verified merchant ratings, foot-traffic tiers, and coordinates across Kuala Lumpur, Selangor, Penang, and Johor.
  3. **Google Ads Telemetry**: Joins digital acquisition campaign spend and clicks with approved `Fact_CC_Judge` applications to compute **Cost Per Approved Card (CPA)** and **ROAS** by channel.
