# OracleShieldBackup

Automated Oracle RMAN Backup, Recovery, and Cloud Archival System.

OracleShieldBackup is a Database Reliability Engineering project that automates Oracle backups with RMAN, Bash, AWS S3, and cron. It schedules full and incremental backups, captures archive logs, uploads offsite recovery copies, validates restore readiness, alerts on failure, enforces local retention, and generates a business-readable backup dashboard.

## Features

- Daily RMAN level 1 cumulative incremental backups
- Weekly RMAN level 0 full backups
- Archive log backup with RMAN deletion policy
- Automatic AWS S3 archival with server-side encryption support
- Timestamped shell and RMAN logs
- Cron-based scheduling
- Non-destructive recovery validation with `RESTORE ... VALIDATE`
- Failure alerts through email or AWS SNS
- Local retention cleanup
- Markdown dashboard and run history report

## Project Structure

```text
OracleShieldBackup/
├── scripts/
│   ├── common.sh
│   ├── full_backup.sh
│   ├── incremental_backup.sh
│   ├── archive_backup.sh
│   ├── upload_to_s3.sh
│   ├── validate_backup.sh
│   ├── restore_test.sh
│   ├── cleanup_old_backups.sh
│   └── generate_report.sh
├── rman/
│   ├── full_backup.rman
│   ├── incremental_backup.rman
│   ├── archive_backup.rman
│   └── restore_database.rman
├── config/
│   ├── backup.conf
│   └── docker-demo.conf
├── docker/
│   └── backups/
├── docker-compose.yml
├── logs/
├── reports/
├── docs/
│   ├── architecture.md
│   ├── disaster_recovery_plan.md
│   └── business_case.md
├── cron/
│   └── crontab.txt
└── README.md
```

## Prerequisites

- Linux host with Bash, cron, and standard GNU tools
- Oracle Database with RMAN available to the Oracle OS user
- AWS CLI v2 configured with permission to write to the target S3 bucket
- Optional alerting tool: `mailx`, `mail`, or AWS SNS

For a local demo without an Oracle Linux VM, use the Docker workflow below.

## Docker Demo

The Docker demo runs Oracle Database Free in a container and executes this project's RMAN scripts inside that container.

Oracle's `latest-lite` image is smaller, but it does not support RMAN. This demo therefore uses the RMAN-capable Oracle Database Free image:

```text
container-registry.oracle.com/database/free:latest
```

Start the database from PowerShell:

```powershell
cd C:\Users\Owner\Documents\PROJECTS\OracleShieldBackup
.\scripts\docker_demo.ps1 up
```

First startup can take several minutes while Docker pulls the image and Oracle initializes. Watch readiness:

```powershell
.\scripts\docker_demo.ps1 logs
```

When the container reports healthy/running, execute the demo jobs:

```powershell
.\scripts\docker_demo.ps1 archive
.\scripts\docker_demo.ps1 full
.\scripts\docker_demo.ps1 incremental
.\scripts\docker_demo.ps1 validate
.\scripts\docker_demo.ps1 report
```

Outputs are written locally:

```text
logs/
reports/
docker/backups/
```

Open a shell inside the database container:

```powershell
.\scripts\docker_demo.ps1 shell
```

Connect with SQL*Plus from inside the container:

```bash
sqlplus system/OracleShield_123@FREE
```

Stop the demo container without deleting the database volume:

```powershell
.\scripts\docker_demo.ps1 down
```

## Setup

1. Copy the project to the Oracle host:

```bash
sudo mkdir -p /opt/oracle-shield-backup
sudo cp -R . /opt/oracle-shield-backup
sudo chown -R oracle:oinstall /opt/oracle-shield-backup
```

2. Edit `config/backup.conf`:

```bash
vi /opt/oracle-shield-backup/config/backup.conf
```

Set at minimum:

- `ORACLE_SID`
- `ORACLE_HOME`
- `BACKUP_ROOT`
- `S3_BUCKET`
- `AWS_REGION`
- `ALERT_EMAIL`

3. Create the local backup filesystem paths:

```bash
sudo mkdir -p /u02/oracle_backups/{rman,archivelog,staging}
sudo chown -R oracle:oinstall /u02/oracle_backups
```

4. Make scripts executable:

```bash
chmod +x /opt/oracle-shield-backup/scripts/*.sh
```

5. Test a recovery validation:

```bash
sudo -iu oracle
BACKUP_CONFIG=/opt/oracle-shield-backup/config/backup.conf /opt/oracle-shield-backup/scripts/validate_backup.sh
```

## Manual Runs

```bash
/opt/oracle-shield-backup/scripts/full_backup.sh
/opt/oracle-shield-backup/scripts/incremental_backup.sh
/opt/oracle-shield-backup/scripts/archive_backup.sh
/opt/oracle-shield-backup/scripts/restore_test.sh
/opt/oracle-shield-backup/scripts/generate_report.sh
```

## Cron Schedule

Install the provided schedule as the Oracle OS user:

```bash
crontab /opt/oracle-shield-backup/cron/crontab.txt
crontab -l
```

Default schedule:

- Monday to Saturday 01:00: level 1 incremental backup
- Sunday 01:00: level 0 full backup
- Every 4 hours: archive log backup
- Daily 05:00: restore validation
- Daily 05:30: local cleanup
- Daily 05:45: dashboard refresh

## Reports

Run history is written to:

```text
reports/backup_runs.tsv
```

Generate the dashboard:

```bash
/opt/oracle-shield-backup/scripts/generate_report.sh
```

Dashboard output:

```text
reports/dashboard.md
```

## S3 Retention

The scripts enforce local retention. S3 retention should be handled with an S3 Lifecycle rule on the bucket or prefix. This keeps cloud retention auditable and separate from database host automation.

## Documentation

- [Architecture](docs/architecture.md)
- [Disaster Recovery Plan](docs/disaster_recovery_plan.md)
- [Business Case](docs/business_case.md)
- [Docker Demo](docs/docker_demo.md)
- [Oracle RMAN Reference](https://docs.oracle.com/en/database/oracle/oracle-database/19/rcmrf/index.html)
- [AWS CLI S3 Sync](https://docs.aws.amazon.com/cli/latest/reference/s3/sync.html)
- [cron manual](https://man7.org/linux/man-pages/man8/cron.8.html)

## Resume Bullet

Built an automated Oracle database backup and recovery system using RMAN, Bash, AWS S3, and Cron Jobs to schedule full and incremental backups, enforce retention policies, upload disaster recovery copies to cloud storage, and reduce manual DBA backup effort.
