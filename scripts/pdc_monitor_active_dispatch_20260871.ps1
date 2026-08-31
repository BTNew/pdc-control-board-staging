[CmdletBinding()]
param([string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging",[switch]$DryRun)
$ErrorActionPreference='Stop'
$Version='2026.08.71'
$CurrentHead='20260831380000'
$ProjectRef='cdsmnqxtyyoeoznmbidd'
$root=[IO.Path]::GetFullPath($InstallRoot)
if(-not $root.EndsWith('\PDCMonitor\Staging',[StringComparison]::OrdinalIgnoreCase)){ throw 'PDC_MONITOR_071_EXACT_ROOT_REQUIRED' }
$current=(Get-Content -LiteralPath (Join-Path $root 'CURRENT') -Raw).Trim()
if($current -ne $Version){ throw 'PDC_MONITOR_071_CURRENT_MISMATCH' }
$release=Join-Path $root "releases\$Version"
$venv=Join-Path $root "venvs\$Version"
$state=Join-Path $root 'state\monitor'
$preflight=Join-Path $root "control\$Version\current-head-preflight.py"
$python=Join-Path $venv 'Scripts\python.exe'
$status=Join-Path $state 'active-dispatch-status.json'
New-Item -ItemType Directory -Path $state -Force | Out-Null
function Write-Status([bool]$Ok,[string]$Code,[string]$Phase,[bool]$Mailbox){
  $payload=[ordered]@{ok=$Ok;status=($(if($Ok){'ok'}else{'failed'}));code=$Code;release_version=$Version;current_staging_migration_head=$CurrentHead;project_ref=$ProjectRef;phase=$Phase;monitor_entrypoint_reached=$Ok;active_dispatch_blocked=(-not $Ok);mailbox_contacted=$Mailbox;uid514_processed=$false;production_contacted=$false;task_enabled=$false;last_cycle=([DateTime]::UtcNow.ToString('o'))}
  $payload | ConvertTo-Json -Compress | Set-Content -LiteralPath $status -Encoding ascii -NoNewline
}
try {
  & $python -B -I -S $preflight --install-root $root --release-root $release --venv-root $venv --expected-head $CurrentHead
  if($LASTEXITCODE -ne 0){ throw 'PDC_MONITOR_071_PREFLIGHT_FAILED' }
  if($DryRun){ Write-Status $true 'PDC_MONITOR_071_DRY_RUN_NO_MAILBOX' 'active_dispatch_boundary' $false; exit 0 }
  $launcher=Join-Path $release 'runtime_launcher.py'
  if(-not (Test-Path -LiteralPath $launcher -PathType Leaf)){ throw 'PDC_MONITOR_071_LAUNCHER_MISSING' }
  Write-Status $true 'PDC_MONITOR_071_REACHED_MONITOR' 'monitor_entrypoint' $true
  & $python -B -I -S $launcher --release-root $release --venv-root $venv --mode monitor
  if($LASTEXITCODE -ne 0){ throw 'PDC_MONITOR_071_MONITOR_FAILED' }
  Write-Output '{"ok":true,"release":"2026.08.71","current_staging_migration_head":"20260831380000","mailbox_contacted":true,"production_contacted":false}'
  exit 0
} catch {
  Write-Status $false 'PDC_MONITOR_071_DENIED' 'active_dispatch' $false
  [Console]::Error.WriteLine('PDC_MONITOR_071_DENIED')
  exit 1
}
