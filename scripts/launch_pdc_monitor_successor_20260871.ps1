[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$Root='C:\Users\nwmgr\Desktop\PDCMonitor-Install-20260871'
$Elevated=Join-Path $Root 'PDCMonitor-Install-20260871-Elevated.ps1'
$Record=Join-Path $Root 'activation-launch-record.json'
$expected=(Get-FileHash $Elevated -Algorithm SHA256).Hash.ToLowerInvariant()
$record=[ordered]@{schema_version=1;launcher='PDCMonitor-Install-20260871.ps1';elevated_script_sha256=$expected;uac_requested=$true;installer_relaunched=$false;task_enable_only=$true;task_started=$false;onecycle_called=$false;mailbox_contacted=$false;production_contacted=$false;secrets_printed=$false;started_utc=[DateTime]::UtcNow.ToString('o')}
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Record -Encoding utf8
try {
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$Elevated) -Verb RunAs -Wait
  $receipt=Join-Path $Root 'install-receipt.json'
  if(Test-Path -LiteralPath $receipt){$r=Get-Content -LiteralPath $receipt -Raw -Encoding utf8|ConvertFrom-Json;$record.ok=($r.ok -eq $true);$record.task_enabled=$r.task_enabled;$record.task_started=$false;$record.mailbox_contacted=$false;$record.production_contacted=$false}
} catch { $record.ok=$false;$record.error='PDC_MONITOR_071_UAC_LAUNCH_FAILED' }
$record.child_completed=$true;$record.finished_utc=[DateTime]::UtcNow.ToString('o');$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Record -Encoding utf8
if($record.ok -ne $true){exit 1}
exit 0
