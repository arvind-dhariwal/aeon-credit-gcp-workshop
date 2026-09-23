# ACSM Mock Datasets & Metadata (`data/`)

This folder contains **100% of the records (`1,625,784 total rows`)** from AEON Credit Service Malaysia's (ACSM) shared workshop Drive folder (`1TszIQpdM6bNfdq9e7C0sNp4KY1Iba0Yq`), organized for both instant GitHub web previewing and zero-step BigQuery ingestion:

1. **[`Mock Metadata.xlsx`](./Mock%20Metadata.xlsx)**: Master data dictionary defining all 8 core tables (`T1`–`T8`) and ~220 column descriptions.
2. **[`full_compressed/`](./full_compressed/)**: Full, 100% lossless `.csv.gz` datasets (`1,625,784 rows` total; natively ingested by `01_ingest_and_metadata_sync.py` and `bq load` without decompression).
3. **[`samples/`](./samples/)**: 1,000-row uncompressed `.csv` files for every table (`T1`–`T8`) so engineers and business users can inspect records directly in the GitHub Web UI.

---

## Dataset Inventory & Row Counts

| Table ID | Full Compressed File (`full_compressed/`) | Browsable Sample (`samples/`) | Total Rows | Columns | Domain Description |
| :--- | :--- | :--- | ---: | ---: | :--- |
| **`T1`** | `T1_Fact_EP_Judge.csv.gz` (`13.81 MB`) | `T1_Fact_EP_Judge.csv` (`1,000 rows`) | **140,000** | 56 | Easy Payment (EP) loan application & underwriting decisions |
| **`T2`** | `T2_Fact_EP_Sales.csv.gz` (`1.41 MB`) | `T2_Fact_EP_Sales.csv` (`1,000 rows`) | **119,859** | 9 | Easy Payment (EP) confirmed sales transaction logs |
| **`T3`** | `T3_Fact_EP_Collection.csv.gz` (`1.98 MB`) | `T3_Fact_EP_Collection.csv` (`1,000 rows`) | **80,000** | 21 | Easy Payment (EP) billing, collection & delinquency snapshot |
| **`T4 (v1)`** | `T4_Fact_CC_Judge.csv.gz` (`17.27 MB`) | `T4_Fact_CC_Judge.csv` (`1,000 rows`) | **227,500** | 55 | Credit Card (CC) application & underwriting decisions (v1) |
| **`T4 (v2)`** | `T4_Fact_CC_Judge_v2.csv.gz` (`17.13 MB`) | `T4_Fact_CC_Judge_v2.csv` (`1,000 rows`) | **227,500** | 55 | Credit Card (CC) application & underwriting decisions (v2 schema evolution) |
| **`T5`** | `T5_Fact_CC_Sales.csv.gz` (`5.85 MB`) | `T5_Fact_CC_Sales.csv` (`1,000 rows`) | **535,925** | 9 | Credit Card (CC) spend & cash advance logs |
| **`T6`** | `T6_Fact_CC_Collection.csv.gz` (`2.35 MB`) | `T6_Fact_CC_Collection.csv` (`1,000 rows`) | **130,000** | 17 | Credit Card (CC) billing, collection & delinquency snapshot |
| **`T7`** | `T7_m3CIF.csv.gz` (`6.61 MB`) | `T7_m3CIF.csv` (`1,000 rows`) | **100,000** | 34 | Customer Information File (`m3CIF`) master customer table |
| **`T8`** | `T8_dimProduct.csv.gz` (`2.62 MB`) | `T8_dimProduct.csv` (`1,000 rows`) | **65,000** | 22 | Card & Product master (`dimProduct`) limits, status & Wallet Tier |
| **Total** | **`69.03 MB` compressed (`277.83 MB` raw)** | **`9,000 sample rows`** | **1,625,784** | **278** | **Complete ACSM Workshop Dataset** |
