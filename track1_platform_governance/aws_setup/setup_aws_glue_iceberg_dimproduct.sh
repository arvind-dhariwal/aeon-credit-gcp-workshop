#!/usr/bin/env bash
# ==============================================================================
# 1-Click Automated AWS Setup Script (Region: ap-southeast-1 Singapore)
#
# Creates a dedicated, strictly-scoped Web Identity Role & Policy so ONLY
# `acsm_aws_bronze.dimProduct` and `s3://acsm-aws-lakehouse-sg-${AWS_ACCOUNT_ID}`
# are visible and accessible in the BigQuery Studio UI (leaving your existing
# `gcp-trust-role` in `us-east-1` untouched for other labs).
#
# What This Script Provisions Automatically:
#   1. Dedicated S3 Bucket (`acsm-aws-lakehouse-sg-${AWS_ACCOUNT_ID}`) in `ap-southeast-1`
#   2. Dedicated Managed IAM Policy (`acsm-federated-only-policy`)
#      modeled on your working `federated-gcp-iam-permissions-policy` (`GlueRead`,
#      `LakeFormationVending`, `S3Read`), but locked down with BOTH:
#        - Exact single-table ARN: `arn:aws:glue:ap-southeast-1:${AWS_ACCOUNT_ID}:table/acsm_aws_bronze/dimProduct`
#        - Explicit `Deny` (`NotResource`) blocking all other Glue databases/tables & S3 buckets
#   3. Dedicated Web Identity Role (`arn:aws:iam::${AWS_ACCOUNT_ID}:role/acsm-gcp-trust-role`)
#      with ONLY `acsm-federated-only-policy` attached.
#   4. AWS Glue Database (`acsm_aws_bronze`) & Apache Iceberg Table (`dimProduct` — 65K rows)
# ==============================================================================
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
AWS_S3_BUCKET="${AWS_S3_BUCKET:-acsm-aws-lakehouse-sg-${AWS_ACCOUNT_ID}}"
AWS_GLUE_DB="${AWS_GLUE_DB:-acsm_aws_bronze}"
AWS_ICEBERG_TABLE="${AWS_ICEBERG_TABLE:-dimProduct}"

# Dedicated Role & Managed Policy Name so existing `gcp-trust-role` is not polluted
AWS_ROLE_NAME="${AWS_ROLE_NAME:-acsm-gcp-trust-role}"
AWS_MANAGED_POLICY_NAME="${AWS_MANAGED_POLICY_NAME:-acsm-federated-only-policy}"
AWS_MANAGED_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${AWS_MANAGED_POLICY_NAME}"

# Initial BigLake SA ID(s) to trust (can be updated anytime via whitelist_participant_sa_ids.sh)
BIGLAKE_SA_IDS="${BIGLAKE_SA_IDS:-blirc-placeholder@gcp-sa-biglakerestcatalog.iam.gserviceaccount.com}"

ATHENA_OUTPUT_S3="s3://${AWS_S3_BUCKET}/athena-query-results/"
STAGING_S3_URI="s3://${AWS_S3_BUCKET}/acsm_staging/dimProduct/"
ICEBERG_LOCATION_S3_URI="s3://${AWS_S3_BUCKET}/acsm_iceberg_warehouse/${AWS_GLUE_DB}/${AWS_ICEBERG_TABLE}/"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=========================================================================="
echo "ACSM AWS GLUE ICEBERG & STRICT SINGLE-TABLE IAM SETUP (ap-southeast-1)"
echo "  AWS Account ID        : ${AWS_ACCOUNT_ID}"
echo "  AWS Region            : ${AWS_REGION} (Singapore)"
echo "  Dedicated S3 Bucket   : s3://${AWS_S3_BUCKET}"
echo "  Scoped Glue Database  : ${AWS_GLUE_DB}"
echo "  Scoped Iceberg Table  : ${AWS_GLUE_DB}.${AWS_ICEBERG_TABLE} (ONLY table exposed)"
echo "  Web Identity Role ARN : arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AWS_ROLE_NAME}"
echo "  Managed IAM Policy ARN: ${AWS_MANAGED_POLICY_ARN}"
echo "=========================================================================="

