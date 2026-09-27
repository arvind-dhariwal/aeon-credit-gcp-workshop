-- =============================================================================
-- TRACK 2: AGENTIC DATA SCIENCE & END-TO-END BIGQUERY ML (BQML + SQL GRAPH RAG)
-- File: sql/04_bqml_credit_and_cross_sell.sql
-- Region: asia-southeast1 (Singapore)
--
-- Fulfils ACSM RFP Clauses C1.1.4.1–C1.1.4.10, C1.1.3.1, C1.1.3.6 & Annexure M1.5.1:
-- 1. Module 1: Governed Feature Store + Property Graph Contagion Features (`acsm_gold.ml_customer_feature_store`)
-- 2. Module 2: Unsupervised Customer Segmentation (`acsm_gold.model_customer_rfm_kmeans`)
-- 3. Module 3: Supervised Credit Delinquency & Cross-Sell Models in Vertex AI Model Registry
--              (`acsm_gold.model_delinquency_propensity`, `acsm_gold.model_ep_to_cc_cross_sell`)
-- 4. Module 4: Explainable AI (`ML.EVALUATE`, `ML.GLOBAL_EXPLAIN`, `ML.EXPLAIN_PREDICT` Local SHAP)
-- 5. Module 5: In-Warehouse SQL Graph RAG Knowledge Base (`acsm_gold.bnm_rmit_akpk_policy_kb`)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- MODULE 1: Governed Feature Store + Graph Contagion Features (Clause C1.1.4.2)
-- Combines `acsm_gold.gold_aeon_customer360_profile` (100,000 customers) with
-- network contagion features extracted via ISO GQL `GRAPH_TABLE` from
-- `acsm_gold.acsm_credit_ecosystem_graph`.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_gold.ml_customer_feature_store`
CLUSTER BY State, CIF_ID
OPTIONS (
  description = 'Governed ACSM ML Feature Store combining Customer 360 demographics, EP/CC underwriting, DSR, CTOS score, and Property Graph merchant contagion features (Clause C1.1.4.2).'
) AS
WITH high_risk_merchants AS (
  SELECT
    merchant_id,
    COUNT(DISTINCT delinq_cif_id) AS delinquent_shoppers_at_merchant
  FROM GRAPH_TABLE(
    `acsm_gold.acsm_credit_ecosystem_graph`
    MATCH (dc:Customer)-[t:TRANSACTED_AT]->(m:Merchant)
    WHERE dc.is_delinquent = TRUE
    COLUMNS (
      m.merchant_id AS merchant_id,
      dc.cif_id AS delinq_cif_id
    )
  )
  GROUP BY merchant_id
  HAVING COUNT(DISTINCT delinq_cif_id) >= 5
),
customer_graph_contagion AS (
  SELECT
    g.cif_id,
    COUNT(DISTINCT hrm.merchant_id) AS delinquent_exposed_merchants,
    COALESCE(SUM(hrm.delinquent_shoppers_at_merchant), 0) AS shared_delinquent_peers_count,
    ROUND(SUM(g.total_spend_myr), 2) AS total_graph_merchant_spend_myr
  FROM GRAPH_TABLE(
    `acsm_gold.acsm_credit_ecosystem_graph`
    MATCH (c:Customer)-[t:TRANSACTED_AT]->(m:Merchant)
    COLUMNS (
      c.cif_id AS cif_id,
      m.merchant_id AS merchant_id,
      t.total_spend_myr AS total_spend_myr
    )
  ) g
  LEFT JOIN high_risk_merchants hrm
    ON g.merchant_id = hrm.merchant_id
  GROUP BY g.cif_id
)
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
  CAST(COALESCE(p.cc_app_count, 0) AS INT64) AS cc_app_count,
  CAST(COALESCE(p.total_cc_limit_myr, 0) AS FLOAT64) AS total_cc_limit_myr,
  CAST(COALESCE(p.latest_ctos_score, 650) AS FLOAT64) AS latest_ctos_score,
  CAST(COALESCE(p.active_card_count, 0) AS INT64) AS active_card_count,
  CAST(COALESCE(p.total_cp_usage_myr, 0) AS FLOAT64) AS total_cp_usage_myr,
  CAST(COALESCE(p.total_cp_available_myr, 0) AS FLOAT64) AS total_cp_available_myr,
  ROUND(
    SAFE_DIVIDE(
      CAST(COALESCE(p.total_cp_usage_myr, 0) AS FLOAT64),
      NULLIF(CAST(COALESCE(p.total_cp_usage_myr, 0) + COALESCE(p.total_cp_available_myr, 0) AS FLOAT64), 0)
    ),
    4
  ) AS credit_utilization_ratio,
  CAST(COALESCE(p.combined_unpaid_osp, 0) AS FLOAT64) AS combined_unpaid_osp,
  COALESCE(p.worst_collection_score_grade, 'NONE') AS worst_collection_score_grade,
  CAST(COALESCE(cg.delinquent_exposed_merchants, 0) AS INT64) AS delinquent_exposed_merchants,
  CAST(COALESCE(cg.shared_delinquent_peers_count, 0) AS INT64) AS shared_delinquent_peers_count,
  CAST(COALESCE(cg.total_graph_merchant_spend_myr, 0) AS FLOAT64) AS total_graph_merchant_spend_myr,
  IF(COALESCE(p.combined_unpaid_osp, 0) > 0, 1, 0) AS label_is_delinquent,
  IF(COALESCE(p.active_card_count, 0) > 0, 1, 0) AS label_has_credit_card
FROM `acsm_gold.gold_aeon_customer360_profile` p
LEFT JOIN customer_graph_contagion cg
  ON p.CIF_ID = cg.cif_id;

-- -----------------------------------------------------------------------------
-- MODULE 2: Unsupervised Customer Segmentation (`KMEANS` — 4 One-AEON Personas)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `acsm_gold.model_customer_rfm_kmeans`
OPTIONS (
  model_type = 'KMEANS',
  num_clusters = 4,
  standardize_features = TRUE,
  kmeans_init_method = 'KMEANS++',
  max_iterations = 10
) AS
SELECT
  N_Age,
  B_NetIncome,
  avg_ep_dsr,
  latest_ctos_score,
  total_ep_financed_myr,
  total_cp_usage_myr,
  credit_utilization_ratio
FROM `acsm_gold.ml_customer_feature_store`;

-- -----------------------------------------------------------------------------
-- MODULE 3A: Supervised Model 1 — Credit Delinquency & AKPK Propensity
-- Registered directly into Vertex AI Model Registry (Clauses C1.1.4.6, C1.1.4.10)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `acsm_gold.model_delinquency_propensity`
OPTIONS (
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['label_is_delinquent'],
  auto_class_weights = TRUE,
  max_iterations = 10,
  enable_global_explain = TRUE,
  model_registry = 'VERTEX_AI',
  vertex_ai_model_id = 'acsm_delinquency_akpk_propensity_v1'
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
  cc_app_count,
  total_cc_limit_myr,
  latest_ctos_score,
  credit_utilization_ratio,
  delinquent_exposed_merchants,
  shared_delinquent_peers_count,
  label_is_delinquent
FROM `acsm_gold.ml_customer_feature_store`;

-- -----------------------------------------------------------------------------
-- MODULE 3B: Supervised Model 2 — Easy Payment (EP) -> Credit Card (CC) Cross-Sell
-- Registered directly into Vertex AI Model Registry (Annexure M1.5.1)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `acsm_gold.model_ep_to_cc_cross_sell`
OPTIONS (
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['label_has_credit_card'],
  auto_class_weights = TRUE,
  max_iterations = 10,
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
  total_graph_merchant_spend_myr,
  label_has_credit_card
FROM `acsm_gold.ml_customer_feature_store`
WHERE label_is_delinquent = 0;

-- -----------------------------------------------------------------------------
-- MODULE 4: Batch Explainable Predictions Table (`ML.EXPLAIN_PREDICT` Local SHAP)
-- Combines Delinquency Risk Probability + Top 3 Local SHAP Feature Attributions
-- with EP -> CC Cross-Sell Propensity Probability across all 100,000 customers.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_gold.ml_customer_risk_and_cross_sell_scores`
CLUSTER BY State, CIF_ID
OPTIONS (
  description = 'Pre-computed Explainable ML Delinquency Risk & EP-to-CC Cross-Sell Propensity scores with Top 3 Local SHAP feature attributions per customer (Clauses C1.1.4.4, C1.1.4.9, M1.5.1).'
) AS
WITH delinq_explain AS (
  SELECT
    CIF_ID,
    CIF_NM,
    State,
    Region,
    Occupation,
    N_Age,
    B_NetIncome,
    avg_ep_dsr,
    latest_ctos_score,
    total_ep_financed_myr,
    total_cc_limit_myr,
    active_card_count,
    credit_utilization_ratio,
    combined_unpaid_osp,
    worst_collection_score_grade,
    RecvPromo_FG,
    delinquent_exposed_merchants,
    shared_delinquent_peers_count,
    label_is_delinquent,
    predicted_label_is_delinquent AS predicted_delinquency_flag,
    ROUND(probability, 4) AS delinquency_risk_probability,
    top_feature_attributions,
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
    ) AS top_3_shap_reason
  FROM ML.EXPLAIN_PREDICT(
    MODEL `acsm_gold.model_delinquency_propensity`,
    TABLE `acsm_gold.ml_customer_feature_store`,
    STRUCT(3 AS top_k_features)
  )
),
cross_sell_pred AS (
  SELECT
    CIF_ID,
    predicted_label_has_credit_card AS predicted_cc_cross_sell_flag,
    ROUND(
      (SELECT p.prob FROM UNNEST(predicted_label_has_credit_card_probs) p WHERE p.label = 1),
      4
    ) AS cc_cross_sell_probability
  FROM ML.PREDICT(
    MODEL `acsm_gold.model_ep_to_cc_cross_sell`,
    TABLE `acsm_gold.ml_customer_feature_store`
  )
)
SELECT
  d.*,
  cs.predicted_cc_cross_sell_flag,
  cs.cc_cross_sell_probability
