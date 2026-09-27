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
- **What Happens**: Auto-detects `PROJECT_ID` in `asia-southeast1`, enables `analyticshub.googleapis.com`, and executes [`05_cleanroom_and_external_datasets.sql`](../sql/05_cleanroom_and_external_datasets.sql) to provision `acsm_cleanroom`, `acsm_subscribed_data`, and the zero-copy views (`acsm_gold.vw_analyticshub_merchant_spend_aggregations` and `acsm_cleanroom.vw_cleanroom_joint_customer_spend`).

### Step 2 (Part A): Analytics Hub Zero-Copy Exchange (`acsm_aeon_exchange`)
- **What Happens**:
  1. Uses the **Analytics Hub REST API v1 (`analyticshub.googleapis.com/v1`)** to create the `acsm_aeon_exchange` Data Exchange in `asia-southeast1` and publish the `acsm_merchant_spend_listing` zero-copy listing.
  2. Queries the curated merchant category spend summary (`vw_analyticshub_merchant_spend_aggregations`) shared with AEON Retail without exposing individual cardholder identities.

### Step 3 (Part B): BigQuery Data Clean Room with Privacy-Preserving Thresholds (`k >= 20`)
- **What Happens**:
  1. Creates the BigQuery Data Clean Room exchange (`acsm_aeon_cleanroom_exchange` with `sharingEnvironmentConfig.dcrExchangeConfig`) via `analyticshub.googleapis.com/v1` and publishes the restricted Clean Room listing (`acsm_aeon_joint_customer_cleanroom_listing` with `restrictedExportConfig.enabled = True`) sharing `acsm_cleanroom.vw_cleanroom_joint_customer_spend`.
  2. Executes the privacy-preserving analysis query joining ACSM cardholders (`m3CIF` + `Fact_CC_Sales`) and AEON Retail loyalty shoppers (`partner_aeon_retail_shoppers`), enforcing `HAVING COUNT(DISTINCT c.CIF_ID) >= 20` (`Malaysian PDPA Safe`).

### Step 4 (Part C): External Dataset Enrichment (Google Trends, Places POI & Google Ads)
- **What Happens**:
  1. **Google Search Trends**: Correlates Malaysian state-level search interest for consumer financing terms (`"Easy Payment Motorcycle"`, `"AEON Credit Card"`, `"Gold Financing"`) with ACSM application volume.
  2. **Google Maps / Places POI**: Geospatially enriches ACSM merchant transactions (`Fact_CC_Sales`) with verified merchant ratings, foot-traffic tiers, and coordinates across Kuala Lumpur, Selangor, Penang, and Johor.
  3. **Google Ads Telemetry**: Joins digital acquisition campaign spend and clicks with approved `Fact_CC_Judge` applications to compute **Cost Per Approved Card (CPA)** and **ROAS** by channel.