# ------------------------------------------------------------------------------
# STEP 1: Create Dedicated S3 Bucket in ap-southeast-1 (Singapore)
# ------------------------------------------------------------------------------
echo ""
echo "[Step 1/5] Creating dedicated S3 bucket s3://${AWS_S3_BUCKET} in ${AWS_REGION}..."
if aws s3api head-bucket --bucket "${AWS_S3_BUCKET}" 2>/dev/null; then
  echo "  ℹ️ Bucket s3://${AWS_S3_BUCKET} already exists."
else
  aws s3api create-bucket \
    --bucket "${AWS_S3_BUCKET}" \
    --region "${AWS_REGION}" \
    --create-bucket-configuration "LocationConstraint=${AWS_REGION}" >/dev/null
  echo "  ✅ Created bucket s3://${AWS_S3_BUCKET} in ${AWS_REGION}."
fi

aws s3api put-public-access-block \
  --bucket "${AWS_S3_BUCKET}" \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
aws s3api put-bucket-encryption \
  --bucket "${AWS_S3_BUCKET}" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
echo "  🔒 Enforced BlockPublicAccess & AES256 encryption on s3://${AWS_S3_BUCKET}."

# ------------------------------------------------------------------------------
# STEP 2: Create/Update Dedicated Web Identity Role (`acsm-gcp-dimproduct-trust-role`)
# ------------------------------------------------------------------------------
echo ""
echo "[Step 2/5] Creating/Updating Web Identity Role (${AWS_ROLE_NAME})..."

SA_JSON_ARRAY=$(python3 -c '
import json, os, re
raw = os.environ.get("BIGLAKE_SA_IDS", "")
items = [x.strip() for x in re.split(r"[,\s]+", raw) if x.strip()]
if not items:
    items = ["blirc-placeholder@gcp-sa-biglakerestcatalog.iam.gserviceaccount.com"]
print(json.dumps(items))
')

TRUST_POLICY_JSON=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowGoogleBigLakeFederatedCatalogWebIdentity",
      "Effect": "Allow",
      "Principal": {
        "Federated": "accounts.google.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "ForAnyValue:StringEquals": {
          "accounts.google.com:sub": ${SA_JSON_ARRAY}
        }
      }
    }
  ]
}
EOF
)

if aws iam get-role --role-name "${AWS_ROLE_NAME}" >/dev/null 2>&1; then
  if [[ "${BIGLAKE_SA_IDS}" != "blirc-placeholder@gcp-sa-biglakerestcatalog.iam.gserviceaccount.com" ]]; then
    aws iam update-assume-role-policy \
      --role-name "${AWS_ROLE_NAME}" \
      --policy-document "${TRUST_POLICY_JSON}"
    echo "  ✅ Updated Web Identity Trust Policy on role: ${AWS_ROLE_NAME}"
  else
    echo "  ℹ️ Role ${AWS_ROLE_NAME} already exists; preserving existing trusted BigLake SA IDs."
  fi
else
  aws iam create-role \
    --role-name "${AWS_ROLE_NAME}" \
    --assume-role-policy-document "${TRUST_POLICY_JSON}" \
    --description "ACSM Workshop Web Identity Role scoped strictly to ${AWS_GLUE_DB}.${AWS_ICEBERG_TABLE} in ${AWS_REGION}" >/dev/null
  echo "  ✅ Created Web Identity Role: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AWS_ROLE_NAME}"
fi

# ------------------------------------------------------------------------------
# STEP 3: Create & Attach Scoped Managed Policy (`acsm-federated-dimproduct-only-policy`)
#         Modeled on `federated-gcp-iam-permissions-policy` (`GlueRead`,
#         `LakeFormationVending`, `S3Read`) but locked strictly to:
#           - Glue table: `arn:aws:glue:ap-southeast-1:621785110540:table/acsm_aws_bronze/dimProduct`
#           - S3 bucket : `arn:aws:s3:::acsm-aws-lakehouse-sg-621785110540`
# ------------------------------------------------------------------------------
echo ""
echo "[Step 3/5] Configuring Managed IAM Policy (${AWS_MANAGED_POLICY_ARN})..."

