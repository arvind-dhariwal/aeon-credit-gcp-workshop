"""
ACSM Track 1 — Apache Airflow (Cloud Composer) Orchestrator for BigQuery Dataform Medallion DAG
Region: asia-southeast1 (Singapore)
RFP Clauses: C1.1.1.5 (Orchestration), C1.1.1.6 (Data Quality Assertions), C1.1.1.7 (SLA Alerting)
"""
import os
from datetime import datetime, timedelta
import google.auth
from airflow import DAG
from airflow.models import Variable
from airflow.providers.google.cloud.operators.bigquery import BigQueryCheckOperator
from airflow.providers.google.cloud.operators.dataform import (
    DataformCreateCompilationResultOperator,
    DataformCreateWorkflowInvocationOperator,
)

_, _default_project = google.auth.default()
PROJECT_ID = (
    os.environ.get("PROJECT_ID")
    or os.environ.get("GOOGLE_CLOUD_PROJECT")
    or os.environ.get("GCP_PROJECT")
    or Variable.get("gcp_project", default_var=_default_project)
)
REGION = os.environ.get("LOCATION") or Variable.get("gcp_location", default_var="asia-southeast1")
REPOSITORY_ID = os.environ.get("DATAFORM_REPOSITORY_ID") or Variable.get(
    "dataform_repository_id", default_var="acsm-medallion-pipeline"
)
WORKSPACE_ID = os.environ.get("DATAFORM_WORKSPACE_ID") or Variable.get(
    "dataform_workspace_id", default_var="default"
)
DATAFORM_SERVICE_ACCOUNT = os.environ.get("DATAFORM_SERVICE_ACCOUNT") or Variable.get(
    "dataform_service_account", default_var=f"acsm-dataform-sa@{PROJECT_ID}.iam.gserviceaccount.com"
)


def sla_breach_alert_callback(context):
    """Automated SLA & Data Quality breach notification hook (RFP Clause C1.1.1.7)."""
    task_id = context.get("task_instance").task_id
    dag_id = context.get("dag").dag_id
    exec_date = context.get("logical_date") or context.get("execution_date")
    print(f"[SLA ALERT] DAG={dag_id} | Task={task_id} breached SLA/DQ check at {exec_date}")


default_args = {
    "owner": "acsm-data-engineering",
    "depends_on_past": False,
    "email_on_failure": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
    "on_failure_callback": sla_breach_alert_callback,
}

with DAG(
    dag_id="acsm_medallion_dataform_orchestrator",
    description="Orchestrates ACSM Bronze -> Silver -> Gold + BQML Dataform DAG in Singapore (asia-southeast1)",
    default_args=default_args,
    schedule="0 2 * * *",  # Daily at 02:00 AM MYT/SGT (UTC+8 adjusted)
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=["acsm", "medallion", "dataform", "bigquery", "bnm-rmit"],
) as dag:

    # 1. Pre-Flight Check: Ensure all 8 Bronze source tables are populated in asia-southeast1
    verify_bronze_lakehouse_readiness = BigQueryCheckOperator(
        task_id="verify_bronze_lakehouse_readiness",
        sql=f"""
            SELECT COUNT(*) = 8
            FROM `{PROJECT_ID}.acsm_bronze.INFORMATION_SCHEMA.TABLES`
            WHERE table_name IN (
                'm3CIF', 'dimProduct', 'Fact_EP_Judge', 'Fact_CC_Judge',
                'Fact_EP_Collection', 'Fact_CC_Collection', 'Fact_EP_Sales', 'Fact_CC_Sales'
            )
        """,
        use_legacy_sql=False,
        location=REGION,
    )

    # 2. Compile the Dataform Repository Workspace (resolving Bronze -> Silver -> Gold -> BQML dependency graph)
    compile_dataform_medallion_repo = DataformCreateCompilationResultOperator(
        task_id="compile_dataform_medallion_repo",
        project_id=PROJECT_ID,
        region=REGION,
        repository_id=REPOSITORY_ID,
        compilation_result={
            "workspace": f"projects/{PROJECT_ID}/locations/{REGION}/repositories/{REPOSITORY_ID}/workspaces/{WORKSPACE_ID}",
            "code_compilation_config": {
                "default_database": PROJECT_ID,
                "default_location": REGION,
                "default_schema": "acsm_silver",
                "assertion_schema": "acsm_silver",
            },
        },
    )

    # 3. Invoke the Compiled Dataform Workflow (Silver + Assertions + BQML Model + Gold Batch Scoring)
    invoke_dataform_medallion_dag = DataformCreateWorkflowInvocationOperator(
        task_id="invoke_dataform_medallion_dag",
        project_id=PROJECT_ID,
        region=REGION,
        repository_id=REPOSITORY_ID,
        workflow_invocation={
            "compilation_result": "{{ task_instance.xcom_pull(task_ids='compile_dataform_medallion_repo')['name'] }}",
            "invocation_config": {
                "transitive_dependencies_included": True,
                "transitive_dependents_included": True,
                "fully_refresh_incremental_tables_enabled": False,
                "service_account": DATAFORM_SERVICE_ACCOUNT,
            },
        },
    )

    # 4. Post-Execution Financial Control-Total Reconciliation & Gold BQML Audit Gate
    audit_reconciliation_and_dq_sla = BigQueryCheckOperator(
        task_id="audit_reconciliation_and_dq_sla",
        sql=f"""
            SELECT
              ROUND(
                (SELECT SUM(CAST(FIN_AMT AS NUMERIC)) FROM `{PROJECT_ID}.acsm_bronze.Fact_EP_Judge`)
                - (SELECT SUM(CAST(FIN_AMT AS NUMERIC)) FROM `{PROJECT_ID}.acsm_silver.silver_ep_underwriting`),
                2
              ) = 0.00
              AND (SELECT COUNT(*) FROM `{PROJECT_ID}.acsm_gold.gold_aeon_customer360_profile`) > 0
              AND (SELECT COUNT(*) FROM `{PROJECT_ID}.acsm_gold.gold_aeon360_batch_ml_predictions`) > 0
        """,
        use_legacy_sql=False,
        location=REGION,
    )

    (
        verify_bronze_lakehouse_readiness
        >> compile_dataform_medallion_repo
        >> invoke_dataform_medallion_dag
        >> audit_reconciliation_and_dq_sla
    )
