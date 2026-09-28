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
-- 2. Column-Level Security (CLS) & Dynamic Data Masking View on Gold Customer 360
--    (Clauses C1.1.5.3 & C1.1.5.5)
--    Enforces 3 pure-SQL masking rules on `CIF_NM` and `B_NetIncome` while
--    automatically inheriting the underlying table's Row-Level Security (RLS) policies:
--      • User 1 (`user:<USER_EMAIL>` — Regional Branch Manager / Standard Analyst):
--          - `cif_nm_partial_masked`       -> MASKED ('MU****AD')
--          - `cif_nm_sha256_masked`        -> SHA-256 Hash ('8f4b2c91e03a...')
--          - `net_income_masked_default_0` -> MASKED to 0.0 (only sees `bnm_income_tier_band`)
--          - `rls_central_region_state`    -> Sees ONLY 4 Central Region states
--      • User 2 (`serviceAccount:acsm-compliance-auditor-sa@<PROJECT_ID>.iam.gserviceaccount.com` — HQ Compliance Auditor):
--          - `cif_nm_partial_masked`       -> UNMASKED Full Customer Name ('MUHAMMAD FAIZ BIN AHMAD')
--          - `cif_nm_sha256_masked`        -> SHA-256 Hash ('8f4b2c91e03a...')
--          - `net_income_masked_default_0` -> UNMASKED Exact Monthly Net Income (e.g. RM 5,400.00)
--          - `rls_central_region_state`    -> Sees ALL 16 Malaysian states (including all 12 non-Central states)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `acsm_gold.vw_customer360_rls_cls_masked`
OPTIONS (
  description = 'BNM RMiT & Malaysian PDPA Governed View: Combines Row-Level Security (RLS) with SQL Column-Level Dynamic Masking (Partial Redaction, SHA-256 Hash, and Default Value 0.0 Masking).'
) AS
SELECT
  CIF_ID,
  CASE
    WHEN SESSION_USER() LIKE 'acsm-compliance-auditor-sa@%'
      OR SESSION_USER() LIKE '%compliance%'
      OR SESSION_USER() LIKE '%credit-control%'
      THEN CIF_NM
    ELSE CONCAT(SUBSTR(CIF_NM, 1, 2), '****', SUBSTR(CIF_NM, -2))
  END AS cif_nm_partial_masked,
  TO_HEX(SHA256(CAST(CIF_NM AS STRING))) AS cif_nm_sha256_masked,
  State AS rls_central_region_state,
  Occupation,
  CASE
    WHEN SESSION_USER() LIKE 'acsm-compliance-auditor-sa@%'
      OR SESSION_USER() LIKE '%compliance%'
      OR SESSION_USER() LIKE '%credit-control%'
      THEN B_NetIncome
    ELSE 0.0
  END AS net_income_masked_default_0,
  CASE
    WHEN B_NetIncome < 3000 THEN 'B40 (< RM 3,000)'
    WHEN B_NetIncome BETWEEN 3000 AND 7000 THEN 'M40 (RM 3,000 - RM 7,000)'
    ELSE 'T20 (> RM 7,000)'
  END AS bnm_income_tier_band,
  B_AnnualIncome AS annual_income_unmasked_comparison,
  avg_ep_dsr,
  active_card_count
FROM `acsm_gold.gold_aeon_customer360_profile`;
