param(
    [ValidateSet("up", "status", "logs", "full", "incremental", "archive", "validate", "restore-test", "cleanup", "report", "shell", "down")]
    [string]$Command = "status"
)

$ErrorActionPreference = "Stop"

$Service = "oracle-db"
$ContainerConfig = "/opt/oracle/oracle-shield/config/docker-demo.conf"
$ScriptRootInContainer = "/opt/oracle/oracle-shield/scripts"

function Invoke-DockerCompose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & docker compose @Args
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed with exit code $LASTEXITCODE"
    }
}

function Invoke-BackupScript {
    param([string]$ScriptName)
    Invoke-DockerCompose exec $Service bash -lc "BACKUP_CONFIG=$ContainerConfig bash $ScriptRootInContainer/$ScriptName"
}

switch ($Command) {
    "up" {
        Invoke-DockerCompose up -d
        Invoke-DockerCompose ps
    }
    "status" {
        Invoke-DockerCompose ps
    }
    "logs" {
        Invoke-DockerCompose logs --tail 80 -f $Service
    }
    "full" {
        Invoke-BackupScript "full_backup.sh"
    }
    "incremental" {
        Invoke-BackupScript "incremental_backup.sh"
    }
    "archive" {
        Invoke-BackupScript "archive_backup.sh"
    }
    "validate" {
        Invoke-BackupScript "validate_backup.sh"
    }
    "restore-test" {
        Invoke-BackupScript "restore_test.sh"
    }
    "cleanup" {
        Invoke-BackupScript "cleanup_old_backups.sh"
    }
    "report" {
        Invoke-BackupScript "generate_report.sh"
    }
    "shell" {
        Invoke-DockerCompose exec $Service bash
    }
    "down" {
        Invoke-DockerCompose down
    }
}