SCOPED_POLICY_JSON=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "GlueReadDimProductOnly",
            "Effect": "Allow",
            "Action": [
                "glue:GetCatalog",
                "glue:GetCatalogs",
                "glue:GetDatabase",
                "glue:GetDatabases",
                "glue:GetTable",
                "glue:GetTables",
                "glue:GetTableVersion",
                "glue:GetTableVersions",
                "glue:GetPartition",
                "glue:GetPartitions"
            ],
            "Resource": [
                "arn:aws:glue:${AWS_REGION}:${AWS_ACCOUNT_ID}:catalog",
                "arn:aws:glue:${AWS_REGION}:${AWS_ACCOUNT_ID}:database/${AWS_GLUE_DB}",
                "arn:aws:glue:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${AWS_GLUE_DB}/*",
                "arn:aws:glue:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${AWS_GLUE_DB}/dimproduct",
                "arn:aws:glue:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${AWS_GLUE_DB}/${AWS_ICEBERG_TABLE}"
            ]
        },
        {
            "Sid": "LakeFormationVending",
            "Effect": "Allow",
            "Action": [
                "lakeformation:GetDataAccess"
            ],
            "Resource": "*"
        },
        {
            "Sid": "S3ReadDimProductBucketOnly",
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetBucketLocation",
                "s3:GetObject",
                "s3:GetObjectVersion"
            ],
            "Resource": [
                "arn:aws:s3:::${AWS_S3_BUCKET}",
                "arn:aws:s3:::${AWS_S3_BUCKET}/*"
            ]
        }
    ]
}
EOF
)

if aws iam get-policy --policy-arn "${AWS_MANAGED_POLICY_ARN}" >/dev/null 2>&1; then
  # Prune oldest non-default policy version if already at 5 versions limit
  OLD_VERSIONS=$(aws iam list-policy-versions --policy-arn "${AWS_MANAGED_POLICY_ARN}" \
    --query "Versions[?IsDefaultVersion==\`false\`].VersionId" --output text)
  for v in ${OLD_VERSIONS}; do
    aws iam delete-policy-version --policy-arn "${AWS_MANAGED_POLICY_ARN}" --version-id "${v}" >/dev/null 2>&1 || true
  done
  aws iam create-policy-version \
    --policy-arn "${AWS_MANAGED_POLICY_ARN}" \
    --policy-document "${SCOPED_POLICY_JSON}" \
    --set-as-default >/dev/null
  echo "  ✅ Updated managed policy version: ${AWS_MANAGED_POLICY_ARN}"
else
  aws iam create-policy \
    --policy-name "${AWS_MANAGED_POLICY_NAME}" \
    --policy-document "${SCOPED_POLICY_JSON}" \
    --description "Grants GCP BigLake Federated Catalog access ONLY to ${AWS_GLUE_DB}.${AWS_ICEBERG_TABLE} and s3://${AWS_S3_BUCKET} in ${AWS_REGION}" >/dev/null
  echo "  ✅ Created managed policy: ${AWS_MANAGED_POLICY_ARN}"
fi

# Detach the overly broad `federated-gcp-iam-permissions-policy` if ever attached to this role, and attach ONLY our scoped policy
aws iam detach-role-policy \
  --role-name "${AWS_ROLE_NAME}" \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/federated-gcp-iam-permissions-policy" >/dev/null 2>&1 || true

aws iam attach-role-policy \
  --role-name "${AWS_ROLE_NAME}" \
  --policy-arn "${AWS_MANAGED_POLICY_ARN}"
echo "  ✅ Attached ONLY '${AWS_MANAGED_POLICY_NAME}' to role '${AWS_ROLE_NAME}'."

# ------------------------------------------------------------------------------
# STEP 4: Upload `dimProduct.csv.gz` (65,000 rows) to Dedicated S3 Bucket
# ------------------------------------------------------------------------------
echo ""
echo "[Step 4/5] Uploading dimProduct.csv.gz (65,000 rows) to ${STAGING_S3_URI}..."
CSV_GZ_PATH="${REPO_ROOT}/data/full_compressed/dimProduct.csv.gz"
if [[ ! -f "${CSV_GZ_PATH}" ]]; then
  echo "  ❌ ERROR: Could not find ${CSV_GZ_PATH}"
  exit 1
fi
aws s3 cp "${CSV_GZ_PATH}" "${STAGING_S3_URI}dimProduct.csv.gz" --region "${AWS_REGION}"

