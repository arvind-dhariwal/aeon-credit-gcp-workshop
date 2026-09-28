# Track 1 (Notebook 06) Walkthrough: BigQuery Conversational Analytics (`BQCA`) Data Agent

**Notebook**: [`06_BigQuery_Conversational_Analytics_Agent.ipynb`](../notebook/06_BigQuery_Conversational_Analytics_Agent.ipynb)
**Target Region**: `asia-southeast1` (Singapore) & `global` (`geminidataanalytics.googleapis.com`)
**ACSM RFP Clauses**: `C1.1.2.9`, `C1.1.2.10`, `C1.1.3.1`, `M1.4.2`, `M1.4.4`

---

## 1. Executive Summary & Customer Context

Today, **65% of ACSM's data users are non-technical business analysts** (`M1.4.4`) across Credit Risk, Collections, Marketing, and Finance who submit ~150 ad-hoc SQL request tickets per day (`M1.4.2`).

This notebook demonstrates **BigQuery Conversational Analytics (`BQCA` — `geminidataanalytics.googleapis.com/v1beta`)**: programmatically provisioning, publishing, and conversing with governed Data Agents (`acsm-aeon360-bqca-agent` and `acsm-credit-graph-bqca-agent`) grounded on ACSM's Gold Semantic Marts, Dataplex Knowledge Graph `schemaRelationships`, ACSM Domain Glossary (`EP`, `CC`, `Unpaid_OSP`, `Collection Efficiency Ratio`, `AKPK`, `DSR`, `FinPlus`), and Verified Golden SQL/GQL queries.

---

## 2. Step-by-Step Walkthrough

### Step 0 & Step 1: Enable Gemini Data Analytics APIs & Bootstrap `acsm_gold` Semantic Marts (`07_bqca_semantic_marts.sql`)
- **What Happens**:
  - Auto-detects `PROJECT_ID`, enables `geminidataanalytics.googleapis.com` and `cloudaicompanion.googleapis.com`, and executes [`07_bqca_semantic_marts.sql`](../sql/07_bqca_semantic_marts.sql) on standard On-Demand BigQuery pricing (no Enterprise slot reservation required) to ensure `acsm_gold.gold_aeon_customer360_profile`, `acsm_gold.gold_underwriting_funnel`, `acsm_gold.gold_collections_risk`, and the `acsm_gold.graph_node_*` / `graph_edge_*` tables are populated.

### Step 2: Audit Governed Gold Marts Grounding the BQCA Agent
- **What Happens**: Verifies the row counts across `gold_aeon_customer360_profile`, `gold_underwriting_funnel`, `gold_collections_risk`, and `acsm_silver.recon_audit_log`.

### Step 3: Create & Publish BigQuery Conversational Analytics (`BQCA`) Data Agents
- **What Happens**:
  - Reads [`track3_self_serve_analytics/bqca_agent_config.yaml`](../../track3_self_serve_analytics/bqca_agent_config.yaml) and provisions/publishes two governed Data Agents via `geminidataanalytics.googleapis.com/v1beta`:
    1. **`acsm-aeon360-bqca-agent`**: Grounded on `tableReferences`, `schemaRelationships` (`CIF_ID`), `glossaryTerms`, and `exampleQueries`.
    2. **`acsm-credit-graph-bqca-agent`**: Grounded on `acsm_gold.acsm_credit_ecosystem_graph` (`propertyGraphReferences`) with automatic fallback to the 7 `graph_node_*` and `graph_edge_*` tables.

### Step 4: Live Multi-Turn Conversational Q&A with `acsm-aeon360-bqca-agent` (`:chat` API)
- **What Happens**: Executes 3 live natural-language executive questions via `:chat`:
  1. **Collections Risk & Efficiency across Malaysian States** (`Billing_OSP`, `Collection_OSP`, `Unpaid_OSP`, `Collection Efficiency Ratio`)
  2. **Underwriting Funnel Comparison (`EP` vs `CC`)** (`application_count`, `avg_credit_score`, `avg_new_dsr`)
  3. **PDPA-Compliant EP-to-CC Cross-Sell Target List** (`active_card_count = 0`, `combined_unpaid_osp = 0`, `B_NetIncome >= 5000`, `RecvPromo_FG = 'Y'`)

### Step 5: Natural-Language Merchant Contagion Q&A with `acsm-credit-graph-bqca-agent` (`:chat` API)
- **What Happens**: Queries `acsm-credit-graph-bqca-agent` in plain English to identify merchants with the highest concentration of delinquent customers and linked unpaid principal (`Unpaid_OSP`).
