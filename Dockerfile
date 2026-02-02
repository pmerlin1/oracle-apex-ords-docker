# syntax=docker/dockerfile:1
# ============================================================================
# Oracle Database + APEX + ORDS - All-in-One Container
# ============================================================================
#
# QUICK START:
#   docker build -t oracle-apex-ords .
#   docker run -d --name orcl \
#     -p 1521:1521 -p 8080:8080 \
#     -e ORACLE_PWD=YourSecurePassword123 \
#     -v orcl-data:/opt/oracle/oradata \
#     oracle-apex-ords
#
# Access APEX at: http://localhost:8080/ords/apex
# Connect via SQL: sqlplus sys/YourSecurePassword123@localhost:1521/FREEPDB1 as sysdba
#
# ============================================================================
# DATA PERSISTENCE - CRITICAL!
# ============================================================================
# The database files live in /opt/oracle/oradata. Without a volume, you LOSE
# ALL DATA when the container is removed.
#
# Option 1: Named volume (recommended)
#   -v orcl-data:/opt/oracle/oradata
#
# Option 2: Bind mount to host directory
#   -v /path/on/host:/opt/oracle/oradata
#
# ORDS config persists in /etc/ords/config (optional to mount separately)
#
# ============================================================================
# ENVIRONMENT VARIABLES
# ============================================================================
# Required:
#   ORACLE_PWD          - SYS/SYSTEM/APEX password (set on first run)
#
# Optional (with defaults for Free edition):
#   ORACLE_SID          - Database SID (default: FREE, use ORCLCDB for EE)
#   ORACLE_PDB          - PDB name (default: FREEPDB1, use ORCLPDB1 for EE)
#   ORACLE_CHARACTERSET - Character set (default: AL32UTF8)
#   ENABLE_ARCHIVELOG   - Set to "true" for archive log mode (EE recommended)
#
# ============================================================================
# BASE IMAGE SELECTION
# ============================================================================
# Free edition (default) - good for dev/test, limited to 2 CPU threads, 2GB RAM:
#   container-registry.oracle.com/database/free:latest        (full - required for APEX)
#   container-registry.oracle.com/database/free:latest-lite   (NO XDB = NO APEX support!)
#
# Enterprise edition - for production, Data Pump, partitioning, etc:
#   container-registry.oracle.com/database/enterprise:latest
#   (Requires Oracle account and license acceptance at container-registry.oracle.com)
#
# When using Enterprise, override build arg and env vars:
#   docker build --build-arg BASE_IMAGE=container-registry.oracle.com/database/enterprise:latest .
#   docker run ... -e ORACLE_SID=ORCLCDB -e ORACLE_PDB=ORCLPDB1 ...
# ============================================================================

# NOTE: Do NOT use "lite" images - they exclude XDB which APEX requires
ARG BASE_IMAGE=container-registry.oracle.com/database/free:latest
FROM ${BASE_IMAGE}

USER root

# ============================================================================
# FIX ORACLE YUM REPOS
# ============================================================================
# Oracle's base images point to regional yum servers that often timeout.
# Clear the region variable to use the global yum.oracle.com instead.
RUN echo "" > /etc/dnf/vars/ociregion && \
    echo "" > /etc/yum/vars/ociregion

# ============================================================================
# INSTALL OS DEPENDENCIES
# ============================================================================
RUN dnf -y install unzip curl java-17-openjdk && \
    dnf clean all

# ============================================================================
# DOWNLOAD AND INSTALL APEX
# ============================================================================
# Oracle provides stable download URLs; version updates automatically.
# APEX files land in /opt/apex/apex/ (note the nested directory from zip)
RUN mkdir -p /opt/apex && \
    curl -Lf -o /tmp/apex-latest.zip \
      https://download.oracle.com/otn_software/apex/apex-latest.zip && \
    unzip -q /tmp/apex-latest.zip -d /opt/apex && \
    rm -f /tmp/apex-latest.zip && \
    chown -R oracle:oinstall /opt/apex

