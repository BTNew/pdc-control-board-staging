[CmdletBinding()]
param([string]$InstallRoot='C:\ProgramData\PDCMonitor\Staging')
$ErrorActionPreference='Stop';$TaskName='PDC-PMB-Email-Monitor-Staging';$Expected='2026.08.68';$before=(Get-ScheduledTaskInfo -TaskName $TaskName).LastRunTime;$success=0;$seen=@();$started=Get-Date;$r=[IO.Path]::GetFullPath($InstallRoot)
try{
 $task=Get-ScheduledTask -TaskName $TaskName
 if($task.Principal.UserId -ne 'LOCAL SERVICE' -or $task.Principal.RunLevel -ne 'Limited' -or $task.Principal.LogonType -ne 'ServiceAccount'){throw 'task identity mismatch'}
 if(@($task.Triggers|Where-Object{$_.Repetition.Interval -eq 'PT5M'}).Count -ne 1){throw 'task repetition mismatch'}
 if($task.Actions[0].Arguments -notmatch '(?i)control[\\/]bootstrap\.ps1'){throw 'task action mismatch'}
 if((Get-Content (Join-Path $r 'CURRENT') -Raw).Trim() -ne $Expected){throw 'CURRENT mismatch'}
 $flags=@{};Get-Content (Join-Path $r 'config\2026.08.68\runtime.env')|ForEach-Object{if($_ -match '^(PDC_OUTBOUND_EMAIL_ENABLED|IMAP_BRIDGE_MARK_READ)=(.*)$'){$flags[$Matches[1]]=$Matches[2]}}
 if($flags.PDC_OUTBOUND_EMAIL_ENABLED -ne 'false' -or $flags.IMAP_BRIDGE_MARK_READ -ne 'false'){throw 'safety flags mismatch'}
 while($success -lt 2 -and ((Get-Date)-$started).TotalMinutes -lt 18){
  Start-Sleep -Seconds 5;$info=Get-ScheduledTaskInfo -TaskName $TaskName;$state=(Get-ScheduledTask -TaskName $TaskName).State
  if($info.LastRunTime -and $info.LastRunTime -gt $before -and $seen -notcontains $info.LastRunTime -and $state -eq 'Ready'){
   $seen+=$info.LastRunTime
   if($info.LastTaskResult -ne 0){throw "natural run failed result $($info.LastTaskResult)"}
   $status=Get-Content (Join-Path $r 'state\monitor\active-dispatch-status.json') -Raw|ConvertFrom-Json
   $proc=Get-Content (Join-Path $r 'state\monitor\.pdc_email_intake_monitor_status.json') -Raw|ConvertFrom-Json
   if($status.release_version -ne $Expected -or $status.code -ne 'PDC_MONITOR_766_CYCLE_COMPLETE' -or -not $status.mailbox_contacted -or $status.production_contacted -or $status.uid514_processed -or -not $proc.ok -or $proc.release -ne $Expected -or $proc.email_processing.failed -ne 0){throw 'natural receipt gate failed'}
   $success++
  }
 }
 if($success -ne 2){throw "natural run timeout count=$success"}
 $info=Get-ScheduledTaskInfo -TaskName $TaskName;$task=Get-ScheduledTask -TaskName $TaskName
 [ordered]@{ok=$true;natural_runs=$success;distinct_last_run_times=($seen|ForEach-Object{$_.ToString('o')});task_state=$task.State;last_task_result=$info.LastTaskResult;last_run=$info.LastRunTime;next_run=$info.NextRunTime;release=$Expected;production_contacted=$false;mailbox_flags_changed=$false;outbound_email_enabled=$false}|ConvertTo-Json -Compress;exit 0
}catch{Disable-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue|Out-Null;[ordered]@{ok=$false;natural_runs=$success;error=$_.Exception.Message;task_disabled=$true;production_contacted=$false}|ConvertTo-Json -Compress;exit 1}
