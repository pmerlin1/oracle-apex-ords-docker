#!/usr/bin/env bash
# ============================================================================
# Create Oracle directory objects (Data Pump, etc.)
# ============================================================================
set -euo pipefail

ORACLE_PDB="${ORACLE_PDB:-FREEPDB1}"

echo "[dirs] Creating Data Pump directory in CDB and ${ORACLE_PDB}..."

sqlplus -s / as sysdba <<SQL
SET ECHO OFF FEEDBACK OFF
WHENEVER SQLERROR CONTINUE

-- CDB level
CREATE OR REPLACE DIRECTORY datapump_dir AS '/opt/oracle/admin/datapump';
GRANT READ, WRITE ON DIRECTORY datapump_dir TO PUBLIC;

-- PDB level
ALTER SESSION SET CONTAINER=${ORACLE_PDB};
CREATE OR REPLACE DIRECTORY datapump_dir AS '/opt/oracle/admin/datapump';
GRANT READ, WRITE ON DIRECTORY datapump_dir TO PUBLIC;

EXIT;
SQL

echo "[dirs] Directory objects created."