# ============================================================================
# DOWNLOAD AND INSTALL ORDS
# ============================================================================
# ORDS is not in public Oracle Linux repos, so we download directly.
# The ords command will be available at /opt/ords/bin/ords
RUN mkdir -p /opt/ords && \
    curl -Lf -o /tmp/ords-latest.zip \
      https://download.oracle.com/otn_software/java/ords/ords-latest.zip && \
    unzip -q /tmp/ords-latest.zip -d /opt/ords && \
    rm -f /tmp/ords-latest.zip && \
    chown -R oracle:oinstall /opt/ords && \
    ln -sf /opt/ords/bin/ords /usr/local/bin/ords

# ============================================================================
# CREATE DIRECTORIES
# ============================================================================
# ORDS config and logs
RUN mkdir -p /etc/ords/config /var/log/ords && \
    chown -R oracle:oinstall /etc/ords /var/log/ords && \
    chmod -R 775 /etc/ords /var/log/ords

# Data Pump directory (for import/export - especially useful with EE)
# Also pre-create admin dirs that the base image expects (avoids permission errors)
RUN mkdir -p /opt/oracle/admin/datapump \
             /opt/oracle/admin/FREE \
             /opt/oracle/admin/FREEPDB1 \
             /opt/oracle/admin/ORCLCDB \
             /opt/oracle/admin/ORCLPDB1 && \
    chown -R oracle:oinstall /opt/oracle/admin && \
    chmod -R 775 /opt/oracle/admin

# Custom scripts directory
RUN mkdir -p /opt/oracle/scripts/setup /opt/oracle/scripts/startup

# ============================================================================
# SETUP SCRIPT: Runs ONCE after DB creation (first container start)
# ============================================================================
# Oracle DB images execute *.sh and *.sql in /opt/oracle/scripts/setup/
# in alphabetical order after the database is created.
#
# This script:
#   1. Applies SPFILE tuning parameters
#   2. Creates Data Pump directory
#   3. Installs APEX into the PDB
#   4. Installs and configures ORDS
# ============================================================================
RUN cat > /opt/oracle/scripts/setup/10_apply_spfile_params.sh <<'SPFILE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# ============================================================================
# SPFILE Parameter Tuning
# ============================================================================
# These parameters are applied once at database creation. Adjust as needed
# for your workload. Some parameters require a database restart to take effect.
#
# NOTE: Oracle Free edition has hard limits (2 CPU threads, 2GB RAM) that
# override these settings. For larger allocations, use Enterprise edition.
# ============================================================================

ORACLE_SID="${ORACLE_SID:-FREE}"

echo "[setup] Applying SPFILE parameters..."

sqlplus -s / as sysdba <<'SQL'
SET ECHO ON
SET FEEDBACK ON
WHENEVER SQLERROR CONTINUE

-- ============================================================================
-- MEMORY PARAMETERS
-- ============================================================================
-- For Free edition: Max 2GB total, so these are modest defaults.
-- For Enterprise: Increase based on available RAM (e.g., SGA 4-8GB, PGA 1-2GB)
--
-- Automatic Memory Management (AMM) - let Oracle manage SGA+PGA:
--   ALTER SYSTEM SET memory_target = 1536M SCOPE=SPFILE;
--   ALTER SYSTEM SET memory_max_target = 2G SCOPE=SPFILE;
--
-- Manual SGA/PGA (more control, recommended for production):
ALTER SYSTEM SET sga_target = 1G SCOPE=SPFILE;
ALTER SYSTEM SET sga_max_size = 1536M SCOPE=SPFILE;
ALTER SYSTEM SET pga_aggregate_target = 512M SCOPE=SPFILE;
ALTER SYSTEM SET pga_aggregate_limit = 1G SCOPE=SPFILE;

-- ============================================================================
-- PROCESS/SESSION PARAMETERS
-- ============================================================================
-- Increase for APEX/ORDS workloads with many concurrent users
ALTER SYSTEM SET processes = 500 SCOPE=SPFILE;
ALTER SYSTEM SET sessions = 600 SCOPE=SPFILE;

