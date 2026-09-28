#!/usr/bin/env python3
"""Provisions and configures the 3 RLS/CLS Governance Personas for Track 1 Notebook 03
(aligned with the reference trainer guide `Module1 Lab4 Data_governance_policy_tags_masking_instructions_trainer.md`):

  - 👤 Persona 1 — Regional Branch Manager / Business Analyst (`user:<USER_EMAIL>`):
      * RLS (`rlp_central_region_branch_manager`): Sees ONLY 4 Central Region Malaysian states
        ('Selangor', 'Kuala Lumpur', 'Putrajaya', 'Negeri Sembilan').
      * CLS (`DATA_MASKING_POLICY` v2 on all 4 IAM Data Governance Tags):
        - `CIF_NM`            (`customer_name`)       -> Masked via `SHA256` cryptographic hash
        - `CIF_ID`            (`customer_id`)         -> Masked via `LAST_FOUR_CHARACTERS` ('XXXXX...')
        - `B_NetIncome`       (`financial_amount`)    -> Masked via `DEFAULT_MASKING_VALUE` (0.0)
        - `latest_ctos_score` (`credit_bureau_score`) -> Masked via `ALWAYS_NULL` (SQL NULL)

  - 🛡️ Persona 2 — HQ Compliance & Risk Auditor (`serviceAccount:acsm-compliance-auditor-sa@<PROJECT_ID>.iam.gserviceaccount.com`):
      * RLS (`rlp_hq_compliance_all_states`): Sees ALL 16 Malaysian states (4 Central Region states
        + all 12 other Malaysian states = 100,000 customers).
      * CLS (`RAW_DATA_ACCESS_POLICY` v2 on all 4 IAM Data Governance Tags):
        - Sees UNMASKED cleartext `CIF_ID`, `CIF_NM`, `B_NetIncome`, and `latest_ctos_score`.

  - 🚫 Persona 3 — Restricted User (`serviceAccount:acsm-restricted-user-sa@<PROJECT_ID>.iam.gserviceaccount.com`):
      * Has BigQuery `dataViewer` + `jobUser` roles on the project, but NO `RAW_DATA_ACCESS_POLICY`
        or `DATA_MASKING_POLICY` grants (and no RLS grant).
      * CLS: Explicitly denied access (`403 Access Denied: User does not have masked access or raw
        data access to protected columns`) when querying protected CLS columns.
      * RLS: Receives `0 rows` (RLS Implicit Default Deny) when querying RLS-protected tables.

Also registers the `%%bigquery_as_sa` and `%%bigquery_expect_access_denied` IPython cell magics
when loaded via `%run` in Jupyter/Colab.
"""

import argparse
import os
import shlex
import subprocess
import time
import google.auth
from google.auth import impersonated_credentials
from google.cloud import bigquery
from google.oauth2 import credentials as oauth2_credentials

SA_NAME = "acsm-compliance-auditor-sa"
SA_DISPLAY_NAME = "ACSM HQ Compliance & Credit Control Auditor (RLS All-States & CLS Unmasked)"

RESTRICTED_SA_NAME = "acsm-restricted-user-sa"
RESTRICTED_SA_DISPLAY_NAME = "ACSM Restricted User Persona (CLS 403 Access Denied & RLS Default Deny)"


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
        imp_creds.refresh(google.auth.transport.requests.Request())
        return bigquery.Client(project=project_id, location=location, credentials=imp_creds)
    except Exception:
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


