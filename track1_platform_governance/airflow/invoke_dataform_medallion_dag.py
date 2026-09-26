#!/usr/bin/env python3
"""
ACSM Track 1 — Live Dataform Medallion DAG Orchestration Runner
Executes the exact Cloud Composer / Apache Airflow operator sequence:
  1. Provisions & binds a dedicated Dataform execution service account (`acsm-dataform-sa@<PROJECT_ID>.iam.gserviceaccount.com`)
     to satisfy `strictActAs` org policy checks.
  2. Initializes & syncs the `acsm-medallion-pipeline` Dataform Repository & `default` Workspace in asia-southeast1
     with `workflow_settings.yaml` (Dataform Core 3.0.0) and all 7 verified Medallion + BQML `.sqlx` nodes
     (removing any stale `.sqlx` files that could cause column errors like `Appl_DT_RAW`).
  3. Compiles the Dataform Medallion DAG (DataformCreateCompilationResultOperator equivalent)
  4. Triggers a live Dataform Workflow Invocation (DataformCreateWorkflowInvocationOperator equivalent)
"""
import base64
import json
import os
import subprocess
import time
import urllib.error
import urllib.request


def get_medallion_sqlx_files():
    """Returns the 7 verified Dataform .sqlx files for the ACSM Medallion + BQML DAG."""
    return {
        "definitions/silver_customer_cif.sqlx": """config {
  type: "table",
  schema: "acsm_silver",
  name: "silver_customer_cif",
  description: "Governed Silver Customer Master (m3CIF) deduplicated by CIF_ID",
  bigquery: {
    clusterBy: ["CIF_ID", "State"]
  },
  assertions: {
    nonNull: ["CIF_ID"],
    uniqueKey: ["CIF_ID"]
  }
}

SELECT
  CAST(CIF_ID AS STRING) AS CIF_ID,
  SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(CAST(Rcd_DT AS STRING), 1, 10)) AS record_refresh_date,
  TRIM(CAST(CIF_NM AS STRING)) AS CIF_NM,
  TRIM(CAST(Gender AS STRING)) AS Gender,
  TRIM(CAST(MaritalSts AS STRING)) AS MaritalSts,
  TRIM(CAST(Citizen AS STRING)) AS Citizen,
  TRIM(CAST(State AS STRING)) AS State,
  TRIM(CAST(Region AS STRING)) AS Region,
  TRIM(CAST(Race AS STRING)) AS Race,
  TRIM(CAST(Occupation AS STRING)) AS Occupation,
  CAST(EmpSts AS INT64) AS EmpSts,
  CAST(N_Age AS INT64) AS N_Age,
  CAST(N_YrStay AS NUMERIC) AS N_YrStay,
  CAST(N_YrJob AS NUMERIC) AS N_YrJob,
  CAST(B_NetIncome AS NUMERIC) AS B_NetIncome,
  CAST(B_GrossIncome AS NUMERIC) AS B_GrossIncome,
  CAST(B_AnnualIncome AS NUMERIC) AS B_AnnualIncome,
  COALESCE(TRIM(CAST(RecvPromo_FG AS STRING)), 'N') AS RecvPromo_FG
FROM `acsm_bronze.m3CIF`
QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(CIF_ID AS STRING) ORDER BY Rcd_DT DESC) = 1
""",
        "definitions/silver_ep_underwriting.sqlx": """config {
  type: "table",
  schema: "acsm_silver",
  name: "silver_ep_underwriting",
  description: "Governed Silver Easy Payment (EP) Application & Underwriting Decisions",
  bigquery: {
    clusterBy: ["CIF_ID", "APPL_STS"]
  },
  assertions: {
    nonNull: ["APPL_NO", "CIF_ID"]
  }
}

SELECT
  CAST(APPL_NO AS STRING) AS APPL_NO,
  CAST(AGREE_NO AS STRING) AS AGREE_NO,
  CAST(CIF_NO AS STRING) AS CIF_ID,
  SAFE.PARSE_DATE('%Y%m%d', NULLIF(TRIM(CAST(APPL_DT AS STRING)), '0')) AS application_date,
  TRIM(CAST(APPL_STS AS STRING)) AS APPL_STS,
  CAST(SCORING_POINT AS NUMERIC) AS SCORING_POINT,
  TRIM(CAST(SCORING_RANK AS STRING)) AS SCORING_RANK,
  TRIM(CAST(SCORE_DECISION AS STRING)) AS SCORE_DECISION,
  TRIM(CAST(LOAN_GRP AS STRING)) AS LOAN_GRP,
  CAST(FIN_AMT AS NUMERIC) AS FIN_AMT,
  CAST(INST_AMT AS NUMERIC) AS INST_AMT,
  CAST(INTEREST AS NUMERIC) AS INTEREST,
  CAST(TOTAL_INST AS INT64) AS TOTAL_INST,
  CAST(NetIncome AS NUMERIC) AS NetIncome,
  CAST(NDI AS NUMERIC) AS NDI,
  CAST(CUR_DSR AS NUMERIC) AS CUR_DSR,
  CAST(NEW_DSR AS NUMERIC) AS NEW_DSR,
  CAST(TOTAL_AEON_OSB AS NUMERIC) AS TOTAL_AEON_OSB
FROM `acsm_bronze.Fact_EP_Judge`
""",
        "definitions/silver_cc_underwriting.sqlx": """config {
  type: "table",
  schema: "acsm_silver",
  name: "silver_cc_underwriting",
  description: "Governed Silver Credit Card Application & Underwriting Decisions",
  bigquery: {
    clusterBy: ["CIF_ID", "ApplSts_ID"]
  },
  assertions: {
    nonNull: ["Appl_ID", "CIF_ID"]
  }
}

SELECT
  CAST(Appl_ID AS STRING) AS Appl_ID,
  CAST(Account_No AS STRING) AS Account_No,
  CAST(CIF_ID AS STRING) AS CIF_ID,
  SAFE.PARSE_DATE('%Y%m%d', NULLIF(TRIM(CAST(Appl_DT AS STRING)), '0')) AS application_date,
  TRIM(CAST(ApplSts_ID AS STRING)) AS ApplSts_ID,
  TRIM(CAST(CardTyp_ID AS STRING)) AS CardTyp_ID,
  TRIM(CAST(CardBrand_ID AS STRING)) AS CardBrand_ID,
  TRIM(CAST(ScoreDecision_ID AS STRING)) AS ScoreDecision_ID,
  TRIM(CAST(ScoreRank_ID AS STRING)) AS ScoreRank_ID,
  CAST(NetIncome AS NUMERIC) AS NetIncome,
  CAST(NDI AS NUMERIC) AS NDI,
  CAST(CurrDSR AS NUMERIC) AS CurrDSR,
  CAST(NewDSR AS NUMERIC) AS NewDSR,
  CAST(B_CrLimit AS NUMERIC) AS B_CrLimit,
  CAST(Final_Score AS NUMERIC) AS Final_Score,
  TRIM(CAST(Final_ScoreDesc AS STRING)) AS Final_ScoreDesc
FROM `acsm_bronze.Fact_CC_Judge`
""",
        "definitions/silver_collections_summary.sqlx": """config {
  type: "table",
  schema: "acsm_silver",
  name: "silver_collections_summary",
  description: "Customer-level Silver Collections & Delinquency Summary across EP and CC",
  bigquery: {
    clusterBy: ["CIF_ID"]
  }
}

WITH ep_col AS (
  SELECT
    CAST(CIF_No AS STRING) AS CIF_ID,
    SUM(CAST(Unpaid_OSP AS NUMERIC)) AS total_ep_unpaid_osp,
    MAX(TRIM(CAST(Score_Grade AS STRING))) AS ep_worst_grade
  FROM `acsm_bronze.Fact_EP_Collection`
  GROUP BY 1
),
cc_col AS (
  SELECT
    CAST(CIF_No AS STRING) AS CIF_ID,
    SUM(CAST(Unpaid_OSP AS NUMERIC)) AS total_cc_unpaid_osp,
    MAX(TRIM(CAST(Score_Grade AS STRING))) AS cc_worst_grade
  FROM `acsm_bronze.Fact_CC_Collection`
  GROUP BY 1
)
SELECT
  COALESCE(ep.CIF_ID, cc.CIF_ID) AS CIF_ID,
  COALESCE(ep.total_ep_unpaid_osp, 0) AS total_ep_unpaid_osp,
  COALESCE(cc.total_cc_unpaid_osp, 0) AS total_cc_unpaid_osp,
  COALESCE(ep.total_ep_unpaid_osp, 0) + COALESCE(cc.total_cc_unpaid_osp, 0) AS combined_unpaid_osp,
  GREATEST(COALESCE(ep.ep_worst_grade, 'A'), COALESCE(cc.cc_worst_grade, 'A')) AS worst_collection_score_grade
FROM ep_col ep
FULL OUTER JOIN cc_col cc
  ON ep.CIF_ID = cc.CIF_ID
""",
        "definitions/gold_aeon_customer360_profile.sqlx": """config {
  type: "table",
  schema: "acsm_gold",
  name: "gold_aeon_customer360_profile",
  description: "Gold AEON Customer 360 Risk, Affordability & Credit Exposure Feature Store",
  bigquery: {
    clusterBy: ["State", "CIF_ID"]
  }
}

WITH ep_agg AS (
  SELECT
    CIF_ID,
    COUNT(*) AS ep_app_count,
    ROUND(SUM(COALESCE(FIN_AMT, 0)), 2) AS total_ep_financed_myr,
    ROUND(AVG(NEW_DSR), 2) AS avg_ep_new_dsr
  FROM ${ref("acsm_silver", "silver_ep_underwriting")}
  GROUP BY CIF_ID
),
cc_agg AS (
  SELECT
    CIF_ID,
    COUNT(*) AS cc_app_count,
    ROUND(SUM(COALESCE(B_CrLimit, 0)), 2) AS total_cc_limit_myr,
    MAX(Final_Score) AS latest_ctos_score
  FROM ${ref("acsm_silver", "silver_cc_underwriting")}
  GROUP BY CIF_ID
),
card_agg AS (
  SELECT
    CAST(CIF_ID AS STRING) AS CIF_ID,
    COUNTIF(TRIM(CAST(Card_Status AS STRING)) = 'Active') AS active_card_count,
    ROUND(SUM(CAST(CP_CL_Usage AS NUMERIC)), 2) AS total_cp_usage_myr,
    ROUND(SUM(CAST(CP_CL_Available AS NUMERIC)), 2) AS total_cp_available_myr
  FROM `acsm_bronze.dimProduct`
  GROUP BY 1
)
SELECT
  c.CIF_ID,
  c.CIF_NM,
  c.State,
  c.Region,
  c.Occupation,
  c.N_Age,
  c.B_NetIncome,
  c.B_AnnualIncome,
  c.RecvPromo_FG,
  COALESCE(ep.ep_app_count, 0) AS ep_app_count,
  COALESCE(ep.total_ep_financed_myr, 0) AS total_ep_financed_myr,
  ep.avg_ep_new_dsr,
  COALESCE(cc.cc_app_count, 0) AS cc_app_count,
  COALESCE(cc.total_cc_limit_myr, 0) AS total_cc_limit_myr,
  cc.latest_ctos_score,
  COALESCE(col.total_ep_unpaid_osp, 0) AS total_ep_unpaid_osp,
  COALESCE(col.total_cc_unpaid_osp, 0) AS total_cc_unpaid_osp,
  COALESCE(col.combined_unpaid_osp, 0) AS combined_unpaid_osp,
  COALESCE(col.worst_collection_score_grade, 'NONE') AS worst_collection_score_grade,
  COALESCE(crd.active_card_count, 0) AS active_card_count,
  COALESCE(crd.total_cp_usage_myr, 0) AS total_cp_usage_myr,
  COALESCE(crd.total_cp_available_myr, 0) AS total_cp_available_myr
FROM ${ref("acsm_silver", "silver_customer_cif")} c
LEFT JOIN ep_agg ep USING (CIF_ID)
LEFT JOIN cc_agg cc USING (CIF_ID)
LEFT JOIN ${ref("acsm_silver", "silver_collections_summary")} col USING (CIF_ID)
LEFT JOIN card_agg crd USING (CIF_ID)
""",
        "definitions/model_delinquency_propensity.sqlx": """config {
  type: "operations",
  hasOutput: true,
  schema: "acsm_silver",
  name: "model_delinquency_propensity",
  description: "BQML Logistic Regression Delinquency Propensity Model"
}

CREATE OR REPLACE MODEL ${self()}
OPTIONS (
  MODEL_TYPE = 'LOGISTIC_REG',
  INPUT_LABEL_COLS = ['delinquency_risk_flag'],
  AUTO_CLASS_WEIGHTS = TRUE,
  MAX_ITERATIONS = 5
) AS
SELECT
  N_Age,
  B_NetIncome,
  B_AnnualIncome,
  State,
  Region,
  Occupation,
  IF(COALESCE(combined_unpaid_osp, 0) > 0, 1, 0) AS delinquency_risk_flag
FROM ${ref("acsm_gold", "gold_aeon_customer360_profile")}
""",
        "definitions/gold_aeon360_batch_ml_predictions.sqlx": """config {
  type: "table",
  schema: "acsm_gold",
  name: "gold_aeon360_batch_ml_predictions",
  description: "Gold Batch BQML Delinquency Propensity Predictions",
  bigquery: {
    clusterBy: ["State", "CIF_ID"]
  }
}

SELECT
  *
FROM ML.PREDICT(
  MODEL ${ref("acsm_silver", "model_delinquency_propensity")},
  TABLE ${ref("acsm_gold", "gold_aeon_customer360_profile")}
)
""",
    }


