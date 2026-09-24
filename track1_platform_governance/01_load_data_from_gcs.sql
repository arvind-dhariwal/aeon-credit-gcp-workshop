-- =============================================================================
-- DEMO FLOW 2 (STEP 2 OF 2): Serverless SQL `LOAD DATA OVERWRITE` from GCS
-- Dynamically resolves `@@project_id` (`gs://acsm-workshop-landing-${PROJECT_ID}/full_compressed/`)
-- into the 8 pre-created `acsm_bronze` tables while preserving all 226 column descriptions.
-- Zero compute provisioning required | $0 BigQuery batch load cost (0 B billed).
-- =============================================================================

DECLARE bucket_uri STRING DEFAULT CONCAT('gs://acsm-workshop-landing-', @@project_id, '/full_compressed');

-- 1. Load Fact_EP_Judge (140,000 rows)
EXECUTE IMMEDIATE FORMAT("""
LOAD DATA OVERWRITE `acsm_bronze.Fact_EP_Judge`
FROM FILES (
  format = 'CSV',
  uris = ['%s/Fact_EP_Judge.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);
""", bucket_uri);

-- 2. Load Fact_EP_Sales (119,859 rows)
EXECUTE IMMEDIATE FORMAT("""
LOAD DATA OVERWRITE `acsm_bronze.Fact_EP_Sales`
FROM FILES (
  format = 'CSV',
  uris = ['%s/Fact_EP_Sales.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);
""", bucket_uri);

-- 3. Load Fact_EP_Collection (80,000 rows)
EXECUTE IMMEDIATE FORMAT("""
LOAD DATA OVERWRITE `acsm_bronze.Fact_EP_Collection`
FROM FILES (
  format = 'CSV',
  uris = ['%s/Fact_EP_Collection.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);
""", bucket_uri);

-- 4. Load Fact_CC_Judge (227,500 rows)
EXECUTE IMMEDIATE FORMAT("""
LOAD DATA OVERWRITE `acsm_bronze.Fact_CC_Judge`
FROM FILES (
  format = 'CSV',
  uris = ['%s/Fact_CC_Judge.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);
""", bucket_uri);

-- 5. Load Fact_CC_Sales (535,925 rows)
EXECUTE IMMEDIATE FORMAT("""
LOAD DATA OVERWRITE `acsm_bronze.Fact_CC_Sales`
FROM FILES (
  format = 'CSV',
  uris = ['%s/Fact_CC_Sales.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);
""", bucket_uri);

-- 6. Load Fact_CC_Collection (130,000 rows)
EXECUTE IMMEDIATE FORMAT("""
LOAD DATA OVERWRITE `acsm_bronze.Fact_CC_Collection`
FROM FILES (
  format = 'CSV',
  uris = ['%s/Fact_CC_Collection.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);
""", bucket_uri);

-- 7. Load m3CIF (100,000 rows)
EXECUTE IMMEDIATE FORMAT("""
LOAD DATA OVERWRITE `acsm_bronze.m3CIF`
FROM FILES (
  format = 'CSV',
  uris = ['%s/m3CIF.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);
""", bucket_uri);

-- 8. Load dimProduct (65,000 rows)
EXECUTE IMMEDIATE FORMAT("""
LOAD DATA OVERWRITE `acsm_bronze.dimProduct`
FROM FILES (
  format = 'CSV',
  uris = ['%s/dimProduct.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);
""", bucket_uri);