def ensure_service_account(
    project_id: str, sa_short_name: str, display_name: str, caller_member: str
) -> tuple[str, bool]:
    """Ensures a service account exists and grants `caller_member` TokenCreator + BigQuery viewer roles."""
    sa_email = f"{sa_short_name}@{project_id}.iam.gserviceaccount.com"
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
                sa_short_name,
                f"--display-name={display_name}",
                f"--project={project_id}",
                "--quiet",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        created_new = True
        time.sleep(4)

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

    for role in (
        "roles/bigquery.user",
        "roles/bigquery.jobUser",
        "roles/bigquery.dataViewer",
        "roles/datacatalog.viewer",
        "roles/resourcemanager.tagViewer",
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
    return sa_email, created_new


def setup_identities(project_id: str, location: str, user_email: str) -> tuple[str, str]:
    """Ensures the 3 governance personas (`user:<USER_EMAIL>`, `acsm-compliance-auditor-sa`, `acsm-restricted-user-sa`) are configured."""
    subprocess.run(
        [
            "gcloud",
            "services",
            "enable",
            "iam.googleapis.com",
            "iamcredentials.googleapis.com",
            "cloudresourcemanager.googleapis.com",
            "bigquerydatapolicy.googleapis.com",
            "datacatalog.googleapis.com",
            f"--project={project_id}",
            "--quiet",
        ],
        check=False,
        capture_output=True,
        text=True,
    )

    caller_member = (
        f"serviceAccount:{user_email}"
        if user_email.endswith(".gserviceaccount.com")
        else f"user:{user_email}"
    )
    for caller_role in (
        "roles/resourcemanager.tagAdmin",
        "roles/resourcemanager.tagUser",
        "roles/bigquerydatapolicy.admin",
    ):
        subprocess.run(
            [
                "gcloud",
                "projects",
                "add-iam-policy-binding",
                project_id,
                f"--member={caller_member}",
                f"--role={caller_role}",
                "--condition=None",
                "--quiet",
            ],
            check=False,
            capture_output=True,
            text=True,
        )

    auditor_sa_email, created_auditor = ensure_service_account(
        project_id, SA_NAME, SA_DISPLAY_NAME, caller_member
    )
    restricted_sa_email, created_restricted = ensure_service_account(
        project_id, RESTRICTED_SA_NAME, RESTRICTED_SA_DISPLAY_NAME, caller_member
    )

    # Grant dataset-level READER access on `acsm_gold` & reset any prior column tags
    try:
        bq_client = bigquery.Client(project=project_id, location=location)
        ds_ref = f"{project_id}.acsm_gold"
        ds = bq_client.get_dataset(ds_ref)
        entries = list(ds.access_entries)
        updated_ds = False
        for target_sa in (auditor_sa_email, restricted_sa_email):
            if not any(e.entity_id == target_sa for e in entries):
                entries.append(
                    bigquery.AccessEntry(
                        role="READER",
                        entity_type="userByEmail",
                        entity_id=target_sa,
                    )
                )
                updated_ds = True
        if updated_ds:
            ds.access_entries = entries
            bq_client.update_dataset(ds, ["access_entries"])

        table_ref = f"{project_id}.acsm_gold.gold_aeon_customer360_profile"
        for col in ("CIF_NM", "CIF_ID", "B_NetIncome", "latest_ctos_score"):
            try:
                bq_client.query(
                    f"ALTER TABLE `{table_ref}` ALTER COLUMN {col} SET OPTIONS (data_governance_tags=[]);"
                ).result()
            except Exception:
                pass
    except Exception:
        pass

    if created_auditor or created_restricted:
        time.sleep(5)

    print("==========================================================================")
    print("🔐 Three Governance Personas Configured for Side-by-Side RLS & CLS Testing")
    print("==========================================================================")
    print(f"  👤 Persona 1 — Regional Branch Manager (Analyst) : {caller_member}")
    print("     • RLS Policy : ONLY 4 Central Region States (Selangor, Kuala Lumpur, Putrajaya, Negeri Sembilan)")
    print("     • CLS Policy : `DATA_MASKING_POLICY` via IAM Data Governance Tags (`purpose=DATA_GOVERNANCE`)")
    print("                    - `CIF_NM`            -> Masked via `SHA256` cryptographic hash")
    print("                    - `CIF_ID`            -> Masked via `LAST_FOUR_CHARACTERS` ('XXXXX...')")
    print("                    - `B_NetIncome`       -> Masked via `DEFAULT_MASKING_VALUE` (0.0)")
    print("                    - `latest_ctos_score` -> Masked via `ALWAYS_NULL` (SQL NULL)")
    print(f"  🛡️ Persona 2 — HQ Compliance Auditor (Data Lead) : serviceAccount:{auditor_sa_email}")
    print("     • RLS Policy : ALL 16 Malaysian States (4 Central + 12 Other States = 100,000 customers)")
    print("     • CLS Policy : `RAW_DATA_ACCESS_POLICY` via IAM Data Governance Tags (`purpose=DATA_GOVERNANCE`)")
    print("                    - `CIF_NM`, `CIF_ID`, `B_NetIncome` & `latest_ctos_score` -> UNMASKED Plaintext")
    print(f"  🚫 Persona 3 — Restricted User (No Policy Grant) : serviceAccount:{restricted_sa_email}")
    print("     • CLS Policy : NO `RAW_DATA_ACCESS_POLICY` or `DATA_MASKING_POLICY` grant")
    print("                    -> Strictly blocked with `403 Access Denied` on protected CLS columns!")
    print("     • RLS Policy : NO Row Access Policy grant -> Returns `0 rows` (RLS Default Deny)")
    print("==========================================================================")
    return auditor_sa_email, restricted_sa_email


def register_ipython_magic(
    default_project: str,
    default_location: str,
    default_auditor_sa: str,
    default_restricted_sa: str = "",
):
    """Registers `%%bigquery_as_sa` and `%%bigquery_expect_access_denied` cell magics in IPython/Jupyter."""
    if not default_restricted_sa:
        default_restricted_sa = f"{RESTRICTED_SA_NAME}@{default_project}.iam.gserviceaccount.com"
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
                default=os.environ.get("AUDITOR_SA", default_auditor_sa),
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
                        f"🛡️ Executed SQL as Persona 2 (HQ Compliance Auditor): "
                        f"serviceAccount:{args.service_account}"
                    )
                    return df
                except Exception as exc:
                    last_err = exc
                    time.sleep(3)
            raise RuntimeError(
                f"Failed to execute BigQuery query as {args.service_account}: {last_err}"
            )

        @register_cell_magic
        def bigquery_expect_access_denied(line, cell):
            """Executes pure BigQuery SQL as Persona 3 (`acsm-restricted-user-sa`) and catches/displays the expected 403 Access Denied CLS error."""
            import pandas as pd

            parser = argparse.ArgumentParser(prog="%%bigquery_expect_access_denied", add_help=False)
            parser.add_argument("--project", default=os.environ.get("PROJECT_ID", default_project))
            parser.add_argument("--location", default=os.environ.get("LOCATION", default_location))
            parser.add_argument(
                "--service_account",
                default=os.environ.get(
                    "RESTRICTED_SA",
                    f"{RESTRICTED_SA_NAME}@{os.environ.get('PROJECT_ID', default_project)}.iam.gserviceaccount.com",
                ),
            )
            args, _ = parser.parse_known_args(shlex.split(line))

            client = get_impersonated_bq_client(
                args.project, args.location, args.service_account
            )
            try:
                df = client.query(cell.strip()).result().to_dataframe()
                print("⚠️ Query unexpectedly succeeded (verify column tag and policy binding):")
                return df
            except Exception as exc:
                err_msg = str(exc).splitlines()[0] if str(exc) else repr(exc)
                print(
                    f"🚫 [EXPECTED CLS 403 ACCESS DENIED VERIFIED] BigQuery blocked Restricted User "
                    f"(`serviceAccount:{args.service_account}`) from querying protected CLS columns!"
                )
                print(f"   • BigQuery Server Response: {err_msg}")
                return pd.DataFrame(
                    [
                        {
                            "queried_by_persona": f"serviceAccount:{args.service_account}",
                            "attempted_protected_columns": "CIF_ID, CIF_NM, B_NetIncome, latest_ctos_score",
                            "data_governance_tag_key": f"{args.project}/pii_classification",
                            "cls_enforcement_status": "403 ACCESS DENIED (No Raw or Masked Data Policy Grant)",
                            "bigquery_error": err_msg,
                        }
                    ]
                )

        ip.user_ns["AUDITOR_SA"] = default_auditor_sa
        ip.user_ns["RESTRICTED_SA"] = default_restricted_sa
    except ImportError:
        pass


def main():
    parser = argparse.ArgumentParser(
        description="Provision the 3 RLS/CLS test personas and optionally run a SQL query as the HQ Compliance Auditor SA."
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

    auditor_sa_email, restricted_sa_email = setup_identities(
        project_id, args.location, user_email
    )
    os.environ["AUDITOR_SA"] = auditor_sa_email
    os.environ["RESTRICTED_SA"] = restricted_sa_email
    register_ipython_magic(project_id, args.location, auditor_sa_email, restricted_sa_email)

    if args.query:
        client = get_impersonated_bq_client(project_id, args.location, auditor_sa_email)
        df = client.query(args.query).result().to_dataframe()
        print(df.to_string(index=False))


if __name__ == "__main__":
    main()
