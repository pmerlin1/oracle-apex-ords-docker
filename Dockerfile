# syntax=docker/dockerfile:1
# ============================================================================
# Oracle Database + APEX + ORDS Container
# ============================================================================
# See README.md for full documentation
# ============================================================================

# ============================================================================
# BUILD ARGUMENTS - Override with: docker build --build-arg VAR=value
# ============================================================================
ARG BASE_IMAGE=container-registry.oracle.com/database/free:latest
ARG APEX_URL=https://download.oracle.com/otn_software/apex/apex-latest.zip
ARG ORDS_URL=https://download.oracle.com/otn_software/java/ords/ords-latest.zip

# ============================================================================
# RUNTIME DEFAULTS - Override with: docker run -e VAR=value
# ============================================================================
# ORACLE_PWD     (required)  SYS/SYSTEM/APEX ADMIN password
# ORACLE_PDB     FREEPDB1    PDB name (ORCLPDB1 for EE)
# ORACLE_SID     FREE        SID (ORCLCDB for EE)
# SKIP_APEX      false       Set "true" to skip APEX install
# SKIP_ORDS      false       Set "true" to skip ORDS (implies SKIP_APEX)
# ORDS_PORT      8080        ORDS HTTP port
# JDBC_INITIAL   10          ORDS connection pool initial size
# JDBC_MIN       10          ORDS connection pool minimum
# JDBC_MAX       50          ORDS connection pool maximum
# ============================================================================

FROM ${BASE_IMAGE}
ARG APEX_URL
ARG ORDS_URL

USER root

# Fix Oracle yum repos (regional servers timeout)
RUN [ -d /etc/dnf/vars ] && echo "" > /etc/dnf/vars/ociregion || true && \
    [ -d /etc/yum/vars ] && echo "" > /etc/yum/vars/ociregion || true

# Install OS dependencies (dnf for OL8+, yum for OL7)
RUN if command -v dnf &>/dev/null; then \
        dnf -y install unzip curl java-17-openjdk && dnf clean all; \
    else \
        yum -y install unzip curl java-17-openjdk && yum clean all; \
    fi

# Download APEX
RUN mkdir -p /opt/apex && \
    curl -Lf -o /tmp/apex.zip "${APEX_URL}" && \
    unzip -q /tmp/apex.zip -d /opt/apex && \
    rm -f /tmp/apex.zip && \
    chown -R oracle:oinstall /opt/apex

# Download ORDS
RUN mkdir -p /opt/ords && \
    curl -Lf -o /tmp/ords.zip "${ORDS_URL}" && \
    unzip -q /tmp/ords.zip -d /opt/ords && \
    rm -f /tmp/ords.zip && \
    chown -R oracle:oinstall /opt/ords && \
    ln -sf /opt/ords/bin/ords /usr/local/bin/ords

# Create directories
RUN mkdir -p /etc/ords/config /var/log/ords \
             /opt/oracle/admin/datapump \
             /opt/oracle/admin/FREE /opt/oracle/admin/FREEPDB1 \
             /opt/oracle/admin/ORCLCDB /opt/oracle/admin/ORCLPDB1 \
             /opt/oracle/config \
             /opt/oracle/scripts/custom \
             /opt/oracle/scripts/startup && \
    chown -R oracle:oinstall /etc/ords /var/log/ords /opt/oracle/admin \
                              /opt/oracle/config /opt/oracle/scripts && \
    chmod -R 775 /etc/ords /var/log/ords /opt/oracle/admin /opt/oracle/config

# Copy configuration and scripts
COPY --chown=oracle:oinstall config/init.ora /opt/oracle/config/init.ora
COPY --chown=oracle:oinstall scripts/*.sh /opt/oracle/scripts/
RUN chmod +x /opt/oracle/scripts/*.sh

# Wire up entrypoint to Oracle's startup hook
RUN ln -sf /opt/oracle/scripts/entrypoint.sh /opt/oracle/scripts/startup/10_setup_and_start.sh

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=3 \
  CMD curl -sf http://localhost:${ORDS_PORT:-8080}/ords/apex 2>/dev/null || \
      sqlplus -s / as sysdba <<< "SELECT 1 FROM DUAL;" 2>/dev/null | grep -q 1

USER oracle
EXPOSE 1521 5500 8080
VOLUME ["/opt/oracle/oradata"]
