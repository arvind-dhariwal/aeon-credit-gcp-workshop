-- =============================================================================
-- TRACK 1: DATA PLATFORM, GOVERNANCE & MODERNIZATION
-- File: 02_medallion_and_reconciliation.sql
--
-- Demonstrates:
-- 1. Creation of Silver (`acsm_silver`) & Gold (`acsm_gold`) Medallion Datasets in Singapore (`asia-southeast1`)
-- 2. Silver Layer Standardization (`silver_customer_cif`, `silver_ep_underwriting`, `silver_cc_underwriting`, `silver_collections_summary`)
-- 3. Gold Layer AEON 360 Customer Profile (`gold_aeon360_customer_profile`)
-- 4. Dual-Run Automated Row & Financial Reconciliation Audit (`recon_audit_log`)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS `acsm_silver`
OPTIONS (
  location = 'asia-southeast1',
  description = 'ACSM Silver Medallion Layer: Standardized, type-cast, and deduplicated Customer CIF, EP/CC Underwriting, and Collections tables in Singapore (asia-southeast1)'
);

CREATE SCHEMA IF NOT EXISTS `acsm_gold`
OPTIONS (
  location = 'asia-southeast1',
  description = 'ACSM Gold Medallion Layer: Unified AEON 360 Customer Risk, Affordability & Credit Exposure Feature Store in Singapore (asia-southeast1)'
);

-- -----------------------------------------------------------------------------
-- 1. Silver Conformed Customer Master (`m3CIF` -> `acsm_silver.silver_customer_cif`)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_silver.silver_customer_cif`
CLUSTER BY CIF_ID, State
OPTIONS (
  description = 'Governed Silver Customer Master (m3CIF) deduplicated by CIF_ID with typed income and PDPA consent flags.'
) AS
SELECT
  CAST(CIF_ID AS STRING) AS CIF_ID,
  SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(CAST(Rcd_DT AS STRING), 1, 10)) AS record_refresh_date,
  TRIM(CAST(CIF_NM AS STRING)) AS CIF_NM,
  TRIM(CAST(Gender AS STRING)) AS Gender,
  TRIM(CAST(MaritalSts AS STRING)) AS MaritalSts,
  TRIM(CAST(Citizen AS STRING)) AS Citizen,
  TRIM(CAST(State AS STRING)) AS State,
  TRIM(CAST(Region AS STRING)) AS Region,
  TRIM(CAST(Race AS STRING)) AS Race,
  TRIM(CAST(Occupation AS STRING)) AS Occupation,
  CAST(EmpSts AS INT64) AS EmpSts,
  CAST(N_Age AS INT64) AS N_Age,
  CAST(N_YrStay AS NUMERIC) AS N_YrStay,
  CAST(N_YrJob AS NUMERIC) AS N_YrJob,
  CAST(B_NetIncome AS NUMERIC) AS B_NetIncome,
  CAST(B_GrossIncome AS NUMERIC) AS B_GrossIncome,
  CAST(B_AnnualIncome AS NUMERIC) AS B_AnnualIncome,
  COALESCE(TRIM(CAST(RecvPromo_FG AS STRING)), 'N') AS RecvPromo_FG
FROM `acsm_bronze.m3CIF`
QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(CIF_ID AS STRING) ORDER BY Rcd_DT DESC) = 1;

-- -----------------------------------------------------------------------------
-- 2. Silver Easy Payment Underwriting (`Fact_EP_Judge` -> `acsm_silver.silver_ep_underwriting`)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_silver.silver_ep_underwriting`
CLUSTER BY CIF_ID, APPL_STS
OPTIONS (
  description = 'Governed Silver Easy Payment (EP) Application & Underwriting Decisions from acsm_bronze.Fact_EP_Judge.'
) AS
SELECT
  CAST(APPL_NO AS STRING) AS APPL_NO,
  CAST(AGREE_NO AS STRING) AS AGREE_NO,
  CAST(CIF_NO AS STRING) AS CIF_ID,
  SAFE.PARSE_DATE('%Y%m%d', NULLIF(TRIM(CAST(APPL_DT AS STRING)), '0')) AS application_date,
  TRIM(CAST(APPL_STS AS STRING)) AS APPL_STS,
  CAST(SCORING_POINT AS NUMERIC) AS SCORING_POINT,
  TRIM(CAST(SCORING_RANK AS STRING)) AS SCORING_RANK,
  TRIM(CAST(SCORE_DECISION AS STRING)) AS SCORE_DECISION,
  TRIM(CAST(LOAN_GRP AS STRING)) AS LOAN_GRP,
  CAST(FIN_AMT AS NUMERIC) AS FIN_AMT,
  CAST(INST_AMT AS NUMERIC) AS INST_AMT,
  CAST(INTEREST AS NUMERIC) AS INTEREST,
  CAST(TOTAL_INST AS INT64) AS TOTAL_INST,
  CAST(NetIncome AS NUMERIC) AS NetIncome,
  CAST(NDI AS NUMERIC) AS NDI,
  CAST(CUR_DSR AS NUMERIC) AS CUR_DSR,
  CAST(NEW_DSR AS NUMERIC) AS NEW_DSR,
  CAST(TOTAL_AEON_OSB AS NUMERIC) AS TOTAL_AEON_OSB