-- ============================================================================
-- UNDO AND TEMP
-- ============================================================================
-- Undo retention in seconds (900 = 15 minutes, good for flashback queries)
ALTER SYSTEM SET undo_retention = 900 SCOPE=SPFILE;

-- ============================================================================
-- OPTIMIZER / PERFORMANCE
-- ============================================================================
-- Optimizer settings (adjust based on workload characteristics)
ALTER SYSTEM SET optimizer_adaptive_plans = TRUE SCOPE=SPFILE;
ALTER SYSTEM SET optimizer_adaptive_statistics = TRUE SCOPE=SPFILE;

-- Result cache (great for APEX read-heavy apps)
ALTER SYSTEM SET result_cache_max_size = 64M SCOPE=SPFILE;

-- Parallel execution (EE only - ignored on Free)
-- ALTER SYSTEM SET parallel_max_servers = 16 SCOPE=SPFILE;
-- ALTER SYSTEM SET parallel_min_servers = 0 SCOPE=SPFILE;

-- ============================================================================
-- CONNECTION / NETWORK
-- ============================================================================
-- Idle connection timeout (0 = never, set to drop abandoned connections)
-- ALTER SYSTEM SET idle_time = 60 SCOPE=SPFILE;  -- 60 minutes

-- ============================================================================
-- OPEN CURSORS
-- ============================================================================
-- APEX and ORDS use many cursors; increase from default 300
ALTER SYSTEM SET open_cursors = 500 SCOPE=SPFILE;

-- ============================================================================
-- SECURITY (optional, uncomment as needed)
-- ============================================================================
-- Enforce password complexity:
-- ALTER PROFILE DEFAULT LIMIT PASSWORD_VERIFY_FUNCTION ora12c_verify_function;
--
-- Lock unused default accounts:
-- ALTER USER ANONYMOUS ACCOUNT LOCK;
-- ALTER USER XS$NULL ACCOUNT LOCK;

-- ============================================================================
-- ARCHIVE LOG MODE (for EE / production - enables point-in-time recovery)
-- ============================================================================
-- Uncomment for production systems (requires restart):
-- ALTER SYSTEM SET log_archive_dest_1 = 'LOCATION=/opt/oracle/oradata/archive' SCOPE=SPFILE;
-- SHUTDOWN IMMEDIATE;
-- STARTUP MOUNT;
-- ALTER DATABASE ARCHIVELOG;
-- ALTER DATABASE OPEN;

-- ============================================================================
-- ENTERPRISE EDITION ONLY - DATA PUMP / ADVANCED FEATURES
-- ============================================================================
-- These are ignored on Free edition but ready for EE:
--
-- Enable Database Vault (EE option):
-- EXEC DVSYS.DBMS_MACADM.ENABLE_DV;
--
-- Transparent Data Encryption (EE option):
-- ADMINISTER KEY MANAGEMENT CREATE KEYSTORE '/opt/oracle/admin/wallet' IDENTIFIED BY wallet_password;
-- ADMINISTER KEY MANAGEMENT SET KEY IDENTIFIED BY wallet_password WITH BACKUP;

EXIT;
SQL

echo "[setup] SPFILE parameters applied. Some require restart to take effect."
SPFILE_SCRIPT

RUN cat > /opt/oracle/scripts/setup/15_create_directories.sh <<'DIR_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# ============================================================================
# Create Oracle Directory Objects
# ============================================================================
# These are Oracle DIRECTORY objects that point to OS paths.
# Useful for Data Pump, external tables, UTL_FILE, etc.

ORACLE_PDB="${ORACLE_PDB:-FREEPDB1}"

echo "[setup] Creating directory objects in CDB and PDB..."

sqlplus -s / as sysdba <<SQL
SET ECHO ON
WHENEVER SQLERROR CONTINUE

