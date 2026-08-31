[CmdletBinding()] param([string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging")
$ErrorActionPreference='Stop'
$current=Join-Path $InstallRoot 'CURRENT'
if(-not(Test-Path -LiteralPath $current -PathType Leaf)){throw 'CURRENT pointer is missing.'}
$version=(Get-Content -LiteralPath $current -Raw).Trim()
if($version -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$'){throw 'CURRENT pointer is invalid.'}
$runner=Join-Path $InstallRoot ("control\"+$version+'\run-current.ps1')
if(-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw 'Release control runner is missing.'}
& $runner -InstallRoot $InstallRoot
exit $LASTEXITCODE
