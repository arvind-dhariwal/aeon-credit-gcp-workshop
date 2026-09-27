# Track 1 (Notebook 03) Walkthrough: End-to-End Google Cloud Data Governance, Security & Data Quality

**Notebook**: [`03_Governance_Security_and_Data_Quality.ipynb`](../notebook/03_Governance_Security_and_Data_Quality.ipynb)
**Helper CLI & Rules YAML**: [`governance_helper.py`](../scripts/governance_helper.py) & [`dq_rules_gold_customer360.yaml`](../scripts/dq_rules_gold_customer360.yaml)
**Target Region**: `asia-southeast1` (Singapore)
**ACSM RFP Clauses**: `C1.1.1.1`, `C1.1.1.4`–`C1.1.1.10`, `C1.1.1.18`, `C1.1.1.24`, `C1.1.5.3`, `C1.1.5.5`, `C1.1.6.6`

---

## 1. Executive Summary & Architectural Design

Notebook 03 showcases Google Cloud's unified **Dataplex Universal Catalog, Sensitive Data Protection (Cloud DLP), Fine-Grained Access Control, and Serverless FinOps** capabilities mapped directly to **BNM RMiT** and **Malaysian PDPA 2010** requirements.

- **Explicit Execution + Verification Pattern (`Module X.1` + `Module X.2`)**: Every module in Notebook 03 pairs a concise **Execution Cell (`Module X.1`)**—which also renders a clickable HTML banner (`target="_blank"`) to open the relevant GCP Console tab in a new browser tab—with an **Explicit `%%bigquery` SQL Verification Cell (`Module X.2` / `4.3`)** so users can immediately inspect and verify the structured outcome inside the notebook.
- **Automatic SQLX Data Lineage**: Because `datalineage.googleapis.com` is enabled across Notebooks 01, 02, and Step 0 of Notebook 03, BigQuery automatically populates the interactive **Lineage** tab across all `acsm_bronze`, `acsm_silver`, and `acsm_gold` SQLX tables.
- **Centralized Observability Dataset (`acsm_observability`)**: Every scan persists its structured outputs into BigQuery tables under `acsm_observability` for historical audit and Looker dashboards.

---

## 2. Module-by-Module Walkthrough (Execution + Explicit Verification Cells)

