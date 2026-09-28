# Track 1 (Notebook 06 — Lab 1.6): Graph-Based BigQuery Conversational Analytics (BQCA) Data Agent
**AEON Credit Service Malaysia (ACSM) — Google Agentic Data Cloud Workshop (`asia-southeast1` Singapore)**

- **Notebook**: [`track1_platform_governance/notebook/06_BigQuery_Conversational_Analytics_Agent.ipynb`](../notebook/06_BigQuery_Conversational_Analytics_Agent.ipynb)
- **Declarative Agent Config**: [`track3_self_serve_analytics/bqca_agent_config.yaml`](../../track3_self_serve_analytics/bqca_agent_config.yaml)
- **Knowledge Catalog Glossary YAML**: [`track1_platform_governance/scripts/business_glossary_acsm.yaml`](../scripts/business_glossary_acsm.yaml)

---

## 🎯 Lab 1.6 Overview & Architecture
In **Notebook 05**, we built the **BigQuery Property Graph (`acsm_gold.acsm_credit_ecosystem_graph`)** over 4 Node tables (`Customer`, `CreditFacility`, `Merchant`, `EmployerSegment`) and 3 Edge tables (`HOLDS_FACILITY`, `TRANSACTED_AT`, `WORKS_IN_SEGMENT`).

In **Notebook 06**, we focus **exclusively** on creating, grounding, publishing, and querying the **Graph-Based BigQuery Conversational Analytics (BQCA) Data Agent (`acsm-credit-graph-bqca-agent`)**:

1. **Step 1 — Materialize & Audit the 7 Graph Node & Edge Tables (`acsm_gold`)**:
   - Ensures all 4 Node tables (`graph_node_customer`, `graph_node_credit_facility`, `graph_node_merchant`, `graph_node_employer_segment`), 3 Edge tables (`graph_edge_holds_facility`, `graph_edge_transacted_at`, `graph_edge_works_in_segment`), and `acsm_gold.acsm_credit_ecosystem_graph` exist in `asia-southeast1`.
2. **Step 2 — Import Business Glossary Live from Dataplex Knowledge Catalog (`acsm-enterprise-credit-glossary`)**:
   - Ensures `acsm-enterprise-credit-glossary` is synced in Dataplex Knowledge Catalog, then queries the live **Dataplex Knowledge Catalog API** (`GET https://dataplex.googleapis.com/v1/projects/{PROJECT_ID}/locations/asia-southeast1/glossaries/acsm-enterprise-credit-glossary/terms`) to import all 10 standardized ACSM Business Terms directly into the agent's `Context.glossaryTerms`.
3. **Step 3 — Generate Data Insights on the 7 Graph Tables & Extract Sample Questions**:
   - Runs **Dataplex `DATA_DOCUMENTATION` (Data Insights)** scans across the 7 tables used in the Property Graph (`graph_node_*` & `graph_edge_*`), publishes the `Insights` tab labels to BigQuery Studio, extracts the **6 Node-to-Edge `schemaRelationships`**, and extracts the **4 Insight-Generated Sample Questions (`exampleQueries`)**.
4. **Step 4 — Provision & Publish the Graph-Based BQCA Agent (`acsm-credit-graph-bqca-agent`)**:
   - Provisions and publishes `projects/{PROJECT_ID}/locations/global/dataAgents/acsm-credit-graph-bqca-agent` via `geminidataanalytics.googleapis.com/v1beta`, binding the 7 Graph Node & Edge tables, the imported Knowledge Catalog Business Glossary terms, the 6 Graph `schemaRelationships`, and the 4 Insight-Generated Sample Queries.
5. **Step 5 — Live Conversational Q&A Using the Insight-Generated Sample Questions**:
   - Queries `acsm-credit-graph-bqca-agent` via `:chat` using the exact sample questions generated from the Graph Table Insights in Step 3:
     1. **Merchant Delinquency Contagion & Unpaid OSP** (`INSIGHT_Q01_MERCHANT_DELINQUENCY_CONTAGION`)
     2. **Customer-to-CreditFacility Exposure & DSR by Product Line** (`INSIGHT_Q02_CUSTOMER_FACILITY_EXPOSURE_AND_DSR`)
     3. **Employer & State Segment Delinquency Risk Clusters** (`INSIGHT_Q03_EMPLOYER_SEGMENT_DELINQUENCY_CLUSTERS`)
     4. **PDPA-Consented EP-to-CC Graph Cross-Sell Path Discovery** (`INSIGHT_Q04_GRAPH_PDPA_EP_TO_CC_CROSS_SELL_PATHS`)
