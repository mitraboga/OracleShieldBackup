# OracleShieldBackup Architecture

OracleShieldBackup is a Linux automation project for scheduled Oracle RMAN backup, recovery validation, and offsite archival to Amazon S3.

```text
Oracle Database
      |
      v
Oracle RMAN
      |
      v
Local Backup Directory
      |
      v
Bash Automation Scripts
      |
      +--> Logs
      +--> Validation
      +--> Compression
      +--> AWS S3 Upload
      +--> Reports
      |
      v
Cron Scheduler
```

## Components

| Component | Purpose |
| --- | --- |
| `config/backup.conf` | Central configuration for Oracle, backup paths, S3, retention, and alerts. |
| `rman/*.rman` | RMAN command templates rendered by Bash at runtime. |
| `scripts/*.sh` | Operational entrypoints for full, incremental, archive log, validation, upload, cleanup, and reporting jobs. |
| `logs/` | Timestamped shell and RMAN logs. |
| `reports/` | Run history TSV and generated Markdown dashboard. |
| `cron/crontab.txt` | Production schedule installed for the Oracle OS user. |

## Backup Strategy

- Weekly level 0 backup captures the full database with compressed RMAN backupsets.
- Daily level 1 cumulative incremental backups reduce backup time and storage while keeping restore chains short.
- Archive logs are backed up every four hours and deleted after RMAN confirms they have been backed up to disk.
- Controlfile autobackup is enabled, and full/incremental jobs also back up the current controlfile.
- S3 receives offsite copies through `aws s3 sync`.

## Failure Handling

Each script uses strict Bash mode, timestamped logs, exit-code checks, and an error trap. Failures are recorded in `reports/backup_runs.tsv` and sent through email or AWS SNS when configured.

## Retention

RMAN retention is controlled by `RMAN_RETENTION_POLICY`. Local filesystem cleanup is controlled by `RETENTION_DAYS` and `LOG_RETENTION_DAYS`. S3 retention should be enforced with an S3 Lifecycle rule so archival cleanup is handled by AWS policy rather than by backup scripts.