| Module | ACSM RFP Clause | Capability Showcased | Execution Cell(s) | Explicit Verification Cell (`%%bigquery` SQL) & Direct Console Link (`target="_blank"`) |
| :--- | :--- | :--- | :--- | :--- |
| **Step 0** | `C1.1.1.9` | **Environment, APIs & Automatic SQLX Lineage** (`datalineage.googleapis.com`) | Enables APIs, creates `acsm_observability` dataset, and downloads `governance_helper.py` + [`dq_rules_gold_customer360.yaml`](../scripts/dq_rules_gold_customer360.yaml) | **BigQuery Studio -> `gold_aeon_customer360_profile` -> `Lineage` tab** |
| **Module 1** | `C1.1.1.1` | **Cloud Storage Lakehouse Data Discovery Scan** (`DATA_DISCOVERY`) | **1.1**: `governance_helper.py data-discovery` (grants Dataplex Discovery Service Agent IAM, organizes `.csv.gz` into per-table folders `discovered_tables/<Table>/<Table>.csv.gz`, sets `csvOptions.headerRows=1`, and triggers scan) | **1.2 (`%%bigquery`)**: Queries **`acsm_observability.dataplex_discovery_scan_results`** (`latest_job_id`, `job_state`, `scanned_file_count`, 7 discovered tables) + direct link to **[Dataplex Cloud Storage Discovery Console ↗](https://console.cloud.google.com/dataplex/cloud-storage-discovery)** (`Scan status` & `Scan history` tab) |
| **Module 2** | `C1.1.1.4` | **Automated Statistical Data Profiling** (`DATA_PROFILE`) | **2.1**: `gcloud dataplex datascans create data-profile --export-results-table=...` + `governance_helper.py data-profile` | **2.2 (`%%bigquery`)**: Queries **`acsm_observability.dataplex_profile_summary`** (null %, uniqueness, income/CTOS/DSR distributions across 100,000 customers) + direct link to **BigQuery Studio `Data Profile` tab ↗** |
| **Module 3** | `C1.1.1.10` | **AI Data Insights & Dataset Knowledge Graph** (`DATA_DOCUMENTATION`) | **3.1**: `governance_helper.py data-insights --datasets=acsm_silver,acsm_gold` | **3.2 (`%%bigquery`)**: Queries `INFORMATION_SCHEMA` across `acsm_bronze`, `acsm_silver`, and `acsm_gold` to verify **100% Dataset, Table & Column description coverage** + direct link to **BigQuery Studio `Insights` tab ↗** |
| **Module 4** | `C1.1.1.5`–`C1.1.1.7` | **Automated Data Quality (AutoDQ) & Quarantine Ledger** (`DATA_QUALITY`) | **4.1**: Inspect table-level rules YAML (`!cat dq_rules_gold_customer360.yaml`)<br>**4.2**: `gcloud dataplex datascans create data-quality --data-quality-spec-file=dq_rules_gold_customer360.yaml` + `governance_helper.py data-quality` | **4.3 (`%%bigquery`)**: Queries **`acsm_observability.dataplex_dq_scan_results`** (5 YAML rule evaluations) & **`acsm_observability.dq_quarantine_records`** + direct link to **BigQuery Studio `Data Quality` tab ↗** |
| **Module 5** | `C1.1.5.3` | **Sensitive Data Protection (Cloud DLP) Built-in & Custom InfoType Scan** (`dlp.googleapis.com`) | **5.1**: `governance_helper.py sdp-pii-scan` (`acsm-pdpa-bnm-inspect-template`) | **5.2 (`%%bigquery`)**: Queries **`acsm_observability.sdp_pii_findings`** to verify Built-in (`PERSON_NAME`) + Custom InfoTypes (`CUSTOM_ACSM_CIF_ID`, `CUSTOM_BNM_FINANCIAL_INCOME_MYR`, `CUSTOM_MALAYSIA_STATE_RESIDENCE`) + direct links to **Cloud DLP Console ↗** |
| **Module 6** | `C1.1.1.8` | **Dataplex Custom Governance Aspect Types & AI-Automated Aspect Tagging via Gemini** | **6.1**: `governance_helper.py ai-catalog-governance` (`acsm-bnm-rmit-governance-aspect`) | **6.2 (`%%bigquery`)**: Queries **`acsm_observability.dataplex_ai_catalog_aspects`** (`data_domain`, `medallion_layer`, `bnm_rmit_tier`, `pdpa_contains_pii`, `identified_pii_columns`, `recommended_masking_policy`, `data_steward`) + direct link to **Dataplex Catalog Entry ↗** |
| **Module 7** | `C1.1.1.24`, `C1.1.5.3`, `C1.1.5.5` | **Fine-Grained Row-Level Security (RLS) & Column Dynamic Masking (CLS) + 1-Click Reset** | **7.1**: `setup-cls-masking` + `bq query` RLS policy | **7.2 (`%%bigquery`)**: Queries `acsm_gold.gold_aeon_customer360_profile` to verify live simultaneous `SHA256` name masking + `0` income masking + 4 Central Region states<br>**7.3**: Runs `reset-security-policies` & verifies 100,000 unmasked rows restored |
| **Module 8** | `C1.1.1.18`, `C1.1.6.6` | **Serverless FinOps Cost Attribution & Workload Telemetry** | **8.1**: `governance_helper.py finops-telemetry` | **8.2 (`%%bigquery`)**: Queries **`acsm_observability.vw_finops_job_telemetry`** to verify 7-day job count, `$0` serverless batch load pool, billed MB, and slot-seconds by workload tier |

---

## 3. Inspecting the Table-Level Data Quality Rules YAML (`Module 4.1`)

Before running the Dataplex AutoDQ scan in **Module 4.2**, **Module 4.1** explicitly displays the declarative YAML file ([`track1_platform_governance/scripts/dq_rules_gold_customer360.yaml`](../scripts/dq_rules_gold_customer360.yaml), downloaded to `./dq_rules_gold_customer360.yaml` in Step 0):
- **`cif_id_not_null`** (`COMPLETENESS`, `threshold: 1.0`): `CIF_ID` must be non-null.
- **`cif_id_unique`** (`UNIQUENESS`, `threshold: 1.0`): `CIF_ID` must be 100% unique.
- **`positive_annual_income`** (`VALIDITY`, `threshold: 0.99`): `B_AnnualIncome` must be strictly `> 0`.
- **`valid_bnm_dsr_range`** (`VALIDITY`, `threshold: 0.95`): `avg_ep_new_dsr` must fall within `[0, 100]`.
- **`malaysian_state_not_null`** (`COMPLETENESS`, `threshold: 1.0`): `State` must be non-null for Row-Level Security (RLS).

---

## 4. Exploring Custom InfoTypes in Module 5

Module 5 creates a Cloud DLP **Inspect Template** (`acsm-pdpa-bnm-inspect-template`) combining Google's built-in detectors with **ACSM Custom InfoTypes (`customInfoTypes`)**:
- **`CUSTOM_ACSM_CIF_ID`**: Custom Regex detector (`^[0-9]{5,10}$`) for One-AEON Customer IDs.
- **`CUSTOM_BNM_FINANCIAL_INCOME_MYR`**: Custom Dictionary detector for BNM RMiT confidential income fields (`B_NetIncome`, `B_AnnualIncome`).
- **`CUSTOM_MALAYSIA_STATE_RESIDENCE`**: Custom 16-State Dictionary detector (`Selangor`, `Kuala Lumpur`, `Johor`, `Penang`, etc.) for regional RLS governance.
