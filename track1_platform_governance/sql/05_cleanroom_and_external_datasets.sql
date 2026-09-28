-- =============================================================================
-- TRACK 1 (NOTEBOOK 04 — LAB 1.4): ANALYTICS HUB, BIGQUERY DATA CLEAN ROOMS
-- & EXTERNAL DATASETS
-- File: 05_cleanroom_and_external_datasets.sql
-- Region: asia-southeast1 (Singapore)
-- =============================================================================

-- 1. Create Clean Room, Partner (AEON Retail), & Subscribed External Data Schemas in asia-southeast1
CREATE SCHEMA IF NOT EXISTS `acsm_cleanroom`
OPTIONS (
  location = 'asia-southeast1',
  description = 'ACSM & AEON Retail Privacy-Preserving Data Clean Room in Singapore (asia-southeast1) — BNM RMiT & Malaysian PDPA Compliant'
);

CREATE SCHEMA IF NOT EXISTS `aeon_retail`
OPTIONS (
  location = 'asia-southeast1',
  description = 'Party 2 (AEON Retail Malaysia / AEON BiG) Partner Loyalty Dataset in Singapore (asia-southeast1) contributed to the Data Clean Room'
);

CREATE SCHEMA IF NOT EXISTS `acsm_subscribed_data`
OPTIONS (
  location = 'asia-southeast1',
  description = 'Subscribed External Google Datasets via Analytics Hub in Singapore (asia-southeast1): Google Trends, Malaysia Places POI Catalog, and Google Ads Campaign Performance'
);

CREATE SCHEMA IF NOT EXISTS `acsm_analyticshub_shared`
OPTIONS (
  location = 'asia-southeast1',
  description = 'ACSM Dedicated Analytics Hub Shared Publisher Dataset in Singapore (asia-southeast1) — exposes ONLY curated zero-copy views to AEON Retail without exposing internal acsm_gold tables'
);

-- =============================================================================
-- PART A: ANALYTICS HUB ZERO-COPY SHARED VIEW (ACSM -> AEON RETAIL)
-- =============================================================================
CREATE OR REPLACE VIEW `acsm_analyticshub_shared.vw_analyticshub_merchant_spend_aggregations`
OPTIONS (
  description = 'Curated Analytics Hub Zero-Copy Authorized View: ACSM Merchant Spend Aggregations shared with AEON Retail without exposing internal gold tables or individual cardholder PII'
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
CREATE OR REPLACE TABLE `aeon_retail.partner_aeon_retail_shoppers`
CLUSTER BY hashed_cif_match, preferred_aeon_store
OPTIONS (
  description = 'Party 2 (AEON Retail Malaysia) Supermarket & Department Store Loyalty Member Spend contributed to the ACSM-AEON Data Clean Room (keyed on privacy-safe CIF match identifier).'
) AS
SELECT
  CAST(c.CIF_ID AS STRING) AS hashed_cif_match,
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

-- Create a Clean Room Privacy-Enforced View with Native BigQuery Analysis Rules (`OPTIONS(privacy_policy=...)`)
-- Enforces Aggregation Threshold (threshold = 20 on privacy_unit_columns = 'CIF_ID') and Join Restriction Policy (JOIN_NOT_REQUIRED on CIF_ID, State)
CREATE OR REPLACE VIEW `acsm_cleanroom.vw_cleanroom_joint_customer_spend`
OPTIONS (
  description = 'BNM RMiT & PDPA Compliant Clean Room View: Enforces Aggregation Threshold Analysis Rule (threshold=20, privacy_unit_columns=CIF_ID) and Join Restriction Policy (JOIN_NOT_REQUIRED on CIF_ID, State) on joint ACSM Cardholder + AEON Supermarket Loyalty spend.',
  privacy_policy = '''{
    "aggregation_threshold_policy": {
      "threshold": 20,
      "privacy_unit_columns": "CIF_ID"
    },
    "join_restriction_policy": {
      "join_condition": "JOIN_NOT_REQUIRED",
      "join_allowed_columns": ["CIF_ID", "State"]
    }
  }'''
) AS
SELECT
  CAST(c.CIF_ID AS STRING) AS CIF_ID,
  c.State,
  c.MaritalSts,
  CAST(c.B_GrossIncome AS NUMERIC) AS monthly_income_rm,
  CAST(s.Amount AS NUMERIC) AS card_spend_rm,
  r.retail_spend_amt AS aeon_supermarket_spend_rm,
  r.preferred_aeon_store,
  r.loyalty_tier
FROM `acsm_bronze.m3CIF` c
JOIN `acsm_bronze.Fact_CC_Sales` s
  ON CAST(c.CIF_ID AS STRING) = CAST(s.CIF_No AS STRING)
JOIN `aeon_retail.partner_aeon_retail_shoppers` r
  ON CAST(c.CIF_ID AS STRING) = CAST(r.hashed_cif_match AS STRING);

-- =============================================================================
-- PART C: LEVERAGING LIVE GOOGLE PUBLIC DATASETS & ANALYTICS HUB PUBLIC LISTINGS
-- =============================================================================
-- Instead of mocked sample rows, Lab 1.4 Part C directly leverages 3 real Google
-- Public Datasets and Analytics Hub Public Listings for Malaysia:
--
--   1. Google Trends International (`bigquery-public-data.google_trends.international_top_terms`
--      & `international_top_rising_terms` where `country_name = 'Malaysia'`)
--      -> Queried directly in `US` and synced to `acsm_subscribed_data.google_trends_malaysia_top_terms`
--         in `asia-southeast1` via `analyticshub_helper.py setup-public-datasets`.
--
--   2. Google Maps Places Insights — Kuala Lumpur, Malaysia (`MY`) Sample Listing
--      (`projects/1069876207066/locations/us/dataExchanges/places_insights_sample_exchange/listings/places_insights_sample_my`
--       -> Subscribed Linked Dataset: `places_insights___my___sample.places_sample`)
--      -> Queried directly in `US` and synced to `acsm_subscribed_data.malaysia_places_insights_kl`
--         in `asia-southeast1` via `analyticshub_helper.py setup-public-datasets`.
--
--   3. Google Ads Public Datasets:
--      a) `bigquery-public-data.google_ads_geo_mapping_asia_southeast1.ads_geo_criteria_mapping`
--         & `ads_geo_region_mapping` (Natively hosted in `asia-southeast1` Singapore!)
--      b) `bigquery-public-data.google_ads_transparency_center.creative_stats` (`US`)
--         -> Queried directly in `US` and synced to `acsm_subscribed_data.google_ads_transparency_creatives`
--            in `asia-southeast1` via `analyticshub_helper.py setup-public-datasets`.
-- =============================================================================