FROM `acsm_bronze.Fact_EP_Judge`;

-- -----------------------------------------------------------------------------
-- 3. Silver Credit Card Underwriting (`Fact_CC_Judge` -> `acsm_silver.silver_cc_underwriting`)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_silver.silver_cc_underwriting`
CLUSTER BY CIF_ID, ApplSts_ID
OPTIONS (
  description = 'Governed Silver Credit Card Application & Underwriting Decisions from acsm_bronze.Fact_CC_Judge.'
) AS
SELECT
  CAST(Appl_ID AS STRING) AS Appl_ID,
  CAST(Account_No AS STRING) AS Account_No,
  CAST(CIF_ID AS STRING) AS CIF_ID,
  SAFE.PARSE_DATE('%Y%m%d', NULLIF(TRIM(CAST(Appl_DT AS STRING)), '0')) AS application_date,
  TRIM(CAST(ApplSts_ID AS STRING)) AS ApplSts_ID,
  TRIM(CAST(CardTyp_ID AS STRING)) AS CardTyp_ID,
  TRIM(CAST(CardBrand_ID AS STRING)) AS CardBrand_ID,
  TRIM(CAST(ScoreDecision_ID AS STRING)) AS ScoreDecision_ID,
  TRIM(CAST(ScoreRank_ID AS STRING)) AS ScoreRank_ID,
  CAST(NetIncome AS NUMERIC) AS NetIncome,
  CAST(NDI AS NUMERIC) AS NDI,
  CAST(CurrDSR AS NUMERIC) AS CurrDSR,
  CAST(NewDSR AS NUMERIC) AS NewDSR,
  CAST(B_CrLimit AS NUMERIC) AS B_CrLimit,
  CAST(Final_Score AS NUMERIC) AS Final_Score,
  TRIM(CAST(Final_ScoreDesc AS STRING)) AS Final_ScoreDesc
FROM `acsm_bronze.Fact_CC_Judge`;

-- -----------------------------------------------------------------------------
-- 4. Silver Collections Summary (`Fact_EP_Collection` + `Fact_CC_Collection` -> `acsm_silver.silver_collections_summary`)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_silver.silver_collections_summary`
CLUSTER BY CIF_ID
OPTIONS (
  description = 'Customer-level Silver Collections & Delinquency Summary across Fact_EP_Collection and Fact_CC_Collection.'
) AS
WITH ep_col AS (
  SELECT
    CAST(CIF_No AS STRING) AS CIF_ID,
    SUM(CAST(Unpaid_OSP AS NUMERIC)) AS total_ep_unpaid_osp,
    MAX(TRIM(CAST(Score_Grade AS STRING))) AS ep_worst_grade
  FROM `acsm_bronze.Fact_EP_Collection`
  GROUP BY 1
),
cc_col AS (
  SELECT
    CAST(CIF_No AS STRING) AS CIF_ID,
    SUM(CAST(Unpaid_OSP AS NUMERIC)) AS total_cc_unpaid_osp,
    MAX(TRIM(CAST(Score_Grade AS STRING))) AS cc_worst_grade
  FROM `acsm_bronze.Fact_CC_Collection`
  GROUP BY 1
)
SELECT
  COALESCE(ep.CIF_ID, cc.CIF_ID) AS CIF_ID,
  COALESCE(ep.total_ep_unpaid_osp, 0) AS total_ep_unpaid_osp,
  COALESCE(cc.total_cc_unpaid_osp, 0) AS total_cc_unpaid_osp,
  COALESCE(ep.total_ep_unpaid_osp, 0) + COALESCE(cc.total_cc_unpaid_osp, 0) AS combined_unpaid_osp,
  GREATEST(COALESCE(ep.ep_worst_grade, 'A'), COALESCE(cc.cc_worst_grade, 'A')) AS worst_collection_score_grade
