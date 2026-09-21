# ACSM Unified Data & AI Platform — RFP Clause-to-Workshop Traceability Matrix

This document maps every clause of **ACSM RFP Annexure C (`Part C-Functional Requirements`)**, **Annexure M (`Current State Operational Drivers`)**, and **Annexure N (`4 Technical Workshop Tracks`)** to the executable code in `aeon-credit-gcp-workshop`.

---

## 1. Clause-by-Clause Mapping (`Part C` $\rightarrow$ Repository Assets)

| RFP Clause | Requirement Name | How It Is Demonstrated in `aeon-credit-gcp-workshop` | Executable File |
| :--- | :--- | :--- | :--- |
| **`C1.1.1.1`–`C1.1.1.2`** | Coherence & Diverse Ingestion | Single unified BigQuery + Dataplex + Vertex AI platform ingesting batch CSVs (`T1`–`T8`) and Excel metadata (`Mock Metadata.xlsx`). | `track1_platform_governance/01_ingest_and_metadata_sync.py` |
| **`C1.1.1.3`–`C1.1.1.4`** | Open Table Format & Schema Evolution | Seamless schema evolution from `T4_Fact_CC_Judge` (`v1`) to `T4_Fact_CC_Judge_v2` (`v2`) using `UNION ALL BY NAME` and ACID snapshots. | `track1_platform_governance/02_medallion_and_reconciliation.sql` |
| **`C1.1.1.6`–`C1.1.1.7`** | Declarative Rule Enforcement & Quarantine | Automated quarantine table `acsm_silver.dq_quarantine_records` catching dormant-card activation anomalies and credit limit balance mismatches. | `track1_platform_governance/02_medallion_and_reconciliation.sql` |
| **`C1.1.1.8`–`C1.1.1.10`** | Unified Governance, Lineage & Metadata | Programmatic parsing of all 8 tabs (`~220 columns`) of `Mock Metadata.xlsx` into BigQuery/Dataplex table and column descriptions. | `track1_platform_governance/01_ingest_and_metadata_sync.py` |
| **`C1.1.1.13` & `C1.1.6.5`** | Parallel Run & Automated Reconciliation | `acsm_silver.recon_audit_log` verifying 0 row-count variance and `RM 0.00` financial variance across `FIN_AMT`, `Unpaid_OSP`, and `Amount`. | `track1_platform_governance/02_medallion_and_reconciliation.sql` |
| **`C1.1.1.24` & `C1.1.5.1`–`C1.1.5.3`** | FGAC, BNM RMiT & Malaysian PDPA 2010 | Dynamic PII masking (`CIF_NM`, `_HomeAddr1`, `B_NetIncome`), Malaysian State RLS (`Selangor`, `KL`, etc.), and `sp_execute_pdpa_subject_erasure`. | `track1_platform_governance/03_bnm_rmit_pdpa_security.sql` |
| **`C1.1.2.1`–`C1.1.2.10`** | Self-Serve Analytics, BQCA & Downstream BI | `gold_customer_360`, `gold_underwriting_funnel`, `gold_collections_risk` + `bqca_agent_config.yaml` (12 Golden SQL queries for the 65% business user cohort). | `track3_self_serve_analytics/05_aeon360_gold_marts.sql`<br>`track3_self_serve_analytics/bqca_agent_config.yaml` |
| **`C1.1.3.1`–`C1.1.3.7`** | Agentic AI, Vector DB, Guardrails & Inference Tracking | Google ADK multi-agent suite (`aeon360_root_orchestrator` + 3 sub-agents), BigQuery Vector DB (`bnm_rmit_akpk_policy_kb`), and LLMOps audit table (`agent_inference_audit_log`). | `track4_genai_agents/06_vector_db_and_llmops_tables.sql`<br>`track4_genai_agents/aeon360_ebuddy_agent/agent.py` |
| **`C1.1.4.1`–`C1.1.4.10`** | Feature Store, Explainable ML & Vertex Model Registry | `ml_customer_feature_store` + `model_delinquency_propensity` (`ML.EXPLAIN_PREDICT` SHAP attributions) + `model_ep_to_cc_cross_sell` registered in Vertex AI. | `track2_ml_development/04_bqml_credit_and_cross_sell.sql` |
