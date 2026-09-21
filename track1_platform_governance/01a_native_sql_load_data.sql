-- =============================================================================
-- Track 1 (Option A — 100% Pure SQL, Zero Python):
-- Native BigQuery `LOAD DATA INTO` + `00_create_8_tables_ddl_with_descriptions.sql`
--
-- Why this is the best approach for ACSM SQL/BI Engineers:
-- 1. Step 1: Run `00_create_8_tables_ddl_with_descriptions.sql` first.
--    That DDL pre-creates all 8 tables (`T1_Fact_EP_Judge` .. `T8_dimProduct`)
--    with 100% of Table Descriptions and all 226 Column Descriptions already
--    stored in BigQuery's catalog.
-- 2. Step 2: Run the pure SQL `LOAD DATA INTO` statements below from a GCS bucket.
--    Because the tables and column descriptions already exist, `LOAD DATA OVERWRITE`
--    (or `LOAD DATA INTO`) loads the `.csv.gz` data directly while PRESERVING
--    all 226 column descriptions and table descriptions automatically!
-- =============================================================================

-- Replace `gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/`
-- with your Cloud Storage bucket URI where the `.csv.gz` files are uploaded.

-- 1. T1_Fact_EP_Judge (140,000 rows | 60 columns described)
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T1_Fact_EP_Judge`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T1_Fact_EP_Judge.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- 2. T2_Fact_EP_Sales (119,859 rows | 9 columns described)
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T2_Fact_EP_Sales`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T2_Fact_EP_Sales.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- 3. T3_Fact_EP_Collection (80,000 rows | 21 columns described)
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T3_Fact_EP_Collection`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T3_Fact_EP_Collection.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- 4. T4_Fact_CC_Judge (227,500 rows | 54 columns described)
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T4_Fact_CC_Judge`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T4_Fact_CC_Judge_v2.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- 5. T5_Fact_CC_Sales (535,925 rows | 9 columns described)
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T5_Fact_CC_Sales`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T5_Fact_CC_Sales.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- 6. T6_Fact_CC_Collection (130,000 rows | 17 columns described)
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T6_Fact_CC_Collection`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T6_Fact_CC_Collection.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- 7. T7_m3CIF (100,000 rows | 34 columns described)
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T7_m3CIF`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T7_m3CIF.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- 8. T8_dimProduct (65,000 rows | 22 columns described)
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T8_dimProduct`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T8_dimProduct.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);