FROM ep_col ep
FULL OUTER JOIN cc_col cc
  ON ep.CIF_ID = cc.CIF_ID;

-- -----------------------------------------------------------------------------
-- 5. Gold AEON 360 Customer Profile (`acsm_gold.gold_aeon360_customer_profile`)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_gold.gold_aeon360_customer_profile`
CLUSTER BY State, CIF_ID
OPTIONS (
  description = 'Gold AEON 360 Customer Risk, Affordability & Credit Exposure Feature Store joining CIF, EP Underwriting, CC Underwriting, Collections, and Card Utilization.'
) AS
WITH ep_agg AS (
  SELECT
    CIF_ID,
    COUNT(*) AS ep_app_count,
    ROUND(SUM(COALESCE(FIN_AMT, 0)), 2) AS total_ep_financed_myr,
    ROUND(AVG(NEW_DSR), 2) AS avg_ep_new_dsr
  FROM `acsm_silver.silver_ep_underwriting`
  GROUP BY CIF_ID
),
cc_agg AS (
  SELECT
    CIF_ID,
    COUNT(*) AS cc_app_count,
    ROUND(SUM(COALESCE(B_CrLimit, 0)), 2) AS total_cc_limit_myr,
    MAX(Final_Score) AS latest_ctos_score
  FROM `acsm_silver.silver_cc_underwriting`
  GROUP BY CIF_ID
),
card_agg AS (
  SELECT
    CAST(CIF_ID AS STRING) AS CIF_ID,
    COUNTIF(TRIM(CAST(Card_Status AS STRING)) = 'Active') AS active_card_count,
    ROUND(SUM(CAST(CP_CL_Usage AS NUMERIC)), 2) AS total_cp_usage_myr,
    ROUND(SUM(CAST(CP_CL_Available AS NUMERIC)), 2) AS total_cp_available_myr
  FROM `acsm_bronze.dimProduct`
  GROUP BY 1
)
SELECT
  c.CIF_ID,
  c.CIF_NM,
  c.State,
  c.Region,
  c.Occupation,
  c.N_Age,
  c.B_NetIncome,
  c.B_AnnualIncome,
  c.RecvPromo_FG,
  COALESCE(ep.ep_app_count, 0) AS ep_app_count,
  COALESCE(ep.total_ep_financed_myr, 0) AS total_ep_financed_myr,
  ep.avg_ep_new_dsr,
  COALESCE(cc.cc_app_count, 0) AS cc_app_count,
  COALESCE(cc.total_cc_limit_myr, 0) AS total_cc_limit_myr,
  cc.latest_ctos_score,
  COALESCE(col.total_ep_unpaid_osp, 0) AS total_ep_unpaid_osp,
  COALESCE(col.total_cc_unpaid_osp, 0) AS total_cc_unpaid_osp,
  COALESCE(col.combined_unpaid_osp, 0) AS combined_unpaid_osp,
  COALESCE(col.worst_collection_score_grade, 'NONE') AS worst_collection_score_grade,
  COALESCE(crd.active_card_count, 0) AS active_card_count,
  COALESCE(crd.total_cp_usage_myr, 0) AS total_cp_usage_myr,
  COALESCE(crd.total_cp_available_myr, 0) AS total_cp_available_myr
FROM `acsm_silver.silver_customer_cif` c
LEFT JOIN ep_agg ep USING (CIF_ID)
LEFT JOIN cc_agg cc USING (CIF_ID)
LEFT JOIN `acsm_silver.silver_collections_summary` col USING (CIF_ID)
LEFT JOIN card_agg crd USING (CIF_ID);

-- -----------------------------------------------------------------------------
-- 6. Silver BQML Delinquency Model (`acsm_silver.model_delinquency_propensity`)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `acsm_silver.model_delinquency_propensity`
OPTIONS (
  MODEL_TYPE = 'LOGISTIC_REG',
  INPUT_LABEL_COLS = ['delinquency_risk_flag'],
  AUTO_CLASS_WEIGHTS = TRUE,
  MAX_ITERATIONS = 5
) AS
SELECT
  N_Age,
  B_NetIncome,
  B_AnnualIncome,
  State,
  Region,
  Occupation,
  IF(COALESCE(combined_unpaid_osp, 0) > 0, 1, 0) AS delinquency_risk_flag
FROM `acsm_gold.gold_aeon360_customer_profile`;

-- -----------------------------------------------------------------------------
-- 7. Gold Batch BQML Predictions (`acsm_gold.gold_aeon360_batch_ml_predictions`)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_gold.gold_aeon360_batch_ml_predictions`
CLUSTER BY State, CIF_ID
OPTIONS (
  description = 'Gold Batch BQML Delinquency Risk Predictions scoring all 100,000 customers via ML.PREDICT(MODEL acsm_silver.model_delinquency_propensity).'
) AS
SELECT
  *
