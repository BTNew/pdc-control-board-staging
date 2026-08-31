[CmdletBinding()]param([ValidateSet('VerifyOnly','OneCycle')][string]$Mode='VerifyOnly')
$ErrorActionPreference='Stop';$log="C:\Users\nwmgr\Desktop\PDCMonitor-Install-20260869\$Mode-20260869-transcript.txt";Start-Transcript -LiteralPath $log -Force|Out-Null
$r='C:\ProgramData\PDCMonitor\Staging';$s=if($Mode -eq 'VerifyOnly'){Join-Path $r 'control\2026.08.69\bootstrap-verifyonly.ps1'}else{Join-Path $r 'control\2026.08.69\run-current-active.ps1'}
if($Mode -eq 'VerifyOnly'){& $s -InstallRoot $r}else{& $s -InstallRoot $r -Mode OneCycle}
$code=$LASTEXITCODE;Write-Output "mode=$Mode exit=$code";Stop-Transcript|Out-Null;exit $code
