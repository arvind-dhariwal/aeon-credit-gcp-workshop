#!/usr/bin/env python3
"""Provisions and configures the two RLS/CLS Governance Identities for Track 1 Notebook 03:
  - Identity 1 (Restricted Regional Analyst): `user:<USER_EMAIL>`
      * RLS (`rlp_central_region_branch_manager`): Sees ONLY 4 Central Region Malaysian states
        ('Selangor', 'Kuala Lumpur', 'Putrajaya', 'Negeri Sembilan').
      * CLS (`vw_customer360_rls_cls_masked`): Sees MASKED customer name ('MU****AD'),
        SHA-256 hash, and MASKED monthly net income (0.0).
  - Identity 2 (HQ Compliance & Risk Auditor): `serviceAccount:acsm-compliance-auditor-sa@<PROJECT_ID>.iam.gserviceaccount.com`
      * RLS (`rlp_hq_compliance_all_states`): Sees ALL 16 Malaysian states (4 Central Region states
        + all 12 other Malaysian states = 100,000 customers).
      * CLS (`vw_customer360_rls_cls_masked`): Sees UNMASKED cleartext customer name (`CIF_NM`)
        and UNMASKED exact monthly net income (`B_NetIncome`).

Also registers the `%%bigquery_as_sa` IPython cell magic when loaded via `%run` in Jupyter/Colab
so participants can run the exact same pure BigQuery SQL query side-by-side under both identities.
"""

import argparse
import os
import shlex
import subprocess
import sys
import time
import google.auth
from google.auth import impersonated_credentials
from google.auth.transport.requests import AuthorizedSession
from google.cloud import bigquery
from google.oauth2 import credentials as oauth2_credentials

SA_NAME = "acsm-compliance-auditor-sa"
SA_DISPLAY_NAME = "ACSM HQ Compliance & Credit Control Auditor (RLS All-States & CLS Unmasked)"


def get_impersonated_bq_client(project_id: str, location: str, sa_email: str) -> bigquery.Client:
    """Returns a BigQuery Client authenticated as `sa_email` via keyless IAM impersonation."""
    try:
        source_creds, _ = google.auth.default(
            scopes=["https://www.googleapis.com/auth/cloud-platform"]
        )
        imp_creds = impersonated_credentials.Credentials(
            source_credentials=source_creds,
            target_principal=sa_email,
            target_scopes=["https://www.googleapis.com/auth/cloud-platform"],
            lifetime=3600,
        )
        # Trigger token refresh to verify impersonation works via ADC
        imp_creds.refresh(google.auth.transport.requests.Request())
        return bigquery.Client(project=project_id, location=location, credentials=imp_creds)
    except Exception:
        # Fallback to gcloud auth print-access-token --impersonate-service-account
        token = subprocess.check_output(
            [
                "gcloud",
                "auth",
                "print-access-token",
                f"--impersonate-service-account={sa_email}",
                "--quiet",
            ],
            text=True,
        ).strip()
        creds = oauth2_credentials.Credentials(token=token)
        return bigquery.Client(project=project_id, location=location, credentials=creds)


