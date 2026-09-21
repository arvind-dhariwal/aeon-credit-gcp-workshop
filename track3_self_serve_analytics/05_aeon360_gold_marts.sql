-- =============================================================================
-- TRACK 3: DASHBOARD & SELF-SERVICE ANALYTICS — AEON360 GOLD SEMANTIC MARTS
-- File: 05_aeon360_gold_marts.sql
--
-- Builds the 3 governed Gold Marts powering BigQuery Conversational Analytics
-- (BQCA), Looker Semantic Layer, and Power BI / Tableau re-pointing:
-- 1. acsm_gold.gold_customer_360       (AEON360 Unified Customer Data Platform)
-- 2. acsm_gold.gold_underwriting_funnel (EP + CC Credit Decision & CTOS Funnel)
-- 3. acsm_gold.gold_collections_risk    (EP + CC Delinquency, OSP & AKPK Exposure)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. AEON360 Unified Customer Profile (acsm_gold.gold_customer_360)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_gold.gold_customer_360`
CLUSTER BY wallet_tier, state, has_unpaid_delinquency
OPTIONS (
  description = 'AEON360 Customer Data Platform (CDP) Gold Mart combining m3CIF, dimProduct, EP/CC Underwriting, Spend, and Collections.'
) AS
WITH card_summary AS (
  SELECT
    cif_id,
    COUNT(DISTINCT account_no) AS total_cards_held,
    COUNTIF(card_status = 'Active') AS active_cards_count,
    MAX(wallet_tier) AS wallet_tier,
    MAX(akpk_status) AS card_akpk_status,
    SUM(credit_purchase_limit_myr) AS total_cp_limit_myr,
    SUM(credit_purchase_usage_myr) AS total_cp_usage_myr,
    SUM(credit_purchase_available_myr) AS total_cp_available_myr,
    SUM(cash_advance_limit_myr) AS total_ca_limit_myr,
    SUM(cash_advance_usage_myr) AS total_ca_usage_myr
  FROM `acsm_silver.dim_card_product`
  GROUP BY cif_id
),
ep_summary AS (
  SELECT
    cif_id,
    COUNT(DISTINCT appl_no) AS ep_applications_count,
    SUM(financed_amount_myr) AS total_ep_financed_myr,
    SUM(monthly_installment_myr) AS total_ep_monthly_installment_myr,
    MAX(new_dsr) AS latest_ep_dsr,
    MAX(total_aeon_osb_myr) AS latest_aeon_osb_myr
  FROM `acsm_silver.fact_ep_judge`
  GROUP BY cif_id
),
sales_summary AS (
  SELECT
    cif_id,
    SUM(IF(product_line = 'EP', transaction_amount_myr, 0)) AS total_ep_spend_myr,
    SUM(IF(product_line = 'CC', transaction_amount_myr, 0)) AS total_cc_spend_myr,
    SUM(transaction_amount_myr) AS total_combined_spend_myr,
    SUM(transaction_count) AS total_transactions_count,
    MAX(transaction_date) AS last_transaction_date
  FROM `acsm_silver.fact_unified_sales`
  GROUP BY cif_id
),
collections_summary AS (
  SELECT
    cif_id,
    SUM(billing_osp_myr) AS total_billing_osp_myr,
    SUM(collection_osp_myr) AS total_collection_osp_myr,
    SUM(unpaid_osp_myr) AS total_unpaid_osp_myr,
    MAX(finplus_tier) AS finplus_tier,
    MAX(collection_score_grade) AS worst_collection_score_grade
  FROM `acsm_silver.fact_unified_collections`
  GROUP BY cif_id
)
SELECT
  c.cif_id,
  c.customer_name,
  c.age,
  c.gender,
  c.marital_status,
  c.state,
  c.region,
  c.occupation,
  c.nature_of_business,
  c.net_income_myr,
  c.gross_income_myr,
  c.felda_program_flag,
  c.pdpa_marketing_consent_flag,
  COALESCE(p.wallet_tier, 'Non-Cardholder') AS wallet_tier,
  COALESCE(p.total_cards_held, 0) AS total_cards_held,
  COALESCE(p.active_cards_count, 0) AS active_cards_count,
  COALESCE(p.card_akpk_status, 'N') AS akpk_status,
  COALESCE(p.total_cp_limit_myr, 0) AS total_cp_limit_myr,
  COALESCE(p.total_cp_usage_myr, 0) AS total_cp_usage_myr,
  SAFE_DIVIDE(COALESCE(p.total_cp_usage_myr, 0), NULLIF(COALESCE(p.total_cp_limit_myr, 0), 0)) AS credit_utilization_ratio,
  COALESCE(e.ep_applications_count, 0) AS ep_applications_count,
  COALESCE(e.total_ep_financed_myr, 0) AS total_ep_financed_myr,
  COALESCE(e.latest_ep_dsr, 0) AS debt_service_ratio_dsr,
  COALESCE(s.total_ep_spend_myr, 0) AS total_ep_spend_myr,
  COALESCE(s.total_cc_spend_myr, 0) AS total_cc_spend_myr,
  COALESCE(s.total_combined_spend_myr, 0) AS total_combined_spend_myr,
  COALESCE(s.total_transactions_count, 0) AS total_transactions_count,
  s.last_transaction_date,
  COALESCE(col.total_billing_osp_myr, 0) AS total_billing_osp_myr,
  COALESCE(col.total_collection_osp_myr, 0) AS total_collection_osp_myr,
  COALESCE(col.total_unpaid_osp_myr, 0) AS total_unpaid_osp_myr,
  COALESCE(col.finplus_tier, 'Unrated') AS finplus_tier,
  COALESCE(col.worst_collection_score_grade, 'A') AS collection_score_grade,
  (COALESCE(col.total_unpaid_osp_myr, 0) > 0 OR COALESCE(p.card_akpk_status, 'N') = 'Y') AS has_unpaid_delinquency
FROM `acsm_silver.dim_customer_cif` c
LEFT JOIN card_summary p USING (cif_id)
LEFT JOIN ep_summary e USING (cif_id)
LEFT JOIN sales_summary s USING (cif_id)
LEFT JOIN collections_summary col USING (cif_id);

-- -----------------------------------------------------------------------------
-- 2. Unified Credit Underwriting Funnel Mart (acsm_gold.gold_underwriting_funnel)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_gold.gold_underwriting_funnel`
CLUSTER BY product_line, application_channel, decision_status
OPTIONS (
  description = 'Gold Credit Underwriting Funnel across Easy Payment (T1) and Credit Cards (T4 v2).'
) AS
SELECT
  'EP (Easy Payment)' AS product_line,
  appl_no AS application_id,
  cif_id,
  application_date,
  decision_date,
  application_channel,
  appl_status AS decision_status,
  scoring_rank AS score_rank,
  scoring_point AS credit_score,
  reject_code AS decline_reason_code,
  financed_amount_myr AS requested_or_approved_exposure_myr,
  net_income_myr,
  new_dsr
