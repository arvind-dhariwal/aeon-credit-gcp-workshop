# Track 1 (Notebook 01) Walkthrough: Serverless Seamless Data Ingestion Across 3 Storage Engines

**Notebook**: [`01_Serverless_Seamless_Data_Ingestion.ipynb`](../notebook/01_Serverless_Seamless_Data_Ingestion.ipynb)
**Target Region**: `asia-southeast1` (Singapore — BNM RMiT Tier-1 Residency)
**ACSM RFP Clauses**: `C1.1.1.1`, `C1.1.1.2`, `C1.1.1.3`, `C1.1.1.9`, `C1.1.2.1`, `C1.1.3.1`, `C1.1.4.2`, `C1.1.6.1`, `C1.1.6.5`

---

## 1. Executive Summary & Customer Context

AEON Credit Service Malaysia (ACSM) operates legacy on-premise **Microsoft SQL Server (EDW)** and **Apache Hadoop (HDFS)** silos across Easy Payment (`EP`), Credit Card (`CC`), Customer Information File (`m3CIF`), and Card Account (`dimProduct`) domains.

This notebook demonstrates how Google Cloud unifies **all 8 ACSM source tables (~1.9M rows)** into a single governed Bronze dataset (`acsm_bronze`) across **3 distinct storage engines** with **zero cluster management** and **$0 batch ingestion compute cost**:

| Storage Engine | ACSM Tables | Row Count | GCP Capability Showcased |
| :--- | :--- | :--- | :--- |
| **Engine 1: BigQuery Native Managed Storage** | `Fact_EP_Judge`, `Fact_EP_Sales`, `Fact_EP_Collection`, `Fact_CC_Judge`, `Fact_CC_Sales`, `Fact_CC_Collection` | ~1,400,000 rows | Pure SQL `LOAD DATA OVERWRITE` via BigQuery's `$0` shared serverless batch pool |
| **Engine 2: GCP Lakehouse Apache Iceberg (GCS)** | `m3CIF` -> governed view `acsm_bronze.m3CIF` | 100,000 rows | **BigLake Iceberg REST Catalog (`acsm_gcp_lakehouse_catalog`)** + Serverless PySpark write |
| **Engine 3: Cross-Cloud AWS Glue Federated Iceberg (S3)** | `dimProduct` -> governed view `acsm_bronze.dimProduct` | 400,000 rows | **BigQuery Omni / BigLake Cross-Cloud AWS Glue Federation (`aws-ap-southeast-1`)** |

---

## 2. Step-by-Step Walkthrough

### Step 0 & Step 1: Environment Setup & Enabling Data Lineage Upfront
- **What Happens**: Auto-detects `PROJECT_ID`, sets `LOCATION = "asia-southeast1"`, clones the workshop repository, and enables `storage.googleapis.com`, `bigquery.googleapis.com`, `biglake.googleapis.com`, **`datalineage.googleapis.com`**, and **`dataplex.googleapis.com`**.
- **Why It Matters**: Enabling `datalineage.googleapis.com` before loading Bronze tables guarantees that BigQuery Data Lineage automatically records end-to-end lineage from GCS files -> `acsm_bronze` -> `acsm_silver` -> `acsm_gold`.

### Step 2 & Step 3: Stage Compressed Source Extracts in Google Cloud Storage
- **What Happens**: Creates `gs://acsm-workshop-landing-{PROJECT_ID}` in `asia-southeast1` with Uniform Bucket-Level Access and uploads the 7 compressed `.csv.gz` extracts (`Fact_EP_*`, `Fact_CC_*`, and `m3CIF.csv.gz`).
- **UI Verification**: Open **Cloud Storage -> Buckets -> `acsm-workshop-landing-{PROJECT_ID}/full_compressed/`**.

### Step 4 & Step 5: Storage Engine 1 — BigQuery Native Storage (`$0` Serverless Batch Load)
- **What Happens**:
  1. Executes governed DDL creating `acsm_bronze` and the 6 Fact tables with partitioning, clustering (`CIF_ID` / `CIF_NO`, `State`), and BNM RMiT column descriptions.
  2. Runs pure SQL `LOAD DATA OVERWRITE acsm_bronze.<Table> FROM FILES(...)` across all 6 Fact tables.
- **Customer Outcome**: Zero Python ETL servers required; batch loads execute on BigQuery's free shared slot pool (`total_bytes_billed = 0`).

### Step 6: Pure SQL `INFORMATION_SCHEMA` Audits
- **What Happens**: Queries `acsm_bronze.INFORMATION_SCHEMA.PARTITIONS`, `region-asia-southeast1.INFORMATION_SCHEMA.JOBS_BY_PROJECT`, and `COLUMN_FIELD_PATHS` to prove row counts, `$0` load cost, and 100% column metadata coverage.

### Step 7: Storage Engine 2 — GCP Lakehouse Apache Iceberg (`m3CIF` — 100,000 Rows)
- **What Happens**:
  1. Creates the regional Iceberg warehouse bucket `gs://acsm-lakehouse-iceberg-{PROJECT_ID}`.
  2. Registers `acsm_gcp_lakehouse_catalog` in the **BigLake Iceberg REST Catalog** (`biglake.googleapis.com/iceberg/v1/restcatalog`).
  3. Writes `m3CIF.csv.gz` into `acsm_gcp_lakehouse_catalog.acsm_gcp_bronze.m3CIF` using Serverless Spark (`org.apache.iceberg.spark.SparkCatalog`) and exposes it in BigQuery via the governed view `acsm_bronze.m3CIF`.

### Step 8: Storage Engine 3 — Cross-Cloud AWS Glue Federated Apache Iceberg (`dimProduct` — 400,000 Rows)
- **What Happens**:
  1. Registers the AWS Glue catalog (`aws-ap-southeast-1`) in BigQuery and retrieves the unique BigLake IAM Service Account ID for AWS IAM trust whitelisting.
  2. Exposes the 400,000-row AWS S3 Iceberg table as `acsm_bronze.dimProduct`.
  3. Executes **1 unified SQL query joining all 3 storage engines** (`BigQuery Native` + `GCP GCS Iceberg` + `AWS S3 Glue Iceberg`) to produce a cross-engine Customer Credit & Card Usage summary.
