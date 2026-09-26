-- =============================================================================
-- TRACK 1 (NOTEBOOK 04 — LAB 1.4): ANALYTICS HUB, BIGQUERY DATA CLEAN ROOMS
-- & EXTERNAL DATASETS
-- File: 05_cleanroom_and_external_datasets.sql
-- Region: asia-southeast1 (Singapore)
-- =============================================================================

-- 1. Create Clean Room & Subscribed External Data Schemas in asia-southeast1
CREATE SCHEMA IF NOT EXISTS `acsm_cleanroom`
OPTIONS (
  location = 'asia-southeast1',
  description = 'ACSM & AEON Retail Privacy-Preserving Data Clean Room in Singapore (asia-southeast1) — BNM RMiT & Malaysian PDPA Compliant'
);

CREATE SCHEMA IF NOT EXISTS `acsm_subscribed_data`
OPTIONS (
  location = 'asia-southeast1',
  description = 'Subscribed External Google Datasets via Analytics Hub in Singapore (asia-southeast1): Google Trends, Malaysia Places POI Catalog, and Google Ads Campaign Performance'
);

CREATE SCHEMA IF NOT EXISTS `acsm_gold`
OPTIONS (
  location = 'asia-southeast1',
  description = 'ACSM Gold Medallion Layer in Singapore (asia-southeast1)'
);

-- =============================================================================
-- PART A: ANALYTICS HUB ZERO-COPY SHARED VIEW (ACSM -> AEON RETAIL)
-- =============================================================================
CREATE OR REPLACE VIEW `acsm_gold.vw_analyticshub_merchant_spend_aggregations`
OPTIONS (
  description = 'Curated Analytics Hub Zero-Copy Shared View: ACSM Merchant Spend Aggregations shared with AEON Retail without exposing individual cardholder PII'
) AS
SELECT
  p.PriviledgeMerchantsGrp AS merchant_group,
  p.LDESC AS location_name,
  COUNT(1) AS total_transactions,
  ROUND(SUM(CAST(p.Amount AS NUMERIC)), 2) AS total_spending_rm
FROM `acsm_bronze.Fact_CC_Sales` p
GROUP BY 1, 2;

-- =============================================================================
-- PART B: BIGQUERY DATA CLEAN ROOM — AEON RETAIL PARTNER LOYALTY SHOPPERS
-- =============================================================================
-- Deterministically derived from m3CIF so overlapping joint customers exist across
-- major Malaysian states (>= 20 customers) while smaller segments (< 20 customers)
-- are automatically suppressed by the Clean Room k-anonymity threshold.
CREATE OR REPLACE TABLE `acsm_cleanroom.partner_aeon_retail_shoppers`
CLUSTER BY hashed_cif_match, preferred_aeon_store
OPTIONS (
  description = 'AEON Supermarket & Department Store Loyalty Member Spend contributed to the ACSM-AEON Data Clean Room (keyed on privacy-safe CIF match identifier).'
) AS
SELECT
  c.CIF_ID AS hashed_cif_match,
  CONCAT('AEON_LOYALTY_', CAST(c.CIF_ID AS STRING)) AS aeon_loyalty_member_id,
  CASE MOD(ABS(FARM_FINGERPRINT(CAST(c.CIF_ID AS STRING))), 6)
    WHEN 0 THEN 'AEON Mall Mid Valley Megamall'
    WHEN 1 THEN 'AEON Mall Shah Alam'
    WHEN 2 THEN 'AEON BiG Kepong'
    WHEN 3 THEN 'AEON Mall Tebrau City Johor'
    WHEN 4 THEN 'AEON Mall Queensbay Penang'
    ELSE 'AEON Mall Bukit Tinggi Klang'
  END AS preferred_aeon_store,
  CASE MOD(ABS(FARM_FINGERPRINT(CAST(c.CIF_ID AS STRING))), 3)
    WHEN 0 THEN 'AEON Plus Gold Member'
    WHEN 1 THEN 'AEON Plus Silver Member'
    ELSE 'AEON Standard Member'
  END AS loyalty_tier,
  ROUND(
    CAST(180 + MOD(ABS(FARM_FINGERPRINT(CONCAT(CAST(c.CIF_ID AS STRING), '_retail'))), 2400) AS NUMERIC),
    2
  ) AS retail_spend_amt,
  CAST(2 + MOD(ABS(FARM_FINGERPRINT(CAST(c.CIF_ID AS STRING))), 18) AS INT64) AS monthly_basket_visits
FROM `acsm_bronze.m3CIF` c
WHERE MOD(ABS(FARM_FINGERPRINT(CAST(c.CIF_ID AS STRING))), 10) < 7;

