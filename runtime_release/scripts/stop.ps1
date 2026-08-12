[CmdletBinding()] param()
$ErrorActionPreference='Stop';$service='PDC-PMB-Email-Monitor-Staging';Stop-ScheduledTask -TaskName $service -ErrorAction SilentlyContinue;Disable-ScheduledTask -TaskName $service|Out-Null
[pscustomobject]@{ok=$true;task=$service;enabled=$false;stopped=$true}|ConvertTo-Json -Compress