-- CDB level directory
CREATE OR REPLACE DIRECTORY datapump_dir AS '/opt/oracle/admin/datapump';
GRANT READ, WRITE ON DIRECTORY datapump_dir TO PUBLIC;

-- PDB level directory
ALTER SESSION SET CONTAINER=${ORACLE_PDB};
CREATE OR REPLACE DIRECTORY datapump_dir AS '/opt/oracle/admin/datapump';
GRANT READ, WRITE ON DIRECTORY datapump_dir TO PUBLIC;

-- Additional directories you might need:
-- CREATE OR REPLACE DIRECTORY scripts_dir AS '/opt/oracle/scripts';
-- CREATE OR REPLACE DIRECTORY export_dir AS '/opt/oracle/admin/export';

EXIT;
SQL

echo "[setup] Directory objects created."
DIR_SCRIPT

RUN cat > /opt/oracle/scripts/setup/20_install_apex.sh <<'APEX_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# ============================================================================
# APEX Installation
# ============================================================================

ORACLE_PDB="${ORACLE_PDB:-FREEPDB1}"
ORACLE_PWD="${ORACLE_PWD:-}"

if [[ -z "${ORACLE_PWD}" ]]; then
  echo "ERROR: ORACLE_PWD must be set for APEX install."
  exit 1
fi

# Find the APEX install directory (apex-latest.zip extracts to /opt/apex/apex/)
APEX_HOME=$(find /opt/apex -maxdepth 2 -name "apexins.sql" -printf "%h" -quit 2>/dev/null)
if [[ -z "${APEX_HOME}" ]]; then
  echo "ERROR: Cannot find apexins.sql in /opt/apex"
  exit 1
fi

echo "[setup] Found APEX at: ${APEX_HOME}"
echo "[setup] Installing APEX into PDB=${ORACLE_PDB}..."

cd "${APEX_HOME}"

sqlplus -s / as sysdba <<SQL
WHENEVER SQLERROR EXIT 1
ALTER SESSION SET CONTAINER=${ORACLE_PDB};

-- APEX install: tablespace_apex, tablespace_files, tablespace_temp, images_prefix
-- Using SYSAUX for both APEX and files tablespaces (standard for dev/test)
-- For production, consider dedicated tablespaces
@apexins.sql SYSAUX SYSAUX TEMP /i/

-- Unlock and set password for APEX_PUBLIC_USER (used by ORDS)
ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY "${ORACLE_PWD}";

-- Create APEX Instance Admin account
-- After install, login at: http://localhost:8080/ords/apex_admin
-- Username: ADMIN, Password: as set below
BEGIN
    APEX_UTIL.SET_SECURITY_GROUP_ID(10);
    APEX_UTIL.CREATE_USER(
        p_user_name       => 'ADMIN',
        p_email_address   => 'admin@localhost',
        p_web_password    => '${ORACLE_PWD}',
        p_developer_privs => 'ADMIN',
        p_change_password_on_first_use => 'N'
    );
    COMMIT;
END;
/

-- Configure APEX REST
@apex_rest_config.sql "${ORACLE_PWD}" "${ORACLE_PWD}"

-- Network ACL for APEX to make external HTTP calls (optional but useful)
BEGIN
    DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
        host => '*',
        ace  => xs\$ace_type(
            privilege_list => xs\$name_list('connect', 'resolve'),
            principal_name => 'APEX_240200',  -- Adjust version as needed
            principal_type => xs_acl.ptype_db
        )
    );
EXCEPTION WHEN OTHERS THEN
    -- Ignore if user doesn't exist or already granted
    NULL;
END;
/

EXIT;
SQL

echo "[setup] APEX installation complete."
echo "[setup] APEX Admin: http://localhost:8080/ords/apex_admin (ADMIN / your password)"
APEX_SCRIPT

RUN cat > /opt/oracle/scripts/setup/25_install_ords.sh <<'ORDS_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# ============================================================================
# ORDS Installation and Configuration
# ============================================================================

ORACLE_PDB="${ORACLE_PDB:-FREEPDB1}"
ORACLE_PWD="${ORACLE_PWD:-}"

