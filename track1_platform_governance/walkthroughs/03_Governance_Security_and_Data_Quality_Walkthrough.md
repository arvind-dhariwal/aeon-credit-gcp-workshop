# Track 1 (Notebook 03) Walkthrough: End-to-End Google Cloud Data Governance, Security & Data Quality

**Notebook**: [`03_Governance_Security_and_Data_Quality.ipynb`](../notebook/03_Governance_Security_and_Data_Quality.ipynb)
**Helper CLI**: [`governance_helper.py`](../scripts/governance_helper.py) & [`dq_rules_gold_customer360.yaml`](../scripts/dq_rules_gold_customer360.yaml)
**Target Region**: `asia-southeast1` (Singapore)
**ACSM RFP Clauses**: `C1.1.1.1`, `C1.1.1.4`–`C1.1.1.10`, `C1.1.1.18`, `C1.1.1.24`, `C1.1.5.3`, `C1.1.5.5`, `C1.1.6.6`

---

## 1. Executive Summary & Architectural Design

Notebook 03 showcases Google Cloud's unified **Dataplex Universal Catalog, Sensitive Data Protection (Cloud DLP), Fine-Grained Access Control, and Serverless FinOps** capabilities mapped directly to **BNM RMiT** and **Malaysian PDPA 2010** requirements.

- **Outcome-Driven 1-Cell Modules**: Each governance capability is executed in a single concise CLI/SQL cell backed by [`governance_helper.py`](../scripts/governance_helper.py) so customers focus on governance outcomes rather than boilerplate code.
- **Automatic SQLX Data Lineage**: Because `datalineage.googleapis.com` is enabled across Notebooks 01, 02, and Step 0 of Notebook 03, BigQuery automatically populates the interactive **Lineage** tab across all `acsm_bronze`, `acsm_silver`, and `acsm_gold` SQLX tables.
- **Centralized Observability Dataset (`acsm_observability`)**: Every scan persists its structured outputs into BigQuery tables under `acsm_observability` for historical audit and Looker dashboards.

---

## 2. Module-by-Module Walkthrough

| Module | Capability Showcased | 1-Cell Command | Observability Table & Console Verification |
| :--- | :--- | :--- | :--- |
| **Step 0** | **Environment, APIs & Automatic SQLX Lineage** (`datalineage.googleapis.com`) | Enables APIs & creates `acsm_observability` dataset | **BigQuery Studio -> `gold_aeon_customer360_profile` -> `Lineage` tab** |
| **Module 1** | **Cloud Storage Lakehouse Data Discovery Scan** (`06-Data-Discovery-Scan`) | `gcloud dataplex datascans create data-discovery` + `governance_helper.py data-discovery` | Scans `gs://acsm-workshop-landing-{PROJECT_ID}` to auto-discover Lakehouse files |
| **Module 2** | **Automated Statistical Data Profiling** (`02-Data-Profile`) | `gcloud dataplex datascans create data-profile --export-results-table=...` + `governance_helper.py data-profile` | Stores summary in **`acsm_observability.dataplex_profile_summary`** (`dataplex_profile_scan_results`) + **BigQuery Studio `Data Profile` tab** |
| **Module 3** | **AI Data Insights & Dataset Knowledge Graph** (`03-Data-Insights`) | `governance_helper.py data-insights --datasets=acsm_silver,acsm_gold` + `%%bigquery` SQL audit | Publishes Dataset Knowledge Graph (`SCHEMA_JOIN` on `CIF_ID`) & **100% Dataset, Table, and Column descriptions** |
| **Module 4** | **Automated Data Quality (AutoDQ) & Quarantine Ledger** (`05-Data-Quality`) | **4.1**: `gcloud dataplex datascans create data-quality` + `governance_helper.py data-quality`<br>**4.2**: `%%bigquery` SQL query on `dataplex_dq_scan_results` | Stores 5-rule evaluation results in **`acsm_observability.dataplex_dq_scan_results`**, quarantined rows in **`acsm_observability.dq_quarantine_records`**, + **BigQuery Studio `Data Quality` tab** |
| **Module 5** | **Sensitive Data Protection (Cloud DLP) Built-in & Custom InfoType Scan** (`07-Sensitive-Data-Protection-Scan`) | `governance_helper.py sdp-pii-scan` | Creates Inspect Template `acsm-pdpa-bnm-inspect-template` with **Built-in (`PERSON_NAME`) + Custom InfoTypes (`CUSTOM_ACSM_CIF_ID`, `CUSTOM_BNM_FINANCIAL_INCOME_MYR`, `CUSTOM_MALAYSIA_STATE_RESIDENCE`)** and writes findings to **`acsm_observability.sdp_pii_findings`** |
| **Module 6** | **Dataplex Custom Governance Aspect Types & AI-Automated Aspect Tagging via Gemini** (`04` + `09`) | `governance_helper.py ai-catalog-governance` | Creates Custom Aspect Type `acsm-bnm-rmit-governance-aspect` and uses `gemini-2.5-flash` + Module 5's DLP findings to auto-populate the Dataplex Catalog Entry |
| **Module 7** | **Fine-Grained Row-Level Security (RLS) & Column Dynamic Masking (CLS) + 1-Click Reset** (`08-Row-Column-Security-Data-Masking`) | **7.1**: `setup-cls-masking` + `bq query` RLS<br>**7.2**: `%%bigquery` live SQL<br>**7.3**: `reset-security-policies` | Demonstrates live simultaneous `SHA256` name masking + `0` net income masking + Central Region state RLS filtering, then restores all 100,000 unmasked rows for Tracks 2–4 |
| **Module 8** | **Serverless FinOps Cost Attribution & Workload Telemetry** (`C1.1.1.18`) | `governance_helper.py finops-telemetry` | Builds and queries **`acsm_observability.vw_finops_job_telemetry`** |

---

## 3. Exploring Custom InfoTypes in Module 5

Module 5 creates a Cloud DLP **Inspect Template** (`acsm-pdpa-bnm-inspect-template`) combining Google's built-in detectors with **ACSM Custom InfoTypes (`customInfoTypes`)**:
- **`CUSTOM_ACSM_CIF_ID`**: Custom Regex detector (`^[0-9]{5,10}$`) for One-AEON Customer IDs.
- **`CUSTOM_BNM_FINANCIAL_INCOME_MYR`**: Custom Dictionary detector for BNM RMiT confidential income fields (`B_NetIncome`, `B_AnnualIncome`).
- **`CUSTOM_MALAYSIA_STATE_RESIDENCE`**: Custom 16-State Dictionary detector (`Selangor`, `Kuala Lumpur`, `Johor`, `Penang`, etc.) for regional RLS governance.

**Helpful Console & Documentation Links**:
- [GCP Console — Sensitive Data Protection Inspect Templates](https://console.cloud.google.com/security/sensitive-data-protection/landing/configuration/templates/inspect)
- [GCP Console — Sensitive Data Protection Inspection Jobs](https://console.cloud.google.com/security/sensitive-data-protection/landing/inspection/jobs)
- [Google Cloud Docs — Creating & Using Custom InfoType Detectors](https://cloud.google.com/sensitive-data-protection/docs/creating-custom-infotypes)
- [Google Cloud Docs — Built-in InfoType Detectors Reference (Malaysia)](https://cloud.google.com/sensitive-data-protection/docs/infotypes-reference#malaysia)