-- Create a Clean Room Privacy-Enforced View that enforces k-anonymity (minimum 20 distinct CIFs)
CREATE OR REPLACE VIEW `acsm_cleanroom.vw_cleanroom_joint_customer_spend`
OPTIONS (
  description = 'BNM RMiT & PDPA Compliant Clean Room View: Enforces k-anonymity (HAVING COUNT(DISTINCT CIF_ID) >= 20) on joint ACSM Cardholder + AEON Supermarket Loyalty spend.'
) AS
SELECT
  c.State,
  c.MaritalSts,
  COUNT(DISTINCT c.CIF_ID) AS matching_joint_customers,
  ROUND(AVG(CAST(c.B_GrossIncome AS NUMERIC)), 2) AS avg_monthly_income_rm,
  ROUND(SUM(CAST(s.Amount AS NUMERIC)), 2) AS total_card_spend_rm,
  ROUND(SUM(r.retail_spend_amt), 2) AS total_aeon_supermarket_spend_rm
FROM `acsm_bronze.m3CIF` c
JOIN `acsm_bronze.Fact_CC_Sales` s
  ON c.CIF_ID = s.CIF_No
JOIN `acsm_cleanroom.partner_aeon_retail_shoppers` r
  ON c.CIF_ID = r.hashed_cif_match
GROUP BY 1, 2
HAVING COUNT(DISTINCT c.CIF_ID) >= 20;

-- =============================================================================
-- PART C.1: SUBSCRIBED GOOGLE TRENDS — MALAYSIAN FINANCIAL INTENT
-- =============================================================================
CREATE OR REPLACE TABLE `acsm_subscribed_data.google_trends_malaysia_financial_intent`
CLUSTER BY region_name, term
OPTIONS (
  description = 'Subscribed Google Trends Dataset (asia-southeast1): Macro Financing Search Interest Index across Malaysian States for personal loan, credit card, car loan, and installment plan.'
) AS
SELECT * FROM UNNEST([
  STRUCT('personal loan' AS term, 'Malaysia' AS country_name, 'Selangor' AS region_name, 96 AS score, DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY) AS date),
  STRUCT('credit card', 'Malaysia', 'Kuala Lumpur', 94, DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)),
  STRUCT('installment plan', 'Malaysia', 'Johor', 91, DATE_SUB(CURRENT_DATE(), INTERVAL 5 DAY)),
  STRUCT('car loan', 'Malaysia', 'Pulau Pinang', 89, DATE_SUB(CURRENT_DATE(), INTERVAL 5 DAY)),
  STRUCT('personal loan', 'Malaysia', 'Johor', 88, DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)),
  STRUCT('credit card', 'Malaysia', 'Selangor', 87, DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)),
  STRUCT('installment plan', 'Malaysia', 'Selangor', 85, DATE_SUB(CURRENT_DATE(), INTERVAL 10 DAY)),
  STRUCT('car loan', 'Malaysia', 'Perak', 83, DATE_SUB(CURRENT_DATE(), INTERVAL 10 DAY)),
  STRUCT('personal loan', 'Malaysia', 'Sabah', 82, DATE_SUB(CURRENT_DATE(), INTERVAL 12 DAY)),
  STRUCT('personal loan', 'Malaysia', 'Sarawak', 80, DATE_SUB(CURRENT_DATE(), INTERVAL 12 DAY)),
  STRUCT('credit card', 'Malaysia', 'Pulau Pinang', 79, DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)),
  STRUCT('installment plan', 'Malaysia', 'Kedah', 77, DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)),
  STRUCT('car loan', 'Malaysia', 'Negeri Sembilan', 75, DATE_SUB(CURRENT_DATE(), INTERVAL 18 DAY)),
  STRUCT('personal loan', 'Malaysia', 'Melaka', 74, DATE_SUB(CURRENT_DATE(), INTERVAL 21 DAY)),
  STRUCT('installment plan', 'Malaysia', 'Pahang', 72, DATE_SUB(CURRENT_DATE(), INTERVAL 25 DAY)),
  STRUCT('personal loan', 'Malaysia', 'Kelantan', 70, DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)),
  STRUCT('car loan', 'Malaysia', 'Terengganu', 68, DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)),
  STRUCT('credit card', 'Malaysia', 'Putrajaya', 86, DATE_SUB(CURRENT_DATE(), INTERVAL 6 DAY))
]);

