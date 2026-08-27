[CmdletBinding()]
param([string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging")
$ErrorActionPreference='Stop';$ExpectedVersion='2026.08.48';$TaskName='PDC-PMB-Email-Monitor-Staging'
try{
 $current=Join-Path $InstallRoot 'CURRENT';if((Get-Content -LiteralPath $current -Raw).Trim()-ne$ExpectedVersion){throw 'PDC_MONITOR_SUCCESSOR_ENABLE_CURRENT_MISMATCH'}
 $task=Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop;if($task.State-ne'Disabled'-or$task.Principal.UserId-ne'LOCAL SERVICE'-or$task.Principal.RunLevel-ne'Limited'-or$task.Principal.LogonType-ne'ServiceAccount'){throw 'PDC_MONITOR_SUCCESSOR_ENABLE_TASK_SHAPE_MISMATCH'};if(@($task.Triggers|Where-Object{$_.Repetition.Interval-eq'PT5M'}).Count-eq0){throw 'PDC_MONITOR_SUCCESSOR_ENABLE_TRIGGER_MISMATCH'}
 Enable-ScheduledTask -TaskName $TaskName|Out-Null;$after=Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop;if($after.State-eq'Disabled'){throw 'PDC_MONITOR_SUCCESSOR_ENABLE_FAILED'}
 [pscustomobject]@{ok=$true;current=$ExpectedVersion;task_enabled=$true;task_started=$false;mailbox_contacted=$false;production_contacted=$false}|ConvertTo-Json -Compress;exit 0
}catch{[Console]::Error.WriteLine('PDC_MONITOR_SUCCESSOR_ENABLE_DENIED');exit 1}
