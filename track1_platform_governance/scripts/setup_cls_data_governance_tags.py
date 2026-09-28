#!/usr/bin/env python3
"""Provisions the Modern IAM Data Governance Tag (`purpose=DATA_GOVERNANCE`) and BigQuery Data Policies v2
for Track 1 Notebook 03 (Step 1.3 — Column-Level Security & Dynamic Data Masking on `CIF_NM`):

  1. Pillar 1 — Cloud Resource Manager API v3 (`/v3/tagKeys`, `/v3/tagValues`):
     • Tag Key   : `<PROJECT_ID>/pii_classification` (`purpose = "DATA_GOVERNANCE"`)
     • Tag Value : `customer_name` (High Sensitivity -> `CIF_NM` Customer Full Name)

  2. Pillar 3 — BigQuery Data Policy API v2 (`/v2/projects/<PROJECT_ID>/locations/<LOCATION>/dataPolicies`):
     • 🛡️ User 2 (`acsm-compliance-auditor-sa@<PROJECT_ID>.iam.gserviceaccount.com`):
       Granted `RAW_DATA_ACCESS_POLICY` on `customer_name`
       -> Sees UNMASKED cleartext `CIF_NM` (e.g., `'MUHAMMAD FAIZ BIN AHMAD'`)!
     • 👤 User 1 (`user:<USER_EMAIL>`):
       Granted `DATA_MASKING_POLICY` (`SHA256`) on `customer_name`
       -> Sees `CIF_NM` dynamically masked via irreversible `SHA256` cryptographic hash!
"""

import argparse
import os
import subprocess
import time
import google.auth
from google.auth.transport.requests import AuthorizedSession
from google.cloud import bigquery

TAG_KEY_SHORT_NAME = "pii_classification"
TAG_VALUES_SPEC = {
    "customer_name": (
        "High",
        "Malaysian PDPA 2010 Direct Customer Full Name (CIF_NM)",
        "SHA256",
    ),
}


def to_iam_v2_principal(email: str) -> str:
    """Converts an email to IAM v2 principal syntax required by BigQuery Data Policy API v2."""
    email = email.strip()
    for prefix in ("user:", "serviceAccount:"):
        if email.startswith(prefix):
            email = email[len(prefix) :]
    if email.endswith(".gserviceaccount.com"):
        return f"principal://iam.googleapis.com/projects/-/serviceAccounts/{email}"
    return f"principal://goog/subject/{email}"


