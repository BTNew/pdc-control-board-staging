[CmdletBinding()]
param([string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging",[ValidateSet('OneCycle','Continuous')][string]$Mode='OneCycle',[switch]$DryRun)
$ErrorActionPreference='Stop';$v='2026.08.66';$c=Join-Path $InstallRoot "control\$v";& (Join-Path $c 'run-current-active.ps1') -InstallRoot $InstallRoot -Mode $Mode -DryRun:$DryRun;exit $LASTEXITCODE
