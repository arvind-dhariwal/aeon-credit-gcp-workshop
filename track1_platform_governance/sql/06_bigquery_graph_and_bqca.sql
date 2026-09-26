-- =============================================================================
-- TRACK 1 (NOTEBOOK 05 — LAB 1.5): BIGQUERY PROPERTY GRAPH (ISO GQL)
-- & BIGQUERY CONVERSATIONAL ANALYTICS (BQCA) DATA AGENT MARTS
-- File: 06_bigquery_graph_and_bqca.sql
-- Region: asia-southeast1 (Singapore)
--
-- Fulfils ACSM RFP Clauses:
-- - C1.1.2.9 / C1.1.2.10: Conversational Analytics (Natural-Language to SQL/GQL & Charts)
-- - M1.4.2 / M1.4.4: Governed Semantic Layer, Verified Golden SQL & Self-Service BI
-- - Advanced Graph Analytics: Multi-hop Fraud/Collusion Ring Detection, Delinquency
--   Contagion & Cross-Sell Path Discovery using BigQuery Property Graph (ISO GQL)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS `acsm_silver`
OPTIONS (
  location = 'asia-southeast1',
  description = 'ACSM Silver Medallion Layer in Singapore (asia-southeast1)'
);

CREATE SCHEMA IF NOT EXISTS `acsm_gold`
OPTIONS (
  location = 'asia-southeast1',
  description = 'ACSM Gold Medallion Layer: AEON 360 Semantic Marts & BigQuery Property Graph in Singapore (asia-southeast1)'
);

-- =============================================================================
-- SECTION 1: GOLD SEMANTIC MARTS FOR BIGQUERY CONVERSATIONAL ANALYTICS (BQCA)
-- =============================================================================

-- 1.1 Unified Credit Underwriting Funnel Mart (`acsm_gold.gold_underwriting_funnel`)
CREATE OR REPLACE TABLE `acsm_gold.gold_underwriting_funnel`
CLUSTER BY product_line, application_channel, decision_status
OPTIONS (
  description = 'Gold Credit Underwriting Funnel across Easy Payment (Fact_EP_Judge) and Credit Cards (Fact_CC_Judge) for BigQuery Conversational Analytics (BQCA).'
) AS
SELECT
  'EP (Easy Payment)' AS product_line,
  CAST(APPL_NO AS STRING) AS application_id,
  CAST(CIF_NO AS STRING) AS cif_id,
  SAFE.PARSE_DATE('%Y%m%d', NULLIF(TRIM(CAST(APPL_DT AS STRING)), '0')) AS application_date,
  SAFE.PARSE_DATE('%Y%m%d', NULLIF(TRIM(CAST(JUDGE_DT AS STRING)), '0')) AS decision_date,
  TRIM(CAST(APPL_CHANNEL AS STRING)) AS application_channel,
  TRIM(CAST(APPL_STS AS STRING)) AS decision_status,
  TRIM(CAST(SCORING_RANK AS STRING)) AS score_rank,
  CAST(SCORING_POINT AS FLOAT64) AS credit_score,
  TRIM(CAST(REJECT_CODE AS STRING)) AS decline_reason_code,
  CAST(FIN_AMT AS FLOAT64) AS requested_or_approved_exposure_myr,
  CAST(NetIncome AS FLOAT64) AS net_income_myr,
  CAST(NEW_DSR AS FLOAT64) AS new_dsr
FROM `acsm_bronze.Fact_EP_Judge`
UNION ALL
SELECT
  'CC (Credit Card)' AS product_line,
  CAST(Appl_ID AS STRING) AS application_id,
  CAST(CIF_ID AS STRING) AS cif_id,
  SAFE.PARSE_DATE('%Y%m%d', NULLIF(TRIM(CAST(Appl_DT AS STRING)), '0')) AS application_date,
  SAFE.PARSE_DATE('%Y%m%d', NULLIF(TRIM(CAST(Judge_DT AS STRING)), '0')) AS decision_date,
  TRIM(CAST(ApplChnnl_ID AS STRING)) AS application_channel,
  TRIM(CAST(ApplSts_ID AS STRING)) AS decision_status,
  TRIM(CAST(ScoreRank_ID AS STRING)) AS score_rank,
  CAST(Final_Score AS FLOAT64) AS credit_score,
  CAST(Decline_ID AS STRING) AS decline_reason_code,
  CAST(B_CrLimit AS FLOAT64) AS requested_or_approved_exposure_myr,
  CAST(NetIncome AS FLOAT64) AS net_income_myr,
  CAST(NewDSR AS FLOAT64) AS new_dsr
