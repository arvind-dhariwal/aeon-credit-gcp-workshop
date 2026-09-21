-- =============================================================================
-- TRACK 1: DATA PLATFORM, GOVERNANCE & MODERNIZATION
-- File: 02_medallion_and_reconciliation.sql
--
-- Demonstrates:
-- 1. Open Table Schema Evolution (T4_Fact_CC_Judge v1 -> v2) [C1.1.1.3, C1.1.1.4]
-- 2. Silver Layer Standardization (YYYYMMDD dates, unified CIF_ID) [C1.1.6.4]
-- 3. Declarative Data Quality & Automated Quarantine Table [C1.1.1.6, C1.1.1.7]
-- 4. Dual-Run Automated Row, Hash & Financial Reconciliation [C1.1.1.13, C1.1.6.5]
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Reusable UDF for safe conversion of ACSM integer/string YYYYMMDD dates
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `acsm_silver.parse_acsm_date`(raw_val ANY TYPE)
RETURNS DATE
AS (
  SAFE.PARSE_DATE(
    '%Y%m%d',
    NULLIF(TRIM(CAST(raw_val AS STRING)), '0')
  )
);

-- -----------------------------------------------------------------------------
-- 2. Silver Conformed Customer Master (T7_m3CIF)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_silver.dim_customer_cif`
CLUSTER BY cif_id, state
OPTIONS (
  description = 'Governed Silver Customer Master (m3CIF) with standardized CIF_ID, typed dates, and PDPA consent attributes.'
) AS
SELECT
  CAST(CIF_ID AS STRING) AS cif_id,
  SAFE.PARSE_DATE('%Y-%m-%d', CAST(Rcd_DT AS STRING)) AS record_refresh_date,
  TRIM(CAST(CIF_NM AS STRING)) AS customer_name,
  TRIM(CAST(MaritalSts AS STRING)) AS marital_status,
  TRIM(CAST(Gender AS STRING)) AS gender,
  TRIM(CAST(Citizen AS STRING)) AS citizenship,
  TRIM(CAST(State AS STRING)) AS state,
  TRIM(CAST(Region AS STRING)) AS region,
  TRIM(CAST(Race AS STRING)) AS race,
  TRIM(CAST(NOB AS STRING)) AS nature_of_business,
  TRIM(CAST(HomeOwn AS STRING)) AS home_ownership,
  TRIM(CAST(HomePost AS STRING)) AS home_postcode,
  TRIM(CAST(_HomeAddr1 AS STRING)) AS home_address_line1,
  TRIM(CAST(Occupation AS STRING)) AS occupation,
  TRIM(CAST(Academic AS STRING)) AS academic_qualification,
  TRIM(CAST(Emp_NM AS STRING)) AS employer_name,
  COALESCE(CAST(SelftEmp_FG AS STRING), 'N') AS self_employed_flag,
  COALESCE(CAST(Felda_FG AS STRING), 'N') AS felda_program_flag,
  COALESCE(CAST(JoinIncome_FG AS STRING), 'N') AS joint_income_flag,
  COALESCE(CAST(RecvPromo_FG AS STRING), 'N') AS pdpa_marketing_consent_flag,
  CAST(N_Age AS INT64) AS age,
  CAST(N_YrStay AS NUMERIC) AS years_at_residence,
  CAST(N_YrJob AS NUMERIC) AS years_in_job,
  CAST(B_NetIncome AS NUMERIC) AS net_income_myr,
  CAST(B_GrossIncome AS NUMERIC) AS gross_income_myr,
  CAST(B_AnnualIncome AS NUMERIC) AS annual_income_myr,
  CAST(EmpSts AS INT64) AS employment_status_code
FROM `acsm_bronze.t7_m3cif`
QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(CIF_ID AS STRING) ORDER BY Rcd_DT DESC) = 1;

-- -----------------------------------------------------------------------------
-- 3. Silver Conformed Card & Product Master (T8_dimProduct)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_silver.dim_card_product`
CLUSTER BY cif_id, card_status, wallet_tier
OPTIONS (
  description = 'Governed Silver Card Master (dimProduct) with credit/cash-advance limits and utilization metrics.'
) AS
SELECT
  CAST(Account_No AS STRING) AS account_no,
  CAST(CIF_ID AS STRING) AS cif_id,
  `acsm_silver.parse_acsm_date`(Expiry_DT) AS expiry_date,
  `acsm_silver.parse_acsm_date`(FirstSpend_DT) AS first_spend_date,
  NULLIF(TRIM(CAST(Block_Code AS STRING)), '') AS block_code,
  `acsm_silver.parse_acsm_date`(Block_Date) AS block_date,
  TRIM(CAST(CIC_Status AS STRING)) AS cic_status,
  TRIM(CAST(Card_Status AS STRING)) AS card_status,
  TRIM(CAST(AKPK_Status AS STRING)) AS akpk_status,
  `acsm_silver.parse_acsm_date`(Card_First_Emboss_Date) AS card_first_emboss_date,
  `acsm_silver.parse_acsm_date`(Card_Emboss_Date) AS card_emboss_date,
  `acsm_silver.parse_acsm_date`(Card_First_Activated_Date) AS card_first_activated_date,
  `acsm_silver.parse_acsm_date`(Card_Activated_Date) AS card_activated_date,
  CAST(CP_CL AS NUMERIC) AS credit_purchase_limit_myr,
  CAST(CP_CL_Available AS NUMERIC) AS credit_purchase_available_myr,
  CAST(CP_CL_Usage AS NUMERIC) AS credit_purchase_usage_myr,
  SAFE_DIVIDE(CAST(CP_CL_Usage AS NUMERIC), NULLIF(CAST(CP_CL AS NUMERIC), 0)) AS credit_purchase_utilization_ratio,
  CAST(CA_CL AS NUMERIC) AS cash_advance_limit_myr,
  CAST(CA_CL_Available AS NUMERIC) AS cash_advance_available_myr,
  CAST(CA_CL_Usage AS NUMERIC) AS cash_advance_usage_myr,
  TRIM(CAST(Account_Agree_Sts AS STRING)) AS account_agreement_status,
  TRIM(CAST(Virtual_Card_Flag AS STRING)) AS virtual_card_flag,
  TRIM(CAST(Wallet_Tier AS STRING)) AS wallet_tier
