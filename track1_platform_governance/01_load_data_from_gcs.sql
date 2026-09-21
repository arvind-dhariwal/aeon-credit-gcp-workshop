-- =============================================================================
-- DEMO FLOW 2 (STEP 2 OF 2): Serverless SQL `LOAD DATA OVERWRITE` from GCS
-- Loads all 1,398,284 records from `gs://acsm-workshop-landing-trustedtesterarvind`
-- into the 8 pre-created tables while preserving all 226 column descriptions.
-- Zero compute provisioning required | $0 BigQuery batch load cost (0 B billed).
-- =============================================================================

-- Load T1_Fact_EP_Judge
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T1_Fact_EP_Judge`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T1_Fact_EP_Judge.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- Load T2_Fact_EP_Sales
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T2_Fact_EP_Sales`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T2_Fact_EP_Sales.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- Load T3_Fact_EP_Collection
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T3_Fact_EP_Collection`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T3_Fact_EP_Collection.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- Load T4_Fact_CC_Judge
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T4_Fact_CC_Judge`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T4_Fact_CC_Judge_v2.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- Load T5_Fact_CC_Sales
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T5_Fact_CC_Sales`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T5_Fact_CC_Sales.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- Load T6_Fact_CC_Collection
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T6_Fact_CC_Collection`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T6_Fact_CC_Collection.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- Load T7_m3CIF
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T7_m3CIF`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T7_m3CIF.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- Load T8_dimProduct
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T8_dimProduct`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T8_dimProduct.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);
