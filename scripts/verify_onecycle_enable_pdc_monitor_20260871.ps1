[CmdletBinding()]
param(
  [string]$InstallRoot='C:\ProgramData\PDCMonitor\Staging',
  [string]$ReceiptPath='C:\Users\nwmgr\Desktop\PDCMonitor-Install-20260871-repaired\verify-onecycle-enable-receipt.json'
)
$ErrorActionPreference='Stop'
$Version='2026.08.71';$Head='20260831380000';$Task='PDC-PMB-Email-Monitor-Staging'
$root=[IO.Path]::GetFullPath($InstallRoot)
function Fail([string]$Code){throw $Code}
function AssertTask([object]$T,[bool]$MustBeDisabled){
  if($T.Principal.UserId -notin @('LOCAL SERVICE','S-1-5-19') -or $T.Principal.LogonType -ne 'ServiceAccount' -or $T.Principal.RunLevel -ne 'Limited'){Fail 'PDC_MONITOR_071_CONTINUATION_TASK_IDENTITY_MISMATCH'}
  if(@($T.Triggers|Where-Object{[string]$_.Repetition.Interval -eq 'PT5M'}).Count -ne 1){Fail 'PDC_MONITOR_071_CONTINUATION_TASK_TRIGGER_MISMATCH'}
  $action=$T.Actions|Select-Object -First 1
  if($null -eq $action -or [IO.Path]::GetFileName($action.Execute) -ine 'powershell.exe' -or [string]$action.Arguments -notmatch 'control\\bootstrap\.ps1'){Fail 'PDC_MONITOR_071_CONTINUATION_TASK_ACTION_MISMATCH'}
  if($MustBeDisabled -and $T.State -ne 'Disabled'){Fail 'PDC_MONITOR_071_CONTINUATION_TASK_MUST_REMAIN_DISABLED'}
}
function Write-Receipt([bool]$Ok,[string]$ErrorText,[object]$Status,[object]$Task){
  $payload=[ordered]@{ok=$Ok;release_version=$Version;current_staging_migration_head=$Head;task_name=$Task.TaskName;task_enabled=($Task.State -ne 'Disabled');task_started=$false;verifyonly_passed=$script:verifyOnlyPassed;onecycle_passed=$script:oneCyclePassed;onecycle_status=$Status;mailbox_contacted=if($Status){[bool]$Status.mailbox_contacted}else{$false};uid514_processed=$false;production_contacted=$false;outbound_email_sent=$false;secrets_printed=$false;error=$ErrorText}
  $payload|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReceiptPath -Encoding utf8
}
$verifyOnlyPassed=$false;$oneCyclePassed=$false;$status=$null;$task=$null
try{
  if(-not $root.EndsWith('\PDCMonitor\Staging',[StringComparison]::OrdinalIgnoreCase)){Fail 'PDC_MONITOR_071_CONTINUATION_EXACT_ROOT_REQUIRED'}
  $current=(Get-Content -LiteralPath (Join-Path $root 'CURRENT') -Raw).Trim();if($current -ne $Version){Fail 'PDC_MONITOR_071_CONTINUATION_CURRENT_MISMATCH'}
  $task=Get-ScheduledTask -TaskName $Task -ErrorAction Stop;AssertTask $task $true
  $release=Join-Path $root "releases\$Version";$control=Join-Path $root "control\$Version";$venv=Join-Path $root "venvs\$Version";$python=Join-Path $venv 'Scripts\python.exe'
  $preflight=Join-Path $control 'current-head-preflight.py';& $python -B -I -S $preflight --install-root $root --release-root $release --venv-root $venv --expected-head $Head|Out-Null;if($LASTEXITCODE -ne 0){Fail 'PDC_MONITOR_071_CONTINUATION_VERIFYONLY_FAILED'};$verifyOnlyPassed=$true
  $dispatch=Join-Path $control 'active-dispatch.ps1';& $dispatch -InstallRoot $root|Out-Null;if($LASTEXITCODE -ne 0){Fail 'PDC_MONITOR_071_CONTINUATION_ONECYCLE_FAILED'}
  $statusPath=Join-Path $root 'state\monitor\active-dispatch-status.json';if(-not(Test-Path -LiteralPath $statusPath -PathType Leaf)){Fail 'PDC_MONITOR_071_CONTINUATION_STATUS_MISSING'};$status=Get-Content -LiteralPath $statusPath -Raw|ConvertFrom-Json
  if($status.ok -ne $true -or [string]$status.release_version -ne $Version -or $status.production_contacted -ne $false -or $status.uid514_processed -ne $false){Fail 'PDC_MONITOR_071_CONTINUATION_ONECYCLE_STATUS_FAILED'};$oneCyclePassed=$true
  $task=Get-ScheduledTask -TaskName $Task -ErrorAction Stop;AssertTask $task $true
  Enable-ScheduledTask -TaskName $Task -ErrorAction Stop|Out-Null
  $task=Get-ScheduledTask -TaskName $Task -ErrorAction Stop;AssertTask $task $false
  Write-Receipt $true $null $status $task
  exit 0
}catch{
  if(-not $task){try{$task=Get-ScheduledTask -TaskName $Task -ErrorAction Stop}catch{}}
  if($task){try{AssertTask $task $true}catch{try{Disable-ScheduledTask -TaskName $Task -ErrorAction SilentlyContinue|Out-Null}catch{}}}
  Write-Receipt $false $_.Exception.Message $status $(if($task){$task}else{[pscustomobject]@{TaskName=$Task;State='Disabled'}})
  exit 1
}