-- C.1: Native `asia-southeast1` View & Table from `bigquery-public-data.google_ads_geo_mapping_asia_southeast1`
CREATE OR REPLACE TABLE `acsm_subscribed_data.google_ads_malaysia_geo_targets`
CLUSTER BY region_iso_3166_2, acsm_state
OPTIONS (
  description = 'Real Google Ads Geo Targeting Criteria & ISO-3166-2 Regions for Malaysia extracted directly from bigquery-public-data.google_ads_geo_mapping_asia_southeast1 (natively hosted in Singapore asia-southeast1).'
) AS
SELECT
  r.region_iso_3166_2,
  r.target_region AS google_ads_target_region,
  r.target_country_region AS country_name,
  r.target_subcontinent AS subcontinent,
  CASE r.region_iso_3166_2
    WHEN 'MY-01' THEN 'Johor'
    WHEN 'MY-02' THEN 'Kedah'
    WHEN 'MY-03' THEN 'Kelantan'
    WHEN 'MY-04' THEN 'Melaka'
    WHEN 'MY-05' THEN 'Negeri Sembilan'
    WHEN 'MY-06' THEN 'Pahang'
    WHEN 'MY-07' THEN 'Pulau Pinang'
    WHEN 'MY-08' THEN 'Perak'
    WHEN 'MY-09' THEN 'Perlis'
    WHEN 'MY-10' THEN 'Selangor'
    WHEN 'MY-11' THEN 'Terengganu'
    WHEN 'MY-12' THEN 'Sabah'
    WHEN 'MY-13' THEN 'Sarawak'
    WHEN 'MY-14' THEN 'Kuala Lumpur'
    WHEN 'MY-15' THEN 'Labuan'
    WHEN 'MY-16' THEN 'Putrajaya'
    ELSE r.target_region
  END AS acsm_state,
  COUNT(DISTINCT c.ads_criteria_id) AS targetable_ads_criteria_ids,
  COUNT(DISTINCT c.target_city) AS targetable_malaysian_cities,
  STRING_AGG(DISTINCT c.target_city, ', ' ORDER BY c.target_city LIMIT 5) AS sample_target_cities
