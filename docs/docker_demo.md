# Docker Demo

This workflow runs OracleShieldBackup locally with Docker Desktop. It is intended for demonstration and portfolio validation, not production backups.

## Why Not The Lite Image?

Oracle provides a smaller Oracle Database Free Lite image, but Oracle documents RMAN as unsupported in the Lite image. Since OracleShieldBackup is an RMAN backup project, the demo uses:

```text
container-registry.oracle.com/database/free:latest
```

This is still lighter than rebuilding a full Oracle Linux VM with Oracle Database installed.

## Start The Database

From PowerShell:

```powershell
cd C:\Users\Owner\Documents\PROJECTS\OracleShieldBackup
.\scripts\docker_demo.ps1 up
```

First startup may take several minutes because Docker must pull the image and Oracle must initialize.

Watch logs:

```powershell
.\scripts\docker_demo.ps1 logs
```

Check status:

```powershell
.\scripts\docker_demo.ps1 status
```

## Run Backup Jobs

The helper runs the project scripts inside the container with `config/docker-demo.conf`.

```powershell
.\scripts\docker_demo.ps1 archive
.\scripts\docker_demo.ps1 full
.\scripts\docker_demo.ps1 incremental
.\scripts\docker_demo.ps1 validate
.\scripts\docker_demo.ps1 report
```

Equivalent Bash command:

```bash
./scripts/docker_demo.sh full
```

## Output Locations

| Path | Purpose |
| --- | --- |
| `logs/` | Shell and RMAN logs from demo runs. |
| `reports/backup_runs.tsv` | Machine-readable run history. |
| `reports/dashboard.md` | Business summary dashboard. |
| `docker/backups/` | RMAN backup pieces, manifests, and staging files. |

## SQL Connection

Open a shell inside the container:

```powershell
.\scripts\docker_demo.ps1 shell
```

Connect to the CDB:

```bash
sqlplus system/OracleShield_123@FREE
```

Connect to the default PDB:

```bash
sqlplus pdbadmin/OracleShield_123@FREEPDB1
```

## S3 Uploads In The Demo

`config/docker-demo.conf` disables S3 uploads by default:

```bash
ENABLE_S3_UPLOAD=false
```

To test S3 from inside the container, you must provide AWS CLI and credentials inside the container or run the upload script on a host where AWS CLI is configured. For the local Docker demo, the main proof is RMAN backup, validation, logs, retention, and dashboard generation.

## Cleanup

Stop the container:

```powershell
.\scripts\docker_demo.ps1 down
```

This keeps the named Oracle data volume. To remove the database volume later:

```powershell
docker compose down -v
```

That deletes the container database storage. It does not delete files under `docker/backups/`, `logs/`, or `reports/`.

