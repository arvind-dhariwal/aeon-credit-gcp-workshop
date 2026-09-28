# Track 1 (Notebook 02) Walkthrough: Data Engineering Agent, SQLX Medallion Architecture & BQML

**Notebook**: [`02_Data_Engineering_Agent_Medallion_Architecture.ipynb`](../notebook/02_Data_Engineering_Agent_Medallion_Architecture.ipynb)
**Target Region**: `asia-southeast1` (Singapore)
**ACSM RFP Clauses**: `C1.1.1.9`, `C1.1.2.1`–`C1.1.2.5`, `C1.1.3.2`, `C1.1.6.11`, `C1.2.1.1`

---

## 1. Executive Summary & Customer Context

Once all 8 source tables are available in `acsm_bronze`, ACSM's data engineering team needs to transform raw Easy Payment (`EP`), Credit Card (`CC`), Customer (`m3CIF`), and Card (`dimProduct`) records into cleansed **Silver (`acsm_silver`)** tables, a unified **100,000-customer Gold Feature Store (`acsm_gold.gold_aeon_customer360_profile`)**, and an in-warehouse **BigQuery ML Delinquency Propensity Model (`acsm_gold.model_delinquency_propensity`, `model_type="LOGISTIC_REG"`)**.

Rather than hand-coding hundreds of lines of SQL/PySpark, this notebook showcases the **BigQuery Data Engineering Agent (Gemini in BigQuery Pipelines / Dataform)** generating and executing governed `.sqlx` transformations from natural-language prompts, followed by **Apache Airflow (Cloud Composer)** orchestration.

---

## 2. Step-by-Step Walkthrough

### Step 0: Configure Parameters, Enable Dataform & Data Lineage APIs, and Stage Files
- **What Happens**: Auto-detects `PROJECT_ID`, sets `LOCATION = "asia-southeast1"`, enables `dataform.googleapis.com`, `cloudaicompanion.googleapis.com`, **`datalineage.googleapis.com`**, and `dataplex.googleapis.com`, stages all 8 `.csv.gz` files in GCS for standalone execution, and grants `roles/datalineage.editor` + BigQuery/BigLake roles to the Dataform & Gemini Service Accounts.
- **Why It Matters**: Enabling `datalineage.googleapis.com` and granting `roles/datalineage.editor` ensures that every `.sqlx` table built by the Data Engineering Agent automatically populates BigQuery's **Lineage** tab across `acsm_bronze` -> `acsm_silver` -> `acsm_gold`.

### Step 1 & Step 2: Standalone Bronze Layer Bootstrap & Pre-Flight Check
- **What Happens**: Invokes [`00_create_8_tables_ddl_with_descriptions.sql`](../sql/00_create_8_tables_ddl_with_descriptions.sql) and [`01_load_bronze_layer_from_gcs.sql`](../sql/01_load_bronze_layer_from_gcs.sql) if `acsm_bronze` isn't already populated, then verifies all 8 Bronze tables (`1,900,000` total rows) using pure `%%bigquery` SQL.

### Step 3: Create Target Medallion & Dataform Datasets
- **What Happens**: Creates `acsm_silver`, `acsm_gold`, and `dataform_assertions` in `asia-southeast1`.

### Step 4: Interactive Prompts for the BigQuery Data Engineering Agent (`.sqlx` Generation)
- **Phase 1 Prompt (Medallion `.sqlx` Pipeline)**: Instructs the BigQuery Data Engineering Agent to generate 8 source declarations (`acsm_bronze.*`), 4 Silver `.sqlx` tables (`silver_customer_cif`, `silver_ep_underwriting`, `silver_cc_underwriting`, `silver_collections_summary`) with Dataform data quality assertions (`uniqueKey`, `nonNull`, `rowConditions`), and 1 Gold `.sqlx` Customer 360 table (`gold_aeon_customer360_profile` with `delinquency_risk_flag`).
- **Phase 2 Prompt (BQML `LOGISTIC_REG` Model)**: Instructs the Agent to create `train_model_delinquency_propensity.sqlx` training `acsm_gold.model_delinquency_propensity` with `model_type="LOGISTIC_REG"` and `input_label_cols=["delinquency_risk_flag"]`.

### Step 5 & Step 6: Verify Medallion Tables & Dual-Run Financial Reconciliation (`$0.00` Variance)
- **What Happens**:
  1. Verifies row counts across `acsm_silver` and `acsm_gold` (`100,000` unique customers).
  2. Executes a **Dual-Run Financial Control Total Reconciliation** comparing raw Bronze financial totals (`FIN_AMT`, `B_CrLimit`, `Unpaid_OSP`, `CP_CL_Usage`) against Silver/Gold totals to prove **`0.00` MYR variance**.
  3. Previews the top 10 customers in `acsm_gold.gold_aeon_customer360_profile`.

### Step 7: Apache Airflow (Cloud Composer) DAG Orchestration (`RFP C1.1.2.1`)
- **What Happens**: Invokes [`invoke_dataform_medallion_dag.py`](../airflow/invoke_dataform_medallion_dag.py) to compile and trigger the Dataform Medallion workflow via the Dataform API (`DataformCreateCompilationResultOperator` -> `DataformCreateWorkflowInvocationOperator`).
