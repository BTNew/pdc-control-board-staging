[CmdletBinding()] param(
 [string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging",
 [Parameter(Mandatory=$true)][string]$PreflightSource,
 [Parameter(Mandatory=$true)][string]$AdapterSource,
 [Parameter(Mandatory=$true)][string]$DispatchSource,
 [Parameter(Mandatory=$true)][string]$BootstrapSource,
 [Parameter(Mandatory=$true)][string]$ExpectedPreflightSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedAdapterSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedDispatchSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedBootstrapSha256
)
$ErrorActionPreference='Stop'
$expectedVersion='2026.08.44';$expectedRelease='pdc-monitor-staging-m502-2026.08.44'
function Fail([string]$Message){throw $Message}
function Hash([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){Fail "Missing file: $Path"};return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Assert-NoReparse([string]$Path,[string]$Label){$probe=[System.IO.Path]::GetFullPath($Path);while(-not[string]::IsNullOrWhiteSpace($probe)){if(Test-Path -LiteralPath $probe){$item=Get-Item -LiteralPath $probe -Force;if(($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){Fail "$Label contains a reparse point."}};$parent=[System.IO.Path]::GetDirectoryName($probe);if([string]::IsNullOrWhiteSpace($parent)-or$parent -eq $probe){break};$probe=$parent}}
function Assert-Source([string]$Path,[string]$Expected,[string]$Label){$full=[System.IO.Path]::GetFullPath($Path);if(-not[System.IO.Path]::IsPathRooted($full)){Fail "$Label must be absolute."};Assert-NoReparse $full $Label;$install=[System.IO.Path]::GetFullPath($InstallRoot).TrimEnd('\');if($full.StartsWith($install+'\',[System.StringComparison]::OrdinalIgnoreCase)){Fail "$Label must remain outside the protected install root."};if((Hash $full) -ne $Expected.ToLowerInvariant()){Fail "$Label hash mismatch."};return $full}
function Protect-File([string]$Path){& icacls.exe $Path '/inheritance:r' '/grant:r' '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' '*S-1-5-19:(RX)'|Out-Null;if($LASTEXITCODE -ne 0){Fail "icacls failed for $Path"}}
$preflight=Assert-Source $PreflightSource $ExpectedPreflightSha256 'Authenticated mailbox preflight successor';$adapter=Assert-Source $AdapterSource $ExpectedAdapterSha256 'External authenticated runtime adapter';$dispatch=Assert-Source $DispatchSource $ExpectedDispatchSha256 'Authenticated monitor dispatch runner';$bootstrap=Assert-Source $BootstrapSource $ExpectedBootstrapSha256 'Authenticated monitor dispatch bootstrap'
$current=Join-Path $InstallRoot 'CURRENT';if((Get-Content -LiteralPath $current -Raw).Trim() -ne $expectedVersion){Fail 'Dispatch install requires CURRENT 2026.08.44.'}
$release=Join-Path $InstallRoot ("releases\"+$expectedVersion);$trust=Join-Path $InstallRoot ("trust\"+$expectedVersion);$control=Join-Path $InstallRoot ("control\"+$expectedVersion);foreach($path in @($release,$trust,$control)){Assert-NoReparse $path 'Protected .44 runtime root'}
$manifest=Join-Path $release 'release-manifest.json';$sealedHash=(Get-Content -LiteralPath (Join-Path $trust 'MANIFEST_SHA256') -Raw).Trim();if((Hash $manifest) -ne $sealedHash){Fail 'Sealed manifest trust anchor mismatch.'};$metadata=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json;if($metadata.release_name -ne $expectedRelease -or $metadata.release_version -ne $expectedVersion -or $metadata.supported_migration_head -ne 503){Fail 'Installed sealed .44 release binding mismatch.'}
$sealed=Join-Path $control 'run-current-sealed.ps1';$sealedExpected=[string]$metadata.files.PSObject.Properties['scripts/run-current.ps1'].Value.sha256;if(-not(Test-Path -LiteralPath $sealed -PathType Leaf) -or (Hash $sealed) -ne $sealedExpected){Fail 'Preserved sealed .44 runner is missing or changed.'}
$targets=@{
 'active-preflight-authenticated-mailbox-compatibility.py'=$preflight;
 'pdc-authenticated-monitor-runtime-adapter.py'=$adapter;
 'run-current.ps1'=$dispatch;
}
foreach($name in $targets.Keys){$target=Join-Path $control $name;Copy-Item -LiteralPath $targets[$name] -Destination $target -Force;Protect-File $target}
$rootBootstrap=Join-Path $InstallRoot 'control\bootstrap.ps1';Copy-Item -LiteralPath $bootstrap -Destination $rootBootstrap -Force;Protect-File $rootBootstrap
$anchors=@{
 'AUTHENTICATED_MAILBOX_PREFLIGHT_SHA256'=$ExpectedPreflightSha256.ToLowerInvariant();
 'AUTHENTICATED_RUNTIME_ADAPTER_SHA256'=$ExpectedAdapterSha256.ToLowerInvariant();
 'AUTHENTICATED_DISPATCH_RUNNER_SHA256'=$ExpectedDispatchSha256.ToLowerInvariant();
 'AUTHENTICATED_DISPATCH_BOOTSTRAP_SHA256'=$ExpectedBootstrapSha256.ToLowerInvariant();
 'SEALED_RUN_CURRENT_SHA256'=$sealedExpected.ToLowerInvariant();
 'SEALED_RUNTIME_LAUNCHER_SHA256'=$metadata.files.PSObject.Properties['runtime_launcher.py'].Value.sha256.ToLowerInvariant()
}
foreach($name in $anchors.Keys){$anchor=Join-Path $trust $name;Set-Content -LiteralPath $anchor -Value $anchors[$name] -Encoding ascii -NoNewline;Protect-File $anchor}
if((Hash $manifest) -ne $sealedHash -or (Hash $sealed) -ne $sealedExpected){Fail 'Sealed .44 bytes changed during dispatch install.'}
[pscustomobject]@{ok=$true;preflight_installed=(Join-Path $control 'active-preflight-authenticated-mailbox-compatibility.py');adapter_installed=(Join-Path $control 'pdc-authenticated-monitor-runtime-adapter.py');runner_installed=(Join-Path $control 'run-current.ps1');bootstrap_installed=$rootBootstrap;sealed_runner=$sealed;release=$expectedRelease;sealed_release_unchanged=$true;task_enabled=$false;task_started=$false;mailbox_contacted=$false;uid514_processed=$false;production_contacted=$false}|ConvertTo-Json -Compress