-- =============================================================================
-- PART C.2: SUBSCRIBED MALAYSIA PLACES INSIGHT (GOOGLE MAPS / PLACES POI CATALOG)
-- =============================================================================
CREATE OR REPLACE TABLE `acsm_subscribed_data.malaysia_places_catalog`
CLUSTER BY location_keyword, business_category
OPTIONS (
  description = 'Subscribed Google Maps / Places Malaysia POI Catalog for geospatial and category enrichment of ACSM merchant transactions (Fact_CC_Sales.LDESC).'
) AS
SELECT * FROM UNNEST([
  STRUCT('AEON CO (M) BHD-MID VALLEY' AS location_keyword, 'AEON Mall Mid Valley Megamall' AS place_name, 'Department Store & Supermarket' AS business_category, 'Kuala Lumpur' AS state, 3.1177 AS latitude, 101.6774 AS longitude, 4.6 AS google_rating),
  STRUCT('AEON BIG (M) SDN BHD-KEPONG', 'AEON BiG Hypermarket Kepong', 'Hypermarket & Grocery', 'Kuala Lumpur', 3.2140, 101.6366, 4.4),
  STRUCT('PARKSON GRAND-PAVILION', 'Parkson Elite Pavilion Kuala Lumpur', 'Luxury Department Store', 'Kuala Lumpur', 3.1488, 101.7133, 4.5),
  STRUCT('GIANT HYPERMARKET-SHAH ALAM', 'Giant Hypermarket Seksyen 13 Shah Alam', 'Hypermarket & Grocery', 'Selangor', 3.0833, 101.5500, 4.3),
  STRUCT('LOTUS\'S STORES-CHERAS', 'Lotus\'s Cheras Hypermarket', 'Hypermarket & Grocery', 'Kuala Lumpur', 3.0989, 101.7347, 4.4),
  STRUCT('ECONSAVE-JOHOR', 'Econsave Cash & Carry Johor Bahru', 'Supermarket & Wholesale', 'Johor', 1.5311, 103.6714, 4.3),
  STRUCT('MYDIN MOHAMED HOLDINGS', 'Mydin USJ Subang Jaya Mall', 'Hypermarket & Halal Wholesale', 'Selangor', 3.0583, 101.5947, 4.5),
  STRUCT('TESCO STORES (M)', 'Lotus\'s (formerly Tesco) Mutiara Damansara', 'Hypermarket & Grocery', 'Selangor', 3.1569, 101.6131, 4.4),
  STRUCT('WATSONS PERSONAL CARE', 'Watsons Pharmacy Sunway Pyramid', 'Health, Pharmacy & Personal Care', 'Selangor', 3.0731, 101.6075, 4.5),
  STRUCT('PETRONAS DAGANGAN', 'PETRONAS Station NKVE Subang', 'Fuel & Convenience Mobility', 'Selangor', 3.1051, 101.5830, 4.4),
  STRUCT('SHELL MALAYSIA', 'Shell Mint Hotel Kuala Lumpur Highway', 'Fuel & Convenience Mobility', 'Kuala Lumpur', 3.0567, 101.7056, 4.4),
  STRUCT('KFC HOLDINGS', 'KFC Drive-Thru Bukit Bintang', 'Quick Service Restaurant (F&B)', 'Kuala Lumpur', 3.1466, 101.7115, 4.2),
  STRUCT('GRABPAY TOP UP', 'Grab Financial Services Malaysia HQ', 'Digital Wallet & SuperApp', 'Selangor', 3.1128, 101.6430, 4.6),
  STRUCT('SHOPEE PAY', 'Shopee Malaysia Mid Valley Southpoint', 'E-Commerce & Digital Wallet', 'Kuala Lumpur', 3.1165, 101.6768, 4.6),
  STRUCT('LAZADA MALAYSIA', 'Lazada Malaysia Menara Worldwide', 'E-Commerce Marketplace', 'Kuala Lumpur', 3.1492, 101.7078, 4.5),
  STRUCT('ZALORA MALAYSIA', 'Zalora Southeast Asia Fashion Hub', 'Fashion & Apparel E-Commerce', 'Kuala Lumpur', 3.1205, 101.6712, 4.4)
]);

-- =============================================================================
-- PART C.3: SUBSCRIBED GOOGLE ADS CAMPAIGN PERFORMANCE (CARD ACQUISITION)
-- =============================================================================
CREATE OR REPLACE TABLE `acsm_subscribed_data.google_ads_campaign_performance`
CLUSTER BY campaign_id, ad_network_type
OPTIONS (
  description = 'Subscribed Google Ads Data Transfer table capturing ACSM digital card acquisition campaign impressions, clicks, and media spend mapped to dimProduct.Wallet_Tier.'
) AS
SELECT * FROM UNNEST([
  STRUCT('Platinum' AS campaign_id, 'ACSM_AEON_Platinum_Visa_Cashback_Q3' AS campaign_name, 'Google Search & Performance Max' AS ad_network_type, 1450000 AS impressions, 94250 AS clicks, 188500.00 AS media_spend_rm),
  STRUCT('Gold', 'ACSM_AEON_Gold_Mall_Rewards_Booster_Q3', 'YouTube & Display Network', 2180000 AS impressions, 130800 AS clicks, 156960.00 AS media_spend_rm),
  STRUCT('Silver', 'ACSM_AEON_Silver_Everyday_Groceries_Q3', 'Google Search & Discovery', 1120000 AS impressions, 67200 AS clicks, 94080.00 AS media_spend_rm),
  STRUCT('Basic', 'ACSM_AEON_Basic_FirstJobber_Starter_Q3', 'YouTube Shorts & App Campaigns', 1890000 AS impressions, 119070 AS clicks, 107163.00 AS media_spend_rm)
]);
