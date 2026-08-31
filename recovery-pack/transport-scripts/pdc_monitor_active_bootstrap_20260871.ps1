[CmdletBinding()]
param([string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging",[switch]$DryRun)
$ErrorActionPreference='Stop'
$Version='2026.08.71'
$CurrentHead='20260831380000'
$root=[IO.Path]::GetFullPath($InstallRoot)
$dispatch=Join-Path $root "control\$Version\active-dispatch.ps1"
if(-not (Test-Path -LiteralPath $dispatch -PathType Leaf)){ throw 'PDC_MONITOR_071_BOOTSTRAP_DISPATCH_MISSING' }
& $dispatch -InstallRoot $root -DryRun:$DryRun
exit $LASTEXITCODE
