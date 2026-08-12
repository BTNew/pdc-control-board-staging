[CmdletBinding()] param([string]$BundleRoot=(Split-Path -Parent $PSScriptRoot),[Parameter(Mandatory=$true)][string]$ExpectedManifestSha256)
$ErrorActionPreference='Stop'
$python=(Get-Command python.exe -ErrorAction Stop).Source
& $python (Join-Path $BundleRoot 'verify_release.py') --bundle $BundleRoot --expected-manifest-sha256 $ExpectedManifestSha256
if($LASTEXITCODE -ne 0){throw 'Release verification failed closed.'}