def setup_identities(project_id: str, location: str, user_email: str) -> str:
    """Ensures `acsm-compliance-auditor-sa` exists and has BigQuery + TokenCreator IAM bindings."""
    sa_email = f"{SA_NAME}@{project_id}.iam.gserviceaccount.com"

    # 1. Ensure IAM Credentials API is enabled for keyless service account impersonation
    subprocess.run(
        [
            "gcloud",
            "services",
            "enable",
            "iam.googleapis.com",
            "iamcredentials.googleapis.com",
            f"--project={project_id}",
            "--quiet",
        ],
        check=False,
        capture_output=True,
        text=True,
    )

    # 2. Check if the Service Account exists; create it if missing
    desc_proc = subprocess.run(
        [
            "gcloud",
            "iam",
            "service-accounts",
            "describe",
            sa_email,
            f"--project={project_id}",
            "--quiet",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    created_new = False
    if desc_proc.returncode != 0:
        subprocess.run(
            [
                "gcloud",
                "iam",
                "service-accounts",
                "create",
                SA_NAME,
                f"--display-name={SA_DISPLAY_NAME}",
                f"--project={project_id}",
                "--quiet",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        created_new = True
        time.sleep(5)

    # 3. Grant TokenCreator on the SA to the logged-in user (and active ADC principal if different)
    caller_member = (
        f"serviceAccount:{user_email}"
        if user_email.endswith(".gserviceaccount.com")
        else f"user:{user_email}"
    )
    subprocess.run(
        [
            "gcloud",
            "iam",
            "service-accounts",
            "add-iam-policy-binding",
            sa_email,
            f"--member={caller_member}",
            "--role=roles/iam.serviceAccountTokenCreator",
            f"--project={project_id}",
            "--quiet",
        ],
        check=False,
        capture_output=True,
        text=True,
    )

    # 4. Grant BigQuery Job & Data Viewer roles to `acsm-compliance-auditor-sa`
    for role in (
        "roles/bigquery.user",
        "roles/bigquery.jobUser",
        "roles/bigquery.dataViewer",
        "roles/datacatalog.viewer",
        "roles/serviceusage.serviceUsageConsumer",
    ):
        subprocess.run(
            [
                "gcloud",
                "projects",
                "add-iam-policy-binding",
                project_id,
                f"--member=serviceAccount:{sa_email}",
                f"--role={role}",
                "--condition=None",
                "--quiet",
            ],
            check=False,
            capture_output=True,
            text=True,
        )

    # 5. Also grant immediate dataset-level READER access on `acsm_gold` (0-second propagation)
    try:
        bq_client = bigquery.Client(project=project_id, location=location)
        ds_ref = f"{project_id}.acsm_gold"
        ds = bq_client.get_dataset(ds_ref)
        entries = list(ds.access_entries)
        if not any(e.entity_id == sa_email for e in entries):
            entries.append(
                bigquery.AccessEntry(
                    role="READER",
                    entity_type="userByEmail",
                    entity_id=sa_email,
                )
            )
            ds.access_entries = entries
            bq_client.update_dataset(ds, ["access_entries"])
    except Exception:
        pass

    if created_new:
        time.sleep(5)

    print("==========================================================================")
    print("🔐 Two Governance Identities Configured for Side-by-Side RLS & CLS Testing")
    print("==========================================================================")
    print(f"  👤 User 1 (Regional Branch Manager - Restricted) : {caller_member}")
    print("     • RLS Access : ONLY 4 Central Region States (Selangor, Kuala Lumpur, Putrajaya, Negeri Sembilan)")
    print("     • CLS Access : MASKED Customer Name ('MU****AD'), SHA-256 Hash, and MASKED Net Income (0.0)")
    print(f"  🛡️ User 2 (HQ Compliance Auditor - Full Access)  : serviceAccount:{sa_email}")
    print("     • RLS Access : ALL 16 Malaysian States (4 Central + 12 Other States = 100,000 customers)")
    print("     • CLS Access : UNMASKED Full Customer Name (CIF_NM) & UNMASKED Exact Net Income (B_NetIncome)")
    print("==========================================================================")
    return sa_email


def register_ipython_magic(default_project: str, default_location: str, default_sa: str):
    """Registers `%%bigquery_as_sa` cell magic in IPython/Jupyter if running inside a notebook."""
    try:
        from IPython import get_ipython
        from IPython.core.magic import register_cell_magic

        ip = get_ipython()
        if ip is None:
            return

        @register_cell_magic
        def bigquery_as_sa(line, cell):
            """Executes pure BigQuery SQL impersonating a target Service Account (`--service_account`)."""
            parser = argparse.ArgumentParser(prog="%%bigquery_as_sa", add_help=False)
            parser.add_argument("--project", default=os.environ.get("PROJECT_ID", default_project))
            parser.add_argument("--location", default=os.environ.get("LOCATION", default_location))
            parser.add_argument(
                "--service_account",
                default=os.environ.get("AUDITOR_SA", default_sa),
            )
            args, _ = parser.parse_known_args(shlex.split(line))

            last_err = None
            for attempt in range(4):
                try:
                    client = get_impersonated_bq_client(
                        args.project, args.location, args.service_account
                    )
                    df = client.query(cell.strip()).result().to_dataframe()
                    print(
                        f"🛡️ Executed SQL as User 2 (HQ Compliance Auditor): "
                        f"serviceAccount:{args.service_account}"
                    )
                    return df
                except Exception as exc:
                    last_err = exc
                    time.sleep(3)
            raise RuntimeError(
                f"Failed to execute BigQuery query as {args.service_account}: {last_err}"
            )

        ip.user_ns["AUDITOR_SA"] = default_sa
    except ImportError:
        pass


def main():
    parser = argparse.ArgumentParser(
        description="Provision RLS/CLS test identities and optionally run a SQL query as the HQ Compliance Auditor SA."
    )
    parser.add_argument(
        "--project",
        default=os.environ.get("PROJECT_ID", ""),
        help="Google Cloud Project ID",
    )
    parser.add_argument(
        "--location",
        default=os.environ.get("LOCATION", "asia-southeast1"),
        help="BigQuery location (default: asia-southeast1)",
    )
    parser.add_argument(
        "--user-email",
        default=os.environ.get("USER_EMAIL", ""),
        help="Logged-in workshop user email",
    )
    parser.add_argument(
        "--query",
        default="",
        help="Optional SQL query to execute as the HQ Compliance Auditor Service Account",
    )
    args, _ = parser.parse_known_args()

    project_id = args.project
    if not project_id:
        project_id = subprocess.check_output(
            ["gcloud", "config", "get-value", "project"], text=True
        ).strip()
    user_email = args.user_email
    if not user_email:
        user_email = subprocess.check_output(
            ["gcloud", "config", "get-value", "account"], text=True
        ).strip()

    sa_email = setup_identities(project_id, args.location, user_email)
    os.environ["AUDITOR_SA"] = sa_email
    register_ipython_magic(project_id, args.location, sa_email)

    if args.query:
        client = get_impersonated_bq_client(project_id, args.location, sa_email)
        df = client.query(args.query).result().to_dataframe()
        print(df.to_string(index=False))


if __name__ == "__main__":
    main()