def ensure_apis_and_tag_iam(project_id: str, user_email: str):
    """Enables Cloud Resource Manager + BigQuery Data Policy APIs and ensures Tag Admin/User roles."""
    subprocess.run(
        [
            "gcloud",
            "services",
            "enable",
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
    for role in (
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
                f"--role={role}",
                "--condition=None",
                "--quiet",
            ],
            check=False,
            capture_output=True,
            text=True,
        )


def clear_other_column_tags(bq_client: bigquery.Client, project_id: str):
    """Clears legacy v1 policyTags and removes any v2 data_governance_tags from clustering/other columns (`CIF_ID`, `B_NetIncome`, `latest_ctos_score`)."""
    table_ref = f"{project_id}.acsm_gold.gold_aeon_customer360_profile"
    try:
        table = bq_client.get_table(table_ref)
        changed = False
        clean_schema = []
        for field in table.schema:
            field_dict = field.to_api_repr()
            if "policyTags" in field_dict:
                field_dict.pop("policyTags", None)
                changed = True
            clean_schema.append(bigquery.SchemaField.from_api_repr(field_dict))
        if changed:
            table.schema = clean_schema
            bq_client.update_table(table, ["schema"])
    except Exception:
        pass

    for col in ("CIF_ID", "B_NetIncome", "latest_ctos_score"):
        try:
            bq_client.query(
                f"ALTER TABLE `{table_ref}` ALTER COLUMN {col} SET OPTIONS (data_governance_tags=[]);"
            ).result()
        except Exception:
            pass


def wait_crm_operation(session: AuthorizedSession, op_json: dict):
    """Waits briefly for a Cloud Resource Manager v3 long-running operation if returned."""
    op_name = op_json.get("name", "")
    if not op_name or not op_name.startswith("operations/"):
        return op_json
    for _ in range(15):
        if op_json.get("done"):
            return op_json.get("response", op_json)
        time.sleep(1)
        r = session.get(f"https://cloudresourcemanager.googleapis.com/v3/{op_name}")
        if r.status_code == 200:
            op_json = r.json()
    return op_json


def ensure_data_governance_tags(session: AuthorizedSession, project_id: str) -> str:
    """Creates or resolves the `pii_classification` Tag Key (`purpose=DATA_GOVERNANCE`) and `customer_name` Tag Value."""
    namespaced_key = f"{project_id}/{TAG_KEY_SHORT_NAME}"
    ns_url = f"https://cloudresourcemanager.googleapis.com/v3/tagKeys/namespaced?name={namespaced_key}"
    resp = session.get(ns_url)

    if resp.status_code == 200 and resp.json().get("name"):
        tag_key_name = resp.json()["name"]
    else:
        create_resp = session.post(
            "https://cloudresourcemanager.googleapis.com/v3/tagKeys",
            json={
                "shortName": TAG_KEY_SHORT_NAME,
                "parent": f"projects/{project_id}",
                "purpose": "DATA_GOVERNANCE",
                "description": "ACSM BNM RMiT & Malaysian PDPA 2010 Data Governance Tag Key for Column-Level Security & Dynamic Data Masking",
            },
        )
        if create_resp.status_code in (200, 201):
            wait_crm_operation(session, create_resp.json())
        tag_key_name = ""
        for _ in range(10):
            r = session.get(ns_url)
            if r.status_code == 200 and r.json().get("name"):
                tag_key_name = r.json()["name"]
                break
            time.sleep(1)
        if not tag_key_name:
            raise RuntimeError(
                f"Failed to create or resolve Tag Key `{namespaced_key}`: {create_resp.text}"
            )

    list_val_resp = session.get(
        f"https://cloudresourcemanager.googleapis.com/v3/tagValues?parent={tag_key_name}"
    )
    existing_values = {
        v.get("shortName"): v.get("name")
        for v in list_val_resp.json().get("tagValues", [])
    }

    for short_name, (_, desc, _) in TAG_VALUES_SPEC.items():
        if short_name in existing_values:
            continue
        val_resp = session.post(
            "https://cloudresourcemanager.googleapis.com/v3/tagValues",
            json={
                "shortName": short_name,
                "parent": tag_key_name,
                "description": desc,
            },
        )
        if val_resp.status_code in (200, 201):
            wait_crm_operation(session, val_resp.json())

    return tag_key_name


def ensure_v2_data_policies(
    session: AuthorizedSession,
    project_id: str,
    location: str,
    user1_v2_principal: str,
    user2_v2_principal: str,
):
    """Provisions `RAW_DATA_ACCESS_POLICY` (for User 2) and `DATA_MASKING_POLICY` (`SHA256` for User 1) on `customer_name`."""
    parent = f"projects/{project_id}/locations/{location}"
    base_url = f"https://bigquerydatapolicy.googleapis.com/v2/{parent}/dataPolicies"
    namespaced_key = f"{project_id}/{TAG_KEY_SHORT_NAME}"

    list_resp = session.get(base_url)
    existing_policies = (
        list_resp.json().get("dataPolicies", []) if list_resp.status_code == 200 else []
    )

    def find_existing_policy(policy_id: str, policy_type: str, tag_value: str):
        for p in existing_policies:
            if p.get("dataPolicyId") == policy_id or p.get("name", "").endswith(f"/{policy_id}"):
                return p
            dg_tag = p.get("dataGovernanceTag", {})
            if (
                p.get("dataPolicyType") == policy_type
                and dg_tag.get("key") == namespaced_key
                and dg_tag.get("value") == tag_value
            ):
                return p
        return None

    for tag_value, (_, _, masking_expr) in TAG_VALUES_SPEC.items():
        # 1. RAW_DATA_ACCESS_POLICY for User 2 (HQ Compliance Auditor SA)
        raw_policy_id = f"raw_{tag_value}_auditor"
        existing_raw = find_existing_policy(raw_policy_id, "RAW_DATA_ACCESS_POLICY", tag_value)
        if not existing_raw:
            r = session.post(
                base_url,
                json={
                    "dataPolicyId": raw_policy_id,
                    "dataPolicy": {
                        "dataPolicyType": "RAW_DATA_ACCESS_POLICY",
                        "dataGovernanceTag": {
                            "key": namespaced_key,
                            "value": tag_value,
                        },
                        "grantees": [user2_v2_principal],
                    },
                },
            )
            if r.status_code not in (200, 201, 409):
                raise RuntimeError(
                    f"Failed creating RAW_DATA_ACCESS_POLICY `{raw_policy_id}`: {r.text}"
                )
            raw_res_name = r.json().get("name", f"{parent}/dataPolicies/{raw_policy_id}")
        else:
            raw_res_name = existing_raw["name"]

        session.post(
            f"https://bigquerydatapolicy.googleapis.com/v2/{raw_res_name}:addGrantees",
            json={"grantees": [user2_v2_principal]},
        )
        if user1_v2_principal != user2_v2_principal:
            session.post(
                f"https://bigquerydatapolicy.googleapis.com/v2/{raw_res_name}:removeGrantees",
                json={"grantees": [user1_v2_principal]},
            )

        # 2. DATA_MASKING_POLICY for User 1 (Regional Branch Manager)
        mask_policy_id = f"mask_{tag_value}_analyst"
        existing_mask = find_existing_policy(mask_policy_id, "DATA_MASKING_POLICY", tag_value)
        if not existing_mask:
            r = session.post(
                base_url,
                json={
                    "dataPolicyId": mask_policy_id,
                    "dataPolicy": {
                        "dataPolicyType": "DATA_MASKING_POLICY",
                        "dataGovernanceTag": {
                            "key": namespaced_key,
                            "value": tag_value,
                        },
                        "dataMaskingPolicy": {
                            "predefinedExpression": masking_expr,
                        },
                        "grantees": [user1_v2_principal],
                    },
                },
            )
            if r.status_code not in (200, 201, 409):
                raise RuntimeError(
                    f"Failed creating DATA_MASKING_POLICY `{mask_policy_id}`: {r.text}"
                )
            mask_res_name = r.json().get("name", f"{parent}/dataPolicies/{mask_policy_id}")
        else:
            mask_res_name = existing_mask["name"]

        session.post(
            f"https://bigquerydatapolicy.googleapis.com/v2/{mask_res_name}:addGrantees",
            json={"grantees": [user1_v2_principal]},
        )


def setup_cls_data_governance(
    project_id: str, location: str, user_email: str, auditor_sa: str
):
    """End-to-end provisioning of IAM Data Governance Tag (`customer_name`) and BigQuery Data Policies v2."""
    if not auditor_sa:
        auditor_sa = f"acsm-compliance-auditor-sa@{project_id}.iam.gserviceaccount.com"

    ensure_apis_and_tag_iam(project_id, user_email)

    creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    session = AuthorizedSession(creds)
    bq_client = bigquery.Client(project=project_id, location=location, credentials=creds)

    clear_other_column_tags(bq_client, project_id)
    tag_key_name = ensure_data_governance_tags(session, project_id)

    user1_v2 = to_iam_v2_principal(user_email)
    user2_v2 = to_iam_v2_principal(auditor_sa)
    ensure_v2_data_policies(session, project_id, location, user1_v2, user2_v2)

    print("==========================================================================")
    print("🏷️  Pillar 1 & Pillar 3 Provisioned: IAM Data Governance Tag & Data Policies v2")
    print("==========================================================================")
    print(f"  • Resource Manager Tag Key : `{project_id}/{TAG_KEY_SHORT_NAME}` ({tag_key_name}, purpose=DATA_GOVERNANCE)")
    print("  • Governed Column & Tag    : `CIF_NM` (Customer Full Name) -> `customer_name` (High Tier)")
    print("  • Note on Clustering Cols  : `CIF_ID` & `State` are clustering keys on `gold_aeon_customer360_profile`")
    print("                               and are kept untagged (BigQuery prohibits masking clustering keys).")
    print("--------------------------------------------------------------------------")
    print(f"  👤 User 1 (Regional Branch Manager) : {user1_v2}")
    print("     • `mask_customer_name_analyst` (`DATA_MASKING_POLICY`) -> `CIF_NM` masked via `SHA256`")
    print(f"  🛡️ User 2 (HQ Compliance Auditor)   : {user2_v2}")
    print("     • `raw_customer_name_auditor`  (`RAW_DATA_ACCESS_POLICY`) -> `CIF_NM` UNMASKED Plaintext")
    print("--------------------------------------------------------------------------")
    print("  👉 Next Step (Step 1.3b): Run the Pure BigQuery SQL `ALTER TABLE ... ALTER COLUMN` cell")
    print("     below to attach the `customer_name` tag to `CIF_NM` on `acsm_gold.gold_aeon_customer360_profile`!")
    print("==========================================================================")


def main():
    parser = argparse.ArgumentParser(
        description="Provision IAM Data Governance Tag (purpose=DATA_GOVERNANCE) and BigQuery Data Policies v2 on CIF_NM."
    )
    parser.add_argument("--project", default=os.environ.get("PROJECT_ID", ""))
    parser.add_argument("--location", default=os.environ.get("LOCATION", "asia-southeast1"))
    parser.add_argument("--user-email", default=os.environ.get("USER_EMAIL", ""))
    parser.add_argument("--auditor-sa", default=os.environ.get("AUDITOR_SA", ""))
    args, _ = parser.parse_known_args()

    project_id = args.project or subprocess.check_output(
        ["gcloud", "config", "get-value", "project"], text=True
    ).strip()
    user_email = args.user_email or subprocess.check_output(
        ["gcloud", "config", "get-value", "account"], text=True
    ).strip()
    auditor_sa = args.auditor_sa or f"acsm-compliance-auditor-sa@{project_id}.iam.gserviceaccount.com"

    setup_cls_data_governance(project_id, args.location, user_email, auditor_sa)


if __name__ == "__main__":
    main()
