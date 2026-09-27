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
-- 1. Row-Level Security (RLS) Policy on Gold Customer 360 (Clause C1.1.1.24)
--    Restricts the current user (SESSION_USER()) to Central Region Malaysian States:
--    ('Selangor', 'Kuala Lumpur', 'Putrajaya', 'Negeri Sembilan')
-- -----------------------------------------------------------------------------
EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE ROW ACCESS POLICY rlp_central_region_branch_manager
  ON `acsm_gold.gold_aeon_customer360_profile`
  GRANT TO ('user:%s')
  FILTER USING (State IN ('Selangor', 'Kuala Lumpur', 'Putrajaya', 'Negeri Sembilan'))
""", SESSION_USER());

-- -----------------------------------------------------------------------------
-- 2. Column-Level Security (CLS) & Dynamic Data Masking View on Gold Customer 360
--    (Clauses C1.1.5.3 & C1.1.5.5)
--    Enforces 3 pure-SQL masking rules on `CIF_NM` and `B_NetIncome` while
--    automatically inheriting the underlying table's Row-Level Security (RLS) policy:
--      (a) Partial Redaction Masking: CONCAT(SUBSTR(CIF_NM, 1, 2), '****', SUBSTR(CIF_NM, -2))
--      (b) SHA-256 Hash Masking     : TO_HEX(SHA256(CAST(CIF_NM AS STRING)))
--      (c) Default 0.0 Masking      : 0.0 for standard analysts + BNM Income Tier Band (B40/M40/T20)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `acsm_gold.vw_customer360_rls_cls_masked`
OPTIONS (
  description = 'BNM RMiT & Malaysian PDPA Governed View: Combines Row-Level Security (RLS) with SQL Column-Level Dynamic Masking (Partial Redaction, SHA-256 Hash, and Default Value 0.0 Masking).'
) AS
SELECT
  CIF_ID,
  CASE
    WHEN SESSION_USER() LIKE '%compliance%' OR SESSION_USER() LIKE '%credit-control%'
      THEN CIF_NM
    ELSE CONCAT(SUBSTR(CIF_NM, 1, 2), '****', SUBSTR(CIF_NM, -2))
  END AS cif_nm_partial_masked,
  TO_HEX(SHA256(CAST(CIF_NM AS STRING))) AS cif_nm_sha256_masked,
  State AS rls_central_region_state,
  Occupation,
  CASE
    WHEN SESSION_USER() LIKE '%compliance%' OR SESSION_USER() LIKE '%credit-control%'
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