FROM `acsm_bronze.t8_dim_product`;

-- -----------------------------------------------------------------------------
-- 4. Schema Evolution & Unified Silver Credit Card Underwriting (T4 v1 + v2)
--    Demonstrates Clause C1.1.1.4: Seamless evolution from T4_Fact_CC_Judge to v2
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_silver.fact_cc_judge`
CLUSTER BY cif_id, appl_status_id
OPTIONS (
  description = 'Silver Credit Card Application & Underwriting Log reconciling T4_Fact_CC_Judge v1 and v2.'
) AS
WITH unioned AS (
  SELECT *, 'v2' AS schema_version, 2 AS priority FROM `acsm_bronze.t4_fact_cc_judge_v2`
  UNION ALL BY NAME
  SELECT *, 'v1' AS schema_version, 1 AS priority FROM `acsm_bronze.t4_fact_cc_judge`
)
SELECT
  CAST(Appl_ID AS STRING) AS appl_id,
  CAST(Account_No AS STRING) AS account_no,
  CAST(CIF_ID AS STRING) AS cif_id,
  TRIM(CAST(ApplSts_ID AS STRING)) AS appl_status_id,
  TRIM(CAST(CardTyp_ID AS STRING)) AS card_type_id,
  TRIM(CAST(CardBrand_ID AS STRING)) AS card_brand_id,
  TRIM(CAST(ApplChnnl_ID AS STRING)) AS application_channel,
  TRIM(CAST(Reject_ID AS STRING)) AS reject_id,
  TRIM(CAST(Decline_ID AS STRING)) AS decline_reason,
  TRIM(CAST(ScoreDecision_ID AS STRING)) AS score_decision_category,
  TRIM(CAST(ScoreRank_ID AS STRING)) AS score_rank,
  CAST(NetIncome AS NUMERIC) AS net_income_myr,
  CAST(GrossIncome AS NUMERIC) AS gross_income_myr,
  CAST(NDI AS NUMERIC) AS net_disposable_income_myr,
  CAST(CurrDSR AS NUMERIC) AS current_dsr,
  CAST(NewDSR AS NUMERIC) AS new_dsr,
  `acsm_silver.parse_acsm_date`(Appl_DT) AS application_date,
  `acsm_silver.parse_acsm_date`(Judge_DT) AS decision_date,
  CAST(B_CrLimit AS NUMERIC) AS approved_credit_limit_myr,
  CAST(B_CashAdvLimit AS NUMERIC) AS approved_cash_advance_limit_myr,
  CAST(Final_Score AS NUMERIC) AS ctos_final_score,
  TRIM(CAST(Final_ScoreDesc AS STRING)) AS ctos_score_description,
  schema_version
FROM unioned
QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(Appl_ID AS STRING) ORDER BY priority DESC) = 1;

-- -----------------------------------------------------------------------------
-- 5. Silver Easy Payment Underwriting (T1_Fact_EP_Judge)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_silver.fact_ep_judge`
CLUSTER BY cif_id, appl_status
OPTIONS (
  description = 'Silver Easy Payment (EP) Application & Underwriting Decisions.'
) AS
SELECT
  CAST(APPL_NO AS STRING) AS appl_no,
  CAST(AGREE_NO AS STRING) AS agree_no,
  CAST(CIF_NO AS STRING) AS cif_id,
  `acsm_silver.parse_acsm_date`(APPL_DT) AS application_date,
  TRIM(CAST(APPL_STS AS STRING)) AS appl_status,
  `acsm_silver.parse_acsm_date`(JUDGE_DT) AS decision_date,
  CAST(SCORING_POINT AS NUMERIC) AS scoring_point,
  TRIM(CAST(SCORING_RANK AS STRING)) AS scoring_rank,
  TRIM(CAST(SCORE_DECISION AS STRING)) AS score_decision,
  TRIM(CAST(LOAN_CODE AS STRING)) AS loan_code,
  TRIM(CAST(LOAN_GRP AS STRING)) AS loan_group,
  TRIM(CAST(APPL_CHANNEL AS STRING)) AS application_channel,
  TRIM(CAST(REJECT_CODE AS STRING)) AS reject_code,
  CAST(FIN_AMT AS NUMERIC) AS financed_amount_myr,
  CAST(FIN_PRFT_AMT AS NUMERIC) AS finance_profit_amount_myr,
  CAST(FIN_TOTAL_AMT AS NUMERIC) AS finance_total_amount_myr,
  CAST(INST_AMT AS NUMERIC) AS monthly_installment_myr,
  CAST(INTEREST AS NUMERIC) AS interest_rate,
  CAST(TOTAL_INST AS INT64) AS tenure_months,
  CAST(NetIncome AS NUMERIC) AS net_income_myr,
  CAST(NDI AS NUMERIC) AS net_disposable_income_myr,
  CAST(CUR_DSR AS NUMERIC) AS current_dsr,
  CAST(NEW_DSR AS NUMERIC) AS new_dsr,
  CAST(TOTAL_AEON_OSB AS NUMERIC) AS total_aeon_osb_myr
