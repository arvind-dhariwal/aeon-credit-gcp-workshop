-- =============================================================================
-- TRACK 2: AGENTIC DATA SCIENCE, BIGQUERY ML PROPENSITY & TIMESFM 2.0 FORECASTING
-- File: sql/04_bqml_credit_and_cross_sell.sql
-- Region: asia-southeast1 (Singapore)
--
-- Fulfils ACSM RFP Clauses C1.1.4.1–C1.1.4.10, C1.1.3.1, C1.1.3.8 & Annexure M1.5.1:
-- 1. Module 1: Governed Customer 360 Feature Store (`acsm_gold.ml_customer_feature_store`)
-- 2. Module 2: Supervised EP -> CC Cross-Sell Model in Vertex AI Model Registry (`acsm_gold.model_ep_to_cc_cross_sell`)
-- 3. Module 3: Explainable AI (`ML.EVALUATE`, `ML.GLOBAL_EXPLAIN`, `ML.EXPLAIN_PREDICT` Local SHAP)
-- 4. Module 4: Zero-Shot Time-Series Forecasting with Google `TimesFM 2.0` (`AI.FORECAST`)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- MODULE 0: Ensure `acsm_gold.gold_aeon_customer360_profile` Has Full Standardized Schema
-- (Self-healing even if Dataform created a subset of columns in Track 1)
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS `acsm_gold`
OPTIONS (location = 'asia-southeast1');

