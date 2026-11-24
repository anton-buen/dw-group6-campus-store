#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${1:-campus_store}"
OUT_DIR="sql/08_ops"
STAMP="$(date +%Y%m%d_%H%M%S)"
DUMP_FILE="${OUT_DIR}/${DB_NAME}_${STAMP}.dump"

echo "Backing up database '${DB_NAME}' to ${DUMP_FILE}..."
time pg_dump -Fc -d "${DB_NAME}" -f "${DUMP_FILE}"
pg_dumpall --roles-only -f "${OUT_DIR}/roles_${STAMP}.sql"
ls -lh "${DUMP_FILE}" "${OUT_DIR}/roles_${STAMP}.sql"