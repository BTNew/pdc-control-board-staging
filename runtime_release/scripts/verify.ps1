[CmdletBinding()] param([string]$BundleRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$python=(Get-Command python.exe -ErrorAction Stop).Source
& $python (Join-Path $BundleRoot 'verify_release.py') --bundle $BundleRoot
if($LASTEXITCODE -ne 0){throw 'Release verification failed closed.'}
