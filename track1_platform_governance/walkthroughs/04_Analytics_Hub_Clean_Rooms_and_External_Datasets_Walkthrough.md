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
- **What Happens**: Auto-detects `PROJECT_ID` in `asia-southeast1`, enables `analyticshub.googleapis.com`, and executes [`05_cleanroom_and_external_datasets.sql`](../sql/05_cleanroom_and_external_datasets.sql) to provision:
  - `acsm_analyticshub_shared`: Dedicated shared publisher dataset containing `vw_analyticshub_merchant_spend_aggregations`
  - `aeon_retail`: Partner dataset representing **AEON Retail Malaysia** (`aeon_retail.partner_aeon_retail_shoppers`)
  - `acsm_cleanroom`: Clean Room dataset containing the privacy-enforced view `acsm_cleanroom.vw_cleanroom_joint_customer_spend`
  - `acsm_subscribed_data`: External Google datasets (Google Trends, Malaysia Places POI, Google Ads)

### Step 2 (Part A): Analytics Hub Zero-Copy Exchange (`acsm_aeon_exchange`)
- **What Happens**:
  1. **Step 2.1**: Authorizes `acsm_analyticshub_shared` as an **Authorized Dataset** on `acsm_bronze`, creates the `acsm_aeon_exchange` (`ACSM_AEON_Ecosystem_Exchange`) Data Exchange in `asia-southeast1` via `analyticshub.googleapis.com/v1`, and publishes `acsm_merchant_spend_listing` (`ACSM_Merchant_Spend_Zero_Copy_Listing`) sharing `acsm_analyticshub_shared` (so internal `acsm_gold` tables are never exposed to external subscribers).
  2. **Subscribe in Console**: Navigate to **BigQuery Sharing (Analytics Hub) -> Data Exchanges -> `ACSM_AEON_Ecosystem_Exchange` -> `ACSM_Merchant_Spend_Zero_Copy_Listing` -> `+ Subscribe`** and create the Linked Dataset **`acsm_merchant_spend_zero_copy_listing`**.
  3. **Step 2.2**: Queries the subscribed zero-copy Linked Dataset (`acsm_merchant_spend_zero_copy_listing.vw_analyticshub_merchant_spend_aggregations`) without exposing individual cardholder identities.

#### 🖼️ Visual Architecture: How Two GCP Projects Share Data via Analytics Hub (Zero-Copy)

```mermaid
flowchart LR
  subgraph PUB["🏢 Publisher GCP Project: AEON Credit (ACSM)"]
    direction TB
    BRONZE[("🔒 acsm_bronze.Fact_CC_Sales\n(Raw Cardholder Transactions — Private)")]
    GOLD[("🔒 acsm_gold.*\n(Customer 360 & Risk Tables — Private, NOT Shared)")]
    SHARED[["📂 Dedicated Shared Dataset:\nacsm_analyticshub_shared\n└── 👁️ vw_analyticshub_merchant_spend_aggregations"]]
    BRONZE -- "1. Authorized Dataset Grant\n(targetTypes: VIEWS)" --> SHARED
  end

  subgraph AH["🌐 Analytics Hub (`asia-southeast1` Singapore)"]
    direction TB
    EX["🤝 Data Exchange:\nACSM_AEON_Ecosystem_Exchange\n(`acsm_aeon_exchange`)"]
    LIST["📋 Published Listing:\nACSM_Merchant_Spend_Zero_Copy_Listing\n(`acsm_merchant_spend_listing`)"]
    EX --> LIST
  end

  subgraph SUB["🛒 Subscriber GCP Project: AEON Retail Malaysia"]
    direction TB
    LINKED[("🔗 Linked Dataset (Read-Only Pointer):\nacsm_merchant_spend_zero_copy_listing\n└── vw_analyticshub_merchant_spend_aggregations")]
    QUERY["📊 Step 2.2 Subscriber SQL:\nSELECT merchant_group, location_name,\ntotal_transactions, total_spending_rm\nFROM acsm_merchant_spend_zero_copy_listing\n.vw_analyticshub_merchant_spend_aggregations"]
    LINKED --> QUERY
  end

  SHARED -- "2. Publish Dedicated Dataset\n(Zero Storage Copy)" --> LIST
  LIST -- "3. Click '+ Subscribe' in Console\n(Creates Symbolic Link 🔗)" --> LINKED
```