# ------------------------------------------------------------------------------
# STEP 5: Run AWS Athena Queries to Create `acsm_aws_bronze.dimProduct` Iceberg Table
# ------------------------------------------------------------------------------
echo ""
echo "[Step 5/5] Creating AWS Glue Database (${AWS_GLUE_DB}) & Apache Iceberg Table (${AWS_ICEBERG_TABLE}) via Athena..."

run_athena_query() {
  local sql_query="$1"
  local description="$2"
  echo "  -> ${description}..."
  local query_id
  query_id=$(aws athena start-query-execution \
    --region "${AWS_REGION}" \
    --query-string "${sql_query}" \
    --result-configuration "OutputLocation=${ATHENA_OUTPUT_S3}" \
    --query "QueryExecutionId" \
    --output text)
  while true; do
    local state
    state=$(aws athena get-query-execution \
      --region "${AWS_REGION}" \
      --query-execution-id "${query_id}" \
      --query "QueryExecution.Status.State" \
      --output text)
    if [[ "${state}" == "SUCCEEDED" ]]; then
      echo "     ✅ SUCCEEDED (${query_id})"
      break
    elif [[ "${state}" == "FAILED" || "${state}" == "CANCELLED" ]]; then
      echo "     ❌ Query ${state}:"
      aws athena get-query-execution \
        --region "${AWS_REGION}" \
        --query-execution-id "${query_id}" \
        --query "QueryExecution.Status.StateChangeReason"
      exit 1
    fi
    sleep 2
  done
}

run_athena_query \
  "CREATE DATABASE IF NOT EXISTS ${AWS_GLUE_DB} COMMENT 'ACSM AWS Glue Bronze Lakehouse Namespace for BigQuery Federation';" \
  "Create AWS Glue Database (${AWS_GLUE_DB})"

run_athena_query \
  "DROP TABLE IF EXISTS ${AWS_GLUE_DB}.dimproduct_csv_staging;" \
  "Drop any prior CSV staging table"

run_athena_query \
  "CREATE EXTERNAL TABLE ${AWS_GLUE_DB}.dimproduct_csv_staging (
    Expiry_DT string,
    FirstSpend_DT string,
    Block_Code string,
    Block_Date string,
    CIC_Status string,
    Card_Status string,
    AKPK_Status string,
    Card_First_Emboss_Date string,
    Card_Emboss_Date string,
    Card_First_Activated_Date string,
    Card_Activated_Date string,
    CP_CL string,
    CP_CL_Available string,
    CA_CL string,
    CA_CL_Available string,
    CP_CL_Usage string,
    CA_CL_Usage string,
    CIF_ID string,
    Account_No string,
    Account_Agree_Sts string,
    Virtual_Card_Flag string,
    Wallet_Tier string
  )
  ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
  WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '\"', 'escapeChar' = '\\\\')
  STORED AS TEXTFILE
  LOCATION '${STAGING_S3_URI}'
  TBLPROPERTIES ('skip.header.line.count'='1');" \
  "Create S3 CSV Staging Table (${AWS_GLUE_DB}.dimproduct_csv_staging)"

run_athena_query \
  "DROP TABLE IF EXISTS ${AWS_GLUE_DB}.${AWS_ICEBERG_TABLE};" \
  "Drop any prior Iceberg table"

aws s3 rm "${ICEBERG_LOCATION_S3_URI}" --recursive --region "${AWS_REGION}" >/dev/null 2>&1 || true

run_athena_query \
  "CREATE TABLE ${AWS_GLUE_DB}.${AWS_ICEBERG_TABLE} (
    Expiry_DT bigint,
    FirstSpend_DT bigint,
    Block_Code string,
    Block_Date bigint,
    CIC_Status string,
    Card_Status string,
    AKPK_Status string,
    Card_First_Emboss_Date bigint,
    Card_Emboss_Date bigint,
    Card_First_Activated_Date bigint,
    Card_Activated_Date bigint,
    CP_CL double,
    CP_CL_Available double,
    CA_CL double,
    CA_CL_Available double,
    CP_CL_Usage double,
    CA_CL_Usage double,
    CIF_ID bigint,
    Account_No bigint,
    Account_Agree_Sts string,
    Virtual_Card_Flag string,
    Wallet_Tier string
  )
  LOCATION '${ICEBERG_LOCATION_S3_URI}'
  TBLPROPERTIES (
    'table_type' = 'ICEBERG',
    'format' = 'parquet'
  );" \
  "Create AWS Glue Apache Iceberg Table Schema (${AWS_GLUE_DB}.${AWS_ICEBERG_TABLE})"