FROM `acsm_bronze.t1_fact_ep_judge`;

-- -----------------------------------------------------------------------------
-- 6. Silver Sales & Collections (T2, T3, T5, T6)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_silver.fact_unified_sales`
CLUSTER BY cif_id, product_line
OPTIONS (
  description = 'Unified Silver Transaction Log combining EP Confirmed Sales (T2) and CC Sales (T5).'
) AS
SELECT
  'EP' AS product_line,
  `acsm_silver.parse_acsm_date`(TX_DT) AS transaction_date,
  CAST(CIF_No AS STRING) AS cif_id,
  TRIM(CAST(TransactionCountry AS STRING)) AS transaction_country,
  TRIM(CAST(TransactionCountryHigherLevel AS STRING)) AS domestic_or_overseas,
  TRIM(CAST(PriviledgeMerchantsGrp AS STRING)) AS privilege_merchant_group,
  TRIM(CAST(LDESC AS STRING)) AS spend_location,
  TRIM(CAST(Sales_Type AS STRING)) AS sales_type,
  CAST(Amount AS NUMERIC) AS transaction_amount_myr,
  CAST(TransCount AS INT64) AS transaction_count
FROM `acsm_bronze.t2_fact_ep_sales`
UNION ALL
SELECT
  'CC' AS product_line,
  `acsm_silver.parse_acsm_date`(TX_DT) AS transaction_date,
  CAST(CIF_No AS STRING) AS cif_id,
  TRIM(CAST(TransactionCountry AS STRING)) AS transaction_country,
  TRIM(CAST(TransactionCountryHigherLevel AS STRING)) AS domestic_or_overseas,
  TRIM(CAST(PriviledgeMerchantsGrp AS STRING)) AS privilege_merchant_group,
  TRIM(CAST(LDESC AS STRING)) AS spend_location,
  TRIM(CAST(Sales_Type AS STRING)) AS sales_type,
  CAST(Amount AS NUMERIC) AS transaction_amount_myr,
  CAST(TransCount AS INT64) AS transaction_count
FROM `acsm_bronze.t5_fact_cc_sales`;

CREATE OR REPLACE TABLE `acsm_silver.fact_unified_collections`
CLUSTER BY cif_id, product_line
OPTIONS (
  description = 'Unified Silver Collections & Delinquency Snapshot combining EP (T3) and CC (T6).'
) AS
SELECT
  'EP' AS product_line,
  `acsm_silver.parse_acsm_date`(TX_DT) AS reporting_date,
  CAST(Agree_No AS STRING) AS facility_account_no,
  CAST(CIF_No AS STRING) AS cif_id,
  TRIM(CAST(Del_Sts AS STRING)) AS delinquency_status,
  TRIM(CAST(Collection_Branch AS STRING)) AS branch_id,
  CAST(Score_Value AS NUMERIC) AS collection_score_value,
  TRIM(CAST(Score_Grade AS STRING)) AS collection_score_grade,
  TRIM(CAST(Sub_Code AS STRING)) AS akpk_sub_code,
  TRIM(CAST(FinPlus_Code AS STRING)) AS finplus_tier,
  CAST(Billing_OSP AS NUMERIC) AS billing_osp_myr,
  CAST(Collection_OSP AS NUMERIC) AS collection_osp_myr,
  CAST(Unpaid_OSP AS NUMERIC) AS unpaid_osp_myr
FROM `acsm_bronze.t3_fact_ep_collection`
UNION ALL
SELECT
  'CC' AS product_line,
  `acsm_silver.parse_acsm_date`(TX_DT) AS reporting_date,
  CAST(Account_No AS STRING) AS facility_account_no,
  CAST(CIF_No AS STRING) AS cif_id,
  TRIM(CAST(DC_Sts AS STRING)) AS delinquency_status,
  TRIM(CAST(Application_Branch AS STRING)) AS branch_id,
  CAST(Score_Value AS NUMERIC) AS collection_score_value,
  TRIM(CAST(Score_Grade AS STRING)) AS collection_score_grade,
  CAST(NULL AS STRING) AS akpk_sub_code,
  TRIM(CAST(FinPlus_Code AS STRING)) AS finplus_tier,
  CAST(Billing_OSP AS NUMERIC) AS billing_osp_myr,
  CAST(Collection_OSP AS NUMERIC) AS collection_osp_myr,
  CAST(Unpaid_OSP AS NUMERIC) AS unpaid_osp_myr
FROM `acsm_bronze.t6_fact_cc_collection`;

-- -----------------------------------------------------------------------------
-- 7. Declarative Data Quality & Automated Quarantine Table (Clauses C1.1.1.6 & C1.1.1.7)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_silver.dq_quarantine_records`
OPTIONS (
  description = 'Automated Data Quality Quarantine Table capturing rule violations (WARN, QUARANTINE, FAIL) across ACSM pipelines.'
) AS
SELECT
  CURRENT_TIMESTAMP() AS evaluated_at,
  'T8_dimProduct' AS source_table,
  account_no AS record_key,
  cif_id,
  'DQ_RULE_01_DORMANT_CARD_WITH_ACTIVATION_DT' AS rule_id,
  'WARN' AS enforcement_action,
  CONCAT('Card status is Dormant but card_activated_date is populated: ', CAST(card_activated_date AS STRING)) AS violation_detail
