#!/usr/bin/env bash
# =============================================================================
# Track 1 (Option B — Standard `bq` CLI, Zero Python):
# 1. Runs `00_create_8_tables_ddl_with_descriptions.sql` via `bq query` so all
#    8 tables (`T1_Fact_EP_Judge` .. `T8_dimProduct`) are created first with
#    100% of their Table Descriptions and all 226 Column Descriptions.
# 2. Loads local `.csv.gz` files into those existing tables via `bq load`
#    (using `--replace`, which preserves existing column descriptions in BQ).
# =============================================================================
set -euo pipefail

PROJECT_ID="${1:-trustedtesterarvind}"
DATASET_ID="${2:-acsm_bronze}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/../data/full_compressed"

echo "[Step 1/2] Creating 8 tables with all Table & Column Descriptions via DDL SQL..."
sed "s/trustedtesterarvind/${PROJECT_ID}/g" \
  "${SCRIPT_DIR}/00_create_8_tables_ddl_with_descriptions.sql" \
  | bq query --project_id="${PROJECT_ID}" --use_legacy_sql=false

echo "[Step 2/2] Loading compressed CSV.GZ data into the 8 pre-described tables via bq load..."
bq load --project_id="${PROJECT_ID}" --replace --source_format=CSV --skip_leading_rows=1 --allow_quoted_newlines \
  "${PROJECT_ID}:${DATASET_ID}.T1_Fact_EP_Judge" "${DATA_DIR}/T1_Fact_EP_Judge.csv.gz"

bq load --project_id="${PROJECT_ID}" --replace --source_format=CSV --skip_leading_rows=1 --allow_quoted_newlines \
  "${PROJECT_ID}:${DATASET_ID}.T2_Fact_EP_Sales" "${DATA_DIR}/T2_Fact_EP_Sales.csv.gz"

bq load --project_id="${PROJECT_ID}" --replace --source_format=CSV --skip_leading_rows=1 --allow_quoted_newlines \
  "${PROJECT_ID}:${DATASET_ID}.T3_Fact_EP_Collection" "${DATA_DIR}/T3_Fact_EP_Collection.csv.gz"

bq load --project_id="${PROJECT_ID}" --replace --source_format=CSV --skip_leading_rows=1 --allow_quoted_newlines \
  "${PROJECT_ID}:${DATASET_ID}.T4_Fact_CC_Judge" "${DATA_DIR}/T4_Fact_CC_Judge_v2.csv.gz"

bq load --project_id="${PROJECT_ID}" --replace --source_format=CSV --skip_leading_rows=1 --allow_quoted_newlines \
  "${PROJECT_ID}:${DATASET_ID}.T5_Fact_CC_Sales" "${DATA_DIR}/T5_Fact_CC_Sales.csv.gz"

bq load --project_id="${PROJECT_ID}" --replace --source_format=CSV --skip_leading_rows=1 --allow_quoted_newlines \
  "${PROJECT_ID}:${DATASET_ID}.T6_Fact_CC_Collection" "${DATA_DIR}/T6_Fact_CC_Collection.csv.gz"

bq load --project_id="${PROJECT_ID}" --replace --source_format=CSV --skip_leading_rows=1 --allow_quoted_newlines \
  "${PROJECT_ID}:${DATASET_ID}.T7_m3CIF" "${DATA_DIR}/T7_m3CIF.csv.gz"

bq load --project_id="${PROJECT_ID}" --replace --source_format=CSV --skip_leading_rows=1 --allow_quoted_newlines \
  "${PROJECT_ID}:${DATASET_ID}.T8_dimProduct" "${DATA_DIR}/T8_dimProduct.csv.gz"

echo "Done! All 8 tables and 226 column descriptions are live in ${PROJECT_ID}.${DATASET_ID}."
