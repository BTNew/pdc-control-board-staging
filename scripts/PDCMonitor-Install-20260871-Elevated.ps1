[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallRoot='C:\ProgramData\PDCMonitor\Staging'
$Bundle=Join-Path $Root 'pdc-monitor-staging-m502-2026.08.71'
$Installer=Join-Path $Bundle 'installer\install_pdc_monitor_successor_20260871.ps1'
$Manifest=(Get-Content (Join-Path $Bundle 'release-manifest.json') -Raw -Encoding utf8 | ConvertFrom-Json)
$ExpectedManifest=(Get-FileHash (Join-Path $Bundle 'release-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
$ExpectedParent=[string]$Manifest.parent_manifest_sha256
$Receipt=Join-Path $Root 'install-receipt.json'
try {
  $output=@(& $Installer -InstallRoot $InstallRoot -BundleRoot $Bundle -ExpectedManifestSha256 $ExpectedManifest -ExpectedParentManifestSha256 $ExpectedParent 2>&1)
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
