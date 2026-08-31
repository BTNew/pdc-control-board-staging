[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$Elevated=Join-Path $Root 'PDCMonitor-Install-20260869-Elevated.ps1'
$Bundle=Join-Path $Root 'pdc-monitor-staging-m502-2026.08.69'
$Manifest='fa528d8d1ce405b430dc265ded7dca69cc7b49e8d190b90d9e55576b32a1a823'
$Receipt=Join-Path $Root 'install-receipt.json'
$LaunchRecord=Join-Path $Root 'launch-record.json'
$mutex=New-Object System.Threading.Mutex($false,'Global\PDCMonitorStagingReceiptLauncher769')
$held=$false
function Write-Json([string]$Path,[object]$Value){$tmp=$Path+'.tmp';$Value|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $tmp -Encoding utf8;Move-Item -LiteralPath $tmp -Destination $Path -Force}
try {
  $held=$mutex.WaitOne(0);if(-not $held){throw 'PDC_MONITOR_769_LAUNCH_OVERLAP'}
  if(-not(Test-Path -LiteralPath $Elevated -PathType Leaf)){throw 'PDC_MONITOR_769_ELEVATED_STAGE_MISSING'}
  if(-not(Test-Path -LiteralPath (Join-Path $Bundle 'release-manifest.json') -PathType Leaf)){throw 'PDC_MONITOR_769_BUNDLE_MISSING'}
  if((Get-FileHash -LiteralPath (Join-Path $Bundle 'release-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Manifest){throw 'PDC_MONITOR_769_MANIFEST_CHANGED'}
  $record=[ordered]@{schema_version=1;wrapper='pdc-monitor-20260869-receipt-wrapper';started_utc=[DateTime]::UtcNow.ToString('o');wrapper_pid=$PID;session_id=(Get-Process -Id $PID).SessionId;interactive=[Environment]::UserInteractive;release='2026.08.69';bundle_root=$Bundle;expected_manifest_sha256=$Manifest;uac_requested=$true;task_enable_requested=$false;mailbox_contacted=$false;production_contacted=$false;secrets_printed=$false}
  Write-Json $LaunchRecord $record
  if(Test-Path -LiteralPath $Receipt -PathType Leaf){Move-Item -LiteralPath $Receipt -Destination (Join-Path $Root ('install-receipt.previous-'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss')+'.json')) -Force}
  try {
    $child=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$Elevated) -WorkingDirectory $Root -WindowStyle Normal -Verb RunAs -PassThru -Wait
    $record.child_pid=$child.Id;$record.child_exit_code=$child.ExitCode;$record.child_completed=$true
    Write-Json $LaunchRecord $record
  } catch {
    $record.child_completed=$false;$record.child_exit_code=1223;$record.error='UAC_CANCELLED_OR_ELEVATED_STAGE_NOT_STARTED'
    Write-Json $LaunchRecord $record
  }
  if(-not(Test-Path -LiteralPath $Receipt -PathType Leaf)){$record.ok=$false;$record.finished_utc=[DateTime]::UtcNow.ToString('o');Write-Json $Receipt $record}
  exit [int]$record.child_exit_code
} catch {
  Write-Json $Receipt ([ordered]@{schema_version=1;wrapper='pdc-monitor-20260869-receipt-wrapper';ok=$false;finished_utc=[DateTime]::UtcNow.ToString('o');error=$_.Exception.Message;uac_requested=$false;task_enable_requested=$false;mailbox_contacted=$false;production_contacted=$false;secrets_printed=$false});exit 1
} finally {if($held){$mutex.ReleaseMutex()|Out-Null};$mutex.Dispose()}
