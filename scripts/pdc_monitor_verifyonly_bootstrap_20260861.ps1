[CmdletBinding()]
param([string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging")
$ErrorActionPreference='Stop';$ExpectedVersion='2026.08.61';$control=Join-Path $InstallRoot ("control\"+$ExpectedVersion);$trust=Join-Path $InstallRoot ("trust\"+$ExpectedVersion);$runner=Join-Path $control 'run-current-verifyonly.ps1';$anchor=Join-Path $trust 'VERIFYONLY_RUNNER_SHA256'
function Hash([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'PDC_MONITOR_SUCCESSOR_VERIFYONLY_BOOTSTRAP_MISSING'};return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
if((Get-Content -LiteralPath (Join-Path $InstallRoot 'CURRENT') -Raw).Trim()-ne$ExpectedVersion){throw 'PDC_MONITOR_SUCCESSOR_VERIFYONLY_BOOTSTRAP_CURRENT_MISMATCH'}
if((Hash $runner)-ne(Get-Content -LiteralPath $anchor -Raw).Trim().ToLowerInvariant()){throw 'PDC_MONITOR_SUCCESSOR_VERIFYONLY_BOOTSTRAP_RUNNER_HASH_MISMATCH'}
& $runner -InstallRoot $InstallRoot;exit $LASTEXITCODE
