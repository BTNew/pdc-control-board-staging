[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$Transcript=Join-Path $Root 'install-elevated-transcript.txt'
try{Start-Transcript -LiteralPath $Transcript -Force | Out-Null}catch{}
$InstallRoot='C:\ProgramData\PDCMonitor\Staging'
$Bundle=Join-Path $Root 'pdc-monitor-staging-m502-2026.08.69'
$Installer='C:\Users\nwmgr\HermesWorkspaces\release-20260869\scripts\install_pdc_monitor_successor_20260869.ps1'
$Verifier='C:\Users\nwmgr\HermesWorkspaces\release-20260869\scripts\verify_pdc_monitor_successor_20260869.py'
$Manifest='fa528d8d1ce405b430dc265ded7dca69cc7b49e8d190b90d9e55576b32a1a823'
$ParentManifest='f55c8ba1f06b342fd3205f5a287f4793cb242d886759218a7470482c7c36f18b'
$Bridge='d19f1ee93b5c45169d10e77956677909d2b5844e4aea3ce2e028c0b2edc30071'
$InstallerSha='bbcdaf90494eddd72c55d2555123eb8e5e5cd4bea364b550ccdfa6bc4ac685cf'
$VerifierSha='bd36682dbb884c749e371f81cc1cd952b3c135cc809e75ab674a738223b6e953'
$Receipt=Join-Path $Root 'install-receipt.json'
$mutex=New-Object System.Threading.Mutex($false,'Global\PDCMonitorStagingReceiptWrapper769')
$held=$false;$started=[DateTime]::UtcNow.ToString('o');$ok=$false;$errorText=$null;$verifyExit=1;$target=$null;$temporarySid=$null;$temporaryAclPaths=@();$temporaryAclSnapshots=@{};$cleanupFailed=$false;$installSucceeded=$false
function Write-Json([string]$Path,[object]$Value){$tmp=$Path+'.tmp';$Value|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $tmp -Encoding utf8;Move-Item -LiteralPath $tmp -Destination $Path -Force}
function Hash([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'PDC_MONITOR_769_HASH_FILE_MISSING'};(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Task-Info(){try{$t=Get-ScheduledTask -TaskName 'PDC-PMB-Email-Monitor-Staging' -ErrorAction Stop;$i=Get-ScheduledTaskInfo -TaskName 'PDC-PMB-Email-Monitor-Staging' -ErrorAction Stop;[ordered]@{state=[string]$t.State;enabled=$t.Settings.Enabled;principal=[string]$t.Principal.UserId;logon_type=[string]$t.Principal.LogonType;run_level=[string]$t.Principal.RunLevel;interval=[string]$t.Triggers[0].Repetition.Interval;last_task_result=$i.LastTaskResult;last_run=$i.LastRunTime}}catch{[ordered]@{read_error=$_.Exception.Message}}}
function Ica([string[]]$Arguments){& icacls.exe @Arguments | Out-Null;if($LASTEXITCODE -ne 0){throw 'PDC_MONITOR_769_ACL_OPERATION_FAILED'}}
function Temp-Grant([string]$Path,[string]$Permission,[switch]$Required){if(-not(Test-Path -LiteralPath $Path) -and -not$Required){return};try{$temporaryAclSnapshots[$Path]=Get-Acl -LiteralPath $Path}catch{$temporaryAclSnapshots[$Path]=$null};$ace=if($Permission -eq 'F'){"*$($temporarySid):(F)"}else{"*$($temporarySid):(RX)"};Ica @($Path,'/grant',$ace);if(-not($temporaryAclPaths.Contains($Path))){$script:temporaryAclPaths+=$Path}}

function Remove-TempGrant([string]$Path){try{if($temporaryAclSnapshots[$Path]){Set-Acl -LiteralPath $Path -AclObject $temporaryAclSnapshots[$Path]}else{Ica @($Path,'/remove',("*$($temporarySid)"))}}catch{$script:cleanupFailed=$true}}
try {
  $held=$mutex.WaitOne(0);if(-not $held){throw 'PDC_MONITOR_769_ELEVATED_OVERLAP'}
  if(-not([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'PDC_MONITOR_769_ADMIN_REQUIRED'}
  $target=Join-Path $InstallRoot 'releases\2026.08.69';$temporarySid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  foreach($ancestor in @($InstallRoot,(Join-Path $InstallRoot 'releases'))){Temp-Grant $ancestor 'RX'}
  if(Test-Path -LiteralPath $target){Temp-Grant $target 'RX';Temp-Grant (Join-Path $target 'release-manifest.json') 'F'}
  if((Hash $Installer) -ne $InstallerSha){throw 'PDC_MONITOR_769_INSTALLER_HASH_MISMATCH'}
  if((Hash $Verifier) -ne $VerifierSha){throw 'PDC_MONITOR_769_VERIFIER_HASH_MISMATCH'}
  $before=Task-Info
  & $Installer -InstallRoot $InstallRoot -BundleRoot $Bundle -ExpectedManifestSha256 $Manifest -ExpectedParentManifestSha256 $ParentManifest | Out-Null
  if($LASTEXITCODE -ne 0){throw "PDC_MONITOR_769_INSTALL_EXIT_$LASTEXITCODE"}
  $installSucceeded=$true
  $python=Join-Path $InstallRoot 'venvs\2026.08.68\Scripts\python.exe'
  & $python -B -I -S $Verifier --bundle $Bundle --expected-manifest-sha256 $Manifest --expected-parent-manifest-sha256 $ParentManifest --expected-bridge-sha256 $Bridge | Out-Null
  $verifyExit=$LASTEXITCODE
  $current=(Get-Content -LiteralPath (Join-Path $InstallRoot 'CURRENT') -Raw).Trim();$after=Task-Info
  $acl=Get-Acl -LiteralPath (Join-Path $InstallRoot 'releases\2026.08.69')
  $ok=($verifyExit -eq 0 -and $current -eq '2026.08.69' -and $after.state -eq 'Disabled' -and $after.principal -eq 'LOCAL SERVICE' -and $acl.AreAccessRulesProtected)
  if(-not $ok){throw 'PDC_MONITOR_769_POSTINSTALL_READBACK_FAILED'}
} catch {$errorText=$_.Exception.Message} finally {
  $currentValue=$null;try{$currentValue=(Get-Content -LiteralPath (Join-Path $InstallRoot 'CURRENT') -Raw).Trim()}catch{}
  $receiptValue=[ordered]@{schema_version=1;wrapper='pdc-monitor-20260869-receipt-wrapper';elevated_stage='PDCMonitor-Install-20260869-Elevated.ps1';ok=$ok;started_utc=$started;finished_utc=[DateTime]::UtcNow.ToString('o');release='2026.08.69';current=$currentValue;manifest_sha256=$Manifest;parent_manifest_sha256=$ParentManifest;bridge_sha256=$Bridge;inventory_verify_exit=$verifyExit;task=$(Task-Info);installer_error=$errorText;task_enable_requested=$false;mailbox_contacted=$false;mailbox_flags_changed=$false;uid514_processed=$false;outbound_email_sent=$false;production_contacted=$false;secrets_printed=$false}
  foreach($path in $temporaryAclPaths){if($installSucceeded -and $target -and ($path -eq $target -or $path.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase))){try{Ica @($path,'/remove',("*$($temporarySid)"))}catch{$cleanupFailed=$true}}else{Remove-TempGrant $path}};if($cleanupFailed){$ok=$false;$receiptValue.ok=$false;$receiptValue.installer_error=if($errorText){$errorText}else{'PDC_MONITOR_769_CLEANUP_FAILED'}};try{Write-Json $Receipt $receiptValue}catch{}
  if($held){$mutex.ReleaseMutex()|Out-Null};$mutex.Dispose()
}
if($ok){exit 0}else{exit 1}
