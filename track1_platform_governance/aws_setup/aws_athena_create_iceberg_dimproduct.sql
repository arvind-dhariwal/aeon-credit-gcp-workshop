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
  Account_No string,
  CIF_ID string,
  Card_Open_DT string,
  Brand_Card_Type string,
  Card_Sub_Category string,
  Card_Prd_Type string,
  Card_Status string,
  Card_Collection_Status string,
  CP_CL string,
  CP_CL_Usage string,
  CP_CL_Available string,
  CC_CA_Usage string,
  CC_CA_Available string
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
  CAST(Account_No AS varchar) AS Account_No,
  CAST(CIF_ID AS varchar) AS CIF_ID,
  CAST(Card_Open_DT AS varchar) AS Card_Open_DT,
  CAST(Brand_Card_Type AS varchar) AS Brand_Card_Type,
  CAST(Card_Sub_Category AS varchar) AS Card_Sub_Category,
  CAST(Card_Prd_Type AS varchar) AS Card_Prd_Type,
  CAST(Card_Status AS varchar) AS Card_Status,
  CAST(Card_Collection_Status AS varchar) AS Card_Collection_Status,
  CAST(NULLIF(CP_CL, '') AS double) AS CP_CL,
  CAST(NULLIF(CP_CL_Usage, '') AS double) AS CP_CL_Usage,
  CAST(NULLIF(CP_CL_Available, '') AS double) AS CP_CL_Available,
  CAST(NULLIF(CC_CA_Usage, '') AS double) AS CC_CA_Usage,
  CAST(NULLIF(CC_CA_Available, '') AS double) AS CC_CA_Available
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
  Brand_Card_Type,
  COUNT(*) AS total_cards,
  ROUND(AVG(CP_CL), 2) AS avg_limit_myr
FROM acsm_aws_bronze.dimProduct
GROUP BY 1, 2
ORDER BY total_cards DESC;