FROM `acsm_silver.fact_ep_judge`
UNION ALL
SELECT
  'CC (Credit Card)' AS product_line,
  appl_id AS application_id,
  cif_id,
  application_date,
  decision_date,
  application_channel,
  appl_status_id AS decision_status,
  score_rank,
  ctos_final_score AS credit_score,
  decline_reason AS decline_reason_code,
  approved_credit_limit_myr AS requested_or_approved_exposure_myr,
  net_income_myr,
  new_dsr
FROM `acsm_silver.fact_cc_judge`;

-- -----------------------------------------------------------------------------
-- 3. Unified Collections & AKPK Risk Mart (acsm_gold.gold_collections_risk)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_gold.gold_collections_risk`
CLUSTER BY product_line, finplus_tier, collection_score_grade
OPTIONS (
  description = 'Gold Collections & Delinquency Mart tracking Billing_OSP, Collection_OSP, Unpaid_OSP, FinPlus tier, and AKPK status by State.'
) AS
SELECT
  col.product_line,
  col.reporting_date,
  col.facility_account_no,
  col.cif_id,
  cif.state,
  cif.region,
  cif.occupation,
  col.branch_id,
  col.delinquency_status,
  col.collection_score_value,
  col.collection_score_grade,
  col.finplus_tier,
  COALESCE(col.akpk_sub_code, card.akpk_status, 'N') AS akpk_indicator,
  col.billing_osp_myr,
  col.collection_osp_myr,
  col.unpaid_osp_myr,
  SAFE_DIVIDE(col.collection_osp_myr, NULLIF(col.billing_osp_myr, 0)) AS collection_efficiency_ratio
FROM `acsm_silver.fact_unified_collections` col
LEFT JOIN `acsm_silver.dim_customer_cif` cif USING (cif_id)
LEFT JOIN `acsm_silver.dim_card_product` card
  ON col.facility_account_no = card.account_no;