FROM ML.PREDICT(
  MODEL `acsm_silver.model_delinquency_propensity`,
  TABLE `acsm_gold.gold_aeon360_customer_profile`
);

-- -----------------------------------------------------------------------------
-- 8. Dual-Run Automated Financial Reconciliation Audit (`acsm_silver.recon_audit_log`)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_silver.recon_audit_log`
OPTIONS (
  description = 'Automated Row-Count and Financial Control Total Reconciliation Audit Table for BNM RMiT & Migration Sign-off.'
) AS
WITH checks AS (
  SELECT
    'Fact_EP_Judge -> silver_ep_underwriting' AS pipeline_flow,
    'FIN_AMT (Financed Principal MYR)' AS control_metric,
    (SELECT COUNT(*) FROM `acsm_bronze.Fact_EP_Judge`) AS bronze_rows,
    (SELECT COUNT(*) FROM `acsm_silver.silver_ep_underwriting`) AS silver_rows,
    (SELECT ROUND(SUM(CAST(FIN_AMT AS NUMERIC)), 2) FROM `acsm_bronze.Fact_EP_Judge`) AS bronze_total_myr,
    (SELECT ROUND(SUM(FIN_AMT), 2) FROM `acsm_silver.silver_ep_underwriting`) AS silver_total_myr
  UNION ALL
  SELECT
    'Fact_CC_Judge -> silver_cc_underwriting' AS pipeline_flow,
    'B_CrLimit (Approved Credit Limit MYR)' AS control_metric,
    (SELECT COUNT(*) FROM `acsm_bronze.Fact_CC_Judge`) AS bronze_rows,
    (SELECT COUNT(*) FROM `acsm_silver.silver_cc_underwriting`) AS silver_rows,
    (SELECT ROUND(SUM(CAST(B_CrLimit AS NUMERIC)), 2) FROM `acsm_bronze.Fact_CC_Judge`) AS bronze_total_myr,
    (SELECT ROUND(SUM(B_CrLimit), 2) FROM `acsm_silver.silver_cc_underwriting`) AS silver_total_myr
  UNION ALL
  SELECT
    'Fact_EP_Collection + Fact_CC_Collection -> silver_collections_summary' AS pipeline_flow,
    'Unpaid_OSP (Combined Unpaid Principal MYR)' AS control_metric,
    (SELECT COUNT(DISTINCT CIF_No) FROM (
      SELECT CIF_No FROM `acsm_bronze.Fact_EP_Collection`
      UNION DISTINCT
      SELECT CIF_No FROM `acsm_bronze.Fact_CC_Collection`
    )) AS bronze_rows,
    (SELECT COUNT(*) FROM `acsm_silver.silver_collections_summary`) AS silver_rows,
    (SELECT ROUND(SUM(CAST(Unpaid_OSP AS NUMERIC)), 2) FROM `acsm_bronze.Fact_EP_Collection`) +
      (SELECT ROUND(SUM(CAST(Unpaid_OSP AS NUMERIC)), 2) FROM `acsm_bronze.Fact_CC_Collection`) AS bronze_total_myr,
    (SELECT ROUND(SUM(combined_unpaid_osp), 2) FROM `acsm_silver.silver_collections_summary`) AS silver_total_myr
)
SELECT
  CURRENT_TIMESTAMP() AS reconciliation_timestamp,
  pipeline_flow,
  control_metric,
  bronze_rows,
  silver_rows,
  bronze_total_myr,
  silver_total_myr,
  (silver_total_myr - bronze_total_myr) AS variance_myr,
  IF(bronze_rows = silver_rows AND ABS(silver_total_myr - bronze_total_myr) = 0, 'PASS (0.00 MYR VARIANCE)', 'INVESTIGATE') AS audit_status
FROM checks;
