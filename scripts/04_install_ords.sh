#!/usr/bin/env bash
# ============================================================================
# Install and configure Oracle REST Data Services (ORDS)
# ============================================================================
set -euo pipefail

ORACLE_PDB="${ORACLE_PDB:-FREEPDB1}"
ORACLE_PWD="${ORACLE_PWD:-}"
ORDS_PORT="${ORDS_PORT:-8080}"

# JDBC connection pool tuning (override via docker run -e)
JDBC_INITIAL="${JDBC_INITIAL:-10}"
JDBC_MIN="${JDBC_MIN:-10}"
JDBC_MAX="${JDBC_MAX:-50}"

if [[ -z "${ORACLE_PWD}" ]]; then
  echo "[ords] ERROR: ORACLE_PWD not set"
  exit 1
fi

if ! command -v ords >/dev/null 2>&1; then
  echo "[ords] ERROR: ords command not found"
  exit 1
fi

# Find APEX images directory
APEX_IMAGES=$(find /opt/apex -maxdepth 2 -type d -name "images" -print -quit 2>/dev/null)
[[ -z "${APEX_IMAGES}" ]] && APEX_IMAGES="/opt/apex/apex/images"

echo "[ords] Installing ORDS for ${ORACLE_PDB}..."

# ORDS silent install
ords --config /etc/ords/config install \
  --admin-user SYS \
  --db-hostname localhost \
  --db-port 1521 \
  --db-servicename "${ORACLE_PDB}" \
  --feature-sdw true \
  --log-folder /var/log/ords \
  --password-stdin <<< "${ORACLE_PWD}"

echo "[ords] Configuring ORDS standalone settings..."

ords --config /etc/ords/config config set standalone.context.path /ords
ords --config /etc/ords/config config set standalone.doc.root "${APEX_IMAGES}"
ords --config /etc/ords/config config set standalone.static.context.path /i
ords --config /etc/ords/config config set standalone.static.path "${APEX_IMAGES}"

# JDBC pool tuning
echo "[ords] JDBC pool: initial=${JDBC_INITIAL}, min=${JDBC_MIN}, max=${JDBC_MAX}"
ords --config /etc/ords/config config set jdbc.InitialLimit "${JDBC_INITIAL}"
ords --config /etc/ords/config config set jdbc.MinLimit "${JDBC_MIN}"
ords --config /etc/ords/config config set jdbc.MaxLimit "${JDBC_MAX}"

echo "[ords] ORDS installation complete."