FROM `acsm_silver.dim_card_product`
WHERE card_status = 'Dormant' AND card_activated_date IS NOT NULL
UNION ALL
SELECT
  CURRENT_TIMESTAMP() AS evaluated_at,
  'T8_dimProduct' AS source_table,
  account_no AS record_key,
  cif_id,
  'DQ_RULE_02_LIMIT_BALANCE_RECONCILIATION' AS rule_id,
  'QUARANTINE' AS enforcement_action,
  CONCAT('Credit Purchase Available + Usage != Total Limit: diff=', CAST(ABS((credit_purchase_available_myr + credit_purchase_usage_myr) - credit_purchase_limit_myr) AS STRING)) AS violation_detail
FROM `acsm_silver.dim_card_product`
WHERE ABS((credit_purchase_available_myr + credit_purchase_usage_myr) - credit_purchase_limit_myr) > 0.05;

-- -----------------------------------------------------------------------------
-- 8. Dual-Run Automated Financial Reconciliation Harness (Clauses C1.1.1.13 & C1.1.6.5)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_silver.recon_audit_log`
OPTIONS (
  description = 'Automated Row-Count, Hash-Digest, and Financial Control Total Reconciliation Audit Table for BNM RMiT & Migration Sign-off.'
) AS
WITH checks AS (
  SELECT
    'T1_Fact_EP_Judge' AS domain_table,
    'FIN_AMT (Financed Principal MYR)' AS metric_name,
    (SELECT COUNT(*) FROM `acsm_bronze.t1_fact_ep_judge`) AS bronze_row_count,
    (SELECT COUNT(*) FROM `acsm_silver.fact_ep_judge`) AS silver_row_count,
    (SELECT ROUND(SUM(CAST(FIN_AMT AS NUMERIC)), 2) FROM `acsm_bronze.t1_fact_ep_judge`) AS bronze_financial_total_myr,
    (SELECT ROUND(SUM(financed_amount_myr), 2) FROM `acsm_silver.fact_ep_judge`) AS silver_financial_total_myr
  UNION ALL
  SELECT
    'T3_plus_T6_Collections' AS domain_table,
    'Unpaid_OSP (Total Unpaid Principal MYR)' AS metric_name,
    (SELECT COUNT(*) FROM `acsm_bronze.t3_fact_ep_collection`) + (SELECT COUNT(*) FROM `acsm_bronze.t6_fact_cc_collection`) AS bronze_row_count,
    (SELECT COUNT(*) FROM `acsm_silver.fact_unified_collections`) AS silver_row_count,
    (SELECT ROUND(SUM(CAST(Unpaid_OSP AS NUMERIC)), 2) FROM `acsm_bronze.t3_fact_ep_collection`) +
      (SELECT ROUND(SUM(CAST(Unpaid_OSP AS NUMERIC)), 2) FROM `acsm_bronze.t6_fact_cc_collection`) AS bronze_financial_total_myr,
    (SELECT ROUND(SUM(unpaid_osp_myr), 2) FROM `acsm_silver.fact_unified_collections`) AS silver_financial_total_myr
  UNION ALL
  SELECT
    'T2_plus_T5_Sales' AS domain_table,
    'Amount (Total Confirmed Spend MYR)' AS metric_name,
    (SELECT COUNT(*) FROM `acsm_bronze.t2_fact_ep_sales`) + (SELECT COUNT(*) FROM `acsm_bronze.t5_fact_cc_sales`) AS bronze_row_count,
    (SELECT COUNT(*) FROM `acsm_silver.fact_unified_sales`) AS silver_row_count,
    (SELECT ROUND(SUM(CAST(Amount AS NUMERIC)), 2) FROM `acsm_bronze.t2_fact_ep_sales`) +
      (SELECT ROUND(SUM(CAST(Amount AS NUMERIC)), 2) FROM `acsm_bronze.t5_fact_cc_sales`) AS bronze_financial_total_myr,
    (SELECT ROUND(SUM(transaction_amount_myr), 2) FROM `acsm_silver.fact_unified_sales`) AS silver_financial_total_myr
)
SELECT
  CURRENT_TIMESTAMP() AS reconciliation_timestamp,
  domain_table,
  metric_name,
  bronze_row_count,
  silver_row_count,
  (silver_row_count - bronze_row_count) AS row_count_variance,
  bronze_financial_total_myr,
  silver_financial_total_myr,
  (silver_financial_total_myr - bronze_financial_total_myr) AS financial_variance_myr,
  CASE
    WHEN bronze_row_count = silver_row_count
     AND ABS(silver_financial_total_myr - bronze_financial_total_myr) = 0 THEN 'PASS'
    ELSE 'INVESTIGATE'
  END AS audit_status
FROM checks;
