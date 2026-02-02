#!/usr/bin/env bash
# ============================================================================
# Container Startup Entrypoint
# ============================================================================
# Runs on every container start. Handles:
#   - First-run setup (PFILE, directories, APEX, ORDS)
#   - Starting ORDS (every startup)
# ============================================================================
set -euo pipefail

# Resolve symlink to get actual script directory
SCRIPT_DIR="/opt/oracle/scripts"

# Configuration from environment
ORACLE_PDB="${ORACLE_PDB:-FREEPDB1}"
ORACLE_PWD="${ORACLE_PWD:-}"
SKIP_APEX="${SKIP_APEX:-false}"
SKIP_ORDS="${SKIP_ORDS:-false}"
ORDS_PORT="${ORDS_PORT:-8080}"

FIRST_RUN_MARKER="/opt/oracle/oradata/.setup_complete"

# SKIP_ORDS implies SKIP_APEX (APEX needs ORDS)
[[ "${SKIP_ORDS}" == "true" ]] && SKIP_APEX="true"

# ============================================================================
# FIRST RUN SETUP
# ============================================================================
if [[ ! -f "${FIRST_RUN_MARKER}" ]]; then
  echo "========================================"
  echo "[startup] First run - running setup..."
  echo "========================================"

  if [[ -z "${ORACLE_PWD}" ]]; then
    echo "ERROR: ORACLE_PWD environment variable must be set"
    exit 1
  fi

  # Step 1: Apply PFILE parameters
  "${SCRIPT_DIR}/01_apply_pfile.sh"

  # Step 2: Create directory objects
  "${SCRIPT_DIR}/02_setup_directories.sh"

  # Step 3: Install APEX (unless skipped)
  if [[ "${SKIP_APEX}" != "true" ]]; then
    "${SCRIPT_DIR}/03_install_apex.sh"
  else
    echo "[startup] SKIP_APEX=true, skipping APEX installation"
  fi

  # Step 4: Install ORDS (unless skipped)
  if [[ "${SKIP_ORDS}" != "true" ]]; then
    "${SCRIPT_DIR}/04_install_ords.sh"
  else
    echo "[startup] SKIP_ORDS=true, skipping ORDS installation"
  fi

  # Step 5: Run custom SQL scripts
  "${SCRIPT_DIR}/05_run_custom.sh"

  # Mark setup complete
  touch "${FIRST_RUN_MARKER}"
  echo "========================================"
  echo "[startup] First run setup complete!"
  echo "========================================"
fi

# ============================================================================
# START ORDS (every startup)
# ============================================================================
if [[ "${SKIP_ORDS}" == "true" ]]; then
  echo "[startup] SKIP_ORDS=true, ORDS not started."
  exit 0
fi

if ! command -v ords >/dev/null 2>&1; then
  echo "[startup] ORDS not installed, skipping."
  exit 0
fi

if [[ ! -d /etc/ords/config/databases ]]; then
  echo "[startup] ORDS not configured, skipping."
  exit 0
fi

if pgrep -f "ords.*serve" >/dev/null 2>&1; then
  echo "[startup] ORDS already running."
  exit 0
fi

APEX_IMAGES=$(find /opt/apex -maxdepth 2 -type d -name "images" -print -quit 2>/dev/null)
[[ -z "${APEX_IMAGES}" ]] && APEX_IMAGES="/opt/apex/apex/images"

echo "[startup] Starting ORDS on port ${ORDS_PORT}..."
nohup ords --config /etc/ords/config serve \
  --port "${ORDS_PORT}" \
  --apex-images "${APEX_IMAGES}" \
  > /var/log/ords/ords-standalone.log 2>&1 &

sleep 3
if pgrep -f "ords.*serve" >/dev/null 2>&1; then
  echo "[startup] ============================================"
  echo "[startup] ORDS started successfully"
  echo "[startup] ============================================"
  echo "[startup] APEX:          http://localhost:${ORDS_PORT}/ords/apex"
  echo "[startup] APEX Admin:    http://localhost:${ORDS_PORT}/ords/apex_admin"
  echo "[startup] SQL Developer: http://localhost:${ORDS_PORT}/ords/<schema>/_sdw/"
  echo "[startup] ============================================"
else
  echo "[startup] WARNING: ORDS may have failed to start"
  echo "[startup] Check: /var/log/ords/ords-standalone.log"
fi
