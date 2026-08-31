[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Start-Transcript -LiteralPath 'C:\Users\nwmgr\Desktop\PDCMonitor-Install-20260869\repair-control-transcript.txt' -Force | Out-Null
$r='C:\ProgramData\PDCMonitor\Staging';$v='2026.08.69';$p='2026.08.68';$task='PDC-PMB-Email-Monitor-Staging';$src='C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead';$bundle='C:\Users\nwmgr\Desktop\PDCMonitor-Install-20260869\pdc-monitor-staging-m502-2026.08.69';$root=Join-Path $r "releases\$v";$old=Join-Path $r "control\$p";$c=Join-Path $r "control\$v";$t=Join-Path $r "trust\$v";$cfg=Join-Path $r "config\$v";$venv=Join-Path $r "venvs\$v";$sec=Join-Path $r "secrets\$v"
function HashFile($x){(Get-FileHash -LiteralPath $x -Algorithm SHA256).Hash.ToLowerInvariant()}
function A($x){& icacls.exe $x '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' '*S-1-5-19:(OI)(CI)(RX)' '/T' '/C'|Out-Null;if($LASTEXITCODE){throw "ACL failed $x"}}
function GrantTemp($x){$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;& icacls.exe $x '/grant' "*${sid}:(F)" '/T' '/C'|Out-Null;if($LASTEXITCODE){throw "temp ACL failed $x"}}
function FileAcl($x){& icacls.exe $x '/inheritance:r' '/grant:r' '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' '*S-1-5-19:(RX)' '/C'|Out-Null;if($LASTEXITCODE){throw "file ACL failed $x"}}
$tinfo=Get-ScheduledTask -TaskName $task;if($tinfo.State -ne 'Disabled'){throw 'task must remain disabled'}
if((HashFile (Join-Path $root 'release-manifest.json')) -ne 'fa528d8d1ce405b430dc265ded7dca69cc7b49e8d190b90d9e55576b32a1a823'){throw 'bundle hash mismatch'}
New-Item $c,$t,$cfg,$venv,$sec -ItemType Directory -Force|Out-Null
foreach($q in @($c,$t,$cfg,$venv,$sec)){A $q}
GrantTemp $c
Remove-Item (Join-Path $c '*') -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $old 'pdc_monitor_refresh_20260868.py') (Join-Path $c 'pdc_monitor_refresh_20260869.py') -Force
Copy-Item (Join-Path $old 'run-current-active.ps1') (Join-Path $c 'run-current-active.ps1') -Force
Copy-Item (Join-Path $old 'run-current-verifyonly.ps1') (Join-Path $c 'run-current-verifyonly.ps1') -Force
Copy-Item (Join-Path $old 'bootstrap-verifyonly.ps1') (Join-Path $c 'bootstrap-verifyonly.ps1') -Force
Copy-Item (Join-Path $src 'scripts\verify_pdc_monitor_successor_20260869.py') (Join-Path $c 'verify-successor.py') -Force
Copy-Item (Join-Path $old 'current-head-preflight.py') (Join-Path $c 'current-head-preflight.py') -Force
if(-not(Test-Path (Join-Path $venv 'Scripts\python.exe'))){Copy-Item (Join-Path $r "venvs\$p\*") $venv -Recurse -Force}
if(-not(Test-Path (Join-Path $cfg 'runtime.env'))){Copy-Item (Join-Path $r "config\$p\runtime.env") (Join-Path $cfg 'runtime.env') -Force}
if(-not(Test-Path (Join-Path $sec 'monitor-refresh.dpapi'))){Copy-Item (Join-Path $r "secrets\$p\monitor-refresh.dpapi") (Join-Path $sec 'monitor-refresh.dpapi') -Force}
GrantTemp $sec
$active=Join-Path $c 'run-current-active.ps1';$x=Get-Content $active -Raw;$x=$x.Replace('2026.08.68','2026.08.69').Replace('2026.08.66','2026.08.68').Replace('--expected-processor-sha256','--expected-bridge-sha256').Replace("Trust 'SUCCESSOR_PROCESSOR_SHA256'","Trust 'SUCCESSOR_BRIDGE_SHA256'");Set-Content $active $x -Encoding utf8
$verify=Join-Path $c 'run-current-verifyonly.ps1';$x=Get-Content $verify -Raw;$x=$x.Replace('2026.08.68','2026.08.69');Set-Content $verify $x -Encoding utf8
$boot=Join-Path $c 'bootstrap-verifyonly.ps1';$x=Get-Content $boot -Raw;$x=$x.Replace('2026.08.68','2026.08.69');Set-Content $boot $x -Encoding utf8
$refresh=Join-Path $c 'pdc_monitor_refresh_20260869.py';$x=Get-Content $refresh -Raw;$x=$x.Replace('20260868','20260869');Set-Content $refresh $x -Encoding utf8
$rootboot=Join-Path $r 'control\bootstrap.ps1';$x=Get-Content $rootboot -Raw;$x=$x.Replace('2026.08.68','2026.08.69');Set-Content $rootboot $x -Encoding utf8
GrantTemp $t;foreach($f in Get-ChildItem $t -File){GrantTemp $f.FullName}
$vals=[ordered]@{'SUCCESSOR_MANIFEST_SHA256'='fa528d8d1ce405b430dc265ded7dca69cc7b49e8d190b90d9e55576b32a1a823';'PARENT_MANIFEST_SHA256'='f55c8ba1f06b342fd3205f5a287f4793cb242d886759218a7470482c7c36f18b';'SUCCESSOR_BRIDGE_SHA256'='d19f1ee93b5c45169d10e77956677909d2b5844e4aea3ce2e028c0b2edc30071';'SUCCESSOR_VERIFIER_SHA256'=(HashFile (Join-Path $c 'verify-successor.py'));'ACTIVE_DISPATCH_SHA256'=(HashFile $active);'VERIFYONLY_BOOTSTRAP_SHA256'=(HashFile $boot);'VERIFYONLY_RUNNER_SHA256'=(HashFile $verify);'ACTIVE_BOOTSTRAP_SHA256'=(HashFile $rootboot);'MACHINE_REFRESH_SHA256'=(HashFile $refresh);'CURRENT_HEAD_PREFLIGHT_SHA256'=(HashFile (Join-Path $c 'current-head-preflight.py'));'ROOT_BOOTSTRAP_SHA256'=(HashFile $rootboot);'FROZEN_066_MANIFEST_SHA256'='f55c8ba1f06b342fd3205f5a287f4793cb242d886759218a7470482c7c36f18b'}
foreach($n in $vals.Keys){$q=Join-Path $t $n;Set-Content $q $vals[$n] -Encoding ascii -NoNewline}
# final ACL hardening after all reads and writes
foreach($q in @($c,$t,$cfg,$venv,$sec,$rootboot)){A $q}
foreach($base in @($c,$t,$cfg,$venv,$sec)){foreach($f in Get-ChildItem $base -Recurse -File){FileAcl $f.FullName}}
[ordered]@{ok=$true;release=$v;current=((Get-Content (Join-Path $r 'CURRENT') -Raw).Trim());task_state=[string](Get-ScheduledTask -TaskName $task).State;control_files=@((Get-ChildItem $c -File).Count);production_contacted=$false;mailbox_contacted=$false}|ConvertTo-Json -Compress