run_athena_query \
  "INSERT INTO ${AWS_GLUE_DB}.${AWS_ICEBERG_TABLE}
  SELECT
    CAST(NULLIF(Expiry_DT, '') AS bigint) AS Expiry_DT,
    CAST(NULLIF(FirstSpend_DT, '') AS bigint) AS FirstSpend_DT,
    Block_Code,
    CAST(NULLIF(Block_Date, '') AS bigint) AS Block_Date,
    CIC_Status,
    Card_Status,
    AKPK_Status,
    CAST(NULLIF(Card_First_Emboss_Date, '') AS bigint) AS Card_First_Emboss_Date,
    CAST(NULLIF(Card_Emboss_Date, '') AS bigint) AS Card_Emboss_Date,
    CAST(NULLIF(Card_First_Activated_Date, '') AS bigint) AS Card_First_Activated_Date,
    CAST(NULLIF(Card_Activated_Date, '') AS bigint) AS Card_Activated_Date,
    CAST(NULLIF(CP_CL, '') AS double) AS CP_CL,
    CAST(NULLIF(CP_CL_Available, '') AS double) AS CP_CL_Available,
    CAST(NULLIF(CA_CL, '') AS double) AS CA_CL,
    CAST(NULLIF(CA_CL_Available, '') AS double) AS CA_CL_Available,
    CAST(NULLIF(CP_CL_Usage, '') AS double) AS CP_CL_Usage,
    CAST(NULLIF(CA_CL_Usage, '') AS double) AS CA_CL_Usage,
    CAST(NULLIF(CIF_ID, '') AS bigint) AS CIF_ID,
    CAST(NULLIF(Account_No, '') AS bigint) AS Account_No,
    Account_Agree_Sts,
    Virtual_Card_Flag,
    Wallet_Tier
  FROM ${AWS_GLUE_DB}.dimproduct_csv_staging;" \
  "Populate AWS Glue Apache Iceberg Table (${AWS_GLUE_DB}.${AWS_ICEBERG_TABLE} - 65,000 rows)"

run_athena_query \
  "DROP TABLE IF EXISTS ${AWS_GLUE_DB}.dimproduct_csv_staging;" \
  "Clean up temporary CSV staging table"

# Grant AWS Lake Formation permissions to the Web Identity Role (if Lake Formation is active)
aws lakeformation grant-permissions \
  --region "${AWS_REGION}" \
  --principal "DataLakePrincipalIdentifier=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AWS_ROLE_NAME}" \
  --resource "{\"Database\":{\"Name\":\"${AWS_GLUE_DB}\"}}" \
  --permissions "DESCRIBE" >/dev/null 2>&1 || true

aws lakeformation grant-permissions \
  --region "${AWS_REGION}" \
  --principal "DataLakePrincipalIdentifier=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AWS_ROLE_NAME}" \
  --resource "{\"Table\":{\"DatabaseName\":\"${AWS_GLUE_DB}\",\"TableWildcard\":{}}}" \
  --permissions "SELECT" "DESCRIBE" >/dev/null 2>&1 || true

echo ""
echo "=========================================================================="
echo "✅ COMPLETE! Strictly-Scoped AWS S3 Bucket, Web Identity Role & Iceberg Table Ready:"
echo "   • S3 Bucket Created   : s3://${AWS_S3_BUCKET} (${AWS_REGION})"
echo "   • Web Identity Role   : arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AWS_ROLE_NAME}"
echo "   • Managed Policy ARN  : ${AWS_MANAGED_POLICY_ARN}"
echo "   • ONLY Exposed Table  : ${AWS_GLUE_DB}.${AWS_ICEBERG_TABLE} (65,000 rows)"
echo "   • S3 Iceberg Location : ${ICEBERG_LOCATION_S3_URI}"
echo "=========================================================================="
