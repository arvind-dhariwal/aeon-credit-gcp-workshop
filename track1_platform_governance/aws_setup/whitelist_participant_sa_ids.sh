#!/usr/bin/env bash
# ==============================================================================
# 1-Second Workshop Instructor Helper: Whitelist Participant BigLake SA IDs
# in the AWS Web Identity Role (`gcp-trust-role`) Trust Policy
#
# Usage:
#   bash track1_platform_governance/aws_setup/whitelist_participant_sa_ids.sh \
#     blirc-111111111@gcp-sa-biglakerestcatalog.iam.gserviceaccount.com \
#     blirc-222222222@gcp-sa-biglakerestcatalog.iam.gserviceaccount.com
# ==============================================================================
set -euo pipefail

AWS_ROLE_NAME="${AWS_ROLE_NAME:-acsm-gcp-trust-role}"

if [[ $# -eq 0 ]]; then
  echo "Usage: bash $0 <BIGLAKE_SA_ID_1> [<BIGLAKE_SA_ID_2> ...]"
  exit 1
fi

SA_JSON_ARRAY=$(python3 - "$@" <<'EOF'
import json, sys
items = [arg.strip() for arg in sys.argv[1:] if arg.strip()]
print(json.dumps(items))
EOF
)

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

aws iam update-assume-role-policy \
  --role-name "${AWS_ROLE_NAME}" \
  --policy-document "${TRUST_POLICY_JSON}"

echo "✅ Updated Web Identity Trust Policy on role '${AWS_ROLE_NAME}' for participant Service Accounts:"
echo "   ${SA_JSON_ARRAY}"
