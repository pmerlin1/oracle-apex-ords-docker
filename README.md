# oracle-apex-ords-docker

All-in-one Docker image for **Oracle Database Free + APEX + ORDS**. Zero config, ephemeral-friendly, perfect for dev/test and legacy app migrations.

## Quick Start

```bash
# Build
docker build -t oracle-apex-ords .

# Run (ephemeral - data lost on container removal)
docker run -d --name orcl \
  -p 1521:1521 -p 8080:8080 \
  -e ORACLE_PWD=YourPassword123 \
  oracle-apex-ords

# Run (persistent - data survives restarts)
docker run -d --name orcl \
  -p 1521:1521 -p 8080:8080 \
  -e ORACLE_PWD=YourPassword123 \
  -v orcl-data:/opt/oracle/oradata \
  oracle-apex-ords
```

First startup takes **10-15 minutes** (APEX installation). Subsequent starts are fast.

## Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| APEX | http://localhost:8080/ords/apex | Create workspace |
| APEX Admin | http://localhost:8080/ords/apex_admin | `ADMIN` / your password |
| SQL Developer Web | http://localhost:8080/ords/admin/_sdw/ | See [Enable SDW](#enable-sql-developer-web) |
| Database | `localhost:1521/FREEPDB1` | `SYS` / your password |

## Credentials

All accounts use the password you set via `ORACLE_PWD`:

| Account | Username | Purpose |
|---------|----------|---------|
| SYS | `sys` | DBA (connect as SYSDBA) |
| SYSTEM | `system` | DBA |
| APEX Admin | `ADMIN` | APEX instance administration |

## Enable SQL Developer Web

SQL Developer Web requires REST-enabling a schema:

```sql
-- Connect as SYS
sqlplus sys/YourPassword123@localhost:1521/FREEPDB1 as sysdba

-- Enable for ADMIN schema
BEGIN
    ORDS_ADMIN.ENABLE_SCHEMA(
        p_enabled => TRUE,
        p_schema => 'ADMIN',
        p_url_mapping_type => 'BASE_PATH',
        p_url_mapping_pattern => 'admin',
        p_auto_rest_auth => FALSE
    );
    COMMIT;
END;
/
```

Then access: `http://localhost:8080/ords/admin/_sdw/`

## Data Pump (Import/Export)

A Data Pump directory is pre-configured at `/opt/oracle/admin/datapump`:

```bash
# Copy dump file into container
docker cp myexport.dmp orcl:/opt/oracle/admin/datapump/

# Import
docker exec orcl impdp system/YourPassword123@FREEPDB1 \
  directory=datapump_dir \
  dumpfile=myexport.dmp \
  logfile=import.log

# Export
docker exec orcl expdp system/YourPassword123@FREEPDB1 \
  directory=datapump_dir \
  dumpfile=myexport.dmp \
  schemas=MYSCHEMA
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ORACLE_PWD` | *required* | Password for SYS, SYSTEM, APEX ADMIN |
| `ORACLE_PDB` | `FREEPDB1` | PDB name |
| `ORACLE_SID` | `FREE` | Database SID |

## Enterprise Edition

For production features (partitioning, advanced compression, etc.), use Oracle Enterprise Edition:

```bash
# Requires Oracle account and license acceptance at container-registry.oracle.com
docker build \
  --build-arg BASE_IMAGE=container-registry.oracle.com/database/enterprise:latest \
  -t oracle-apex-ords-ee .

docker run -d --name orcl \
  -p 1521:1521 -p 8080:8080 \
  -e ORACLE_PWD=YourPassword123 \
  -e ORACLE_SID=ORCLCDB \
  -e ORACLE_PDB=ORCLPDB1 \
  oracle-apex-ords-ee
```

## Persistence

| Path | Purpose | Mount? |
|------|---------|--------|
| `/opt/oracle/oradata` | Database files | **Required for persistence** |
| `/opt/oracle/admin/datapump` | Data Pump files | Optional |
| `/etc/ords/config` | ORDS configuration | Optional |
| `/var/log/ords` | ORDS logs | Optional |

Without mounting `/opt/oracle/oradata`, all data is lost when the container is removed (useful for CI/CD).

## Ports

| Port | Service |
|------|---------|
| 1521 | Oracle Net Listener (SQL*Plus, JDBC) |
| 8080 | ORDS / APEX HTTP |
| 5500 | EM Express (if enabled) |

## Troubleshooting

**Container logs:**
```bash
docker logs -f orcl
```

**ORDS logs:**
```bash
docker exec orcl tail -f /var/log/ords/ords-standalone.log
```

**Database alert log:**
```bash
docker exec orcl tail -f /opt/oracle/diag/rdbms/free/FREE/trace/alert_FREE.log
```

**Shell access:**
```bash
docker exec -it orcl bash
```

## Known Issues

- **Do NOT use `*-lite` images** (e.g., `free:latest-lite`) - they exclude XDB which APEX requires
- First startup is slow (~10-15 min) due to APEX installation
- The `mkdir: cannot create directory '/opt/oracle/admin/FREE': Permission denied` warning is harmless

## License

The Dockerfile and scripts in this repository are provided as-is. Oracle Database, APEX, and ORDS are subject to [Oracle's licensing terms](https://www.oracle.com/downloads/licenses/standard-license.html).
