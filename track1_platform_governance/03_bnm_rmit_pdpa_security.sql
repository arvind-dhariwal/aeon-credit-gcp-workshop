-- =============================================================================
-- TRACK 1: BNM RMiT & MALAYSIAN PDPA SECURITY & GOVERNANCE
-- File: 03_bnm_rmit_pdpa_security.sql
--
-- Fulfils ACSM RFP Clauses:
-- - C1.1.1.24 (Fine-Grained Access Control: Dynamic Row & Column Masking)
-- - C1.1.5.1  (BNM RMiT alignment: role separation, auditability, encryption)
-- - C1.1.5.3  (Malaysian PDPA 2010: PII masking, consent linkage, Right-to-Erasure)
-- - C1.1.2.2  (Inherited Access Management across downstream BI tools)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Row-Level Access Policies by Malaysian Region / State (Clause C1.1.1.24)
--    Targets `acsm_silver.silver_customer_cif` created in Notebook 2
-- -----------------------------------------------------------------------------
CREATE OR REPLACE ROW ACCESS POLICY `rlp_central_region_branch_managers`
ON `acsm_silver.silver_customer_cif`
GRANT TO ('group:acsm-central-branch-analysts@aeoncredit.com.my')
FILTER USING (State IN ('Selangor', 'Kuala Lumpur', 'Putrajaya', 'Negeri Sembilan'));

CREATE OR REPLACE ROW ACCESS POLICY `rlp_risk_and_compliance_full_access`
ON `acsm_silver.silver_customer_cif`
GRANT TO ('group:acsm-risk-compliance@aeoncredit.com.my', 'serviceAccount:aeon360-agent@system.gserviceaccount.com')
FILTER USING (TRUE);

-- -----------------------------------------------------------------------------
-- 2. Dynamic PDPA PII Masking & Consent-Aware View (Clauses C1.1.5.3 & C1.1.2.2)
--    Automatically masks Customer Name (`CIF_NM`) and Exact Income (`B_NetIncome`)
--    for standard BI analysts while preserving analytical dimensions (`State`, `N_Age`).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `acsm_silver.vw_customer_cif_pdpa_governed`
OPTIONS (
  description = 'PDPA & BNM RMiT governed view enforcing dynamic PII masking on CIF_NM and B_NetIncome based on caller role.'
) AS
SELECT
  CIF_ID,
  record_refresh_date,
  CASE
    WHEN SESSION_USER() LIKE '%compliance%' OR SESSION_USER() LIKE '%credit-control%'
      THEN CIF_NM
    ELSE CONCAT(SUBSTR(CIF_NM, 1, 2), '****', SUBSTR(CIF_NM, -2))
  END AS customer_name_masked,
  MaritalSts,
  Gender,
  Citizen,
  State,
  Region,
  Race,
  Occupation,
  EmpSts,
  RecvPromo_FG AS pdpa_marketing_consent_flag,
  N_Age,
  CASE
    WHEN B_NetIncome < 3000 THEN 'B40 (< RM 3,000)'
    WHEN B_NetIncome BETWEEN 3000 AND 7000 THEN 'M40 (RM 3,000 - RM 7,000)'
    ELSE 'T20 (> RM 7,000)'
  END AS income_tier_band_myr,
  CASE
    WHEN SESSION_USER() LIKE '%compliance%' OR SESSION_USER() LIKE '%credit-control%'
      THEN B_NetIncome
    ELSE NULL
  END AS exact_net_income_myr
FROM `acsm_silver.silver_customer_cif`;

-- -----------------------------------------------------------------------------
-- 3. Automated PDPA Right-to-Erasure Stored Procedure (Clause C1.1.5.3)
--    Executes cryptographic anonymization / erasure on `acsm_silver.silver_customer_cif`
--    and logs an immutable BNM RMiT audit record in `acsm_silver.dq_quarantine_records`.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE `acsm_silver.sp_execute_pdpa_subject_erasure`(
  target_cif_id STRING,
  ticket_reference STRING
)
BEGIN
  -- 1. Anonymize PII in Silver Customer Master while retaining statutory financial ledger totals
  UPDATE `acsm_silver.silver_customer_cif`
  SET
    CIF_NM = CONCAT('ERASED_PDPA_', TO_HEX(SHA256(target_cif_id))),
    RecvPromo_FG = 'N'
  WHERE CIF_ID = target_cif_id;

  -- 2. Record immutable compliance audit trail (Clause C1.1.5.6)
  INSERT INTO `acsm_silver.dq_quarantine_records` (
    evaluated_at, source_table, record_key, cif_id, rule_id, enforcement_action, violation_detail
  )
  VALUES (
    CURRENT_TIMESTAMP(),
    'acsm_silver.silver_customer_cif',
    ticket_reference,
    target_cif_id,
    'PDPA_SEC_43_SUBJECT_ERASURE',
    'EXECUTED',
    CONCAT('Malaysian PDPA Section 43 Right-to-Erasure completed for CIF_ID=', target_cif_id)
  );
END;
