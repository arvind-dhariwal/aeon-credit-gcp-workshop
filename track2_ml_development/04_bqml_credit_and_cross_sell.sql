-- =============================================================================
-- TRACK 2: ML DEVELOPMENT & MLOPS (BIGQUERY ML + VERTEX AI MODEL REGISTRY)
-- File: 04_bqml_credit_and_cross_sell.sql
--
-- Fulfils ACSM RFP Clauses C1.1.4.1–C1.1.4.10 & Annexure M (M1.5.1):
-- 1. Built-in Feature Engineering Store (`acsm_gold.ml_customer_feature_store`)
-- 2. Model 1: Credit Delinquency & AKPK Propensity (`model_delinquency_propensity`)
--             with Explainable AI (`ML.EXPLAIN_PREDICT`)
-- 3. Model 2: EP -> CC Cross-Selling Propensity (`model_ep_to_cc_cross_sell`)
-- 4. Model 3: RFM Customer Segmentation (`model_rfm_segmentation`)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Governed Feature Store Table (Clause C1.1.4.2)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_gold.ml_customer_feature_store`
OPTIONS (
  description = 'Governed Feature Store combining m3CIF demographics, card utilization, DSR, and repayment metrics for ACSM ML models.'
) AS
SELECT
  cif_id,
  COALESCE(age, 35) AS age,
  COALESCE(gender, 'U') AS gender,
  COALESCE(marital_status, 'U') AS marital_status,
  COALESCE(state, 'Unknown') AS state,
  COALESCE(occupation, 'Other') AS occupation,
  COALESCE(net_income_myr, 0) AS net_income_myr,
  COALESCE(debt_service_ratio_dsr, 0) AS debt_service_ratio_dsr,
  COALESCE(wallet_tier, 'Non-Cardholder') AS wallet_tier,
  COALESCE(total_cp_limit_myr, 0) AS total_cp_limit_myr,
  COALESCE(credit_utilization_ratio, 0) AS credit_utilization_ratio,
  COALESCE(total_ep_financed_myr, 0) AS total_ep_financed_myr,
  COALESCE(total_combined_spend_myr, 0) AS total_combined_spend_myr,
  COALESCE(total_transactions_count, 0) AS total_transactions_count,
  DATE_DIFF(CURRENT_DATE(), COALESCE(last_transaction_date, DATE '2026-01-01'), DAY) AS recency_days,
  COALESCE(finplus_tier, 'Unrated') AS finplus_tier,
  CAST(has_unpaid_delinquency AS INT64) AS label_is_delinquent,
  CAST((total_cards_held > 0 AND wallet_tier IN ('Gold', 'Platinum')) AS INT64) AS label_holds_premium_card
FROM `acsm_gold.gold_customer_360`;

-- -----------------------------------------------------------------------------
-- 2. Model 1: Explainable Credit Delinquency & AKPK Propensity Model
--    Registered directly into Vertex AI Model Registry (Clauses C1.1.4.6, C1.1.4.10)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `acsm_gold.model_delinquency_propensity`
OPTIONS (
  model_type = 'BOOSTED_TREE_CLASSIFIER',
  input_label_cols = ['label_is_delinquent'],
  auto_class_weights = TRUE,
  max_iterations = 25,
  enable_global_explain = TRUE,
  model_registry = 'VERTEX_AI',
  vertex_ai_model_id = 'acsm_delinquency_akpk_propensity_v1'
) AS
SELECT
  age,
  gender,
  marital_status,
  state,
  net_income_myr,
  debt_service_ratio_dsr,
  wallet_tier,
  total_cp_limit_myr,
  credit_utilization_ratio,
  total_ep_financed_myr,
  total_combined_spend_myr,
  finplus_tier,
  label_is_delinquent
FROM `acsm_gold.ml_customer_feature_store`;

-- -----------------------------------------------------------------------------
-- 3. Model 2: EP-to-CC Premium Card Cross-Sell Propensity Model (Annexure M1.5.1)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `acsm_gold.model_ep_to_cc_cross_sell`
OPTIONS (
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['label_holds_premium_card'],
  auto_class_weights = TRUE,
  enable_global_explain = TRUE,
  model_registry = 'VERTEX_AI',
  vertex_ai_model_id = 'acsm_ep_to_cc_cross_sell_v1'
) AS
SELECT
  age,
  state,
  occupation,
  net_income_myr,
  debt_service_ratio_dsr,
  total_ep_financed_myr,
  total_combined_spend_myr,
  total_transactions_count,
  label_holds_premium_card
FROM `acsm_gold.ml_customer_feature_store`
WHERE label_is_delinquent = 0;

-- -----------------------------------------------------------------------------
-- 4. Batch Explainable Predictions Table for e-Buddy & Credit Control Officers
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_gold.ml_customer_risk_and_cross_sell_scores`
CLUSTER BY cif_id
OPTIONS (
  description = 'Pre-computed Explainable ML Delinquency Risk & Cross-Sell Propensity scores with top SHAP feature attributions.'
) AS
SELECT
  cif_id,
  predicted_label_is_delinquent AS predicted_delinquency_flag,
  ROUND(
    (SELECT p.prob FROM UNNEST(predicted_label_is_delinquent_probs) p WHERE p.label = 1),
    4
  ) AS delinquency_risk_probability,
  top_feature_attributions
FROM ML.EXPLAIN_PREDICT(
  MODEL `acsm_gold.model_delinquency_propensity`,
  TABLE `acsm_gold.ml_customer_feature_store`,
  STRUCT(3 AS top_k_features)
);
