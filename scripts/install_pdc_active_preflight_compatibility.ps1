[CmdletBinding()] param(
 [string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging",
 [Parameter(Mandatory=$true)][string]$CompatibilitySource,
 [Parameter(Mandatory=$true)][string]$RunnerSource,
 [Parameter(Mandatory=$true)][string]$ExpectedCompatibilitySha256,
 [Parameter(Mandatory=$true)][string]$ExpectedRunnerSha256
)
$ErrorActionPreference='Stop'
$expectedVersion='2026.08.44';$expectedRelease='pdc-monitor-staging-m502-2026.08.44'
$expectedPlanner='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'
$expectedTrust='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'
$compatibilityName='active-preflight-compatibility.py';$anchorName='ACTIVE_PREFLIGHT_COMPATIBILITY_SHA256'
$mutex=New-Object System.Threading.Mutex($false,'Global\PDCMonitorStagingCompatibilityInstall');$mutexHeld=$false;$changed=@();$oldRunner=$null;$oldAnchor=$null;$oldAnchorExists=$false;$oldCompatibility=$null;$oldCompatibilityExists=$false;$sealedRunnerCreated=$false;$compatibilityTouched=$false;$anchorTouched=$false;$runnerTouched=$false
function Fail([string]$Message){throw $Message}
function Hash([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){Fail "Missing file: $Path"};return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Assert-NoReparse([string]$Path,[string]$Label){$probe=[System.IO.Path]::GetFullPath($Path);while(-not[string]::IsNullOrWhiteSpace($probe)){if(Test-Path -LiteralPath $probe){$item=Get-Item -LiteralPath $probe -Force;if(($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){Fail "$Label contains a reparse point."}};$parent=[System.IO.Path]::GetDirectoryName($probe);if([string]::IsNullOrWhiteSpace($parent)-or$parent -eq $probe){break};$probe=$parent}}
function Assert-ExactSource([string]$Path,[string]$Expected,[string]$Label){$full=[System.IO.Path]::GetFullPath($Path);Assert-NoReparse $full $Label;if(-not([System.IO.Path]::IsPathRooted($full))){Fail "$Label must be absolute."};$installFull=[System.IO.Path]::GetFullPath($InstallRoot).TrimEnd('\');if($full.StartsWith($installFull+'\',[System.StringComparison]::OrdinalIgnoreCase)){Fail "$Label must be outside the install root."};if((Hash $full) -ne $Expected.ToLowerInvariant()){Fail "$Label hash mismatch."};return $full}
function Assert-FileAcl([string]$Path,[string]$Label){$acl=Get-Acl -LiteralPath $Path;if(-not $acl.AreAccessRulesProtected){Fail "$Label ACL inheritance is not protected."};$writers=@('S-1-5-18','S-1-5-32-544');$readers=@('S-1-5-19','S-1-5-18','S-1-5-32-544');$writeMask=[System.Security.AccessControl.FileSystemRights]::WriteData -bor [System.Security.AccessControl.FileSystemRights]::CreateFiles -bor [System.Security.AccessControl.FileSystemRights]::AppendData -bor [System.Security.AccessControl.FileSystemRights]::CreateDirectories -bor [System.Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor [System.Security.AccessControl.FileSystemRights]::WriteAttributes -bor [System.Security.AccessControl.FileSystemRights]::Delete -bor [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor [System.Security.AccessControl.FileSystemRights]::TakeOwnership;$localServiceRead=$false;foreach($rule in $acl.Access){$sid=$rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value;if($rule.AccessControlType -eq 'Allow' -and (($rule.FileSystemRights -band $writeMask) -ne 0) -and $sid -notin $writers){Fail "$Label grants write authority outside SYSTEM or Administrators."};if($sid -eq 'S-1-5-19' -and $rule.AccessControlType -eq 'Allow' -and (($rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadAndExecute) -eq [System.Security.AccessControl.FileSystemRights]::ReadAndExecute) -and (($rule.FileSystemRights -band $writeMask) -eq 0)){$localServiceRead=$true}};if(-not $localServiceRead){Fail "$Label does not grant LOCAL SERVICE read/execute only."}}
function Protect-File([string]$Path){& icacls.exe $Path '/inheritance:r' '/grant:r' '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' '*S-1-5-19:(RX)'|Out-Null;if($LASTEXITCODE -ne 0){Fail "icacls failed for $Path"};Assert-FileAcl $Path 'Compatibility control file'}
try{
 if(-not $mutex.WaitOne(0)){Fail 'Another compatibility install is active.'};$mutexHeld=$true
 $compat=Assert-ExactSource $CompatibilitySource $ExpectedCompatibilitySha256 'External compatibility successor'
 $runner=Assert-ExactSource $RunnerSource $ExpectedRunnerSha256 'External compatibility runner'
 $current=Join-Path $InstallRoot 'CURRENT';if(-not(Test-Path -LiteralPath $current -PathType Leaf)){Fail 'CURRENT pointer is missing.'};if((Get-Content -LiteralPath $current -Raw).Trim() -ne $expectedVersion){Fail 'Compatibility install requires CURRENT 2026.08.44.'}
 $release=Join-Path $InstallRoot ("releases\"+$expectedVersion);$trust=Join-Path $InstallRoot ("trust\"+$expectedVersion);$control=Join-Path $InstallRoot ("control\"+$expectedVersion)
 foreach($path in @($release,$trust,$control)){Assert-NoReparse $path 'Compatibility install root'}
 $manifestPath=Join-Path $release 'release-manifest.json';$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
 if($manifest.release_name -ne $expectedRelease -or $manifest.release_version -ne $expectedVersion -or $manifest.supported_migration_head -ne 503){Fail 'Installed sealed .44 release binding mismatch.'}
 if((Hash $manifestPath) -ne (Get-Content -LiteralPath (Join-Path $trust 'MANIFEST_SHA256') -Raw).Trim().ToLowerInvariant()){Fail 'Installed sealed manifest trust anchor mismatch.'}
 $planner=Join-Path $trust 'pdc_active_semantic_planner.py';$receipt=Join-Path $trust 'pdc-active-semantic-planner-trust-receipt.json';if((Hash $planner) -ne $expectedPlanner){Fail 'Installed external planner digest mismatch.'};if((Hash $receipt) -ne $expectedTrust){Fail 'Installed external trust receipt digest mismatch.'}
 $targetRunner=Join-Path $control 'run-current.ps1';$sealedRunner=Join-Path $control 'run-current-sealed.ps1';$targetCompat=Join-Path $control $compatibilityName;$anchor=Join-Path $trust $anchorName
 $sealedRunnerHash=[string]$manifest.files.PSObject.Properties['scripts/run-current.ps1'].Value.sha256
 if(Test-Path -LiteralPath $sealedRunner){if((Hash $sealedRunner) -ne $sealedRunnerHash){Fail 'Preserved sealed control runner drifted.'};$currentRunnerHash=Hash $targetRunner;if($currentRunnerHash -ne $sealedRunnerHash -and $currentRunnerHash -ne $ExpectedRunnerSha256){Fail 'Control runner is not an approved sealed or compatibility runner.'}}
 else{if((Hash $targetRunner) -ne $sealedRunnerHash){Fail 'Control runner is not the exact sealed .44 runner; refusing overwrite.'};Copy-Item -LiteralPath $targetRunner -Destination $sealedRunner;Protect-File $sealedRunner;$sealedRunnerCreated=$true}
 if(Test-Path -LiteralPath $anchor){$oldAnchorExists=$true;$oldAnchor=Get-Content -LiteralPath $anchor -Raw}
 if(Test-Path -LiteralPath $targetCompat){$oldCompatibilityExists=$true;$oldCompatibility=Get-Content -LiteralPath $targetCompat -Raw;$existingCompatibilityHash=Hash $targetCompat;if($existingCompatibilityHash -ne $ExpectedCompatibilitySha256 -and (!$oldAnchorExists -or $existingCompatibilityHash -ne $oldAnchor.Trim().ToLowerInvariant())){Fail 'Existing compatibility successor drifted.'}}
 $oldRunner=(Get-Content -LiteralPath $targetRunner -Raw);$oldManifestHash=Hash $manifestPath
 Copy-Item -LiteralPath $compat -Destination $targetCompat -Force;$compatibilityTouched=$true;Protect-File $targetCompat;$changed+=$targetCompat
 Set-Content -LiteralPath $anchor -Value $ExpectedCompatibilitySha256.ToLowerInvariant() -Encoding ascii -NoNewline;$anchorTouched=$true;Protect-File $anchor;$changed+=$anchor
 Copy-Item -LiteralPath $runner -Destination $targetRunner -Force;$runnerTouched=$true;Protect-File $targetRunner;$changed+=$targetRunner
 if((Hash $manifestPath) -ne $oldManifestHash){Fail 'Sealed .44 release bytes changed during compatibility install.'}
 [pscustomobject]@{ok=$true;compatibility_installed=$targetCompat;runner_installed=$targetRunner;sealed_runner_backup=$sealedRunner;anchor=$anchor;release=$expectedRelease;planner_sha256=$expectedPlanner;trust_receipt_sha256=$expectedTrust;sealed_release_unchanged=$true;task_enabled=$false;task_started=$false;mailbox_contacted=$false;production_contacted=$false}|ConvertTo-Json -Compress
} catch {
 if($compatibilityTouched){if($oldCompatibilityExists -and $oldCompatibility -ne $null){Set-Content -LiteralPath (Join-Path $InstallRoot 'control\2026.08.44\active-preflight-compatibility.py') -Value $oldCompatibility -Encoding utf8 -NoNewline;Protect-File (Join-Path $InstallRoot 'control\2026.08.44\active-preflight-compatibility.py')}else{Remove-Item -LiteralPath (Join-Path $InstallRoot 'control\2026.08.44\active-preflight-compatibility.py') -Force -ErrorAction SilentlyContinue}}
 if($runnerTouched -and $oldRunner -ne $null){Set-Content -LiteralPath (Join-Path $InstallRoot 'control\2026.08.44\run-current.ps1') -Value $oldRunner -Encoding utf8 -NoNewline;Protect-File (Join-Path $InstallRoot 'control\2026.08.44\run-current.ps1')}
 if($anchorTouched){if($oldAnchorExists){Set-Content -LiteralPath (Join-Path $InstallRoot 'trust\2026.08.44\ACTIVE_PREFLIGHT_COMPATIBILITY_SHA256') -Value $oldAnchor -Encoding ascii -NoNewline}else{Remove-Item -LiteralPath (Join-Path $InstallRoot 'trust\2026.08.44\ACTIVE_PREFLIGHT_COMPATIBILITY_SHA256') -Force -ErrorAction SilentlyContinue}}
 if($sealedRunnerCreated){Remove-Item -LiteralPath (Join-Path $InstallRoot 'control\2026.08.44\run-current-sealed.ps1') -Force -ErrorAction SilentlyContinue}
 throw
} finally {if($mutexHeld){$mutex.ReleaseMutex();$mutexHeld=$false};$mutex.Dispose()}
