-- =============================================================================
-- DEMO FLOW 2 (STEP 2 OF 2): Serverless SQL `LOAD DATA OVERWRITE` from GCS
-- Loads all 1,398,284 records from `gs://acsm-workshop-landing-trustedtesterarvind`
-- into the 8 pre-created tables while preserving all 226 column descriptions.
-- Zero compute provisioning required | $0 BigQuery batch load cost (0 B billed).
-- =============================================================================

-- Load Fact_EP_Judge
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.Fact_EP_Judge`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/Fact_EP_Judge.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- Load Fact_EP_Sales
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.Fact_EP_Sales`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/Fact_EP_Sales.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- Load Fact_EP_Collection
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.Fact_EP_Collection`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/Fact_EP_Collection.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- Load Fact_CC_Judge
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.Fact_CC_Judge`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/Fact_CC_Judge.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- Load Fact_CC_Sales
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.Fact_CC_Sales`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/Fact_CC_Sales.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- Load Fact_CC_Collection
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.Fact_CC_Collection`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/Fact_CC_Collection.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- Load m3CIF
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.m3CIF`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/m3CIF.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

-- Load dimProduct
LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.dimProduct`
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/dimProduct.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);
