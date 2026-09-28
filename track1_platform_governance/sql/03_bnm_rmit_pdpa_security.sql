-- =============================================================================
-- TRACK 1 (NOTEBOOK 03): BNM RMiT & MALAYSIAN PDPA SECURITY & GOVERNANCE (PURE SQL)
-- File: 03_bnm_rmit_pdpa_security.sql
--
-- Fulfils ACSM RFP Clauses:
-- - C1.1.1.24 (Fine-Grained Access Control: Dynamic Row & Column Masking)
-- - C1.1.5.1  (BNM RMiT alignment: role separation, auditability, encryption)
-- - C1.1.5.3  (Malaysian PDPA 2010: PII masking, consent linkage, Right-to-Erasure)
-- - C1.1.5.5  (Dynamic Data Masking: Partial Redaction, SHA-256 Hash, Default Value 0.0)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Row-Level Security (RLS) Policies on Gold Customer 360 (Clause C1.1.1.24)
--    Creates two Row Access Policies on `acsm_gold.gold_aeon_customer360_profile`
--    so we can validate the exact same query with two different users/identities:
--      • Policy 1 (`rlp_central_region_branch_manager`):
--        Granted to User 1 (`user:<USER_EMAIL>` / `SESSION_USER()`)
--        Filter: `State IN ('Selangor', 'Kuala Lumpur', 'Putrajaya', 'Negeri Sembilan')`
--        Result: Sees ONLY the 4 Central Region Malaysian states (~25,000 customers;
--                all 12 other Malaysian states are filtered out).
--      • Policy 2 (`rlp_hq_compliance_all_states`):
--        Granted to User 2 (`serviceAccount:acsm-compliance-auditor-sa@<PROJECT_ID>.iam.gserviceaccount.com`)
--        Filter: `TRUE` (All 16 Malaysian States)
--        Result: Sees ALL 16 Malaysian states (the 4 Central Region states PLUS
--                all 12 other Malaysian states = 100,000 customers).
-- -----------------------------------------------------------------------------
EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE ROW ACCESS POLICY rlp_central_region_branch_manager
  ON `acsm_gold.gold_aeon_customer360_profile`
  GRANT TO ('%s:%s')
  FILTER USING (State IN ('Selangor', 'Kuala Lumpur', 'Putrajaya', 'Negeri Sembilan'))
""", IF(ENDS_WITH(SESSION_USER(), '.gserviceaccount.com'), 'serviceAccount', 'user'), SESSION_USER());

EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE ROW ACCESS POLICY rlp_hq_compliance_all_states
  ON `acsm_gold.gold_aeon_customer360_profile`
  GRANT TO ('serviceAccount:acsm-compliance-auditor-sa@%s.iam.gserviceaccount.com')
  FILTER USING (TRUE)
""", @@project_id);

-- -----------------------------------------------------------------------------
-- 2. Column-Level Security (CLS) & Dynamic Data Masking via IAM Data Governance Tags
--    (`purpose = DATA_GOVERNANCE` + BigQuery Data Policy API v2, Clauses C1.1.5.3 & C1.1.5.5)
--    Attaches 4 IAM Data Governance Tags directly to physical columns on
--    `acsm_gold.gold_aeon_customer360_profile` (provisioned by `setup_cls_data_governance_tags.py`):
--      • `CIF_NM`            -> `<PROJECT_ID>/pii_classification` = `customer_name`
--                               (Persona 1: `SHA256` hash | Persona 2: `RAW_DATA_ACCESS_POLICY` | Persona 3: `403 Access Denied`)
--      • `CIF_ID`            -> `<PROJECT_ID>/pii_classification` = `customer_id`
--                               (Persona 1: `LAST_FOUR_CHARACTERS` | Persona 2: `RAW_DATA_ACCESS_POLICY` | Persona 3: `403 Access Denied`)
--      • `B_NetIncome`       -> `<PROJECT_ID>/pii_classification` = `financial_amount`
--                               (Persona 1: `DEFAULT_MASKING_VALUE` 0.0 | Persona 2: `RAW_DATA_ACCESS_POLICY` | Persona 3: `403 Access Denied`)
--      • `latest_ctos_score` -> `<PROJECT_ID>/pii_classification` = `credit_bureau_score`
--                               (Persona 1: `ALWAYS_NULL` -> NULL | Persona 2: `RAW_DATA_ACCESS_POLICY` | Persona 3: `403 Access Denied`)
-- -----------------------------------------------------------------------------
EXECUTE IMMEDIATE FORMAT("""
  ALTER TABLE `acsm_gold.gold_aeon_customer360_profile`
  ALTER COLUMN CIF_NM
  SET OPTIONS (data_governance_tags=[('%s/pii_classification', 'customer_name')])
""", @@project_id);

EXECUTE IMMEDIATE FORMAT("""
  ALTER TABLE `acsm_gold.gold_aeon_customer360_profile`
  ALTER COLUMN CIF_ID
  SET OPTIONS (data_governance_tags=[('%s/pii_classification', 'customer_id')])
""", @@project_id);

EXECUTE IMMEDIATE FORMAT("""
  ALTER TABLE `acsm_gold.gold_aeon_customer360_profile`
  ALTER COLUMN B_NetIncome
  SET OPTIONS (data_governance_tags=[('%s/pii_classification', 'financial_amount')])
""", @@project_id);

EXECUTE IMMEDIATE FORMAT("""
  ALTER TABLE `acsm_gold.gold_aeon_customer360_profile`
  ALTER COLUMN latest_ctos_score
  SET OPTIONS (data_governance_tags=[('%s/pii_classification', 'credit_bureau_score')])
""", @@project_id);

-- -----------------------------------------------------------------------------
-- 3. Audit Active Column Data Governance Tags via INFORMATION_SCHEMA.COLUMNS
-- -----------------------------------------------------------------------------
SELECT
  table_schema AS dataset_id,
  table_name,
  column_name,
  data_type,
  data_governance_tags[SAFE_OFFSET(0)].key AS tag_key,
  data_governance_tags[SAFE_OFFSET(0)].value AS tag_value
FROM `acsm_gold.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'gold_aeon_customer360_profile'
  AND ARRAY_LENGTH(data_governance_tags) > 0
ORDER BY column_name;
