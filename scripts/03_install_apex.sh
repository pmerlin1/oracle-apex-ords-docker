#!/usr/bin/env bash
# ============================================================================
# Install Oracle APEX
# ============================================================================
set -euo pipefail

ORACLE_PDB="${ORACLE_PDB:-FREEPDB1}"
ORACLE_PWD="${ORACLE_PWD:-}"

if [[ -z "${ORACLE_PWD}" ]]; then
  echo "[apex] ERROR: ORACLE_PWD not set"
  exit 1
fi

# Find APEX installation directory
APEX_HOME=$(find /opt/apex -maxdepth 2 -name "apexins.sql" -printf "%h" -quit 2>/dev/null)
if [[ -z "${APEX_HOME}" ]]; then
  echo "[apex] ERROR: Cannot find apexins.sql in /opt/apex"
  exit 1
fi

echo "[apex] Installing APEX from ${APEX_HOME} into ${ORACLE_PDB}..."
echo "[apex] This takes 10-15 minutes..."

cd "${APEX_HOME}"

# Main APEX installation
sqlplus -s / as sysdba <<SQL
WHENEVER SQLERROR EXIT 1
ALTER SESSION SET CONTAINER=${ORACLE_PDB};
@apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT;
SQL

echo "[apex] Configuring APEX users..."

# Write to temp file to handle PL/SQL parentheses
cat > /tmp/apex_config.sql <<CFGSQL
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER=${ORACLE_PDB};

-- Unlock APEX_PUBLIC_USER for ORDS
ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY "${ORACLE_PWD}";

-- Create APEX admin account
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
    -- User may already exist
    NULL;
END;
/
EXIT;
CFGSQL

sqlplus -s / as sysdba @/tmp/apex_config.sql
rm -f /tmp/apex_config.sql

# Configure APEX RESTful Services
echo "[apex] Configuring APEX REST services..."
cd "${APEX_HOME}"
sqlplus -s / as sysdba <<SQL
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER=${ORACLE_PDB};
@apex_rest_config.sql ${ORACLE_PWD} ${ORACLE_PWD}
EXIT;
SQL

echo "[apex] APEX installation complete."
echo "[apex] Admin URL: http://localhost:8080/ords/apex_admin"
echo "[apex] Credentials: ADMIN / <your ORACLE_PWD>"