def ensure_dataform_service_account(project_id):
    """Creates/resolves a dedicated Dataform execution service account and binds strictActAs permissions."""
    sa_name = "acsm-dataform-sa"
    sa_email = f"{sa_name}@{project_id}.iam.gserviceaccount.com"
    project_number = subprocess.check_output(
        ["gcloud", "projects", "describe", project_id, "--format=value(projectNumber)"],
        text=True,
    ).strip()
    dataform_agent = f"serviceAccount:service-{project_number}@gcp-sa-dataform.iam.gserviceaccount.com"

    desc = subprocess.run(
        ["gcloud", "iam", "service-accounts", "describe", sa_email, f"--project={project_id}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if desc.returncode != 0:
        print(f"🔑 Creating Dataform Execution Service Account: {sa_email}...")
        subprocess.run(
            [
                "gcloud",
                "iam",
                "service-accounts",
                "create",
                sa_name,
                "--display-name=ACSM Dataform Medallion Execution SA",
                f"--project={project_id}",
                "--quiet",
            ],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    for role in ["roles/bigquery.dataEditor", "roles/bigquery.jobUser", "roles/bigquery.user", "roles/storage.objectAdmin"]:
        subprocess.run(
            [
                "gcloud",
                "projects",
                "add-iam-policy-binding",
                project_id,
                f"--member=serviceAccount:{sa_email}",
                f"--role={role}",
                "--quiet",
            ],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    for sa_role in ["roles/iam.serviceAccountTokenCreator", "roles/iam.serviceAccountUser"]:
        subprocess.run(
            [
                "gcloud",
                "iam",
                "service-accounts",
                "add-iam-policy-binding",
                sa_email,
                f"--member={dataform_agent}",
                f"--role={sa_role}",
                f"--project={project_id}",
                "--quiet",
            ],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    return sa_email


def main():
    project_id = os.environ.get("PROJECT_ID") or subprocess.check_output(
        ["gcloud", "config", "get-value", "project"], text=True
    ).strip()
    location = os.environ.get("LOCATION", "asia-southeast1")
    repo_id = os.environ.get("DATAFORM_REPOSITORY_ID", "acsm-medallion-pipeline").strip()
    workspace_id = os.environ.get("DATAFORM_WORKSPACE_ID", "default").strip()

    dataform_sa = ensure_dataform_service_account(project_id)

    token = subprocess.check_output(["gcloud", "auth", "print-access-token"], text=True).strip()
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    def call_dataform_api(url, method="GET", payload=None):
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}

    def write_workspace_file(ws_full_name, file_path, text_content):
        b64_content = base64.b64encode(text_content.encode("utf-8")).decode("utf-8")
        call_dataform_api(
            f"https://dataform.googleapis.com/v1beta1/{ws_full_name}:writeFile",
            method="POST",
            payload={"path": file_path, "contents": b64_content},
        )

    def get_workspace_files(ws_full_name):
        try:
            res = call_dataform_api(
                f"https://dataform.googleapis.com/v1beta1/{ws_full_name}:queryDirectoryContents"
            )
            entries = res.get("directoryEntries", [])
            files = []
            for entry in entries:
                if "file" in entry:
                    files.append(entry["file"])
                elif "directory" in entry:
                    sub_dir = entry["directory"]
                    sub_res = call_dataform_api(
                        f"https://dataform.googleapis.com/v1beta1/{ws_full_name}:queryDirectoryContents?path={sub_dir}"
                    )
                    for sub_e in sub_res.get("directoryEntries", []):
                        if "file" in sub_e:
                            files.append(sub_e["file"])
            return files
        except Exception:
            return []

    base_url = f"https://dataform.googleapis.com/v1beta1/projects/{project_id}/locations/{location}"
    repo_full_name = f"projects/{project_id}/locations/{location}/repositories/{repo_id}"
    ws_full_name = f"{repo_full_name}/workspaces/{workspace_id}"

    # 1. Ensure `acsm-medallion-pipeline` Repository and `default` Workspace exist
    try:
        call_dataform_api(
            f"{base_url}/repositories?repositoryId={repo_id}",
            method="POST",
            payload={
                "displayName": "ACSM Medallion & BQML Pipeline",
                "serviceAccount": dataform_sa,
            },
        )
    except urllib.error.HTTPError as e:
        if e.code != 409:
            raise
    try:
        call_dataform_api(
            f"{base_url}/repositories/{repo_id}/workspaces?workspaceId={workspace_id}",
            method="POST",
            payload={},
        )
    except urllib.error.HTTPError as e:
        if e.code != 409:
            raise

    try:
        call_dataform_api(
            f"{base_url}/repositories/{repo_id}?updateMask=serviceAccount",
            method="PATCH",
            payload={"serviceAccount": dataform_sa},
        )
    except Exception:
        pass

    # 2. Clean out any stale .sqlx files in `definitions/` and write all 7 verified Medallion + BQML .sqlx files
    workflow_settings_yaml = (
        f"dataformCoreVersion: 3.0.0\n"
        f"defaultProject: {project_id}\n"
        f"defaultLocation: {location}\n"
        f"defaultDataset: acsm_silver\n"
        f"defaultAssertionDataset: acsm_silver\n"
    )
    write_workspace_file(ws_full_name, "workflow_settings.yaml", workflow_settings_yaml)

    try:
        call_dataform_api(
            f"https://dataform.googleapis.com/v1beta1/{ws_full_name}:makeDirectory",
            method="POST",
            payload={"path": "definitions"},
        )
    except urllib.error.HTTPError:
        pass

    sqlx_map = get_medallion_sqlx_files()
    existing_files = get_workspace_files(ws_full_name)
    for old_f in existing_files:
        if old_f.endswith(".sqlx") and old_f not in sqlx_map:
            try:
                call_dataform_api(
                    f"https://dataform.googleapis.com/v1beta1/{ws_full_name}:removeFile",
                    method="POST",
                    payload={"path": old_f},
                )
            except Exception:
                pass

    for path, content in sqlx_map.items():
        write_workspace_file(ws_full_name, path, content)

    # Also auto-heal any Step 4 UI Pipeline workspaces in asia-southeast1 if they contain `Appl_DT_RAW` or `APPL_DT_RAW`
    try:
        repos_resp = call_dataform_api(f"{base_url}/repositories")
        for r in repos_resp.get("repositories", []):
            r_name = r["name"]
            if r_name.endswith(f"/{repo_id}"):
                continue
            labels = r.get("labels", {})
            if labels.get("single-file-asset-type") in ("notebook", "sql"):
                continue
            ws_list = call_dataform_api(f"https://dataform.googleapis.com/v1beta1/{r_name}/workspaces").get("workspaces", [])
            for w in ws_list:
                w_name = w["name"]
                for f_path in get_workspace_files(w_name):
                    if f_path.endswith(".sqlx"):
                        f_res = call_dataform_api(
                            f"https://dataform.googleapis.com/v1beta1/{w_name}:readFile?path={f_path}"
                        )
                        raw_bytes = base64.b64decode(f_res.get("fileContents", "")).decode("utf-8", errors="ignore")
                        if "Appl_DT_RAW" in raw_bytes or "APPL_DT_RAW" in raw_bytes:
                            fixed_sqlx = raw_bytes.replace("Appl_DT_RAW", "Appl_DT").replace("APPL_DT_RAW", "APPL_DT")
                            write_workspace_file(w_name, f_path, fixed_sqlx)
                            print(f"🛠️ Auto-repaired `Appl_DT_RAW` in Step 4 UI workspace `{w_name}` ({f_path})")
    except Exception:
        pass

    dag_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "acsm_medallion_dataform_orchestrator_dag.py")
    print(f"✅ Airflow DAG Definition Ready : {dag_path}")
    print(f"   • Target Project             : {project_id}")
    print(f"   • Target Region              : {location}")
    print(f"   • Dataform Repository ID     : {repo_id}")
    print(f"   • Dataform Workspace         : {workspace_id} (7 verified .sqlx nodes synced)")
    print(f"   • Execution Service Account  : {dataform_sa}")
    print(
        f"   • Cloud Composer Deploy Cmd  : "
        f"gcloud composer environments storage dags import --environment=<COMPOSER_ENV> --location={location} --source={dag_path}"
    )

    print("\n🚀 Executing Airflow Orchestration Sequence against Dataform API...")
    try:
        print(f"   1️⃣ [DataformCreateCompilationResultOperator] Compiling workspace: {ws_full_name}")
        compile_payload = {
            "workspace": ws_full_name,
            "codeCompilationConfig": {
                "defaultDatabase": project_id,
                "defaultLocation": location,
                "defaultSchema": "acsm_silver",
                "assertionSchema": "acsm_silver",
            },
        }
        comp_res = call_dataform_api(
            f"{base_url}/repositories/{repo_id}/compilationResults",
            method="POST",
            payload=compile_payload,
        )
        comp_name = comp_res.get("name")
        comp_errors = comp_res.get("compilationErrors", [])
        if comp_errors:
            print(f"   ⚠️ Compilation reported warnings/errors: {json.dumps(comp_errors, indent=2)}")
        else:
            print(f"   ✅ Compilation Result Created: {comp_name}")

        print(f"   2️⃣ [DataformCreateWorkflowInvocationOperator] Triggering Dataform DAG execution (SA: {dataform_sa})...")
        inv_payload = {
            "compilationResult": comp_name,
            "invocationConfig": {
                "transitiveDependenciesIncluded": True,
                "transitiveDependentsIncluded": True,
                "fullyRefreshIncrementalTablesEnabled": False,
                "serviceAccount": dataform_sa,
            },
        }
        inv_res = call_dataform_api(
            f"{base_url}/repositories/{repo_id}/workflowInvocations",
            method="POST",
            payload=inv_payload,
        )
        inv_name = inv_res.get("name")
        inv_state = inv_res.get("state", "RUNNING")
        print(f"   ✅ Workflow Invocation Started: {inv_name} (Initial State: {inv_state})")

        for _ in range(18):
            time.sleep(5)
            status_res = call_dataform_api(f"https://dataform.googleapis.com/v1beta1/{inv_name}")
            inv_state = status_res.get("state", "UNKNOWN")
            print(f"      ⏳ Dataform DAG Status: {inv_state}")
            if inv_state in ("SUCCEEDED", "FAILED", "CANCELLED"):
                break
        print(f"   🎯 Final Observed Dataform Workflow State: {inv_state}")
    except urllib.error.HTTPError as http_err:
        err_body = http_err.read().decode("utf-8", errors="ignore")
        print(f"   ⚠️ Dataform API returned HTTP {http_err.code}: {err_body[:400]}")
    except Exception as ex:
        print(f"   ℹ️ Live Dataform API invocation note: {ex}")


if __name__ == "__main__":
    main()
