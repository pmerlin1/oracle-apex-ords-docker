#!/usr/bin/env bash
# ============================================================================
# Apply PFILE parameters to SPFILE
# ============================================================================
set -euo pipefail

PFILE="${1:-/opt/oracle/config/init.ora}"

if [[ ! -f "${PFILE}" ]]; then
  echo "[pfile] No PFILE found at ${PFILE}, skipping."
  exit 0
fi

echo "[pfile] Applying parameters from ${PFILE}..."

while IFS='=' read -r param value || [[ -n "$param" ]]; do
  # Skip comments and empty lines
  [[ -z "$param" || "$param" =~ ^[[:space:]]*# ]] && continue

  # Clean whitespace
  param=$(echo "$param" | xargs)
  value=$(echo "$value" | xargs)
  [[ -z "$param" ]] && continue

  echo "[pfile]   ${param}=${value}"
  sqlplus -s / as sysdba <<SQL >/dev/null
WHENEVER SQLERROR CONTINUE
ALTER SYSTEM SET ${param}=${value} SCOPE=SPFILE;
EXIT;
SQL
done < "${PFILE}"

echo "[pfile] Parameters applied. Some require restart to take effect."
