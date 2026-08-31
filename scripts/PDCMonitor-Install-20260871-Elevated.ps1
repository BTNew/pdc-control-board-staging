[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallRoot='C:\ProgramData\PDCMonitor\Staging'
$Bundle=Join-Path $Root 'pdc-monitor-staging-m502-2026.08.71'
$Installer=Join-Path $Bundle 'installer\install_pdc_monitor_successor_20260871.ps1'
$ExpectedManifestSha256='13f3affa82e334195b93126c09764c29b50da55e2339642063c2e94d22811c1f'
$ExpectedParent='fa528d8d1ce405b430dc265ded7dca69cc7b49e8d190b90d9e55576b32a1a823'
$InstallerSha256='476b47b99b8e982424bc9516e6c4337d6d91eb8bd5433ce07b6fef2f7ee95e21'
$Receipt=Join-Path $Root 'install-receipt.json'
function Hash([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'PDC_MONITOR_071_HASH_INPUT_MISSING'};(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
try {
  if((Hash (Join-Path $Bundle 'release-manifest.json')) -ne $ExpectedManifestSha256){throw 'PDC_MONITOR_071_MANIFEST_HASH_MISMATCH'}
  if((Hash $Installer) -ne $InstallerSha256){throw 'PDC_MONITOR_071_INSTALLER_HASH_MISMATCH'}
  $output=@(& $Installer -InstallRoot $InstallRoot -BundleRoot $Bundle -ExpectedManifestSha256 $ExpectedManifestSha256 -ExpectedParentManifestSha256 $ExpectedParent 2>&1)
  $exit=$LASTEXITCODE
  $jsonLine=$output | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
  if($exit -ne 0 -or -not $jsonLine){ throw 'PDC_MONITOR_071_ELEVATED_INSTALL_FAILED' }
  $result=$jsonLine | ConvertFrom-Json
  if($result.ok -ne $true -or $result.task_enabled -ne $false -or $result.task_started -ne $false){ throw 'PDC_MONITOR_071_ELEVATED_INSTALL_ASSERTION_FAILED' }
  $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Receipt -Encoding utf8
  exit 0
} catch {
  [ordered]@{ok=$false;error='PDC_MONITOR_071_ELEVATED_INSTALL_FAILED';detail=$_.Exception.Message;task_enabled=$false;task_started=$false;mailbox_contacted=$false;production_contacted=$false;secrets_printed=$false}|ConvertTo-Json -Compress|Set-Content -LiteralPath $Receipt -Encoding utf8
  exit 1
}
