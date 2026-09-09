# scheduled_refresh_flujo.ps1
# Corrida programada del dashboard Flujo de Fondos.
# Ejecuta la ingesta de Excel a SQL y regenera el data.json.
# Log rotativo a logs\flujo_fondos_YYYY-MM.log
#
# Registrar en Task Scheduler (una vez desde una consola PS como admin):
#   $repo   = 'C:\Users\marco\OneDrive\Documentos\Desarrollos Claude\Sql Señales'
#   $script = "$repo\scripts\scheduled_refresh_flujo.ps1"
#   $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
#             -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`"" `
#             -WorkingDirectory $repo
#   $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddHours(8) `
#              -RepetitionInterval (New-TimeSpan -Hours 2) `
#              -RepetitionDuration (New-TimeSpan -Hours 14)
#   Register-ScheduledTask -TaskName 'FlujoFondos-Refresh' -Action $action -Trigger $trigger `
#     -Description 'Refresca ingesta Excel + data.json del dashboard de flujo de fondos'
#
# Verificar:
#   Get-ScheduledTask -TaskName 'FlujoFondos-Refresh' | Get-ScheduledTaskInfo
#   Start-ScheduledTask -TaskName 'FlujoFondos-Refresh'

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo    = Split-Path $PSScriptRoot -Parent
$export  = Join-Path $repo 'flujo-fondos-dashboard\export_data.ps1'
$logDir  = Join-Path $repo 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("flujo_fondos_" + (Get-Date -Format 'yyyy-MM') + ".log")

function Write-Log { param([string]$msg) Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" -Encoding UTF8 }

Write-Log "── Inicio refresh ──"
try {
    $out = & $export 2>&1 | Out-String
    Write-Log $out.TrimEnd()
    Write-Log "── OK ──`n"
    exit 0
} catch {
    Write-Log ("ERROR: " + $_.Exception.Message)
    Write-Log $_.ScriptStackTrace
    Write-Log "── FALLÓ ──`n"
    exit 1
}
