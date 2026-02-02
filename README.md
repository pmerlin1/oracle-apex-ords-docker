# oracle-apex-ords-docker

All-in-one Docker image for **Oracle Database Free + APEX + ORDS**. Zero config, ephemeral-friendly, perfect for dev/test and legacy app migrations.

## Quick Start

```bash
# Build
docker build -t oracle-apex-ords .

# Run (ephemeral)
docker run -d --name orcl \
  -p 1521:1521 -p 8080:8080 \
  -e ORACLE_PWD=YourPassword123 \
  oracle-apex-ords

# Run (persistent)
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
| SQL Developer Web | http://localhost:8080/ords/\<schema\>/_sdw/ | [Enable first](#enable-sql-developer-web) |
| Database | `localhost:1521/FREEPDB1` | `SYS` / your password |

## Environment Variables

### Required
| Variable | Description |
|----------|-------------|
| `ORACLE_PWD` | Password for SYS, SYSTEM, and APEX ADMIN |

### Optional
| Variable | Default | Description |
|----------|---------|-------------|
| `ORACLE_PDB` | `FREEPDB1` | PDB name (`ORCLPDB1` for EE) |
| `ORACLE_SID` | `FREE` | Database SID (`ORCLCDB` for EE) |
| `SKIP_APEX` | `false` | Set `true` to skip APEX installation |
| `SKIP_ORDS` | `false` | Set `true` for DB-only mode |
| `ORDS_PORT` | `8080` | ORDS HTTP port |
| `JDBC_INITIAL` | `10` | ORDS connection pool initial size |
| `JDBC_MIN` | `10` | ORDS connection pool minimum |
| `JDBC_MAX` | `50` | ORDS connection pool maximum |

## Customization

### Custom Database Parameters (PFILE)

Edit `config/init.ora` before building, or mount your own at runtime:

```bash
docker run -d --name orcl \
  -p 1521:1521 -p 8080:8080 \
  -e ORACLE_PWD=YourPassword123 \
  -v ./my-init.ora:/opt/oracle/config/init.ora:ro \
  oracle-apex-ords
```

The default `init.ora` includes common tuning parameters with comments:
- Memory (SGA/PGA)
- Processes & sessions
- Cursors
- Result cache

### Custom SQL Scripts

Mount SQL files to `/opt/oracle/scripts/custom/` - they run after APEX install:

```bash
docker run -d --name orcl \
  -v ./my-scripts:/opt/oracle/scripts/custom:ro \
  ...
```

### DB-Only Mode (No APEX/ORDS)

```bash
docker run -d --name orcl \
  -p 1521:1521 \
  -e ORACLE_PWD=YourPassword123 \
  -e SKIP_ORDS=true \
  oracle-apex-ords
```

## Enable SQL Developer Web

REST-enable a schema first:

```sql
sqlplus sys/YourPassword123@localhost:1521/FREEPDB1 as sysdba

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

Access: `http://localhost:8080/ords/admin/_sdw/`

## Data Pump

Pre-configured directory at `/opt/oracle/admin/datapump`:

```bash
# Import
docker cp myexport.dmp orcl:/opt/oracle/admin/datapump/
docker exec orcl impdp system/YourPwd@FREEPDB1 \
  directory=datapump_dir dumpfile=myexport.dmp logfile=import.log

# Export
docker exec orcl expdp system/YourPwd@FREEPDB1 \
  directory=datapump_dir dumpfile=export.dmp schemas=MYSCHEMA
```

## Enterprise Edition

```bash
docker build \
  --build-arg BASE_IMAGE=container-registry.oracle.com/database/enterprise:latest \
  -t oracle-apex-ords-ee .

docker run -d --name orcl \
  -e ORACLE_PWD=YourPassword123 \
  -e ORACLE_SID=ORCLCDB \
  -e ORACLE_PDB=ORCLPDB1 \
  oracle-apex-ords-ee
```

## Project Structure

```
├── Dockerfile              # Image build definition
├── config/
│   └── init.ora            # Database parameters (editable)
├── scripts/
│   ├── entrypoint.sh       # Main startup orchestrator
│   ├── 01_apply_pfile.sh   # Apply PFILE to SPFILE
│   ├── 02_setup_directories.sh
│   ├── 03_install_apex.sh
│   ├── 04_install_ords.sh
│   └── 05_run_custom.sh    # Run custom SQL scripts
└── README.md
```

## Troubleshooting

```bash
# Container logs
docker logs -f orcl

# ORDS logs
docker exec orcl tail -f /var/log/ords/ords-standalone.log

# Database alert log
docker exec orcl tail -f /opt/oracle/diag/rdbms/free/FREE/trace/alert_FREE.log

# Shell access
docker exec -it orcl bash
```

## Known Issues

- **Do NOT use `-lite` images** - they exclude XDB which APEX requires
- First startup is slow (~10-15 min) due to APEX installation
- `mkdir: cannot create directory` warnings during startup are harmless

## License

Dockerfile and scripts are provided as-is. Oracle software is subject to [Oracle licensing](https://www.oracle.com/downloads/licenses/standard-license.html).
