# Disaster Recovery Plan

This plan describes a practical recovery workflow for an Oracle database protected by OracleShieldBackup.

## Recovery Objectives

Set these values with the business owner before production rollout:

| Objective | Target |
| --- | --- |
| RPO | Depends on archive backup frequency. Default schedule targets up to 4 hours of redo exposure. |
| RTO | Depends on database size, S3 download speed, and restore host capacity. |
| Backup retention | Default local retention is 14 days. S3 lifecycle should match business and compliance needs. |

## Routine Validation

The scheduled `validate_backup.sh` job runs RMAN restore validation:

```bash
/opt/oracle-shield-backup/scripts/validate_backup.sh
```

This checks that RMAN can find and read the backup pieces required for restore without overwriting database files.

## Recovery Steps

1. Provision or repair an Oracle host with the same Oracle major version.
2. Install AWS CLI and configure access to the backup bucket.
3. Restore the OracleShieldBackup project and edit `config/backup.conf` for the recovery host.
4. Download the required backup pieces from S3:

```bash
aws s3 sync s3://replace-me-oracle-backups/ORCLCDB/database/full/20260523 /u02/oracle_backups/rman/ORCLCDB/full/20260523
aws s3 sync s3://replace-me-oracle-backups/ORCLCDB/database/incremental/20260523 /u02/oracle_backups/rman/ORCLCDB/incremental/20260523
aws s3 sync s3://replace-me-oracle-backups/ORCLCDB/archivelog/20260523 /u02/oracle_backups/archivelog/ORCLCDB/archive/20260523
```

5. Start the instance in the appropriate recovery state.
6. Catalog downloaded backup pieces if RMAN does not already know them:

```rman
CATALOG START WITH '/u02/oracle_backups/rman/ORCLCDB/';
CATALOG START WITH '/u02/oracle_backups/archivelog/ORCLCDB/';
```

7. Restore and recover with RMAN according to the outage scenario:

```rman
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN;
```

For incomplete recovery, recover to a known timestamp or SCN, then open with `RESETLOGS` only after DBA approval.

## Controlled Restore Test

Do not run destructive restore commands on the production host. Use an isolated recovery server or Oracle duplicate database workflow. The included `restore_test.sh` intentionally defaults to `RESTORE DATABASE VALIDATE` to prove recovery readiness without writing datafiles.

## Post-Recovery Checks

- Confirm application connectivity.
- Review Oracle alert logs.
- Confirm latest business transactions.
- Run application-level smoke tests.
- Record outage timeline, restore duration, data loss window, and follow-up actions.