FROM `acsm_bronze.Fact_CC_Judge`;

-- 1.2 Unified Collections & AKPK Risk Mart (`acsm_gold.gold_collections_risk`)
CREATE OR REPLACE TABLE `acsm_gold.gold_collections_risk`
CLUSTER BY product_line, state, collection_score_grade
OPTIONS (
  description = 'Gold Collections & Delinquency Mart tracking Billing_OSP, Collection_OSP, Unpaid_OSP, FinPlus tier, and AKPK status across Malaysian states for BQCA.'
) AS
WITH unified_collections AS (
  SELECT
    'EP' AS product_line,
    SAFE.PARSE_DATE('%Y%m%d', NULLIF(TRIM(CAST(TX_DT AS STRING)), '0')) AS reporting_date,
    CAST(Agree_No AS STRING) AS facility_account_no,
    CAST(CIF_No AS STRING) AS cif_id,
    CAST(Collection_Branch AS STRING) AS branch_id,
    CAST(Del_Sts AS INT64) AS delinquency_status,
    CAST(Score_Value AS FLOAT64) AS collection_score_value,
    TRIM(CAST(Score_Grade AS STRING)) AS collection_score_grade,
    TRIM(CAST(FinPlus_Code AS STRING)) AS finplus_tier,
    TRIM(CAST(Sub_Code AS STRING)) AS akpk_sub_code,
    CAST(Billing_OSP AS FLOAT64) AS billing_osp_myr,
    CAST(Collection_OSP AS FLOAT64) AS collection_osp_myr,
    CAST(Unpaid_OSP AS FLOAT64) AS unpaid_osp_myr
  FROM `acsm_bronze.Fact_EP_Collection`
  UNION ALL
  SELECT
    'CC' AS product_line,
    SAFE.PARSE_DATE('%Y%m%d', NULLIF(TRIM(CAST(TX_DT AS STRING)), '0')) AS reporting_date,
    CAST(Account_No AS STRING) AS facility_account_no,
    CAST(CIF_No AS STRING) AS cif_id,
    CAST(Application_Branch AS STRING) AS branch_id,
    CAST(DC_Sts AS INT64) AS delinquency_status,
    CAST(Score_Value AS FLOAT64) AS collection_score_value,
    TRIM(CAST(Score_Grade AS STRING)) AS collection_score_grade,
    TRIM(CAST(FinPlus_Code AS STRING)) AS finplus_tier,
    CAST(NULL AS STRING) AS akpk_sub_code,
    CAST(Billing_OSP AS FLOAT64) AS billing_osp_myr,
    CAST(Collection_OSP AS FLOAT64) AS collection_osp_myr,
    CAST(Unpaid_OSP AS FLOAT64) AS unpaid_osp_myr
  FROM `acsm_bronze.Fact_CC_Collection`
),
dedup_cif AS (
  SELECT
    CAST(CIF_ID AS STRING) AS cif_id,
    TRIM(CAST(State AS STRING)) AS state,
    TRIM(CAST(Region AS STRING)) AS region,
    TRIM(CAST(Occupation AS STRING)) AS occupation
  FROM `acsm_bronze.m3CIF`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(CIF_ID AS STRING) ORDER BY Rcd_DT DESC) = 1
),
dedup_card AS (
  SELECT
    CAST(Account_No AS STRING) AS account_no,
    TRIM(CAST(AKPK_Status AS STRING)) AS akpk_status
  FROM `acsm_bronze.dimProduct`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(Account_No AS STRING) ORDER BY Expiry_DT DESC) = 1
)
SELECT
  col.product_line,
  col.reporting_date,
  col.facility_account_no,
  col.cif_id,
  COALESCE(cif.state, 'Unknown') AS state,
  COALESCE(cif.region, 'Unknown') AS region,
  COALESCE(cif.occupation, 'Unknown') AS occupation,
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
FROM unified_collections col
LEFT JOIN dedup_cif cif
  ON col.cif_id = cif.cif_id
LEFT JOIN dedup_card card
  ON col.facility_account_no = card.account_no;

-- =============================================================================
-- SECTION 2: BIGQUERY PROPERTY GRAPH NODE & EDGE BASE TABLES (`acsm_gold`)
-- =============================================================================