if [[ -z "${ORACLE_PWD}" ]]; then
  echo "ERROR: ORACLE_PWD must be set for ORDS install."
  exit 1
fi

if ! command -v ords >/dev/null 2>&1; then
  echo "ERROR: 'ords' command not found at /opt/ords/bin/ords"
  exit 1
fi

echo "[setup] Installing ORDS for PDB=${ORACLE_PDB}..."

# Find APEX images directory
APEX_IMAGES=$(find /opt/apex -maxdepth 2 -type d -name "images" -print -quit 2>/dev/null)
if [[ -z "${APEX_IMAGES}" ]]; then
  echo "WARNING: APEX images directory not found, static files may not work"
  APEX_IMAGES="/opt/apex/apex/images"
fi
echo "[setup] APEX images at: ${APEX_IMAGES}"

# ORDS silent install
# The install command creates ORDS schema and REST-enables the PDB
ords --config /etc/ords/config install \
  --admin-user SYS \
  --db-hostname localhost \
  --db-port 1521 \
  --db-servicename "${ORACLE_PDB}" \
  --feature-sdw true \
  --log-folder /var/log/ords \
  --password-stdin <<< "${ORACLE_PWD}"

# Configure standalone server settings
ords --config /etc/ords/config config set standalone.context.path /ords
ords --config /etc/ords/config config set standalone.doc.root "${APEX_IMAGES}"
ords --config /etc/ords/config config set standalone.static.context.path /i
ords --config /etc/ords/config config set standalone.static.path "${APEX_IMAGES}"

# Set JDBC pool settings for better APEX performance
ords --config /etc/ords/config config set jdbc.InitialLimit 10
ords --config /etc/ords/config config set jdbc.MinLimit 10
ords --config /etc/ords/config config set jdbc.MaxLimit 50

echo "[setup] ORDS installation complete."
ORDS_SCRIPT

