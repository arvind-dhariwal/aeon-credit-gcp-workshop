-- =============================================================================
-- TRACK 4: GENAI & AGENTIC AI DEVELOPMENT — VECTOR DB & LLMOPS TELEMETRY
-- File: 06_vector_db_and_llmops_tables.sql
--
-- Fulfils ACSM RFP Clauses:
-- - C1.1.3.1 (Agentic Capabilities & Orchestration)
-- - C1.1.3.3 (Inference Tracking: Token usage, latency, and compute cost)
-- - C1.1.3.5 (AI Guardrails: Prompt version tracking & safety policy logs)
-- - C1.1.3.6 (Native Managed Vector DB for RAG & Semantic Search)
-- - C1.1.3.7 (Threat & Access Monitoring: Forensics on AI model data access)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Native Managed Vector Database Knowledge Base (Clause C1.1.3.6)
--    Stores BNM RMiT guidelines, AKPK debt restructuring SOPs, PDPA policies,
--    and AEON Credit product underwriting rules for the e-Buddy RAG Agent.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `acsm_gold.bnm_rmit_akpk_policy_kb`
OPTIONS (
  description = 'Managed BigQuery Vector Database storing BNM RMiT, AKPK Restructuring, PDPA, and ACSM Credit Policy clauses for e-Buddy RAG.'
) AS
SELECT * FROM UNNEST([
  STRUCT(
    'POL-BNM-RMIT-10.55' AS policy_id,
    'BNM RMiT Sec 10.55 & Credit Risk Governance' AS policy_title,
    'Regulatory & Compliance' AS category,
    'Under Bank Negara Malaysia (BNM) Risk Management in Technology (RMiT) and Responsible Financing Guidelines, any credit limit increase or Easy Payment (EP) refinancing for applicants with Debt Service Ratio (DSR) exceeding 60% requires documented affordability verification, Net Disposable Income (NDI) check >= RM 1,500, and senior credit committee approval.' AS content
  ),
  STRUCT(
    'POL-AKPK-DMP-01',
    'AKPK Debt Management Programme (DMP) Restructuring Eligibility',
    'Collections & Restructuring',
    'Customers flagged with AKPK_Status = Y or FinPlus Tier D/E with Unpaid_OSP > RM 1,000 must be suspended from new Cash Advance (CA_CL) drawdowns. Credit Control officers via e-Buddy may offer a 36-to-60 month installment tenure restructure at reduced profit rate (<= 6.0% p.a.) once 3 consecutive monthly payments are verified.'
  ),
  STRUCT(
    'POL-ACSM-TIER-UPGRADE-02',
    'AEON360 Gold & Platinum Card Upgrade & EP Cross-Sell Policy',
    'Underwriting & Cross-Sell',
    'Existing Easy Payment (EP) customers with >= 6 months repayment history, zero overdue balance (Unpaid_OSP = 0), Net Income >= RM 4,000 (Gold) or >= RM 8,000 (Platinum), and CTOS Final_Score >= 680 qualify for pre-approved AEON Credit Card issuance with fast-track biometric onboarding.'
  ),
  STRUCT(
    'POL-PDPA-2010-SEC43',
    'Malaysian PDPA 2010 Section 43 Consent & PII Protection',
    'Data Privacy & Security',
    'Personal data (CIF_NM, Home Address, Net Income) must never be echoed unmasked to unauthorized users or external marketing channels unless RecvPromo_FG = Y. Autonomous agents (e-Buddy) must enforce Model Armor PII redaction and log every CIF_ID access to acsm_gold.agent_inference_audit_log.'
  )
]);

-- -----------------------------------------------------------------------------
-- 2. LLMOps Inference, Token Usage, Guardrail & Data Access Forensic Table
--    Fulfils Clauses C1.1.3.3, C1.1.3.5, and C1.1.3.7 (scaling 60M -> 1.2B tokens)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `acsm_gold.agent_inference_audit_log` (
  invocation_id STRING OPTIONS(description = 'Unique invocation trace ID'),
  logged_at TIMESTAMP OPTIONS(description = 'UTC timestamp of agent execution'),
  session_user STRING OPTIONS(description = 'Authenticated user or persona triggering the agent'),
  agent_name STRING OPTIONS(description = 'ADK sub-agent invoked (aeon360_orchestrator, customer_insight_bqca_agent, ebuddy_credit_collection_agent, data_governance_steward_agent)'),
  prompt_version STRING OPTIONS(description = 'Governed prompt template version ID [C1.1.3.5]'),
  model_name STRING OPTIONS(description = 'Vertex AI Gemini model identifier'),
  user_query STRING OPTIONS(description = 'Sanitized user prompt'),
  referenced_cif_ids ARRAY<STRING> OPTIONS(description = 'Customer CIF_IDs accessed during execution [C1.1.3.7 Forensics]'),
  referenced_tables ARRAY<STRING> OPTIONS(description = 'BigQuery tables queried during tool execution [C1.1.3.7]'),
  guardrail_status STRING OPTIONS(description = 'Model Armor / Enterprise Safety Guardrail evaluation result (PASS, PII_REDACTED, BLOCKED) [C1.1.3.5]'),
  prompt_tokens INT64 OPTIONS(description = 'Input token count [C1.1.3.3]'),
  completion_tokens INT64 OPTIONS(description = 'Output token count [C1.1.3.3]'),
  total_tokens INT64 OPTIONS(description = 'Total tokens consumed [C1.1.3.3]'),
  latency_ms FLOAT64 OPTIONS(description = 'End-to-end inference latency in milliseconds [C1.1.3.3]'),
  estimated_cost_myr NUMERIC OPTIONS(description = 'Estimated inference compute cost in MYR [C1.1.3.3]')
)
PARTITION BY DATE(logged_at)
CLUSTER BY agent_name, guardrail_status
OPTIONS (
  description = 'Enterprise LLMOps Telemetry & Forensic Audit Log for ACSM Agentic AI workloads (Clauses C1.1.3.3, C1.1.3.5, C1.1.3.7).'
);
