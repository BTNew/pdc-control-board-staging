[CmdletBinding()] param(
 [string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging",
 [Parameter(Mandatory=$true)][string]$AdapterSource,
 [Parameter(Mandatory=$true)][string]$ExpectedAdapterSha256
)
$ErrorActionPreference='Stop'
$expectedVersion='2026.08.44'
$expectedRelease='pdc-monitor-staging-m502-2026.08.44'
$adapterName='pdc-authenticated-monitor-runtime-adapter.py'
$anchorName='AUTHENTICATED_RUNTIME_ADAPTER_SHA256'
function Fail([string]$Message){throw $Message}
function Hash([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){Fail "Missing file: $Path"};return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Assert-NoReparse([string]$Path,[string]$Label){$probe=[System.IO.Path]::GetFullPath($Path);while(-not[string]::IsNullOrWhiteSpace($probe)){if(Test-Path -LiteralPath $probe){$item=Get-Item -LiteralPath $probe -Force;if(($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){Fail "$Label contains a reparse point."}};$parent=[System.IO.Path]::GetDirectoryName($probe);if([string]::IsNullOrWhiteSpace($parent)-or$parent -eq $probe){break};$probe=$parent}}
function Assert-Source([string]$Path,[string]$Expected,[string]$Label){$full=[System.IO.Path]::GetFullPath($Path);if(-not[System.IO.Path]::IsPathRooted($full)){Fail "$Label must be absolute."};Assert-NoReparse $full $Label;$root=[System.IO.Path]::GetFullPath($InstallRoot).TrimEnd('\');if($full.StartsWith($root+'\',[System.StringComparison]::OrdinalIgnoreCase)){Fail "$Label must remain outside the protected install root."};if((Hash $full) -ne $Expected.ToLowerInvariant()){Fail "$Label hash mismatch."};return $full}
function Protect-File([string]$Path){& icacls.exe $Path '/inheritance:r' '/grant:r' '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' '*S-1-5-19:(RX)'|Out-Null;if($LASTEXITCODE -ne 0){Fail "icacls failed for $Path"}}
$source=Assert-Source $AdapterSource $ExpectedAdapterSha256 'External authenticated runtime adapter'
$current=Join-Path $InstallRoot 'CURRENT';if((Get-Content -LiteralPath $current -Raw).Trim() -ne $expectedVersion){Fail 'Runtime adapter install requires CURRENT 2026.08.44.'}
$release=Join-Path $InstallRoot ("releases\"+$expectedVersion);$trust=Join-Path $InstallRoot ("trust\"+$expectedVersion);$control=Join-Path $InstallRoot ("control\"+$expectedVersion);foreach($path in @($release,$trust,$control)){Assert-NoReparse $path 'Protected .44 runtime root'}
$manifest=Join-Path $release 'release-manifest.json';$sealedHash=(Get-Content -LiteralPath (Join-Path $trust 'MANIFEST_SHA256') -Raw).Trim();if((Hash $manifest) -ne $sealedHash){Fail 'Sealed manifest trust anchor mismatch.'};$metadata=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json;if($metadata.release_name -ne $expectedRelease -or $metadata.release_version -ne $expectedVersion -or $metadata.supported_migration_head -ne 503){Fail 'Installed sealed .44 release binding mismatch.'}
$target=Join-Path $control $adapterName;$anchor=Join-Path $trust $anchorName;Copy-Item -LiteralPath $source -Destination $target -Force;Protect-File $target;Set-Content -LiteralPath $anchor -Value $ExpectedAdapterSha256.ToLowerInvariant() -Encoding ascii -NoNewline;Protect-File $anchor
if((Hash $manifest) -ne $sealedHash){Fail 'Sealed .44 release bytes changed during adapter install.'}
[pscustomobject]@{ok=$true;adapter_installed=$target;anchor=$anchor;release=$expectedRelease;sealed_release_unchanged=$true;task_enabled=$false;task_started=$false;mailbox_contacted=$false;production_contacted=$false}|ConvertTo-Json -Compress
