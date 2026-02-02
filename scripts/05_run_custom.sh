#!/usr/bin/env bash
# ============================================================================
# Run custom SQL scripts from /opt/oracle/scripts/custom/
# ============================================================================
set -euo pipefail

ORACLE_PDB="${ORACLE_PDB:-FREEPDB1}"
CUSTOM_DIR="/opt/oracle/scripts/custom"

if ! compgen -G "${CUSTOM_DIR}/*.sql" > /dev/null 2>&1; then
  echo "[custom] No custom SQL scripts found in ${CUSTOM_DIR}"
  exit 0
fi

echo "[custom] Running custom SQL scripts..."

for f in "${CUSTOM_DIR}"/*.sql; do
  echo "[custom]   Executing $(basename "$f")..."
  sqlplus -s / as sysdba <<SQL
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER=${ORACLE_PDB};
@${f}
EXIT;
SQL
done

echo "[custom] Custom scripts complete."
