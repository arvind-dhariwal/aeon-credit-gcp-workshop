"""ACSM Unified Data & AI Platform — 4-Track Technical Workshop Live Portal.

Interactive Streamlit application organized around the 4 Official Technical
Workshop Tracks from ACSM RFP Annexure N:
- Track 1: Data Platform, Governance, and Modernization
- Track 2: ML Development & MLOps
- Track 3: Dashboard & Self-Service Analytics (BQCA & AEON360)
- Track 4: GenAI & Agentic AI Development ('AEON360 & e-Buddy' + LLMOps)
"""

import pandas as pd
import streamlit as st

st.set_page_config(
    page_title="ACSM Unified Data & AI Platform — GCP Workshop",
    page_icon="🏦",
    layout="wide",
)

st.title("🏦 AEON Credit Service Malaysia (ACSM) — Google Agentic Data Cloud")
st.caption(
    "RFP Technical Demonstration & Workshop Command Center | Aligned to Annexure N (Tracks 1–4), Annexure M & Part C (C1.1.1–C1.1.6)"
)

kpi1, kpi2, kpi3, kpi4 = st.columns(4)
kpi1.metric("ACSM Mock Tables Governed", "8 Core Tables (T1–T8)", "220 Columns Enriched")
kpi2.metric("Dual-Run Financial Recon", "100% PASS", "RM 0.00 Variance")
kpi3.metric("Ad-Hoc Ticket Queue Reduction", "-85% (BQCA Self-Serve)", "150 Queries/Day Automated")
kpi4.metric("Active ML & GenAI Models", "BQML + Gemini 2.5 ADK", "BNM RMiT & PDPA Governed")

tab1, tab2, tab3, tab4 = st.tabs([
    "🏗️ Track 1: Platform, Governance & Modernization",
    "🧠 Track 2: ML Development & Explainable MLOps",
    "📊 Track 3: Self-Serve Analytics (BQCA & AEON360)",
    "🤖 Track 4: GenAI & e-Buddy Agentic Suite",
])

with tab1:
  st.subheader("Track 1: Medallion Lakehouse, Automated Metadata, DQ Quarantine & BNM RMiT Security")
  c1, c2 = st.columns(2)
  with c1:
    st.markdown("#### 1. Dual-Run Financial Reconciliation (`acsm_silver.recon_audit_log`)")
    recon_df = pd.DataFrame([
        {
            "Domain Table": "T1_Fact_EP_Judge",
            "Control Metric": "FIN_AMT (Financed Principal)",
            "Bronze Rows": "50,000",
            "Silver Rows": "50,000",
            "Financial Variance (MYR)": "RM 0.00",
            "Status": "✅ PASS",
        },
        {
            "Domain Table": "T4_Fact_CC_Judge (v1 → v2)",
            "Control Metric": "B_CrLimit (Approved Card Limit)",
            "Bronze Rows": "65,000",
            "Silver Rows": "65,000",
            "Financial Variance (MYR)": "RM 0.00",
            "Status": "✅ PASS (Schema Evolved)",
        },
        {
            "Domain Table": "T3 + T6 Collections",
            "Control Metric": "Unpaid_OSP (Total Overdue Principal)",
            "Bronze Rows": "115,000",
            "Silver Rows": "115,000",
            "Financial Variance (MYR)": "RM 0.00",
            "Status": "✅ PASS",
        },
    ])
    st.dataframe(recon_df, use_container_width=True, hide_index=True)

  with c2:
    st.markdown("#### 2. PDPA Dynamic PII Masking & State RLS (`vw_customer_cif_pdpa_governed`)")
    role = st.radio(
        "Simulate Authenticated Caller Role:",
        ["BI Analyst (Masked PII + Central Region RLS)", "Credit Control / Compliance Officer (Unmasked Authorized)"],
        horizontal=True,
    )
    if "BI Analyst" in role:
      st.dataframe(
          pd.DataFrame([
              {"CIF_ID": "97588190", "Customer Name": "AH****IN", "State": "Selangor", "Home Address": "*** REDACTED UNDER PDPA 2010 ***", "Income Band": "T20 (> RM 7,000)", "Exact Net Income": "MASKED"},
              {"CIF_ID": "85853367", "Customer Name": "TA****NG", "State": "Kuala Lumpur", "Home Address": "*** REDACTED UNDER PDPA 2010 ***", "Income Band": "M40 (RM 3,000 - RM 7,000)", "Exact Net Income": "MASKED"},
          ]),
          use_container_width=True,
          hide_index=True,
      )
    else:
      st.dataframe(
          pd.DataFrame([
              {"CIF_ID": "97588190", "Customer Name": "AHMAD FAIZ BIN ZAINUDDIN", "State": "Selangor", "Home Address": "NO 14 JALAN USJ 11/3 SUBANG JAYA", "Income Band": "T20 (> RM 7,000)", "Exact Net Income": "RM 9,450.00"},
              {"CIF_ID": "85853367", "Customer Name": "TAN MEI LING", "State": "Kuala Lumpur", "Home Address": "B-12-05 MONT KIARA DAMAI", "Income Band": "M40 (RM 3,000 - RM 7,000)", "Exact Net Income": "RM 5,800.00"},
          ]),
          use_container_width=True,
          hide_index=True,
      )

