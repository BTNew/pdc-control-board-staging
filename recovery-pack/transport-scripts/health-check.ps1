[CmdletBinding()] param(
 [string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging",
 [int]$MaximumStatusAgeMinutes=10,
 [switch]$StaticOnly
)
$ErrorActionPreference='Stop'
$taskName='PDC-PMB-Email-Monitor-Staging'
$version=(Get-Content -LiteralPath (Join-Path $InstallRoot 'CURRENT') -Raw).Trim()
if($version -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$'){throw 'CURRENT pointer is invalid.'}
$runner=Join-Path $InstallRoot ("control\"+$version+'\run-current.ps1')
if($StaticOnly){
 & $runner -InstallRoot $InstallRoot -ReleaseVersion $version -StaticOnly
 if($LASTEXITCODE -ne 0){throw 'Static installed-runtime verification failed.'}
 [pscustomobject]@{ok=$true;static_ready=$true;intake_contacted=$false;release=$version}|ConvertTo-Json -Compress
 exit 0
}
& $runner -InstallRoot $InstallRoot -ReleaseVersion $version -VerifyOnly
if($LASTEXITCODE -ne 0){throw 'Live installed-runtime verification failed.'}
$task=Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
$info=Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop
$bootstrap=Join-Path $InstallRoot 'control\bootstrap.ps1'
$expectedArguments="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$bootstrap`" -InstallRoot `"$InstallRoot`""
$actionOk=($task.Actions.Count -eq 1 -and [string]$task.Actions[0].Execute -ieq 'powershell.exe' -and [string]$task.Actions[0].Arguments -ceq $expectedArguments -and [string]$task.Actions[0].WorkingDirectory -eq '')
$principalOk=([string]$task.Principal.UserId -in @('NT AUTHORITY\LOCAL SERVICE','S-1-5-19') -and [string]$task.Principal.LogonType -eq 'ServiceAccount' -and [string]$task.Principal.RunLevel -eq 'Limited')
$statusPath=Join-Path $InstallRoot 'state\monitor\.pdc_email_intake_monitor_status.json'
if(-not(Test-Path -LiteralPath $statusPath -PathType Leaf)){throw 'Local cycle status is missing.'}
$statusFile=Get-Item -LiteralPath $statusPath
$local=Get-Content -LiteralPath $statusPath -Raw|ConvertFrom-Json
$statusAt=[DateTimeOffset]::MinValue;$finishedAt=[DateTimeOffset]::MinValue
if(-not[DateTimeOffset]::TryParse([string]$local.at,[ref]$statusAt) -or -not[DateTimeOffset]::TryParse([string]$local.finished_at,[ref]$finishedAt)){throw 'Local cycle timestamps are invalid.'}
$now=[DateTimeOffset]::UtcNow
$lastRun=[DateTimeOffset]($info.LastRunTime.ToUniversalTime())
$fresh=(($now-$finishedAt.ToUniversalTime()).TotalMinutes -le $MaximumStatusAgeMinutes -and $finishedAt -le $now.AddSeconds(2))
$temporalOk=($statusAt -ge $lastRun.AddSeconds(-2) -and $statusAt -le $lastRun.AddSeconds(5) -and $statusAt -le $finishedAt -and [DateTimeOffset]($statusFile.LastWriteTimeUtc) -ge $finishedAt.AddSeconds(-2))
$ok=($task.State -ne 'Disabled' -and $info.LastTaskResult -eq 0 -and $actionOk -and $principalOk -and $fresh -and $temporalOk -and $local.ok -eq $true -and [string]$local.release -eq $version -and -not $local.skipped)
$result=[pscustomobject]@{ok=$ok;task=$taskName;state=[string]$task.State;principal=[string]$task.Principal.UserId;principal_verified=$principalOk;action_verified=$actionOk;last_task_result=$info.LastTaskResult;last_run=$info.LastRunTime;release=$version;status_fresh=$fresh;temporal_binding_verified=$temporalOk;local_status=$local}
$result|ConvertTo-Json -Depth 8 -Compress
if(-not $ok){exit 1}