-- 2.1 Node Table 1: `acsm_gold.graph_node_customer` (Customer Entities)
CREATE OR REPLACE TABLE `acsm_gold.graph_node_customer`
CLUSTER BY cif_id, state
OPTIONS (
  description = 'BigQuery Property Graph Node Table (Customer): Governed ACSM Customer 360 nodes with income, state, wallet tier, AKPK status, and delinquency metrics.'
) AS
WITH card_agg AS (
  SELECT
    CAST(CIF_ID AS STRING) AS cif_id,
    COUNTIF(TRIM(CAST(Card_Status AS STRING)) = 'Active') AS active_card_count,
    MAX(TRIM(CAST(Wallet_Tier AS STRING))) AS wallet_tier,
    MAX(TRIM(CAST(AKPK_Status AS STRING))) AS akpk_status,
    ROUND(SUM(CAST(CP_CL AS FLOAT64)), 2) AS total_cp_limit_myr,
    ROUND(SUM(CAST(CP_CL_Usage AS FLOAT64)), 2) AS total_cp_usage_myr
  FROM `acsm_bronze.dimProduct`
  GROUP BY 1
),
col_agg AS (
  SELECT
    cif_id,
    ROUND(SUM(unpaid_osp_myr), 2) AS combined_unpaid_osp_myr,
    MAX(collection_score_grade) AS worst_collection_score_grade
  FROM `acsm_gold.gold_collections_risk`
  GROUP BY 1
)
SELECT
  CAST(c.CIF_ID AS STRING) AS cif_id,
  TRIM(CAST(c.CIF_NM AS STRING)) AS customer_name,
  COALESCE(TRIM(CAST(c.State AS STRING)), 'Unknown') AS state,
  COALESCE(TRIM(CAST(c.Region AS STRING)), 'Unknown') AS region,
  COALESCE(TRIM(CAST(c.Occupation AS STRING)), 'Unknown') AS occupation,
  CAST(c.N_Age AS INT64) AS age,
  ROUND(CAST(c.B_NetIncome AS FLOAT64), 2) AS net_income_myr,
  COALESCE(TRIM(CAST(c.RecvPromo_FG AS STRING)), 'N') AS pdpa_marketing_consent,
  COALESCE(crd.wallet_tier, 'Non-Cardholder') AS wallet_tier,
  COALESCE(crd.akpk_status, 'N') AS akpk_status,
  COALESCE(crd.active_card_count, 0) AS active_card_count,
  COALESCE(crd.total_cp_limit_myr, 0.0) AS total_cp_limit_myr,
  COALESCE(crd.total_cp_usage_myr, 0.0) AS total_cp_usage_myr,
  COALESCE(col.combined_unpaid_osp_myr, 0.0) AS combined_unpaid_osp_myr,
  COALESCE(col.worst_collection_score_grade, 'A') AS worst_collection_score_grade,
  (COALESCE(col.combined_unpaid_osp_myr, 0.0) > 0 OR COALESCE(crd.akpk_status, 'N') = 'Y') AS is_delinquent
FROM `acsm_bronze.m3CIF` c
LEFT JOIN card_agg crd
  ON CAST(c.CIF_ID AS STRING) = crd.cif_id
LEFT JOIN col_agg col
  ON CAST(c.CIF_ID AS STRING) = col.cif_id
WHERE c.CIF_ID IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(c.CIF_ID AS STRING) ORDER BY c.Rcd_DT DESC) = 1;

