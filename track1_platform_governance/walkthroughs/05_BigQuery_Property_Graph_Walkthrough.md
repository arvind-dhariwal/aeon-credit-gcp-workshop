# Track 1 (Notebook 05) Walkthrough: BigQuery Property Graph (`ISO GQL` & Interactive Graph Visualization)

**Notebook**: [`05_BigQuery_Property_Graph.ipynb`](../notebook/05_BigQuery_Property_Graph.ipynb)
**Target Region**: `asia-southeast1` (Singapore)
**ACSM RFP Clauses**: `C1.1.1.14`, `C1.1.1.15`, `C1.1.2.3`, `C1.1.2.4`

---

## 1. Executive Summary & Customer Context

Traditional relational SQL tables require complex multi-way self-joins to uncover **first-party fraud rings, delinquency contagion across shared merchants/employers, and cross-sell paths** between Easy Payment (`EP`) and Credit Card (`CC`) product lines.

This notebook showcases **BigQuery Property Graph (`CREATE OR REPLACE PROPERTY GRAPH` & `ISO/IEC 39075 GQL`)**: zero-ETL graph analytics directly over governed `acsm_gold` tables (`acsm_gold.acsm_credit_ecosystem_graph`) with interactive node-and-edge visualizations (`%%bigquery --graph`) directly inside the notebook—without exporting data to an external graph database.

---

## 2. Step-by-Step Walkthrough

### Step 0 & Step 1: Enable APIs, Install `bigquery-magics>=0.12.1` (`--graph`), & Build the `acsm_gold.acsm_credit_ecosystem_graph` Property Graph
- **What Happens**:
  - Installs/upgrades `bigquery-magics>=0.12.1` and loads `%reload_ext bigquery_magics` to enable native interactive node-and-edge graph visualizations (`%%bigquery --graph`) directly inside the notebook output.
  - Provisions an autoscaling BigQuery Enterprise reservation (`acsm-graph-enterprise-res`, `0` baseline / `500` max slots) in `asia-southeast1` and executes [`06_bigquery_graph_and_bqca.sql`](../sql/06_bigquery_graph_and_bqca.sql) to build the Gold node/edge tables and the `CREATE OR REPLACE PROPERTY GRAPH acsm_gold.acsm_credit_ecosystem_graph` definition:
    - **Node Tables (4)**: `Customer` (`graph_node_customer`), `CreditFacility` (`graph_node_credit_facility`), `Merchant` (`graph_node_merchant`), `EmployerSegment` (`graph_node_employer_segment`).
    - **Edge Tables (3)**: `HOLDS_FACILITY` (`Customer -> CreditFacility`), `TRANSACTED_AT` (`Customer -> Merchant`), `WORKS_IN_SEGMENT` (`Customer -> EmployerSegment`).

### Step 2: Inspect Property Graph Schema & Node/Edge Cardinality
- **What Happens**: Audits the row counts across all 4 Node tables and 3 Edge tables in `acsm_gold` and explains how to interact with the `%%bigquery --graph` widget (**Force**, **Hierarchical**, **Sequential**, and **Schema** views, plus right-click node **Expand / Collapse / Show neighbors**).

### Step 3 (`ISO GQL` Query 1 — `%%bigquery --graph`): 2-Hop Customer $\rightarrow$ CreditFacility & Merchant Portfolio Traversal
- **What Happens**:
  - **Step 3.1 (`%%bigquery --graph`)**: Runs `GRAPH acsm_gold.acsm_credit_ecosystem_graph MATCH p = (f:CreditFacility)<-[h:HOLDS_FACILITY]-(c:Customer)-[t:TRANSACTED_AT]->(m:Merchant) ... RETURN TO_JSON(p) AS path` to render an interactive node-and-edge graph canvas directly in the notebook.
  - **Step 3.2 (`GRAPH_TABLE`)**: Aggregates the 2-hop traversal by Malaysian state, product line (`EP` / `CC`), and privilege merchant group.

### Step 4 (`ISO GQL` Query 2 — `%%bigquery --graph`): Multi-Hop First-Party Fraud & Delinquency Contagion Ring Detection
- **What Happens**:
  - **Step 4.1 (`%%bigquery --graph`)**: Matches the cyclical diamond pattern `p1 = (c1:Customer)-[t1:TRANSACTED_AT]->(m:Merchant)<-[t2:TRANSACTED_AT]-(c2:Customer), p2 = (c1)-[w1:WORKS_IN_SEGMENT]->(e:EmployerSegment)<-[w2:WORKS_IN_SEGMENT]-(c2)` and returns `TO_JSON(p1) AS merchant_ring_path, TO_JSON(p2) AS employer_ring_path` so users can visually inspect delinquent customer pairs sharing both a merchant and employer segment.
  - **Step 4.2 (`GRAPH_TABLE`)**: Ranks the top delinquency contagion rings by connected delinquent pair count and combined unpaid balance (`pair_unpaid_osp_myr`).

### Step 5 (`ISO GQL` Query 3 — `%%bigquery --graph`): AEON Ecosystem Cross-Sell Path Discovery (`EP` $\rightarrow$ `CC`)
- **What Happens**:
  - **Step 5.1 (`%%bigquery --graph`)**: Visualizes the cross-sell paths `p = (f:CreditFacility)<-[h:HOLDS_FACILITY]-(c:Customer)-[t:TRANSACTED_AT]->(m:Merchant)` (`RETURN TO_JSON(p) AS path`) for PDPA-consented (`pdpa_marketing_consent = 'Y'`), zero-delinquency Easy Payment (`EP`) customers with no active Credit Card (`active_card_count = 0`).
  - **Step 5.2 (`GRAPH_TABLE`)**: Outputs the prioritized tabular candidate list for instant Credit Card cross-sell at point-of-sale.

### Step 6: Cleanup Activity — Delete BigQuery Enterprise Reservation & Project Assignment
- **What Happens**: Unassigns `projects/{PROJECT_ID}` and deletes the temporary `acsm-graph-enterprise-res` Enterprise slot reservation so the project reverts to standard On-Demand query pricing before proceeding to **Notebook 06 (`06_BigQuery_Conversational_Analytics_Agent.ipynb`)**.
