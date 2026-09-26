#!/usr/bin/env python3
"""
ACSM Track 1 — Live Dataform Medallion DAG Orchestration Runner
Executes the exact Cloud Composer / Apache Airflow operator sequence:
  1. Auto-discovers the active Dataform Repository & Workspace in asia-southeast1
  2. Compiles the Dataform Medallion DAG (DataformCreateCompilationResultOperator equivalent)
  3. Triggers a live Dataform Workflow Invocation (DataformCreateWorkflowInvocationOperator equivalent)
"""
import json
import os
import subprocess
import time
import urllib.error
import urllib.request


def main():
    project_id = os.environ.get("PROJECT_ID") or subprocess.check_output(
        ["gcloud", "config", "get-value", "project"], text=True
    ).strip()
    location = os.environ.get("LOCATION", "asia-southeast1")
    repo_id = os.environ.get("DATAFORM_REPOSITORY_ID", "").strip()
    workspace_id = os.environ.get("DATAFORM_WORKSPACE_ID", "").strip()

    token = subprocess.check_output(["gcloud", "auth", "print-access-token"], text=True).strip()
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    def call_dataform_api(url, method="GET", payload=None):
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))

    base_url = f"https://dataform.googleapis.com/v1beta1/projects/{project_id}/locations/{location}"

    if not repo_id:
        try:
            repos_resp = call_dataform_api(f"{base_url}/repositories")
            repos = repos_resp.get("repositories", [])
            if repos:
                repo_id = repos[-1]["name"].split("/")[-1]
                print(f"🔍 Auto-discovered Dataform Repository in {location}: {repo_id}")
            else:
                repo_id = "acsm-medallion-pipeline"
                print(f"ℹ️ No existing Dataform repository found in {location}; using template ID: {repo_id}")
        except Exception as e:
            repo_id = "acsm-medallion-pipeline"
            print(f"ℹ️ Using default template Repository ID ({repo_id}): {e}")

    if not workspace_id:
        try:
            ws_resp = call_dataform_api(f"{base_url}/repositories/{repo_id}/workspaces")
            workspaces = ws_resp.get("workspaces", [])
            if workspaces:
                workspace_id = workspaces[0]["name"].split("/")[-1]
                print(f"🔍 Auto-discovered Dataform Workspace: {workspace_id}")
            else:
                workspace_id = "default"
        except Exception:
            workspace_id = "default"

    dag_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "acsm_medallion_dataform_orchestrator_dag.py")
    print(f"✅ Airflow DAG Definition Ready : {dag_path}")
    print(f"   • Target Project             : {project_id}")
    print(f"   • Target Region              : {location}")
    print(f"   • Dataform Repository ID     : {repo_id}")
    print(f"   • Dataform Workspace         : {workspace_id}")
    print(
        f"   • Cloud Composer Deploy Cmd  : "
        f"gcloud composer environments storage dags import --environment=<COMPOSER_ENV> --location={location} --source={dag_path}"
    )

    print("\n🚀 Executing Airflow Orchestration Sequence against Dataform API...")
    try:
        compile_payload = {
            "codeCompilationConfig": {
                "defaultDatabase": project_id,
                "defaultLocation": location,
            }
        }
        try:
            ws_check = call_dataform_api(f"{base_url}/repositories/{repo_id}/workspaces")
            if ws_check.get("workspaces"):
                ws_full_name = ws_check["workspaces"][0]["name"]
                compile_payload["workspace"] = ws_full_name
                print(f"   1️⃣ [DataformCreateCompilationResultOperator] Compiling workspace: {ws_full_name}")
            else:
                compile_payload["gitCommitish"] = "main"
                print(f"   1️⃣ [DataformCreateCompilationResultOperator] Compiling branch 'main' in {repo_id}")
        except Exception:
            compile_payload["gitCommitish"] = "main"

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

        print("   2️⃣ [DataformCreateWorkflowInvocationOperator] Triggering Dataform DAG execution...")
        inv_payload = {
            "compilationResult": comp_name,
            "invocationConfig": {
                "includeDependencies": True,
                "includeDependents": True,
                "fullyRefreshIncrementalTablesEnabled": False,
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

        for _ in range(6):
            time.sleep(5)
            status_res = call_dataform_api(f"https://dataform.googleapis.com/v1beta1/{inv_name}")
            inv_state = status_res.get("state", "UNKNOWN")
            print(f"      ⏳ Dataform DAG Status: {inv_state}")
            if inv_state in ("SUCCEEDED", "FAILED", "CANCELLED"):
                break
        print(f"   🎯 Final Observed Dataform Workflow State: {inv_state}")
    except urllib.error.HTTPError as http_err:
        err_body = http_err.read().decode("utf-8", errors="ignore")
        print(
            f"   ℹ️ Live Dataform API invocation skipped or repo not yet created in Step 4 "
            f"(HTTP {http_err.code}): {err_body[:300]}"
        )
        print("   💡 Tip: Once you create and save your Pipeline in Step 4, re-run this cell to trigger it via the Dataform API!")
    except Exception as ex:
        print(f"   ℹ️ Live Dataform API invocation note: {ex}")


if __name__ == "__main__":
    main()
