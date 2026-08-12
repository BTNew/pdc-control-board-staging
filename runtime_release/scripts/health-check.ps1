[CmdletBinding()] param([string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging",[switch]$StaticOnly)
$ErrorActionPreference='Stop';$service='PDC-PMB-Email-Monitor-Staging';$version=(Get-Content (Join-Path $InstallRoot 'CURRENT') -Raw).Trim();$root=Join-Path $InstallRoot ("releases\"+$version)
& (Join-Path $root 'scripts\verify.ps1') -BundleRoot $root
if($StaticOnly){[pscustomobject]@{ok=$true;static_ready=$true;intake_contacted=$false;release=$version}|ConvertTo-Json -Compress;exit 0}
$task=Get-ScheduledTask -TaskName $service -ErrorAction Stop;$info=Get-ScheduledTaskInfo -TaskName $service
$statusPath=Join-Path $root 'backend\.pdc_email_intake_monitor_status.json';$local=$null;if(Test-Path $statusPath){$local=Get-Content $statusPath -Raw|ConvertFrom-Json}
[pscustomobject]@{ok=($task.State -ne 'Disabled');task=$service;state=[string]$task.State;last_task_result=$info.LastTaskResult;last_run=$info.LastRunTime;release=$version;local_status=$local}|ConvertTo-Json -Depth 8 -Compress
