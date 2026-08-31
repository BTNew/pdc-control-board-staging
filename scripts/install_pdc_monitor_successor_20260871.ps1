[CmdletBinding()]
param(
  [string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging",
  [Parameter(Mandatory=$true)][string]$BundleRoot,
  [Parameter(Mandatory=$true)][string]$ExpectedManifestSha256,
  [Parameter(Mandatory=$true)][string]$ExpectedParentManifestSha256,
  [switch]$EnableAutomation
)
$ErrorActionPreference='Stop'
$Version='2026.08.71';$Parent='2026.08.69';$Head='20260831380000';$Task='PDC-PMB-Email-Monitor-Staging'
$mutex=New-Object System.Threading.Mutex($false,'Global\PDCMonitorStagingSuccessorInstall071');$held=$false
$published=@();$currentChanged=$false;$rootBootstrapChanged=$false;$stage=$null;$root=$null
function Fail([string]$Code){throw $Code}
function Hash([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){Fail 'PDC_MONITOR_071_HASH_INPUT_MISSING'};(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function TreeLines([string]$Path){$base=[IO.Path]::GetFullPath($Path).TrimEnd('\')+'\';@(Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName | ForEach-Object{$rel=$_.FullName.Substring($base.Length).Replace('\','/');$h=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant();"$rel`t$h`t$($_.Length)"})}
function TreeHash([string]$Path){$text=((TreeLines $Path)-join "`n")+"`n";$bytes=[Text.Encoding]::UTF8.GetBytes($text);$tmp=[IO.Path]::GetTempFileName();try{[IO.File]::WriteAllBytes($tmp,$bytes);return Hash $tmp}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}}
function ProtectTree([string]$Path){& icacls.exe $Path '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' '*S-1-5-19:(OI)(CI)(RX)' '/T' '/C' | Out-Null;if($LASTEXITCODE -ne 0){Fail 'PDC_MONITOR_071_ACL_WRITE_FAILED'}}
function AssertAcl([string]$Path){$out=(icacls.exe $Path 2>&1|Out-String);if($LASTEXITCODE -ne 0 -or $out -notmatch '(?:S-1-5-19|NT AUTHORITY\\LOCAL SERVICE):(?:\(OI\)\(CI\))?\(RX\)'){Fail 'PDC_MONITOR_071_ACL_READBACK_FAILED'}}
function AssertTask([object]$T,[bool]$Disabled){if($T.Principal.UserId -ne 'LOCAL SERVICE' -or $T.Principal.LogonType -ne 'ServiceAccount' -or $T.Principal.RunLevel -ne 'Limited'){Fail 'PDC_MONITOR_071_TASK_IDENTITY_MISMATCH'};if(@($T.Triggers|Where-Object{[string]$_.Repetition.Interval -eq 'PT5M'}).Count -ne 1){Fail 'PDC_MONITOR_071_TASK_TRIGGER_MISMATCH'};if($Disabled -and $T.State -ne 'Disabled'){Fail 'PDC_MONITOR_071_TASK_MUST_REMAIN_DISABLED'};$action=($T.Actions|Select-Object -First 1);if($null -eq $action -or [IO.Path]::GetFileName($action.Execute) -ine 'powershell.exe' -or [string]$action.Arguments -notmatch 'control\\bootstrap\.ps1'){Fail 'PDC_MONITOR_071_TASK_ACTION_MISMATCH'}}
function Publish([string]$Source,[string]$Destination){if(Test-Path -LiteralPath $Destination){Fail 'PDC_MONITOR_071_TARGET_ALREADY_EXISTS'};Move-Item -LiteralPath $Source -Destination $Destination -Force;$script:published+=$Destination}
try{
  $held=$mutex.WaitOne(0);if(-not$held){Fail 'PDC_MONITOR_071_INSTALL_OVERLAP'}
  $root=[IO.Path]::GetFullPath($InstallRoot);$bundle=[IO.Path]::GetFullPath($BundleRoot)
  if(-not $root.EndsWith('\PDCMonitor\Staging',[StringComparison]::OrdinalIgnoreCase)){Fail 'PDC_MONITOR_071_EXACT_ROOT_REQUIRED'}
  if($bundle.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){Fail 'PDC_MONITOR_071_BUNDLE_MUST_BE_EXTERNAL'}
  if((Hash (Join-Path $bundle 'release-manifest.json')) -ne $ExpectedManifestSha256.ToLowerInvariant()){Fail 'PDC_MONITOR_071_MANIFEST_MISMATCH'}
  $manifest=Get-Content -LiteralPath (Join-Path $bundle 'release-manifest.json') -Raw -Encoding utf8|ConvertFrom-Json
  if($manifest.release_version -ne $Version -or $manifest.release_name -ne 'pdc-monitor-staging-m502-2026.08.71' -or $manifest.current_staging_migration_head -ne $Head -or $manifest.expected_staging_project_ref -ne 'cdsmnqxtyyoeoznmbidd' -or $manifest.outbound_email_enabled -ne $false -or $manifest.mark_read_enabled -ne $false){Fail 'PDC_MONITOR_071_MANIFEST_ASSERTION_FAILED'}
  if((Hash (Join-Path $bundle 'backend\imap_bridge.py')) -ne [string]$manifest.successor_patch.storage_bridge_sha256){Fail 'PDC_MONITOR_071_STORAGE_BRIDGE_HASH_MISMATCH'}
  if((Hash (Join-Path $bundle 'backend\email_intake_processor.py')) -ne [string]$manifest.successor_patch.processor_sha256){Fail 'PDC_MONITOR_071_PROCESSOR_HASH_MISMATCH'}
  $taskObj=Get-ScheduledTask -TaskName $Task -ErrorAction Stop;AssertTask $taskObj $true
  $currentPath=Join-Path $root 'CURRENT';$cur=(Get-Content -LiteralPath $currentPath -Raw).Trim();if($cur -ne $Parent -and $cur -ne $Version){Fail 'PDC_MONITOR_071_CURRENT_NOT_069_OR_071'}
  $parentManifest=Join-Path $root "releases\$Parent\release-manifest.json";if((Hash $parentManifest) -ne $ExpectedParentManifestSha256.ToLowerInvariant()){Fail 'PDC_MONITOR_071_PARENT_MANIFEST_CHANGED'}
  foreach($required in @('control\2026.08.71\active-bootstrap.ps1','control\2026.08.71\active-dispatch.ps1','control\2026.08.71\current-head-preflight.py','control-root\bootstrap.ps1','trust\2026.08.71\TRUST-VALUES.json','venv-contract.json')){if(-not(Test-Path -LiteralPath (Join-Path $bundle $required) -PathType Leaf)){Fail 'PDC_MONITOR_071_BUNDLE_CONTROL_OR_TRUST_MISSING'}}
  $stage=Join-Path $root ('.staging\pdc-monitor-071-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $stage -Force|Out-Null
  $stageRelease=Join-Path $stage 'release';$stageControl=Join-Path $stage 'control';$stageTrust=Join-Path $stage 'trust';$stageVenv=Join-Path $stage 'venv';$stageConfig=Join-Path $stage 'config';$stageRootControl=Join-Path $stage 'root-control';$rollbackRootControl=Join-Path $stage 'rollback-root-control'
  Copy-Item -LiteralPath $bundle -Destination $stageRelease -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $bundle 'control\2026.08.71') -Destination $stageControl -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $bundle 'trust\2026.08.71') -Destination $stageTrust -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $bundle 'control-root\bootstrap.ps1') -Destination (Join-Path $stageRootControl 'bootstrap.ps1') -Force
  $sourceVenv=Join-Path $root "venvs\$Parent";$sourceConfig=Join-Path $root "config\$Parent";if(-not(Test-Path -LiteralPath $sourceVenv -PathType Container)){Fail 'PDC_MONITOR_071_PARENT_VENV_MISSING'};if(-not(Test-Path -LiteralPath $sourceConfig -PathType Container)){Fail 'PDC_MONITOR_071_PARENT_CONFIG_MISSING'}
  Copy-Item -LiteralPath $sourceVenv -Destination $stageVenv -Recurse -Force;Copy-Item -LiteralPath $sourceConfig -Destination $stageConfig -Recurse -Force
  $venvLines=TreeLines $stageVenv;Set-Content -LiteralPath (Join-Path $stageTrust 'VENV_SHA256.tsv') -Value $venvLines -Encoding ascii
  ProtectTree $stageRelease;ProtectTree $stageControl;ProtectTree $stageTrust;ProtectTree $stageVenv;ProtectTree $stageConfig;ProtectTree $stageRootControl
  AssertAcl $stageRelease;AssertAcl $stageControl;AssertAcl $stageTrust;AssertAcl $stageVenv
  $controlHash=(TreeHash $stageControl);$trustHash=Hash (Join-Path $stageTrust 'TRUST-VALUES.json')
  $venvHash=TreeHash $stageVenv
  if($controlHash -ne [string]$manifest.active_current_head_controls.control_sha256){Fail 'PDC_MONITOR_071_CONTROL_HASH_MISMATCH'}
  $targetRelease=Join-Path $root "releases\$Version";$targetControl=Join-Path $root "control\$Version";$targetTrust=Join-Path $root "trust\$Version";$targetVenv=Join-Path $root "venvs\$Version";$targetConfig=Join-Path $root "config\$Version"
  Publish $stageRelease $targetRelease;Publish $stageControl $targetControl;Publish $stageTrust $targetTrust;Publish $stageVenv $targetVenv;Publish $stageConfig $targetConfig
  New-Item -ItemType Directory -Path $rollbackRootControl -Force|Out-Null;Copy-Item -LiteralPath (Join-Path $root 'control\bootstrap.ps1') -Destination (Join-Path $rollbackRootControl 'bootstrap.ps1') -Force;Copy-Item -LiteralPath (Join-Path $stageRootControl 'bootstrap.ps1') -Destination (Join-Path $root 'control\bootstrap.ps1') -Force;$rootBootstrapChanged=$true
  Set-Content -LiteralPath (Join-Path $targetTrust 'VENV_SHA256.tsv') -Value $venvLines -Encoding ascii;Set-Content -LiteralPath (Join-Path $targetTrust 'CONTROL_SHA256') -Value $controlHash -Encoding ascii;Set-Content -LiteralPath (Join-Path $targetTrust 'TRUST_SHA256') -Value $trustHash -Encoding ascii
  Set-Content -LiteralPath $currentPath -Value $Version -Encoding ascii -NoNewline;$currentChanged=$true
  $python=Join-Path $targetVenv 'Scripts\python.exe';$preflight=Join-Path $targetControl 'current-head-preflight.py';& $python -B -I -S $preflight --install-root $root --release-root $targetRelease --venv-root $targetVenv --expected-head $Head|Out-Null;if($LASTEXITCODE -ne 0){Fail 'PDC_MONITOR_071_PREFLIGHT_FAILED'}
  $after=Get-ScheduledTask -TaskName $Task -ErrorAction Stop;AssertTask $after $true
  if($EnableAutomation){Enable-ScheduledTask -TaskName $Task -ErrorAction Stop|Out-Null;$enabled=Get-ScheduledTask -TaskName $Task -ErrorAction Stop;AssertTask $enabled $false}else{$enabled=$after}
  $receipt=[ordered]@{ok=$true;release_version=$Version;parent_release_version=$Parent;manifest_sha256=(Hash (Join-Path $targetRelease 'release-manifest.json'));parent_manifest_sha256=$ExpectedParentManifestSha256.ToLowerInvariant();storage_bridge_sha256=[string]$manifest.successor_patch.storage_bridge_sha256;processor_sha256=[string]$manifest.successor_patch.processor_sha256;venv_sha256=$venvHash;control_sha256=$controlHash;trust_sha256=$trustHash;current_staging_migration_head=$Head;task_enabled=($enabled.State -ne 'Disabled');task_started=$false;mailbox_contacted=$false;uid514_processed=$false;production_contacted=$false;outbound_email_sent=$false;rollback_versions=@('2026.08.68','2026.08.69');secrets_printed=$false}|ConvertTo-Json -Depth 8
  Write-Output $receipt
  exit 0
}catch{
  try{if($currentChanged){Set-Content -LiteralPath (Join-Path $root 'CURRENT') -Value $Parent -Encoding ascii -NoNewline};if($rootBootstrapChanged -and $rollbackRootControl -and (Test-Path -LiteralPath (Join-Path $rollbackRootControl 'bootstrap.ps1'))){Copy-Item -LiteralPath (Join-Path $rollbackRootControl 'bootstrap.ps1') -Destination (Join-Path $root 'control\bootstrap.ps1') -Force};$taskRollback=Get-ScheduledTask -TaskName $Task -ErrorAction SilentlyContinue;if($taskRollback -and $taskRollback.State -ne 'Disabled'){Disable-ScheduledTask -TaskName $Task|Out-Null};foreach($item in @($published|Sort-Object Length -Descending)){if(Test-Path -LiteralPath $item){Remove-Item -LiteralPath $item -Recurse -Force -ErrorAction SilentlyContinue}}}catch{}
  throw ('PDC_MONITOR_071_INSTALL_FAILED:' + $_.Exception.Message)
}finally{if($stage){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue};if($held){$mutex.ReleaseMutex()|Out-Null};$mutex.Dispose()}
