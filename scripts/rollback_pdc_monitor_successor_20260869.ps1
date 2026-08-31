[CmdletBinding()]
param([string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging")
$ErrorActionPreference='Stop';$Version='2026.08.69';$Parent='2026.08.68';$Task='PDC-PMB-Email-Monitor-Staging'
$root=[IO.Path]::GetFullPath($InstallRoot);if(-not$root.EndsWith('\PDCMonitor\Staging',[StringComparison]::OrdinalIgnoreCase)){throw 'PDC_MONITOR_NOSUCHKEY_ROLLBACK_EXACT_ROOT_REQUIRED'}
$task=Get-ScheduledTask -TaskName $Task -ErrorAction Stop;if($task.Principal.UserId -ne 'LOCAL SERVICE' -or $task.Principal.RunLevel -ne 'Limited' -or $task.Principal.LogonType -ne 'ServiceAccount' -or @($task.Triggers|Where-Object{[string]$_.Repetition.Interval -eq 'PT5M'}).Count -ne 1){throw 'PDC_MONITOR_NOSUCHKEY_ROLLBACK_TASK_CONTRACT_MISMATCH'};$taskInfo=Get-ScheduledTaskInfo -TaskName $Task -ErrorAction Stop;Disable-ScheduledTask -TaskName $Task|Out-Null
$current=Join-Path $root 'CURRENT';$cur=(Get-Content -LiteralPath $current -Raw).Trim();if($cur -ne $Version){throw 'PDC_MONITOR_NOSUCHKEY_ROLLBACK_CURRENT_MISMATCH'}
Set-Content -LiteralPath $current -Value $Parent -Encoding ascii -NoNewline
[ordered]@{ok=$true;rolled_back_from=$Version;rolled_back_to=$Parent;task_enabled=$false;task_started=$false;mailbox_contacted=$false;production_contacted=$false;outbound_email_sent=$false;previous_last_task_result=$taskInfo.LastTaskResult}|ConvertTo-Json -Compress
