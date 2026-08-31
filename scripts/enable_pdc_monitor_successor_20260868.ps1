[CmdletBinding()]
param([string]$InstallRoot='C:\ProgramData\PDCMonitor\Staging')
$ErrorActionPreference='Stop';$Expected='2026.08.68';$TaskName='PDC-PMB-Email-Monitor-Staging';$r=[IO.Path]::GetFullPath($InstallRoot)
try{
 $task=Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
 if($task.Principal.UserId -ne 'LOCAL SERVICE' -or $task.Principal.RunLevel -ne 'Limited' -or $task.Principal.LogonType -ne 'ServiceAccount'){throw 'task identity mismatch'}
 if(@($task.Triggers|Where-Object{$_.Repetition.Interval -eq 'PT5M'}).Count -ne 1){throw 'task repetition mismatch'}
 if($task.Actions[0].Arguments -notmatch '(?i)control[\\/]bootstrap\.ps1'){throw 'task action mismatch'}
 if((Get-Content (Join-Path $r 'CURRENT') -Raw).Trim() -ne $Expected){throw 'CURRENT mismatch'}
 $envPath=Join-Path $r 'config\2026.08.68\runtime.env';$flags=@{};Get-Content $envPath|ForEach-Object{if($_ -match '^(PDC_OUTBOUND_EMAIL_ENABLED|IMAP_BRIDGE_MARK_READ)=(.*)$'){$flags[$Matches[1]]=$Matches[2]}}
 if($flags.PDC_OUTBOUND_EMAIL_ENABLED -ne 'false' -or $flags.IMAP_BRIDGE_MARK_READ -ne 'false'){throw 'safety flags mismatch'}
 Enable-ScheduledTask -TaskName $TaskName|Out-Null;$after=Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop;$info=Get-ScheduledTaskInfo -TaskName $TaskName
 if($after.State -eq 'Disabled'){throw 'enablement failed'}
 [ordered]@{ok=$true;task=$TaskName;state=$after.State;principal=$after.Principal.UserId;runlevel=$after.Principal.RunLevel;logontype=$after.Principal.LogonType;interval='PT5M';last_task_result=$info.LastTaskResult;last_run=$info.LastRunTime;next_run=$info.NextRunTime;release=$Expected;production_contacted=$false;outbound_email_enabled=$false;mailbox_flags_changed=$false}|ConvertTo-Json -Compress;exit 0
}catch{[ordered]@{ok=$false;error=$_.Exception.Message;task_disabled=$true;production_contacted=$false}|ConvertTo-Json -Compress;exit 1}