-- 2.2 Node Table 2: `acsm_gold.graph_node_credit_facility` (EP & CC Facilities)
CREATE OR REPLACE TABLE `acsm_gold.graph_node_credit_facility`
CLUSTER BY facility_id, product_line
OPTIONS (
  description = 'BigQuery Property Graph Node Table (CreditFacility): Easy Payment (EP) loan agreements and Credit Card (CC) facilities with credit scores, DSR, and MYR exposure.'
) AS
WITH raw_facilities AS (
  SELECT
    CONCAT('EP_', CAST(APPL_NO AS STRING)) AS facility_id,
    CAST(CIF_NO AS STRING) AS cif_id,
    'EP' AS product_line,
    TRIM(CAST(APPL_STS AS STRING)) AS application_status,
    TRIM(CAST(SCORING_RANK AS STRING)) AS score_rank,
    CAST(SCORING_POINT AS FLOAT64) AS credit_score,
    ROUND(CAST(FIN_AMT AS FLOAT64), 2) AS exposure_amount_myr,
    ROUND(CAST(NEW_DSR AS FLOAT64), 2) AS new_dsr
  FROM `acsm_bronze.Fact_EP_Judge`
  WHERE APPL_NO IS NOT NULL AND CIF_NO IS NOT NULL
  UNION ALL
  SELECT
    CONCAT('CC_', CAST(Appl_ID AS STRING)) AS facility_id,
    CAST(CIF_ID AS STRING) AS cif_id,
    'CC' AS product_line,
    TRIM(CAST(ApplSts_ID AS STRING)) AS application_status,
    TRIM(CAST(ScoreRank_ID AS STRING)) AS score_rank,
    CAST(Final_Score AS FLOAT64) AS credit_score,
    ROUND(CAST(B_CrLimit AS FLOAT64), 2) AS exposure_amount_myr,
    ROUND(CAST(NewDSR AS FLOAT64), 2) AS new_dsr
  FROM `acsm_bronze.Fact_CC_Judge`
  WHERE Appl_ID IS NOT NULL AND CIF_ID IS NOT NULL
)
SELECT *
FROM raw_facilities
QUALIFY ROW_NUMBER() OVER (PARTITION BY facility_id ORDER BY exposure_amount_myr DESC) = 1;

-- 2.3 Node Table 3: `acsm_gold.graph_node_merchant` (Merchant Spend Locations)
CREATE OR REPLACE TABLE `acsm_gold.graph_node_merchant`
CLUSTER BY merchant_id, merchant_group
OPTIONS (
  description = 'BigQuery Property Graph Node Table (Merchant): Privilege merchant groups and retail spend locations across Fact_CC_Sales and Fact_EP_Sales.'
) AS
WITH all_sales AS (
  SELECT
    TRIM(CAST(LDESC AS STRING)) AS merchant_id,
    TRIM(CAST(PriviledgeMerchantsGrp AS STRING)) AS merchant_group,
    CAST(CIF_No AS STRING) AS cif_id,
    CAST(Amount AS FLOAT64) AS amount_myr,
    CAST(TransCount AS INT64) AS tx_count
  FROM `acsm_bronze.Fact_CC_Sales`
  WHERE LDESC IS NOT NULL AND TRIM(CAST(LDESC AS STRING)) != ''
  UNION ALL
  SELECT
    TRIM(CAST(LDESC AS STRING)) AS merchant_id,
    TRIM(CAST(PriviledgeMerchantsGrp AS STRING)) AS merchant_group,
    CAST(CIF_No AS STRING) AS cif_id,
    CAST(Amount AS FLOAT64) AS amount_myr,
    CAST(TransCount AS INT64) AS tx_count
  FROM `acsm_bronze.Fact_EP_Sales`
  WHERE LDESC IS NOT NULL AND TRIM(CAST(LDESC AS STRING)) != ''
)
SELECT
  merchant_id,
  merchant_id AS merchant_name,
  COALESCE(MAX(merchant_group), 'General Retail') AS merchant_group,
  ROUND(SUM(amount_myr), 2) AS total_sales_volume_myr,
  SUM(COALESCE(tx_count, 1)) AS total_tx_count,
  COUNT(DISTINCT cif_id) AS distinct_customers_count
FROM all_sales
GROUP BY merchant_id;

-- 2.4 Node Table 4: `acsm_gold.graph_node_employer_segment` (Employer / NOB & State Segment)
CREATE OR REPLACE TABLE `acsm_gold.graph_node_employer_segment`
CLUSTER BY employer_segment_id, state
OPTIONS (
  description = 'BigQuery Property Graph Node Table (EmployerSegment): Shared employer / nature-of-business and state segments for detecting employment-linked credit risk clusters.'
) AS
SELECT
  CONCAT(
    COALESCE(NULLIF(TRIM(CAST(NOB AS STRING)), ''), 'GENERAL_SECTOR'),
    '|',
    COALESCE(NULLIF(TRIM(CAST(State AS STRING)), ''), 'UNKNOWN_STATE')
  ) AS employer_segment_id,
  COALESCE(NULLIF(TRIM(CAST(NOB AS STRING)), ''), 'GENERAL_SECTOR') AS employer_or_nob,
  COALESCE(NULLIF(TRIM(CAST(State AS STRING)), ''), 'UNKNOWN_STATE') AS state,
  COUNT(DISTINCT CAST(CIF_ID AS STRING)) AS employee_customer_count,
  ROUND(AVG(CAST(B_NetIncome AS FLOAT64)), 2) AS avg_net_income_myr