FROM delinq_explain d
LEFT JOIN cross_sell_pred cs
  USING (CIF_ID);

-- -----------------------------------------------------------------------------
-- MODULE 5: Regulatory & Product Policy Knowledge Base (`acsm_gold.bnm_rmit_akpk_policy_kb_autonomous`)
-- Uses Autonomous Embedding Generation (`GENERATED ALWAYS AS (AI.EMBED(...)) STORED OPTIONS(asynchronous = TRUE)`)
-- so BigQuery automatically embeds rows for zero-pipeline `AI.SEARCH` queries, plus `bnm_rmit_akpk_policy_kb`
-- for synchronous `VECTOR_SEARCH` + `GRAPH_TABLE` + `ML.GENERATE_TEXT` SQL Graph RAG.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_gold.bnm_rmit_akpk_policy_kb_autonomous` (
  policy_id STRING,
  policy_title STRING,
  category STRING,
  content STRING,
  content_embedding STRUCT<result ARRAY<FLOAT64>, status STRING>
    GENERATED ALWAYS AS (
      AI.EMBED(
        content,
        connection_id => 'asia-southeast1.acsm_vertex_genai_conn',
        endpoint => 'text-embedding-005'
      )
    )
    STORED OPTIONS (asynchronous = TRUE)
)
OPTIONS (
  description = 'Autonomous Embedding Knowledge Base where BigQuery automatically maintains content_embedding via AI.EMBED for zero-pipeline AI.SEARCH queries (Clause C1.1.3.6).'
);

INSERT INTO `acsm_gold.bnm_rmit_akpk_policy_kb_autonomous` (policy_id, policy_title, category, content)
VALUES
  (
    'POL-BNM-RMIT-10.55',
    'BNM RMiT Sec 10.55 & Responsible Financing DSR > 60% Control',
    'Regulatory & Affordability',
    'Under Bank Negara Malaysia (BNM) Risk Management in Technology (RMiT) and Responsible Financing Guidelines, customers with Debt Service Ratio (DSR) exceeding 60% or high credit utilization ratio (> 80%) must be restricted from automatic credit limit increases and routed for proactive affordability review with documented SHAP feature attributions.'
  ),
  (
    'POL-AKPK-DMP-01',
    'AKPK Debt Management Programme (DMP) & Early Tenure Restructuring',
    'Collections & Restructuring',
    'Customers flagged with high delinquency propensity (probability >= 0.65), Collection Score Grade D/E, or Unpaid_OSP > RM 1,000 qualify for proactive AEON Early Restructuring or AKPK Debt Management Programme (DMP) referral: freeze new Cash Advance drawdowns and offer a 36-to-60 month installment conversion at <= 6.0% p.a. subject to 3 consecutive monthly payments.'
  ),
  (
    'POL-GRAPH-CONTAGION-03',
    'Merchant & Shared-Network Delinquency Contagion Ring Protocol',
    'Fraud & Network Risk',
    'When BigQuery Property Graph traversal identifies a high-risk customer transacting across merchants with elevated delinquent peer clusters (delinquent_exposed_merchants >= 1), Credit Control officers must review linked Easy Payment (EP) and Credit Card (CC) facilities simultaneously and verify merchant settlement authenticity before approving restructuring.'
  ),
  (
    'POL-ACSM-CROSSSELL-02',
    'One-AEON Easy Payment (EP) to Gold/Platinum Credit Card Fast-Track Policy',
    'Underwriting & Cross-Sell',
    'Performing Easy Payment (EP) customers with zero unpaid delinquency (Unpaid_OSP = 0), DSR <= 50%, CTOS Score >= 660, and active PDPA marketing consent (RecvPromo_FG = Y) who hold zero AEON Credit Cards (active_card_count = 0) qualify for pre-approved AEON Gold/Platinum Credit Card issuance with instant reward points at AEON Privilege Merchants.'
  ),
  (
    'POL-PDPA-2010-SEC43',
    'Malaysian PDPA 2010 Section 43 Consent & Fair Lending Explainability',
    'Data Privacy & Fair Lending',
    'Personal data (CIF_NM, Net Income) must be protected under Malaysian PDPA 2010, and marketing outreach is strictly restricted to customers with RecvPromo_FG = Y. All automated ML credit risk and restructuring recommendations must log their top SHAP feature attributions and exclude protected demographic attributes.'
  );

CREATE OR REPLACE TABLE `acsm_gold.bnm_rmit_akpk_policy_kb`
OPTIONS (
  description = 'Managed BigQuery Vector Knowledge Base storing BNM RMiT, Responsible Financing (DSR > 60%), AKPK DMP Restructuring, and One-AEON Cross-Sell Policy clauses for SQL Graph RAG (Clause C1.1.3.6).'
) AS
SELECT policy_id, policy_title, category, content
FROM `acsm_gold.bnm_rmit_akpk_policy_kb_autonomous`;