```text
+-------------------------------------------------------+      +------------------------------------------+      +-------------------------------------------------------+
| 🏢 PUBLISHER GCP PROJECT (AEON Credit - ACSM)         |      | 🌐 BIGQUERY ANALYTICS HUB (Singapore)    |      | 🛒 SUBSCRIBER GCP PROJECT (AEON Retail Malaysia)      |
|                                                       |      |                                          |      |  (Simulated in workshop project `aeon-demo-workshop`) |
|  [🔒 acsm_gold.*]  (Private - NEVER shared!)          |      |  Exchange: ACSM_AEON_Ecosystem_Exchange  |      |                                                       |
|                                                       |      |    (`acsm_aeon_exchange`)                |      |  [🔗 acsm_merchant_spend_zero_copy_listing]           |
|  [🔒 acsm_bronze.Fact_CC_Sales] (Raw PII/Txns)        |      |               |                          |      |    └── vw_analyticshub_merchant_spend_aggregations    |
|         |                                             |      |               v                          |      |               |                                       |
|         | 1. Authorized Dataset Grant (VIEWS only)    |      |  Listing:  ACSM_Merchant_Spend_          |      |               | 4. Step 2.2 Live SQL Query            |
|         v                                             |      |            Zero_Copy_Listing             |      |               v    (Zero ETL, Zero Storage Copy!)     |
|  [📂 acsm_analyticshub_shared] (Dedicated Shared DS)  | ===> |            (`acsm_merchant_spend_listing`)| ===> |  📊 Store-Level Spend Summary                         |
|    └── 👁️ vw_analyticshub_merchant_spend_aggregations | 2.   |                                          | 3.   |     (Storage read in ACSM; Compute slot in AEON Retail)|
+-------------------------------------------------------+      +------------------------------------------+      +-------------------------------------------------------+
```

---

### Step 3 (Part B): BigQuery Data Clean Room with Privacy-Preserving Thresholds (`k >= 20`)
- **What Happens**:
  1. **Step 3.1**: Authorizes `acsm_cleanroom` (`targetTypes: ["VIEWS"]`) on both `acsm_bronze` (Party 1) and `aeon_retail` (Party 2), creates the BigQuery Data Clean Room exchange (`acsm_aeon_cleanroom_exchange` / `ACSM_AEON_Retail_Data_Clean_Room` with `sharingEnvironmentConfig.dcrExchangeConfig`) via `analyticshub.googleapis.com/v1`, and publishes the restricted Clean Room listing (`acsm_aeon_joint_customer_cleanroom_listing` with `restrictedExportConfig.enabled = True`) sharing `acsm_cleanroom.vw_cleanroom_joint_customer_spend`.
  2. **Subscribe in Console**: Navigate to **BigQuery Sharing -> Data Clean Rooms -> `ACSM_AEON_Retail_Data_Clean_Room` -> `+ Subscribe`** and create the Clean Room Linked Dataset **`acsm_aeon_retail_data_clean_room`**.
  3. **Step 3.2**: Queries the subscribed Clean Room Linked Dataset (`acsm_aeon_retail_data_clean_room.vw_cleanroom_joint_customer_spend`), which enforces `HAVING COUNT(DISTINCT c.CIF_ID) >= 20` (`Malaysian PDPA Safe`).

#### 👥 Who Does What? Roles & Step-by-Step Workflow for Both Parties
| Role | Organization | Exact Responsibilities & Steps |
| :--- | :--- | :--- |
| **1. Clean Room Owner & Contributor 1** | **AEON Credit Service Malaysia (ACSM)** | 1. Creates the **Data Clean Room** (`ACSM_AEON_Retail_Data_Clean_Room` / `acsm_aeon_cleanroom_exchange`) in BigQuery Sharing.<br/>2. Contributes its Clean Room dataset (`acsm_cleanroom.vw_cleanroom_joint_customer_spend` authorized over `acsm_bronze.m3CIF` and `acsm_bronze.Fact_CC_Sales`) with **Analysis Rules (`k >= 20`)** and **Egress Controls (`restrictDirectTableAccess = True`)**.<br/>3. Invites **AEON Retail Malaysia** (`roles/analyticshub.publisher`) to contribute their loyalty dataset to the Clean Room, and grants Subscriber access (`roles/analyticshub.subscriber`) to the Joint Marketing team. |
| **2. External Data Contributor 2** | **AEON Retail Malaysia (Supermarket & Mall Loyalty)** | 1. Maintains its own private loyalty dataset **`aeon_retail.partner_aeon_retail_shoppers`** (containing `hashed_cif_match`, `retail_spend_amt`, `preferred_aeon_store`, `loyalty_tier`).<br/>2. Contributes **`aeon_retail.partner_aeon_retail_shoppers`** into ACSM's Clean Room with analysis/egress rules so ACSM cannot copy or view individual AEON Retail shopper rows. |
| **3. Clean Room Subscriber** | **One-AEON Joint Marketing / Analytics Team** *(can be analysts in ACSM or AEON Retail)* | 1. Opens **BigQuery Sharing -> Data Clean Rooms -> `ACSM_AEON_Retail_Data_Clean_Room`** and clicks **`+ Subscribe`**.<br/>2. This creates the read-only **Linked Dataset** **`acsm_aeon_retail_data_clean_room`** inside the Subscriber's GCP project.<br/>3. Runs aggregate SQL queries (`Step 3.2`) against **`acsm_aeon_retail_data_clean_room.vw_cleanroom_joint_customer_spend`**. |