FROM `bigquery-public-data.google_ads_geo_mapping_asia_southeast1.ads_geo_region_mapping` r
LEFT JOIN `bigquery-public-data.google_ads_geo_mapping_asia_southeast1.ads_geo_criteria_mapping` c
  ON r.target_country_region = c.target_country_region
 AND r.target_region = c.target_region
WHERE r.target_country_region = 'Malaysia'
GROUP BY 1, 2, 3, 4, 5;

-- =============================================================================
-- C.2: BIGQUERY GEOSPATIAL ANALYTICS (`GEOGRAPHY` DATA TYPE & SPATIAL CLUSTERING)
-- Reference: https://docs.cloud.google.com/bigquery/docs/geospatial-data
-- Persists WGS84 `GEOGRAPHY` points (`ST_GEOGPOINT`), 5 km spherical geodesic
-- catchment polygons (`ST_BUFFER`), WKT (`ST_ASTEXT`), and GeoJSON (`ST_ASGEOJSON`),
-- clustered by the `GEOGRAPHY` column (`CLUSTER BY branch_geog`) for optimized
-- spatial joins (`ST_DWITHIN`, `ST_INTERSECTS`, `ST_CONTAINS`, `ST_DISTANCE`).
-- =============================================================================
CREATE OR REPLACE TABLE `acsm_subscribed_data.aeon_malaysia_branch_hubs_geog`
CLUSTER BY branch_geog, malaysian_state
OPTIONS (
  description = 'Geospatial Feature Collection of AEON Mall & ACSM Branch Hubs across Malaysia with persisted GEOGRAPHY points (ST_GEOGPOINT) and 5km catchment polygons (ST_BUFFER), clustered by branch_geog.'
) AS
WITH raw_hubs AS (
  SELECT * FROM UNNEST([
    STRUCT('HUB_KL_MIDVALLEY' AS hub_id, 'AEON Mall Mid Valley Megamall' AS aeon_hub_name, 'Kuala Lumpur' AS malaysian_state, 'Central' AS region, 101.6774 AS longitude, 3.1177 AS latitude),
    STRUCT('HUB_KL_MALURI', 'AEON Style Taman Maluri', 'Kuala Lumpur', 'Central', 101.7295, 3.1259),
    STRUCT('HUB_KL_KEPONG', 'AEON BiG Kepong & Metro Prima', 'Kuala Lumpur', 'Central', 101.6366, 3.2135),
    STRUCT('HUB_KL_ALPHA_ANGLE', 'AEON Alpha Angle Wangsa Maju', 'Kuala Lumpur', 'Central', 101.7322, 3.2054),
    STRUCT('HUB_KL_AU2', 'AEON Mall AU2 Setiawangsa', 'Kuala Lumpur', 'Central', 101.7495, 3.1766),
    STRUCT('HUB_SEL_SHAH_ALAM', 'AEON Mall Shah Alam', 'Selangor', 'Central', 101.5432, 3.0769),
    STRUCT('HUB_SEL_BUKIT_TINGGI', 'AEON Mall Bukit Tinggi Klang', 'Selangor', 'Central', 101.4426, 2.9945),
    STRUCT('HUB_SEL_CHERAS_SELATAN', 'AEON Mall Cheras Selatan', 'Selangor', 'Central', 101.7584, 3.0338),
    STRUCT('HUB_JHR_TEBRAU', 'AEON Mall Tebrau City Johor', 'Johor', 'Southern', 103.7959, 1.5494),
    STRUCT('HUB_PNG_QUEENSBAY', 'AEON Mall Queensbay Penang', 'Pulau Pinang', 'Northern', 100.3069, 5.3332),
    STRUCT('HUB_PRK_KINTA_CITY', 'AEON Mall Kinta City Ipoh', 'Perak', 'Northern', 101.1235, 4.6143),
    STRUCT('HUB_SWK_KUCHING', 'AEON Mall Kuching Central', 'Sarawak', 'East Malaysia', 110.3358, 1.5293)
  ])
)
SELECT
  hub_id,
  aeon_hub_name,
  malaysian_state,
  region,
  longitude,
  latitude,
  ST_GEOGPOINT(longitude, latitude) AS branch_geog,
  ST_BUFFER(ST_GEOGPOINT(longitude, latitude), 5000) AS catchment_5km_polygon_geog,
  ST_ASTEXT(ST_GEOGPOINT(longitude, latitude)) AS branch_wkt,
  ST_ASGEOJSON(ST_GEOGPOINT(longitude, latitude)) AS branch_geojson
FROM raw_hubs;