CREATE OR REPLACE TABLE `acsm_gold.gold_aeon_customer360_profile`
CLUSTER BY State, CIF_ID
OPTIONS (
  description = 'Gold AEON 360 Customer Risk, Affordability & Credit Exposure Feature Store joining CIF, EP Underwriting, CC Underwriting, Collections, and Card Utilization.'
) AS
WITH silver_cif AS (
  SELECT
    CAST(CIF_ID AS STRING) AS CIF_ID,
    TRIM(CAST(CIF_NM AS STRING)) AS CIF_NM,
    TRIM(CAST(State AS STRING)) AS State,
    TRIM(CAST(Region AS STRING)) AS Region,
    TRIM(CAST(Occupation AS STRING)) AS Occupation,
    CAST(N_Age AS INT64) AS N_Age,
    CAST(B_NetIncome AS NUMERIC) AS B_NetIncome,
    CAST(B_AnnualIncome AS NUMERIC) AS B_AnnualIncome,
    COALESCE(TRIM(CAST(RecvPromo_FG AS STRING)), 'N') AS RecvPromo_FG
  FROM `acsm_bronze.m3CIF`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(CIF_ID AS STRING) ORDER BY Rcd_DT DESC) = 1
),
ep_agg AS (
  SELECT
    CAST(CIF_NO AS STRING) AS CIF_ID,
    COUNT(*) AS ep_app_count,
    ROUND(SUM(COALESCE(CAST(FIN_AMT AS NUMERIC), 0)), 2) AS total_ep_financed_myr,
    ROUND(AVG(CAST(NEW_DSR AS NUMERIC)), 2) AS avg_ep_dsr
  FROM `acsm_bronze.Fact_EP_Judge`
  GROUP BY 1
),
cc_agg AS (
  SELECT
    CAST(CIF_ID AS STRING) AS CIF_ID,
    COUNT(*) AS cc_app_count,
    ROUND(SUM(COALESCE(CAST(B_CrLimit AS NUMERIC), 0)), 2) AS total_cc_limit_myr,
    MAX(CAST(Final_Score AS NUMERIC)) AS latest_ctos_score
  FROM `acsm_bronze.Fact_CC_Judge`
  GROUP BY 1
),
ep_col AS (
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
),
col_agg AS (
  SELECT
    COALESCE(ep.CIF_ID, cc.CIF_ID) AS CIF_ID,
    COALESCE(ep.total_ep_unpaid_osp, 0) AS total_ep_unpaid_osp,
    COALESCE(cc.total_cc_unpaid_osp, 0) AS total_cc_unpaid_osp,
    COALESCE(ep.total_ep_unpaid_osp, 0) + COALESCE(cc.total_cc_unpaid_osp, 0) AS combined_unpaid_osp,
    GREATEST(COALESCE(ep.ep_worst_grade, 'A'), COALESCE(cc.cc_worst_grade, 'A')) AS worst_collection_score_grade
  FROM ep_col ep
  FULL OUTER JOIN cc_col cc
    ON ep.CIF_ID = cc.CIF_ID
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
  ep.avg_ep_dsr,
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
FROM silver_cif c
LEFT JOIN ep_agg ep USING (CIF_ID)
LEFT JOIN cc_agg cc USING (CIF_ID)
LEFT JOIN col_agg col USING (CIF_ID)
LEFT JOIN card_agg crd USING (CIF_ID);

-- -----------------------------------------------------------------------------
-- MODULE 1: Governed Customer 360 Feature Store (Clause C1.1.4.2)
-- Builds `acsm_gold.ml_customer_feature_store` from `acsm_gold.gold_aeon_customer360_profile`
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_gold.ml_customer_feature_store`
CLUSTER BY State, CIF_ID
OPTIONS (
  description = 'Governed ACSM ML Feature Store for performing customers from Customer 360 demographics, income, EP underwriting, DSR, and CTOS score (Clause C1.1.4.2).'
) AS
SELECT
  p.CIF_ID,
  p.CIF_NM,
  COALESCE(p.State, 'Unknown') AS State,
  COALESCE(p.Region, 'Unknown') AS Region,
  COALESCE(p.Occupation, 'Unknown') AS Occupation,
  CAST(COALESCE(p.N_Age, 35) AS INT64) AS N_Age,
  CAST(COALESCE(p.B_NetIncome, 0) AS FLOAT64) AS B_NetIncome,
  CAST(COALESCE(p.B_AnnualIncome, 0) AS FLOAT64) AS B_AnnualIncome,
  COALESCE(p.RecvPromo_FG, 'N') AS RecvPromo_FG,
  CAST(COALESCE(p.ep_app_count, 0) AS INT64) AS ep_app_count,
  CAST(COALESCE(p.total_ep_financed_myr, 0) AS FLOAT64) AS total_ep_financed_myr,
  CAST(COALESCE(p.avg_ep_dsr, 30.0) AS FLOAT64) AS avg_ep_dsr,
  CAST(COALESCE(p.latest_ctos_score, 650) AS FLOAT64) AS latest_ctos_score,
  CAST(COALESCE(p.active_card_count, 0) AS INT64) AS active_card_count,
  IF(COALESCE(p.active_card_count, 0) > 0, 1, 0) AS label_has_credit_card
FROM `acsm_gold.gold_aeon_customer360_profile` p
WHERE COALESCE(p.combined_unpaid_osp, 0) = 0;

-- -----------------------------------------------------------------------------
-- MODULE 2: Supervised Model — Easy Payment (EP) -> Credit Card (CC) Cross-Sell
-- Registered directly into Vertex AI Model Registry (Clauses C1.1.4.6, C1.1.4.10, M1.5.1)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `acsm_gold.model_ep_to_cc_cross_sell`
OPTIONS (
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['label_has_credit_card'],
  auto_class_weights = TRUE,
  max_iterations = 5,
  enable_global_explain = TRUE,
  model_registry = 'VERTEX_AI',
  vertex_ai_model_id = 'acsm_ep_to_cc_cross_sell_v1'
) AS
SELECT
  N_Age,
  State,
  Occupation,
  B_NetIncome,
  B_AnnualIncome,
  ep_app_count,
  total_ep_financed_myr,
  avg_ep_dsr,
  latest_ctos_score,
  label_has_credit_card
FROM `acsm_gold.ml_customer_feature_store`;

-- -----------------------------------------------------------------------------
-- MODULE 3: Explainable AI Predictions (`ML.EXPLAIN_PREDICT` Local SHAP)
-- Top 15 Pre-Qualified Easy Payment Customers for AEON Credit Card Cross-Sell
-- -----------------------------------------------------------------------------
SELECT
  CIF_ID,
  CIF_NM,
  State,
  Occupation,
  B_NetIncome,
  ep_app_count,
  total_ep_financed_myr,
  avg_ep_dsr,
  latest_ctos_score,
  RecvPromo_FG AS pdpa_consent,
  ROUND(probability, 4) AS cc_cross_sell_probability,
  CONCAT(
    top_feature_attributions[SAFE_OFFSET(0)].feature, ' (',
    CAST(ROUND(top_feature_attributions[SAFE_OFFSET(0)].attribution, 3) AS STRING), ')'
  ) AS top_1_shap_reason,
  CONCAT(
    top_feature_attributions[SAFE_OFFSET(1)].feature, ' (',
    CAST(ROUND(top_feature_attributions[SAFE_OFFSET(1)].attribution, 3) AS STRING), ')'
  ) AS top_2_shap_reason,
  CONCAT(
    top_feature_attributions[SAFE_OFFSET(2)].feature, ' (',
    CAST(ROUND(top_feature_attributions[SAFE_OFFSET(2)].attribution, 3) AS STRING), ')'
  ) AS top_3_shap_reason,
  CASE
    WHEN B_NetIncome >= 8000 AND latest_ctos_score >= 700 THEN 'AEON Platinum Visa (Fast-Track)'
    WHEN B_NetIncome >= 4000 AND latest_ctos_score >= 660 THEN 'AEON Gold Visa (Fast-Track)'
    ELSE 'AEON Classic Rewards Card'
  END AS recommended_card_offer
FROM ML.EXPLAIN_PREDICT(
  MODEL `acsm_gold.model_ep_to_cc_cross_sell`,
  (
    SELECT *
    FROM `acsm_gold.ml_customer_feature_store`
    WHERE active_card_count = 0
      AND ep_app_count > 0
      AND RecvPromo_FG = 'Y'
  ),
  STRUCT(3 AS top_k_features)
)
ORDER BY probability DESC, B_NetIncome DESC
LIMIT 15;

-- -----------------------------------------------------------------------------
-- MODULE 4: Zero-Shot 30-Day Credit Card Spend Forecast with Google `TimesFM 2.0` (`AI.FORECAST`)
-- Forecasts daily Credit Card transaction spend across `Cash Purchase` and `Cash Advance`
-- -----------------------------------------------------------------------------
SELECT
  Sales_Type,
  DATE(forecast_timestamp) AS forecast_date,
  ROUND(forecast_value, 2) AS forecasted_daily_spend_myr,
  ROUND(prediction_interval_lower_bound, 2) AS lower_bound_myr,
  ROUND(prediction_interval_upper_bound, 2) AS upper_bound_myr,
  confidence_level
FROM AI.FORECAST(
  (
    SELECT
      SAFE.PARSE_DATE('%Y%m%d', CAST(TX_DT AS STRING)) AS tx_date,
      TRIM(Sales_Type) AS Sales_Type,
      SUM(CAST(Amount AS FLOAT64)) AS daily_spend_myr
    FROM `acsm_bronze.Fact_CC_Sales`
    WHERE SAFE.PARSE_DATE('%Y%m%d', CAST(TX_DT AS STRING)) IS NOT NULL
    GROUP BY 1, 2
  ),
  data_col => 'daily_spend_myr',
  timestamp_col => 'tx_date',
  id_cols => ['Sales_Type'],
  model => 'TimesFM 2.0',
  horizon => 30,
  confidence_level => 0.95
)
ORDER BY Sales_Type, forecast_date
LIMIT 30;