#### 🛡️ What Happens If `HAVING COUNT(DISTINCT c.CIF_ID) >= 20` Is False (`< 20` Customers)?
> [!IMPORTANT]
> - **Automatic Row Suppression (Zero Leakage)**: If any `State x MaritalSts` cohort has **fewer than 20 matched customers (`1` to `19` customers)**, BigQuery **automatically suppresses (filters out / omits) that entire cohort row** from the query result!
> - **Why This Matters for Malaysian PDPA 2010**: Suppose an analyst tries to isolate a tiny demographic segment (for example, `State = 'Perlis' AND MaritalSts = 'Widowed'`) that happens to have only **1 or 2 customers**. Without the `>= 20` aggregation threshold, the analyst could deduce that specific person's exact income, credit card spend, and supermarket spend (a *re-identification / differencing attack*). Because `HAVING COUNT(DISTINCT c.CIF_ID) >= 20` is enforced inside the Clean Room view, any group with `< 20` distinct customers returns **no row at all**, guaranteeing that individual customer PII and financial behavior can never be reverse-engineered.

#### 🖼️ Visual Architecture: Multi-Party Collaboration in BigQuery Data Clean Room (`k >= 20`)

```mermaid
flowchart LR
  subgraph P1["🏢 Party 1 (Clean Room Owner & Contributor 1): AEON Credit (ACSM)"]
    CIF[("🔒 acsm_bronze.m3CIF\n(Demographics & Income)")]
    SALES[("🔒 acsm_bronze.Fact_CC_Sales\n(Credit Card Spend)")]
  end

  subgraph P2["🛒 Party 2 (External Contributor 2): AEON Retail Loyalty"]
    RETAIL[("🔒 aeon_retail.partner_aeon_retail_shoppers\n(Supermarket Spend & Store Visits)")]
  end

  subgraph DCR["🛡️ BigQuery Data Clean Room (`acsm_aeon_cleanroom_exchange`)"]
    VIEW[["🔐 Clean Room View:\nacsm_cleanroom.vw_cleanroom_joint_customer_spend\n• Joins on CIF_ID = hashed_cif_match\n• Enforces HAVING COUNT(DISTINCT CIF_ID) >= 20\n  (Cohorts with < 20 customers are SUPPRESSED!)\n• restrictDirectTableAccess = True (No Export/Copy)"]]
  end

  subgraph ANALYST["👩‍💻 Subscriber Project: One-AEON Joint Marketing"]
    DCR_LINK[("🔗 Clean Room Linked Dataset:\nacsm_aeon_retail_data_clean_room\n└── vw_cleanroom_joint_customer_spend")]
    OUT["✅ Cohort Output (State x MaritalSts)\nOnly cohorts with >= 20 customers returned;\ncohorts with < 20 customers automatically hidden (PDPA Safe)"]
    DCR_LINK --> OUT
  end

  CIF & SALES -- "1. Contribute Party 1 Data" --> VIEW
  RETAIL -- "2. Contribute Party 2 Data" --> VIEW
  VIEW -- "3. Click '+ Subscribe' on Clean Room" --> DCR_LINK
```