RUN chmod +x /opt/oracle/scripts/setup/*.sh && \
    chown -R oracle:oinstall /opt/oracle/scripts/setup

# ============================================================================
# STARTUP SCRIPT: Runs on EVERY container start
# ============================================================================
# Oracle 26ai images ship with pre-built databases and DON'T run setup scripts.
# So we handle first-run setup here in the startup script instead.
# ============================================================================
RUN cat > /opt/oracle/scripts/startup/10_setup_and_start.sh <<'STARTUP_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

ORACLE_PDB="${ORACLE_PDB:-FREEPDB1}"
ORACLE_PWD="${ORACLE_PWD:-}"
FIRST_RUN_MARKER="/opt/oracle/oradata/.apex_installed"

# ============================================================================
# FIRST RUN: Install APEX and configure ORDS
# ============================================================================
if [[ ! -f "${FIRST_RUN_MARKER}" ]]; then
  echo "========================================"
  echo "[startup] First run detected - installing APEX and ORDS..."
  echo "========================================"

  if [[ -z "${ORACLE_PWD}" ]]; then
    echo "ERROR: ORACLE_PWD must be set for APEX/ORDS install."
    exit 1
  fi

  # --- Apply SPFILE parameters ---
  echo "[startup] Applying SPFILE parameters..."
  sqlplus -s / as sysdba <<'SPFILE_SQL'
SET ECHO OFF FEEDBACK OFF
WHENEVER SQLERROR CONTINUE
ALTER SYSTEM SET sga_target = 1G SCOPE=SPFILE;
ALTER SYSTEM SET sga_max_size = 1536M SCOPE=SPFILE;
ALTER SYSTEM SET pga_aggregate_target = 512M SCOPE=SPFILE;
ALTER SYSTEM SET processes = 500 SCOPE=SPFILE;
ALTER SYSTEM SET sessions = 600 SCOPE=SPFILE;
ALTER SYSTEM SET open_cursors = 500 SCOPE=SPFILE;
ALTER SYSTEM SET undo_retention = 900 SCOPE=SPFILE;
ALTER SYSTEM SET result_cache_max_size = 64M SCOPE=SPFILE;
EXIT;
SPFILE_SQL
  echo "[startup] SPFILE parameters applied (effective after restart)."

  # --- Create Data Pump directory ---
  echo "[startup] Creating Data Pump directory..."
  sqlplus -s / as sysdba <<DPUMP_SQL
SET ECHO OFF FEEDBACK OFF
WHENEVER SQLERROR CONTINUE
CREATE OR REPLACE DIRECTORY datapump_dir AS '/opt/oracle/admin/datapump';
GRANT READ, WRITE ON DIRECTORY datapump_dir TO PUBLIC;
ALTER SESSION SET CONTAINER=${ORACLE_PDB};
CREATE OR REPLACE DIRECTORY datapump_dir AS '/opt/oracle/admin/datapump';
GRANT READ, WRITE ON DIRECTORY datapump_dir TO PUBLIC;
EXIT;
DPUMP_SQL

  # --- Recompile invalid objects (fixes ORA-65047 JSON_DATAGUIDE issue in 26ai) ---
  echo "[startup] Recompiling invalid objects (JSON_DATAGUIDE fix)..."
  sqlplus -s / as sysdba <<'RECOMPILE_SQL'
WHENEVER SQLERROR CONTINUE
-- Recompile specific problematic object
ALTER TYPE SYS.JSON_DATAGUIDE COMPILE;
-- Run UTL_RECOMP to fix any invalid objects
EXEC UTL_RECOMP.RECOMP_SERIAL();
EXIT;
RECOMPILE_SQL

  sqlplus -s / as sysdba <<RECOMPILE_PDB_SQL
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER=${ORACLE_PDB};
ALTER TYPE SYS.JSON_DATAGUIDE COMPILE;
EXEC UTL_RECOMP.RECOMP_SERIAL();
EXIT;
RECOMPILE_PDB_SQL

  # --- Install APEX ---
  APEX_HOME=$(find /opt/apex -maxdepth 2 -name "apexins.sql" -printf "%h" -quit 2>/dev/null)
  if [[ -z "${APEX_HOME}" ]]; then
    echo "ERROR: Cannot find apexins.sql in /opt/apex"
    exit 1
  fi
  echo "[startup] Installing APEX from ${APEX_HOME} into ${ORACLE_PDB}..."
  echo "[startup] This will take 10-15 minutes..."

  cd "${APEX_HOME}"
  sqlplus -s / as sysdba <<APEX_SQL
WHENEVER SQLERROR EXIT 1
ALTER SESSION SET CONTAINER=${ORACLE_PDB};
@apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT;
APEX_SQL

  echo "[startup] Configuring APEX users..."
  # Write SQL to temp file to avoid heredoc escaping issues
  cat > /tmp/apex_config.sql <<APEX_CFG_SQL
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER=${ORACLE_PDB};
ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY "${ORACLE_PWD}";
BEGIN
    APEX_UTIL.SET_SECURITY_GROUP_ID(10);
    APEX_UTIL.CREATE_USER(
        p_user_name       => 'ADMIN',
        p_email_address   => 'admin@localhost',
        p_web_password    => '${ORACLE_PWD}',
        p_developer_privs => 'ADMIN',
        p_change_password_on_first_use => 'N'
    );
    COMMIT;
EXCEPTION WHEN OTHERS THEN
    NULL;
END;
/
EXIT;
APEX_CFG_SQL
  sqlplus -s / as sysdba @/tmp/apex_config.sql
  rm -f /tmp/apex_config.sql

  echo "[startup] Running APEX REST config..."
  cd "${APEX_HOME}"
  sqlplus -s / as sysdba <<APEX_REST_SQL
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER=${ORACLE_PDB};
@apex_rest_config.sql ${ORACLE_PWD} ${ORACLE_PWD}
EXIT;
APEX_REST_SQL

  # --- Install ORDS ---
  echo "[startup] Installing ORDS..."
  APEX_IMAGES=$(find /opt/apex -maxdepth 2 -type d -name "images" -print -quit 2>/dev/null)
  [[ -z "${APEX_IMAGES}" ]] && APEX_IMAGES="/opt/apex/apex/images"

  ords --config /etc/ords/config install \
    --admin-user SYS \
    --db-hostname localhost \
    --db-port 1521 \
    --db-servicename "${ORACLE_PDB}" \
    --feature-sdw true \
    --log-folder /var/log/ords \
    --password-stdin <<< "${ORACLE_PWD}"

  # Configure ORDS settings
  ords --config /etc/ords/config config set standalone.context.path /ords
  ords --config /etc/ords/config config set standalone.doc.root "${APEX_IMAGES}"
  ords --config /etc/ords/config config set standalone.static.context.path /i
  ords --config /etc/ords/config config set standalone.static.path "${APEX_IMAGES}"
  ords --config /etc/ords/config config set jdbc.InitialLimit 10
  ords --config /etc/ords/config config set jdbc.MinLimit 10
  ords --config /etc/ords/config config set jdbc.MaxLimit 50

  # Mark installation complete
  touch "${FIRST_RUN_MARKER}"
  echo "========================================"
  echo "[startup] APEX and ORDS installation complete!"
  echo "========================================"
fi

# ============================================================================
# START ORDS (every startup)
# ============================================================================
if ! command -v ords >/dev/null 2>&1; then
  echo "[startup] ORDS not installed; skipping."
  exit 0
fi

if [[ ! -d /etc/ords/config/databases ]]; then
  echo "[startup] ORDS not configured; skipping."
  exit 0
fi

if pgrep -f "ords.*serve" >/dev/null 2>&1; then
  echo "[startup] ORDS already running."
  exit 0
fi

APEX_IMAGES=$(find /opt/apex -maxdepth 2 -type d -name "images" -print -quit 2>/dev/null)
[[ -z "${APEX_IMAGES}" ]] && APEX_IMAGES="/opt/apex/apex/images"

echo "[startup] Starting ORDS on port 8080..."
nohup ords --config /etc/ords/config serve \
  --port 8080 \
  --apex-images "${APEX_IMAGES}" \
  > /var/log/ords/ords-standalone.log 2>&1 &

sleep 3
if pgrep -f "ords.*serve" >/dev/null 2>&1; then
  echo "[startup] ORDS started successfully."
  echo "[startup] ============================================"
  echo "[startup] APEX URL:       http://localhost:8080/ords/apex"
  echo "[startup] APEX Admin:     http://localhost:8080/ords/apex_admin"
  echo "[startup] SQL Developer:  http://localhost:8080/ords/sql-developer"
  echo "[startup] ============================================"
else
  echo "[startup] WARNING: ORDS may have failed. Check /var/log/ords/ords-standalone.log"
fi
STARTUP_SCRIPT

RUN chmod +x /opt/oracle/scripts/startup/*.sh && \
    chown -R oracle:oinstall /opt/oracle/scripts/startup

# ============================================================================
# HEALTHCHECK
# ============================================================================
# Verifies both the database listener and ORDS are responding
HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=3 \
  CMD curl -sf http://localhost:8080/ords/apex || exit 1

USER oracle

# ============================================================================
# EXPOSED PORTS
# ============================================================================
#   1521  - Oracle Net Listener (SQL*Plus, JDBC, etc.)
#   5500  - EM Express (if enabled in base image)
#   8080  - ORDS/APEX HTTP
# ============================================================================
EXPOSE 1521 5500 8080

# ============================================================================
# VOLUMES (declared for documentation; actual mount at runtime)
# ============================================================================
# Mount these for data persistence:
#   /opt/oracle/oradata     - Database files (REQUIRED for persistence!)
#   /opt/oracle/admin       - Admin files, Data Pump exports
#   /etc/ords/config        - ORDS configuration (optional)
#   /var/log/ords           - ORDS logs (optional)
# ============================================================================
VOLUME ["/opt/oracle/oradata"]
