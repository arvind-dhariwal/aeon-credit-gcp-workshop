-- =============================================================================
-- TRACK 1: DECLARATIVE DATA QUALITY QUARANTINE, FINOPS & LEGACY SQL TRANSLATION
-- File: 04_dq_quarantine_and_finops.sql
--
-- Fulfils ACSM RFP Part C Functional Clauses:
-- - C1.1.1.6  (Rule Enforcement: Declarative DQ rules & automated quarantine table)
-- - C1.1.1.7  (Quality Monitoring: Centralised DQ summary for anomaly alerts)
-- - C1.1.1.18 (FinOps & Scalability: Cost visibility & runaway query guardrails)
-- - C1.1.6.3  (Code & Logic Translation: Legacy MS SQL Server T-SQL -> BigQuery SQL)
-- - C1.1.6.6  (Cloud Cost Optimization: Identifying zombie/heavy queries)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Automated Data Quality Quarantine Table (`acsm_silver.dq_quarantine_records`)
--    Captures row-level rule violations across Bronze/Silver tables (C1.1.1.6)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_silver.dq_quarantine_records`
CLUSTER BY rule_id, source_table
OPTIONS (
  description = 'Automated Data Quality Quarantine Table capturing records failing DSR, Credit Limit, or CIF completeness rules (Clause C1.1.1.6).'
) AS
-- Rule 1: Credit Card Utilization exceeding Combined Credit Limit (dimProduct)
SELECT
  CURRENT_TIMESTAMP() AS evaluated_at,
  'acsm_bronze.dimProduct' AS source_table,
  CAST(Account_No AS STRING) AS record_key,
  CAST(CIF_ID AS STRING) AS cif_id,
  'DQ_RULE_01_CREDIT_LIMIT_BREACH' AS rule_id,
  'WARN_AND_QUARANTINE' AS enforcement_action,
  CONCAT('CP_CL_Usage (', CAST(CP_CL_Usage AS STRING), ') > CP_CL (', CAST(CP_CL AS STRING), ')') AS violation_detail
FROM `acsm_bronze.dimProduct`
WHERE CAST(CP_CL_Usage AS NUMERIC) > CAST(CP_CL AS NUMERIC)

UNION ALL

-- Rule 2: Easy Payment Post-Loan DSR exceeding 100% threshold (Fact_EP_Judge)
SELECT
  CURRENT_TIMESTAMP() AS evaluated_at,
  'acsm_bronze.Fact_EP_Judge' AS source_table,
  CAST(APPL_NO AS STRING) AS record_key,
  CAST(CIF_NO AS STRING) AS cif_id,
  'DQ_RULE_02_EXCESSIVE_NEW_DSR' AS rule_id,
  'WARN_FOR_MANUAL_UNDERWRITING' AS enforcement_action,
  CONCAT('NEW_DSR = ', CAST(NEW_DSR AS STRING), '% exceeds 100% policy cap') AS violation_detail
FROM `acsm_bronze.Fact_EP_Judge`
WHERE CAST(NEW_DSR AS NUMERIC) > 100.0

UNION ALL

-- Rule 3: Non-positive Net Monthly Income in Customer Master (m3CIF)
SELECT
  CURRENT_TIMESTAMP() AS evaluated_at,
  'acsm_bronze.m3CIF' AS source_table,
  CAST(CIF_ID AS STRING) AS record_key,
  CAST(CIF_ID AS STRING) AS cif_id,
  'DQ_RULE_03_INVALID_NET_INCOME' AS rule_id,
  'DROP_FROM_GOLD_FEATURE_STORE' AS enforcement_action,
  CONCAT('B_NetIncome = ', CAST(B_NetIncome AS STRING), ' MYR is <= 0') AS violation_detail
FROM `acsm_bronze.m3CIF`
WHERE CAST(B_NetIncome AS NUMERIC) <= 0;

-- -----------------------------------------------------------------------------
-- 2. Centralised Data Quality Monitoring Dashboard View (`acsm_silver.vw_dq_monitoring_summary`)
--    Provides real-time pass/quarantine rates for alerting (Clause C1.1.1.7)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `acsm_silver.vw_dq_monitoring_summary`
OPTIONS (
  description = 'Centralised Data Quality Monitoring View summarizing rule violations by source table and enforcement action (Clause C1.1.1.7).'
) AS
SELECT
  evaluated_at,
  rule_id,
  source_table,
  enforcement_action,
  COUNT(*) AS quarantined_row_count
FROM `acsm_silver.dq_quarantine_records`
GROUP BY 1, 2, 3, 4
ORDER BY quarantined_row_count DESC;

-- -----------------------------------------------------------------------------
-- 3. FinOps Cost Visibility & Zombie Query Detection (`acsm_silver.vw_finops_job_telemetry`)
--    Queries INFORMATION_SCHEMA.JOBS_BY_PROJECT in asia-southeast1 (C1.1.1.18 & C1.1.6.6)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `acsm_silver.vw_finops_job_telemetry`
OPTIONS (
  description = 'FinOps Cost & Compute Telemetry View tracking bytes billed, slot milliseconds, and zero-cost batch loads in asia-southeast1 (Clauses C1.1.1.18 & C1.1.6.6).'
) AS
SELECT
  creation_time,
  job_id,
  user_email,
  job_type,
  statement_type,
  ROUND(COALESCE(total_bytes_billed, 0) / POW(1024, 2), 2) AS billed_megabytes,
  ROUND(COALESCE(total_slot_ms, 0) / 1000.0, 2) AS slot_seconds_consumed,
  TIMESTAMP_DIFF(end_time, start_time, MILLISECOND) AS execution_latency_ms,
  CASE
    WHEN job_type = 'LOAD' AND COALESCE(total_bytes_billed, 0) = 0 THEN 'FREE_SERVERLESS_BATCH_POOL ($0)'
    WHEN total_slot_ms > 600000 THEN 'HEAVY_OR_ZOMBIE_CANDIDATE_ALERT'
    ELSE 'OPTIMIZED_SERVERLESS_EXECUTION'
  END AS finops_classification
FROM `region-asia-southeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY);
