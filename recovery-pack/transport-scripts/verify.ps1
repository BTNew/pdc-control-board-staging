[CmdletBinding()] param(
 [string]$BundleRoot=(Split-Path -Parent $PSScriptRoot),
 [Parameter(Mandatory=$true)][string]$ExpectedManifestSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedSourceSha,
 [Parameter(Mandatory=$true)][string]$ExpectedSourceTree,
 [Parameter(Mandatory=$true)][string]$ExpectedStagingSha,
 [Parameter(Mandatory=$true)][string]$ExpectedGatewayInstanceId,
 [Parameter(Mandatory=$true)][string]$ExpectedReleaseName,
 [Parameter(Mandatory=$true)][string]$ExpectedReleaseVersion,
 [Parameter(Mandatory=$true)][string]$ExpectedBuiltAtUtc,
 [Parameter(Mandatory=$true)][string]$ExpectedBundleHashDefinition
)
$ErrorActionPreference='Stop'
$python=(Get-Command python.exe -ErrorAction Stop).Source
& $python (Join-Path $BundleRoot 'verify_release.py') --bundle $BundleRoot --expected-manifest-sha256 $ExpectedManifestSha256 --expected-source-sha $ExpectedSourceSha --expected-source-tree $ExpectedSourceTree --expected-staging-sha $ExpectedStagingSha --expected-gateway-instance-id $ExpectedGatewayInstanceId --expected-release-name $ExpectedReleaseName --expected-release-version $ExpectedReleaseVersion --expected-built-at-utc $ExpectedBuiltAtUtc --expected-bundle-hash-definition $ExpectedBundleHashDefinition
if($LASTEXITCODE -ne 0){throw 'Release verification failed closed.'}
