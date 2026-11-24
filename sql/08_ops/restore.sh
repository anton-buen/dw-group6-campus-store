#!/usr/bin/env bash
set -euo pipefail

DUMP_FILE="${1:-sql/08_ops/campus_store.dump}"
DB_NAME="${2:-campus_store}"

echo "Restoring '${DB_NAME}' from ${DUMP_FILE}..."
psql -d postgres -c "DROP DATABASE IF EXISTS ${DB_NAME} WITH (FORCE);"
psql -d postgres -c "CREATE DATABASE ${DB_NAME};"
time pg_restore -d "${DB_NAME}" "${DUMP_FILE}"

echo "Running post-restore maintenance and verification..."
psql -d "${DB_NAME}" \
  -c "ANALYZE;" \
  -c "REFRESH MATERIALIZED VIEW mart.mv_net_sales_branch_term;" \
  -c "SELECT COUNT(*) AS fact_rows, SUM(net_sales) AS total_net_sales FROM mart.v_net_sales;" \
  -c "SELECT schemaname, tablename, policyname FROM pg_policies WHERE schemaname = 'mart' AND tablename = 'fct_sales';"