FROM `acsm_bronze.m3CIF`
WHERE CIF_ID IS NOT NULL
GROUP BY 1, 2, 3;

-- 2.5 Edge Table 1: `acsm_gold.graph_edge_holds_facility` (Customer -> CreditFacility)
CREATE OR REPLACE TABLE `acsm_gold.graph_edge_holds_facility`
CLUSTER BY cif_id, facility_id
OPTIONS (
  description = 'BigQuery Property Graph Edge Table (HOLDS_FACILITY): Connects Customer nodes to their Easy Payment (EP) and Credit Card (CC) CreditFacility nodes.'
) AS
SELECT
  CONCAT(f.cif_id, '->', f.facility_id) AS edge_id,
  f.cif_id,
  f.facility_id,
  f.product_line,
  f.exposure_amount_myr,
  f.new_dsr,
  f.application_status
FROM `acsm_gold.graph_node_credit_facility` f
INNER JOIN `acsm_gold.graph_node_customer` c
  ON f.cif_id = c.cif_id;

-- 2.6 Edge Table 2: `acsm_gold.graph_edge_transacted_at` (Customer -> Merchant)
CREATE OR REPLACE TABLE `acsm_gold.graph_edge_transacted_at`
CLUSTER BY cif_id, merchant_id
OPTIONS (
  description = 'BigQuery Property Graph Edge Table (TRANSACTED_AT): Connects Customer nodes to Merchant nodes with aggregated MYR spend and transaction count.'
) AS
WITH combined_tx AS (
  SELECT
    CAST(CIF_No AS STRING) AS cif_id,
    TRIM(CAST(LDESC AS STRING)) AS merchant_id,
    'CC' AS product_line,
    TRIM(CAST(Sales_Type AS STRING)) AS sales_type,
    CAST(Amount AS FLOAT64) AS amount_myr,
    CAST(TransCount AS INT64) AS tx_count
  FROM `acsm_bronze.Fact_CC_Sales`
  WHERE CIF_No IS NOT NULL AND LDESC IS NOT NULL AND TRIM(CAST(LDESC AS STRING)) != ''
  UNION ALL
  SELECT
    CAST(CIF_No AS STRING) AS cif_id,
    TRIM(CAST(LDESC AS STRING)) AS merchant_id,
    'EP' AS product_line,
    TRIM(CAST(Sales_Type AS STRING)) AS sales_type,
    CAST(Amount AS FLOAT64) AS amount_myr,
    CAST(TransCount AS INT64) AS tx_count
  FROM `acsm_bronze.Fact_EP_Sales`
  WHERE CIF_No IS NOT NULL AND LDESC IS NOT NULL AND TRIM(CAST(LDESC AS STRING)) != ''
),
agg_tx AS (
  SELECT
    cif_id,
    merchant_id,
    MAX(product_line) AS product_line,
    MAX(sales_type) AS sales_type,
    ROUND(SUM(amount_myr), 2) AS total_spend_myr,
    SUM(COALESCE(tx_count, 1)) AS tx_count
  FROM combined_tx
  GROUP BY cif_id, merchant_id
)
SELECT
  CONCAT(t.cif_id, '->', t.merchant_id) AS edge_id,
  t.cif_id,
  t.merchant_id,
  t.product_line,
  t.sales_type,
  t.total_spend_myr,
  t.tx_count
FROM agg_tx t
INNER JOIN `acsm_gold.graph_node_customer` c
  ON t.cif_id = c.cif_id
INNER JOIN `acsm_gold.graph_node_merchant` m
  ON t.merchant_id = m.merchant_id;

