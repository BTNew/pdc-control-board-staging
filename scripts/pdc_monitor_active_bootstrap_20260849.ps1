[CmdletBinding()]
param([string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging",[switch]$DryRun)
$ErrorActionPreference='Stop';$ExpectedVersion='2026.08.49';$control=Join-Path $InstallRoot ("control\"+$ExpectedVersion);$trust=Join-Path $InstallRoot ("trust\"+$ExpectedVersion);$dispatch=Join-Path $control 'run-current-active.ps1';$anchor=Join-Path $trust 'ACTIVE_DISPATCH_SHA256'
function Hash([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'PDC_MONITOR_SUCCESSOR_ACTIVE_BOOTSTRAP_DISPATCH_MISSING'};return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
if((Get-Content -LiteralPath (Join-Path $InstallRoot 'CURRENT') -Raw).Trim()-ne$ExpectedVersion){throw 'PDC_MONITOR_SUCCESSOR_ACTIVE_BOOTSTRAP_CURRENT_MISMATCH'}
if((Hash $dispatch)-ne(Get-Content -LiteralPath $anchor -Raw).Trim().ToLowerInvariant()){throw 'PDC_MONITOR_SUCCESSOR_ACTIVE_BOOTSTRAP_DISPATCH_HASH_MISMATCH'}
if($DryRun){& $dispatch -InstallRoot $InstallRoot -Mode OneCycle -DryRun}else{& $dispatch -InstallRoot $InstallRoot -Mode OneCycle};exit $LASTEXITCODE
