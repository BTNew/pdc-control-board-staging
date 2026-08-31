[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$Elevated=Join-Path $Root 'verify_onecycle_enable_pdc_monitor_20260871.ps1'
$Receipt=Join-Path $Root 'verify-onecycle-enable-receipt.json'
$RecordPath=Join-Path $Root 'verify-onecycle-enable-launch-record.json'
$expected=(Get-FileHash -LiteralPath $Elevated -Algorithm SHA256).Hash.ToLowerInvariant()
$record=[ordered]@{schema_version=1;launcher='launch_verify_onecycle_enable_pdc_monitor_20260871.ps1';elevated_script_sha256=$expected;uac_requested=$true;task_started=$false;onecycle_called=$false;mailbox_contacted=$false;production_contacted=$false;secrets_printed=$false;started_utc=[DateTime]::UtcNow.ToString('o')}
$record|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $RecordPath -Encoding utf8
try{
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$Elevated,'-ReceiptPath',$Receipt) -Verb RunAs -Wait
  if(Test-Path -LiteralPath $Receipt){$r=Get-Content -LiteralPath $Receipt -Raw|ConvertFrom-Json;$record.ok=($r.ok -eq $true);$record.verifyonly_passed=$r.verifyonly_passed;$record.onecycle_passed=$r.onecycle_passed;$record.task_enabled=$r.task_enabled;$record.task_started=$false;$record.mailbox_contacted=$r.mailbox_contacted;$record.production_contacted=$r.production_contacted}
}catch{$record.ok=$false;$record.error='PDC_MONITOR_071_CONTINUATION_UAC_LAUNCH_FAILED'}
$record.child_completed=$true;$record.finished_utc=[DateTime]::UtcNow.ToString('o');$record|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $RecordPath -Encoding utf8
if($record.ok -ne $true){exit 1};exit 0
