# Track 1 (Notebook 05) Walkthrough: BigQuery Property Graph (`ISO GQL`) & Conversational Analytics (`BQCA`) Agent

**Notebook**: [`05_BigQuery_Graph_and_BQCA_Agent.ipynb`](../notebook/05_BigQuery_Graph_and_BQCA_Agent.ipynb)
**Target Region**: `asia-southeast1` (Singapore)
**ACSM RFP Clauses**: `C1.1.4.4`, `C1.1.6.11`, `C1.2.1.3`, `C1.2.2.1`, `C1.2.3.1`

---

## 1. Executive Summary & Customer Context

Traditional relational SQL tables require complex multi-way self-joins to uncover **first-party fraud rings, delinquency contagion across shared merchants/employers, and cross-sell paths** between Easy Payment (`EP`) and Credit Card (`CC`) product lines. At the same time, business executives and branch managers need **natural-language self-service analytics** over governed Gold tables without writing SQL or GQL.

This notebook showcases two cutting-edge capabilities natively inside BigQuery:
1. **Part A — BigQuery Property Graph (`CREATE OR REPLACE PROPERTY GRAPH` & `ISO/IEC 39075 GQL`)**: Zero-ETL graph analytics directly over `acsm_gold` tables (`acsm_gold.acsm_credit_ecosystem_graph`) without exporting data to an external graph database.
2. **Part B — BigQuery Conversational Analytics (`BQCA` — `geminidataanalytics.googleapis.com`)**: Provisioning and chatting with two governed Data Agents (`acsm-aeon360-bqca-agent` for SQL Customer 360 Q&A and `acsm-credit-graph-bqca-agent` for natural-language Graph traversal).

---

## 2. Step-by-Step Walkthrough

### Step 0 & Step 1: Enable APIs & Build the `acsm_gold.acsm_credit_ecosystem_graph` Property Graph
- **What Happens**: Enables `bigquery.googleapis.com` and `geminidataanalytics.googleapis.com`, and executes [`03_semantic_gold_and_graph.sql`](../sql/03_semantic_gold_and_graph.sql) to build the Gold node/edge tables and the `CREATE OR REPLACE PROPERTY GRAPH acsm_gold.acsm_credit_ecosystem_graph` definition:
  - **Node Tables (3)**: `Customer` (`gold_aeon_customer360_profile`), `CreditFacility` (`graph_node_credit_facility`), `Merchant` (`graph_node_merchant`).
  - **Edge Tables (3)**: `HOLDS_FACILITY` (`Customer -> CreditFacility`), `TRANSACTS_AT` (`Customer -> Merchant`), `FINANCED_AT_MERCHANT` (`CreditFacility -> Merchant`).

### Step 2: Inspect Property Graph Schema & Node/Edge Cardinality
- **What Happens**: Audits the row counts across all 3 Node tables and 3 Edge tables in `acsm_gold`.

### Step 3 (`ISO GQL` Query 1): 2-Hop Customer -> CreditFacility & Merchant Exposure Traversal
- **What Happens**: Runs native `GRAPH acsm_gold.acsm_credit_ecosystem_graph MATCH (c:Customer)-[h:HOLDS_FACILITY]->(f:CreditFacility), (c)-[t:TRANSACTS_AT]->(m:Merchant)` to rank customers by combined credit facility exposure and merchant spend.

### Step 4 (`ISO GQL` Query 2): Multi-Hop First-Party Fraud & Delinquency Contagion Risk
- **What Happens**: Traverses `(c1:Customer)-[:HOLDS_FACILITY]->(f:CreditFacility)-[:FINANCED_AT_MERCHANT]->(m:Merchant)<-[:TRANSACTS_AT]-(c2:Customer)` to identify high-risk merchant hubs where multiple delinquent or high-DSR customers cluster.

### Step 5 (`ISO GQL` Query 3): AEON Ecosystem Cross-Sell Path Discovery (`EP -> CC`)
- **What Happens**: Identifies prime Easy Payment (`EP`) customers (`latest_ctos_score >= 700`, `delinquency_risk_flag = 0`, `active_card_count = 0`) transacting at top AEON merchants who are pre-qualified for an instant AEON Credit Card upgrade.

### Step 6, Step 7 & Step 8 (Part B): BigQuery Conversational Analytics (`BQCA`) Data Agents
- **What Happens**:
  1. **Step 6**: Provisions and publishes two governed BQCA Data Agents (`acsm-aeon360-bqca-agent` and `acsm-credit-graph-bqca-agent`) via `geminidataanalytics.googleapis.com/v1beta` with verified golden SQL/GQL examples and Malaysian MYR / BNM RMiT system instructions.
  2. **Step 7**: Runs a live multi-turn natural-language conversation (`:chat` API) asking business questions over `gold_aeon_customer360_profile` (with context carry-over across turns).
  3. **Step 8**: Asks a natural-language graph traversal question via `acsm-credit-graph-bqca-agent`, which automatically generates and executes `ISO GQL` over `acsm_gold.acsm_credit_ecosystem_graph`.