```text
+-----------------------------------------------+    +--------------------------------------------------+    +-------------------------------------------------------+
| 🏢 PARTY 1 (OWNER & CONTRIBUTOR 1): ACSM      |    | 🛡️ BIGQUERY DATA CLEAN ROOM (Singapore)          |    | 👩‍💻 SUBSCRIBER PROJECT: One-AEON Joint Marketing       |
|  • 🔒 acsm_bronze.m3CIF (Demographics)        |    |  Clean Room: ACSM_AEON_Retail_Data_Clean_Room    |    |  (Simulated in workshop project `aeon-demo-workshop`) |
|  • 🔒 acsm_bronze.Fact_CC_Sales (Card Spend)  | => |    (`acsm_aeon_cleanroom_exchange`)              |    |                                                       |
+-----------------------------------------------+ 1. |  View: acsm_cleanroom.                           | => |  [🔗 acsm_aeon_retail_data_clean_room]                |
                                                     |        vw_cleanroom_joint_customer_spend         | 3. |    └── vw_cleanroom_joint_customer_spend              |
+-----------------------------------------------+ 2. |    • Joins on CIF_ID = hashed_cif_match          |    |               |                                       |
| 🛒 PARTY 2 (CONTRIBUTOR 2): AEON Retail       | => |    • HAVING COUNT(DISTINCT CIF_ID) >= 20         |    |               v 4. Step 3.2 Privacy-Safe Cohort Query |
|  • 🔒 aeon_retail.                            |    |      (If < 20 customers -> Row is SUPPRESSED!)   |    |  ✅ Returns ONLY cohorts with >= 20 matched customers |
|       partner_aeon_retail_shoppers            |    |    • restrictDirectTableAccess = True            |    |  🚫 Cohorts with < 20 customers are hidden (PDPA Safe)|
+-----------------------------------------------+    +--------------------------------------------------+    +-------------------------------------------------------+
```

---

### Step 4 (Part C): External Dataset Enrichment (Google Trends, Places POI & Google Ads)
- **What Happens**:
  1. **Google Search Trends (`Step 4.1`)**: Queries Malaysian state-level search interest (`acsm_subscribed_data.google_trends_malaysia_financial_intent`) for consumer financing terms (`'personal loan'`, `'credit card'`, `'car loan'`, `'installment plan'`).
  2. **Google Maps / Places POI (`Step 4.2`)**: Geospatially enriches ACSM merchant transactions (`acsm_bronze.Fact_CC_Sales`) by joining `LDESC` with `acsm_subscribed_data.malaysia_places_catalog` across Kuala Lumpur, Selangor, Penang, and Johor.
  3. **Google Ads Telemetry (`Step 4.3`)**: Joins digital acquisition campaign impressions and clicks (`acsm_subscribed_data.google_ads_campaign_performance`) with active `acsm_bronze.dimProduct` cards (`Card_Status = 'Active'`) to measure activated card conversions and first-month credit line usage (`CP_CL_Usage`).

#### 📥 How `acsm_subscribed_data` Tables Are Populated (Workshop vs. Production)
| Table in `acsm_subscribed_data` | How Populated in This Workshop (`Step 1.1`) | How Populated in Production (`asia-southeast1`) |
| :--- | :--- | :--- |
| **`google_trends_malaysia_financial_intent`** | Created by [`05_cleanroom_and_external_datasets.sql`](../sql/05_cleanroom_and_external_datasets.sql) (lines 100–124) in `asia-southeast1` (`SELECT * FROM UNNEST([...])`) because Google's public `bigquery-public-data.google_trends.international_top_terms` dataset resides in the **`US` multi-region** and cannot be joined directly with `asia-southeast1` tables without cross-region replication. | Subscribe to the **Google Trends: International Top Terms** listing in **BigQuery Sharing (Analytics Hub)** or schedule a daily **BigQuery Data Transfer Service (Cross-Region Copy)** filtering `WHERE country_name = 'Malaysia'` into `asia-southeast1`. |
| **`malaysia_places_catalog`** | Created by [`05_cleanroom_and_external_datasets.sql`](../sql/05_cleanroom_and_external_datasets.sql) (lines 129–151) with 16 verified Malaysian merchant POIs (`AEON Mall Mid Valley Megamall`, `AEON BiG Kepong`, `Parkson Pavilion`, etc.) matching `Fact_CC_Sales.LDESC`. | Subscribe to **Google Maps Places Insights / Geo Data** via **BigQuery Sharing (Analytics Hub)** in `asia-southeast1`. |
| **`google_ads_campaign_performance`** | Created by [`05_cleanroom_and_external_datasets.sql`](../sql/05_cleanroom_and_external_datasets.sql) (lines 156–166) with Q3 card acquisition campaign metrics mapped to `dimProduct.Wallet_Tier` (`Platinum`, `Gold`, `Silver`, `Basic`). | Automated zero-code ingestion via **BigQuery Data Transfer Service for Google Ads** directly into `asia-southeast1`. |

