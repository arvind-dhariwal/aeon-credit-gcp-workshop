#!/usr/bin/env bash
# =============================================================================
# ACSM Workshop Prerequisite Script: Create VPC Network & Singapore Subnetwork
# for BigQuery Studio Notebooks (Colab Enterprise Runtime in asia-southeast1)
#
# Usage (in Google Cloud Shell):
#   bash track1_platform_governance/scripts/setup_colab_vpc_network.sh [PROJECT_ID]
# =============================================================================
set -euo pipefail

PROJECT_ID="${1:-${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}}"
LOCATION="${LOCATION:-asia-southeast1}"
NETWORK_NAME="${NETWORK_NAME:-acsm-colab-network}"
SUBNET_NAME="${SUBNET_NAME:-acsm-colab-subnet-sg}"
ROUTER_NAME="${ROUTER_NAME:-acsm-colab-router-sg}"
NAT_NAME="${NAT_NAME:-acsm-colab-nat-sg}"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo "❌ Error: PROJECT_ID is not set. Pass it as an argument or run 'gcloud config set project <PROJECT_ID>'."
  exit 1
fi

echo "=========================================================================="
echo "🌐 Provisioning BigQuery Studio / Colab Enterprise VPC in ${LOCATION}"
echo "   • Project ID  : ${PROJECT_ID}"
echo "   • VPC Network : ${NETWORK_NAME}"
echo "   • Subnetwork  : ${SUBNET_NAME} (${LOCATION}, Private Google Access ON)"
echo "=========================================================================="

gcloud config set project "${PROJECT_ID}" >/dev/null

# 1. Enable required APIs for BigQuery Studio Notebooks (Colab Enterprise)
echo "1️⃣  Enabling required Google Cloud APIs..."
gcloud services enable \
  bigquery.googleapis.com \
  aiplatform.googleapis.com \
  compute.googleapis.com \
  dataform.googleapis.com \
  --project="${PROJECT_ID}"

# 2. Create Custom VPC Network (idempotent)
echo "2️⃣  Creating Custom VPC Network '${NETWORK_NAME}'..."
gcloud compute networks describe "${NETWORK_NAME}" --project="${PROJECT_ID}" >/dev/null 2>&1 || \
gcloud compute networks create "${NETWORK_NAME}" \
  --project="${PROJECT_ID}" \
  --subnet-mode=custom

# 3. Create Regional Subnetwork in Singapore (asia-southeast1) with Private Google Access
echo "3️⃣  Creating Regional Subnetwork '${SUBNET_NAME}' (${LOCATION})..."
gcloud compute networks subnets describe "${SUBNET_NAME}" --project="${PROJECT_ID}" --region="${LOCATION}" >/dev/null 2>&1 || \
gcloud compute networks subnets create "${SUBNET_NAME}" \
  --project="${PROJECT_ID}" \
  --network="${NETWORK_NAME}" \
  --region="${LOCATION}" \
  --range="10.10.0.0/24" \
  --enable-private-ip-google-access

# 4. Create Cloud Router & Cloud NAT in Singapore (allows git clone from GitHub without public IPs)
echo "4️⃣  Creating Cloud Router '${ROUTER_NAME}' & Cloud NAT '${NAT_NAME}' (${LOCATION})..."
gcloud compute routers describe "${ROUTER_NAME}" --project="${PROJECT_ID}" --region="${LOCATION}" >/dev/null 2>&1 || \
gcloud compute routers create "${ROUTER_NAME}" \
  --project="${PROJECT_ID}" \
  --network="${NETWORK_NAME}" \
  --region="${LOCATION}"

gcloud compute routers nats describe "${NAT_NAME}" --router="${ROUTER_NAME}" --project="${PROJECT_ID}" --region="${LOCATION}" >/dev/null 2>&1 || \
gcloud compute routers nats create "${NAT_NAME}" \
  --project="${PROJECT_ID}" \
  --router="${ROUTER_NAME}" \
  --region="${LOCATION}" \
  --auto-allocate-nat-external-ips \
  --nat-all-subnet-ip-ranges

echo "=========================================================================="
echo "✅ VPC '${NETWORK_NAME}' and Subnetwork '${SUBNET_NAME}' (${LOCATION}) Ready!"
echo "👉 In BigQuery Studio, click 'Connect' -> select '${NETWORK_NAME}' / '${SUBNET_NAME}'."
echo "=========================================================================="