with tab2:
  st.subheader("Track 2: End-to-End MLOps — Delinquency Propensity & EP↔CC Cross-Sell (`ML.EXPLAIN_PREDICT`)")
  st.dataframe(
      pd.DataFrame([
          {
              "CIF_ID": "97588190",
              "Wallet Tier": "Platinum",
              "CP Limit (MYR)": "RM 45,500",
              "CP Usage (MYR)": "RM 19,131.62",
              "AKPK Status": "Y",
              "Delinquency Risk Score": "0.782 (High Risk)",
              "Top SHAP Attribution 1": "akpk_status (+0.34)",
              "Top SHAP Attribution 2": "debt_service_ratio_dsr (+0.22)",
              "Recommended Action": "Offer AKPK 48-Month Restructure & Suspend CA_CL",
          },
          {
              "CIF_ID": "45349744",
              "Wallet Tier": "Platinum",
              "CP Limit (MYR)": "RM 26,000",
              "CP Usage (MYR)": "RM 2,711.37",
              "AKPK Status": "N",
              "Delinquency Risk Score": "0.064 (Low Risk)",
              "Top SHAP Attribution 1": "credit_utilization_ratio (-0.19)",
              "Top SHAP Attribution 2": "pay_in_full_history (-0.15)",
              "Recommended Action": "Pre-Approve Limit Upgrade (+RM 10,000) & EP Cross-Sell",
          },
      ]),
      use_container_width=True,
      hide_index=True,
  )

with tab3:
  st.subheader("Track 3: BigQuery Conversational Analytics (BQCA) & AEON360 Gold Marts")
  selected_q = st.selectbox(
      "Select a Business User Natural Language Query (65% Non-Technical User Cohort):",
      [
          "Break down credit purchase limit, usage, average utilization rate, and AKPK restructuring count by Wallet Tier.",
          "What is our total Billing OSP, Collection OSP, Unpaid OSP, and Collection Efficiency Ratio across Easy Payment (EP) vs Credit Cards (CC)?",
          "Find top Easy Payment (EP) customers with zero unpaid delinquency, net income above RM 5,000, and DSR below 40% eligible for a Platinum Credit Card.",
      ],
  )
  st.code(
      """SELECT
  wallet_tier,
  COUNT(DISTINCT cif_id) AS total_customers,
  COUNTIF(akpk_status = 'Y') AS akpk_restructured_customers,
  ROUND(SUM(total_cp_limit_myr), 2) AS total_credit_limit_myr,
  ROUND(SUM(total_cp_usage_myr), 2) AS total_credit_usage_myr,
  ROUND(AVG(credit_utilization_ratio) * 100, 2) AS avg_utilization_pct
FROM `acsm_gold.gold_customer_360`
GROUP BY wallet_tier
ORDER BY total_credit_limit_myr DESC;""",
      language="sql",
  )
  st.dataframe(
      pd.DataFrame([
          {"Wallet Tier": "Platinum", "Total Customers": 29265, "AKPK Restructured": 9763, "Total Credit Limit (MYR)": "RM 877,950,000", "Total Usage (MYR)": "RM 298,503,000", "Avg Utilization %": "34.00%"},
          {"Wallet Tier": "Gold", "Total Customers": 19510, "AKPK Restructured": 6508, "Total Credit Limit (MYR)": "RM 585,300,000", "Total Usage (MYR)": "RM 198,900,000", "Avg Utilization %": "33.98%"},
          {"Wallet Tier": "Silver", "Total Customers": 9755, "AKPK Restructured": 3241, "Total Credit Limit (MYR)": "RM 292,650,000", "Total Usage (MYR)": "RM 99,500,000", "Avg Utilization %": "34.00%"},
          {"Wallet Tier": "Basic", "Total Customers": 6470, "AKPK Restructured": 2155, "Total Credit Limit (MYR)": "RM 194,100,000", "Total Usage (MYR)": "RM 65,900,000", "Avg Utilization %": "33.95%"},
      ]),
      use_container_width=True,
      hide_index=True,
  )

with tab4:
  st.subheader("Track 4: Google ADK 'AEON360 & e-Buddy' Multi-Agent System + LLMOps Telemetry")
  st.markdown("#### Live LLMOps Token, Latency, Cost & Forensic Audit Trail (`acsm_gold.agent_inference_audit_log`)")
  st.dataframe(
      pd.DataFrame([
          {
              "Invocation ID": "e8a1-49c2-901a",
              "ADK Sub-Agent": "ebuddy_credit_collection_agent",
              "Prompt Version": "acsm-ebuddy-v2026.09.1",
              "Accessed CIF_IDs": "['97588190']",
              "Tables Queried": "gold_customer_360, bnm_rmit_akpk_policy_kb",
              "Guardrail Status": "✅ PASS_PII_MASKED",
              "Total Tokens": 700,
              "Latency (ms)": 412.5,
              "Est. Cost (MYR)": "RM 0.00187",
          },
          {
              "Invocation ID": "b3f4-81d0-772c",
              "ADK Sub-Agent": "customer_insight_bqca_agent",
              "Prompt Version": "acsm-ebuddy-v2026.09.1",
              "Accessed CIF_IDs": "[]",
              "Tables Queried": "gold_collections_risk",
              "Guardrail Status": "✅ PASS",
              "Total Tokens": 645,
              "Latency (ms)": 358.0,
              "Est. Cost (MYR)": "RM 0.00172",
          },
      ]),
      use_container_width=True,
      hide_index=True,
  )
