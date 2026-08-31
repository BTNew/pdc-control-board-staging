[CmdletBinding()]
param([string]$BundleRoot,[string]$HandoffRoot=(Split-Path -Parent $MyInvocation.MyCommand.Path))
$ErrorActionPreference='Stop';$Version='2026.08.69';$Installer=Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'install_pdc_monitor_successor_20260869.ps1';$Receipt=Join-Path $HandoffRoot 'pdc-monitor-20260869-launch-receipt.json'
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()};function Write-Receipt([object]$v){$v|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Receipt -Encoding utf8}
try{
 if(-not $BundleRoot){throw 'BundleRoot is required'};$manifest=Join-Path $BundleRoot 'release-manifest.json';if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'bundle manifest missing'};$m=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
 $record=[ordered]@{schema_version=1;release=$Version;bundle_root=[IO.Path]::GetFullPath($BundleRoot);manifest_sha256=Hash $manifest;installer=$Installer;installer_sha256=Hash $Installer;uac_requested=$false;task_enable_requested=$false;mailbox_contacted=$false;production_contacted=$false;secrets_printed=$false;rollback='Run scripts\rollback_pdc_monitor_successor_20260869.ps1 -InstallRoot C:\ProgramData\PDCMonitor\Staging'}
 Write-Receipt $record
 # This is the prepared launcher path; unattended callers must not invoke it.
 $record.uac_required=$true;$record.human_action="Run this launcher interactively once to approve UAC: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -BundleRoot `"$BundleRoot`"";Write-Receipt $record;Write-Output ($record|ConvertTo-Json -Compress);exit 1223
}catch{$record=[ordered]@{ok=$false;release=$Version;error=$_.Exception.Message;uac_requested=$false;task_enable_requested=$false;mailbox_contacted=$false;production_contacted=$false;secrets_printed=$false};Write-Receipt $record;exit 1}