-- 2.7 Edge Table 3: `acsm_gold.graph_edge_works_in_segment` (Customer -> EmployerSegment)
CREATE OR REPLACE TABLE `acsm_gold.graph_edge_works_in_segment`
CLUSTER BY cif_id, employer_segment_id
OPTIONS (
  description = 'BigQuery Property Graph Edge Table (WORKS_IN_SEGMENT): Connects Customer nodes to their Employer/NOB and State segment node.'
) AS
WITH latest_cif AS (
  SELECT
    CAST(CIF_ID AS STRING) AS cif_id,
    CONCAT(
      COALESCE(NULLIF(TRIM(CAST(NOB AS STRING)), ''), 'GENERAL_SECTOR'),
      '|',
      COALESCE(NULLIF(TRIM(CAST(State AS STRING)), ''), 'UNKNOWN_STATE')
    ) AS employer_segment_id,
    CAST(N_YrJob AS INT64) AS years_in_job,
    ROUND(CAST(B_NetIncome AS FLOAT64), 2) AS net_income_myr
  FROM `acsm_bronze.m3CIF`
  WHERE CIF_ID IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(CIF_ID AS STRING) ORDER BY Rcd_DT DESC) = 1
)
SELECT
  CONCAT(l.cif_id, '->', l.employer_segment_id) AS edge_id,
  l.cif_id,
  l.employer_segment_id,
  COALESCE(l.years_in_job, 0) AS years_in_job,
  COALESCE(l.net_income_myr, 0.0) AS net_income_myr
FROM latest_cif l
INNER JOIN `acsm_gold.graph_node_customer` c
  ON l.cif_id = c.cif_id
INNER JOIN `acsm_gold.graph_node_employer_segment` e
  ON l.employer_segment_id = e.employer_segment_id;

-- =============================================================================
-- SECTION 3: CREATE BIGQUERY PROPERTY GRAPH (`acsm_gold.acsm_credit_ecosystem_graph`)
-- =============================================================================
CREATE OR REPLACE PROPERTY GRAPH `acsm_gold.acsm_credit_ecosystem_graph`
NODE TABLES (
  `acsm_gold.graph_node_customer` AS Customer
    KEY (cif_id)
    LABEL Customer
    PROPERTIES (
      cif_id, customer_name, state, region, occupation, age,
      net_income_myr, pdpa_marketing_consent, wallet_tier, akpk_status,
      active_card_count, total_cp_limit_myr, total_cp_usage_myr,
      combined_unpaid_osp_myr, worst_collection_score_grade, is_delinquent
    ),
  `acsm_gold.graph_node_credit_facility` AS CreditFacility
    KEY (facility_id)
    LABEL CreditFacility
    PROPERTIES (
      facility_id, cif_id, product_line, application_status,
      score_rank, credit_score, exposure_amount_myr, new_dsr
    ),
  `acsm_gold.graph_node_merchant` AS Merchant
    KEY (merchant_id)
    LABEL Merchant
    PROPERTIES (
      merchant_id, merchant_name, merchant_group,
      total_sales_volume_myr, total_tx_count, distinct_customers_count
    ),
  `acsm_gold.graph_node_employer_segment` AS EmployerSegment
    KEY (employer_segment_id)
    LABEL EmployerSegment
    PROPERTIES (
      employer_segment_id, employer_or_nob, state,
      employee_customer_count, avg_net_income_myr
    )
)
EDGE TABLES (
  `acsm_gold.graph_edge_holds_facility` AS HOLDS_FACILITY
    KEY (edge_id)
    SOURCE KEY (cif_id) REFERENCES Customer (cif_id)
    DESTINATION KEY (facility_id) REFERENCES CreditFacility (facility_id)
    LABEL HOLDS_FACILITY
    PROPERTIES (
      edge_id, cif_id, facility_id, product_line,
      exposure_amount_myr, new_dsr, application_status
    ),
  `acsm_gold.graph_edge_transacted_at` AS TRANSACTED_AT
    KEY (edge_id)
    SOURCE KEY (cif_id) REFERENCES Customer (cif_id)
    DESTINATION KEY (merchant_id) REFERENCES Merchant (merchant_id)
    LABEL TRANSACTED_AT
    PROPERTIES (
      edge_id, cif_id, merchant_id, product_line,
      sales_type, total_spend_myr, tx_count
    ),
  `acsm_gold.graph_edge_works_in_segment` AS WORKS_IN_SEGMENT
    KEY (edge_id)
    SOURCE KEY (cif_id) REFERENCES Customer (cif_id)
    DESTINATION KEY (employer_segment_id) REFERENCES EmployerSegment (employer_segment_id)
    LABEL WORKS_IN_SEGMENT
    PROPERTIES (
      edge_id, cif_id, employer_segment_id, years_in_job, net_income_myr
    )
);
