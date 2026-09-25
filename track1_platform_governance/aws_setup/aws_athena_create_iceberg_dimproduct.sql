-- =============================================================================
-- ONE-TIME INSTRUCTOR SETUP IN AWS ATHENA (Region: ap-southeast-1 Singapore)
-- Creates AWS Glue Database `acsm_aws_bronze` and Apache Iceberg Table `dimProduct`
-- (65,000 rows, Credit Card Product Master stored as Parquet + Iceberg in S3)
--
-- Prerequisite:
-- Upload `dimProduct.csv.gz` to:
--   s3://<YOUR_S3_BUCKET>/acsm_staging/dimProduct/dimProduct.csv.gz
-- Replace `<YOUR_S3_BUCKET>` below with your S3 bucket in ap-southeast-1 (Singapore).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- STEP 1: Create the AWS Glue Database / Namespace (`acsm_aws_bronze`)
-- -----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS acsm_aws_bronze
COMMENT 'AEON Credit Service Malaysia (ACSM) AWS Glue Bronze Lakehouse Namespace for BigQuery Federation';

-- -----------------------------------------------------------------------------
-- STEP 2: Create Temporary CSV Staging Table over `dimProduct.csv.gz` in S3
-- -----------------------------------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS acsm_aws_bronze.dimproduct_csv_staging (
  Expiry_DT string,
  FirstSpend_DT string,
  Block_Code string,
  Block_Date string,
  CIC_Status string,
  Card_Status string,
  AKPK_Status string,
  Card_First_Emboss_Date string,
  Card_Emboss_Date string,
  Card_First_Activated_Date string,
  Card_Activated_Date string,
  CP_CL string,
  CP_CL_Available string,
  CA_CL string,
  CA_CL_Available string,
  CP_CL_Usage string,
  CA_CL_Usage string,
  CIF_ID string,
  Account_No string,
  Account_Agree_Sts string,
  Virtual_Card_Flag string,
  Wallet_Tier string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
  'separatorChar' = ',',
  'quoteChar'     = '"',
  'escapeChar'    = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://<YOUR_S3_BUCKET>/acsm_staging/dimProduct/'
TBLPROPERTIES ('skip.header.line.count'='1');

-- -----------------------------------------------------------------------------
-- STEP 3: Create the Native AWS Glue Apache Iceberg Table (`acsm_aws_bronze.dimProduct`)
--         Populates all 65,000 rows into open Parquet + Iceberg metadata on S3
-- -----------------------------------------------------------------------------
CREATE TABLE acsm_aws_bronze.dimProduct
WITH (
  table_type = 'ICEBERG',
  format = 'PARQUET',
  location = 's3://<YOUR_S3_BUCKET>/acsm_iceberg_warehouse/acsm_aws_bronze/dimProduct/',
  is_external = false
) AS
SELECT
  CAST(NULLIF(Expiry_DT, '') AS bigint) AS Expiry_DT,
  CAST(NULLIF(FirstSpend_DT, '') AS bigint) AS FirstSpend_DT,
  CAST(Block_Code AS varchar) AS Block_Code,
  CAST(NULLIF(Block_Date, '') AS bigint) AS Block_Date,
  CAST(CIC_Status AS varchar) AS CIC_Status,
  CAST(Card_Status AS varchar) AS Card_Status,
  CAST(AKPK_Status AS varchar) AS AKPK_Status,
  CAST(NULLIF(Card_First_Emboss_Date, '') AS bigint) AS Card_First_Emboss_Date,
  CAST(NULLIF(Card_Emboss_Date, '') AS bigint) AS Card_Emboss_Date,
  CAST(NULLIF(Card_First_Activated_Date, '') AS bigint) AS Card_First_Activated_Date,
  CAST(NULLIF(Card_Activated_Date, '') AS bigint) AS Card_Activated_Date,
  CAST(NULLIF(CP_CL, '') AS double) AS CP_CL,
  CAST(NULLIF(CP_CL_Available, '') AS double) AS CP_CL_Available,
  CAST(NULLIF(CA_CL, '') AS double) AS CA_CL,
  CAST(NULLIF(CA_CL_Available, '') AS double) AS CA_CL_Available,
  CAST(NULLIF(CP_CL_Usage, '') AS double) AS CP_CL_Usage,
  CAST(NULLIF(CA_CL_Usage, '') AS double) AS CA_CL_Usage,
  CAST(NULLIF(CIF_ID, '') AS bigint) AS CIF_ID,
  CAST(NULLIF(Account_No, '') AS bigint) AS Account_No,
  CAST(Account_Agree_Sts AS varchar) AS Account_Agree_Sts,
  CAST(Virtual_Card_Flag AS varchar) AS Virtual_Card_Flag,
  CAST(Wallet_Tier AS varchar) AS Wallet_Tier
FROM acsm_aws_bronze.dimproduct_csv_staging;

-- -----------------------------------------------------------------------------
-- STEP 4: Drop the Temporary CSV Staging Table so `acsm_aws_bronze` contains
--         ONLY the clean Apache Iceberg table `acsm_aws_bronze.dimProduct`
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS acsm_aws_bronze.dimproduct_csv_staging;

-- -----------------------------------------------------------------------------
-- STEP 5: Verify 65,000 Rows in AWS Athena
-- -----------------------------------------------------------------------------
SELECT
  Card_Status,
  Wallet_Tier,
  COUNT(*) AS total_cards,
  ROUND(AVG(CP_CL), 2) AS avg_limit_myr
FROM acsm_aws_bronze.dimProduct
GROUP BY 1, 2
ORDER BY total_cards DESC;
