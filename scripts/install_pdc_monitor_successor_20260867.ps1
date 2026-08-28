[CmdletBinding()]
param(
  [string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging",
  [Parameter(Mandatory=$true)][string]$BundleRoot,
  [Parameter(Mandatory=$true)][string]$ExpectedManifestSha256,
  [Parameter(Mandatory=$true)][string]$ExpectedParentManifestSha256
)
$ErrorActionPreference='Stop'
$Version='2026.08.67';$Parent='2026.08.65';$TaskName='PDC-PMB-Email-Monitor-Staging'
$mutex=New-Object System.Threading.Mutex($false,'Global\PDCMonitorStagingAttachmentSuccessorInstall');$held=$false
function Fail([string]$Message){throw $Message}
function Hash([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){Fail 'PDC_MONITOR_ATTACHMENT_SUCCESSOR_MISSING_FILE'};(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function ProtectTree([string]$Path){& icacls.exe $Path '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' '*S-1-5-19:(OI)(CI)(RX)' '/T' '/C'|Out-Null;if($LASTEXITCODE){Fail 'PDC_MONITOR_ATTACHMENT_SUCCESSOR_ACL_FAILED'}}
try{
  $held=$mutex.WaitOne(0);if(-not$held){Fail 'PDC_MONITOR_ATTACHMENT_SUCCESSOR_OVERLAP'}
  $root=[IO.Path]::GetFullPath($InstallRoot);if(-not$root.EndsWith('\PDCMonitor\Staging',[StringComparison]::OrdinalIgnoreCase)){Fail 'PDC_MONITOR_ATTACHMENT_SUCCESSOR_EXACT_ROOT_REQUIRED'}
  $bundle=[IO.Path]::GetFullPath($BundleRoot);if($bundle.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){Fail 'PDC_MONITOR_ATTACHMENT_SUCCESSOR_BUNDLE_MUST_BE_EXTERNAL'}
  if((Hash (Join-Path $bundle 'release-manifest.json')) -ne $ExpectedManifestSha256.ToLowerInvariant()){Fail 'PDC_MONITOR_ATTACHMENT_SUCCESSOR_MANIFEST_HASH_MISMATCH'}
  $task=Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
  if($task.State -ne 'Disabled'){Fail 'PDC_MONITOR_ATTACHMENT_SUCCESSOR_TASK_MUST_REMAIN_DISABLED'}
  if($task.Principal.UserId -ne 'LOCAL SERVICE' -or $task.Principal.RunLevel -ne 'Limited' -or $task.Principal.LogonType -ne 'ServiceAccount'){Fail 'PDC_MONITOR_ATTACHMENT_SUCCESSOR_TASK_IDENTITY_MISMATCH'}
  if(@($task.Triggers|Where-Object{$_.Repetition.Interval -eq 'PT5M'}).Count -eq 0){Fail 'PDC_MONITOR_ATTACHMENT_SUCCESSOR_TASK_TRIGGER_MISMATCH'}
  $current=Join-Path $root 'CURRENT';if((Get-Content -LiteralPath $current -Raw).Trim() -ne $Parent){Fail 'PDC_MONITOR_ATTACHMENT_SUCCESSOR_CURRENT_NOT_065'}
  $parentManifest=Join-Path $root "releases\$Parent\release-manifest.json";if((Hash $parentManifest) -ne $ExpectedParentManifestSha256.ToLowerInvariant()){Fail 'PDC_MONITOR_ATTACHMENT_SUCCESSOR_PARENT_MANIFEST_CHANGED'}
  $target=Join-Path $root "releases\$Version"
  if(Test-Path -LiteralPath $target){if((Hash (Join-Path $target 'release-manifest.json')) -ne $ExpectedManifestSha256.ToLowerInvariant()){Fail 'PDC_MONITOR_ATTACHMENT_SUCCESSOR_EXISTING_TARGET_MISMATCH'}}else{Copy-Item -LiteralPath $bundle -Destination $target -Recurse -Force}
  ProtectTree $target
  $oldVenv=Join-Path $root "venvs\$Parent";$newVenv=Join-Path $root "venvs\$Version";if(-not(Test-Path -LiteralPath $newVenv)){Copy-Item -LiteralPath $oldVenv -Destination $newVenv -Recurse -Force};ProtectTree $newVenv
  $oldConfig=Join-Path $root "config\$Parent";$newConfig=Join-Path $root "config\$Version";if(-not(Test-Path -LiteralPath $newConfig)){Copy-Item -LiteralPath $oldConfig -Destination $newConfig -Recurse -Force};ProtectTree $newConfig
  Set-Content -LiteralPath $current -Value $Version -Encoding ascii -NoNewline;ProtectTree $target
  [ordered]@{ok=$true;successor=$Version;parent=$Parent;manifest_sha256=$ExpectedManifestSha256.ToLowerInvariant();parent_manifest_sha256=$ExpectedParentManifestSha256.ToLowerInvariant();current=$Version;task_enabled=$false;task_started=$false;mailbox_contacted=$false;uid514_processed=$false;production_contacted=$false}|ConvertTo-Json -Compress
} catch { throw ('PDC_MONITOR_ATTACHMENT_SUCCESSOR_INSTALL_DENIED:' + $_.Exception.Message) } finally { if($held){$mutex.ReleaseMutex()|Out-Null};$mutex.Dispose() }
