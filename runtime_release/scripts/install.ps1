[CmdletBinding()] param(
 [string]$BundleRoot=(Split-Path -Parent $PSScriptRoot),
 [string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging",
 [Parameter(Mandatory=$true)][string]$ExpectedManifestSha256,
 [switch]$StaticOnly
)
$ErrorActionPreference='Stop';$service='PDC-PMB-Email-Monitor-Staging'
& (Join-Path $BundleRoot 'scripts\verify.ps1') -BundleRoot $BundleRoot -ExpectedManifestSha256 $ExpectedManifestSha256
if($LASTEXITCODE -ne 0){throw 'Bundle verification failed.'}
$manifest=Get-Content (Join-Path $BundleRoot 'release-manifest.json') -Raw|ConvertFrom-Json
$releaseDir=Join-Path $InstallRoot ("releases\"+$manifest.release_version)
if(Test-Path $releaseDir){Remove-Item $releaseDir -Recurse -Force}
New-Item $releaseDir -ItemType Directory -Force|Out-Null
Copy-Item (Join-Path $BundleRoot '*') $releaseDir -Recurse -Force
& (Join-Path $releaseDir 'scripts\verify.ps1') -BundleRoot $releaseDir -ExpectedManifestSha256 $ExpectedManifestSha256
if($LASTEXITCODE -ne 0){throw 'Installed-byte verification failed.'}
New-Item (Join-Path $InstallRoot 'config') -ItemType Directory -Force|Out-Null
if(-not(Test-Path (Join-Path $InstallRoot 'config\runtime.env'))){Copy-Item (Join-Path $releaseDir 'templates\runtime.env.example') (Join-Path $InstallRoot 'config\runtime.env.example') -Force}
Set-Content (Join-Path $InstallRoot 'CURRENT') $manifest.release_version -Encoding ascii
Set-Content (Join-Path $InstallRoot 'MANIFEST_SHA256') $ExpectedManifestSha256 -Encoding ascii
if($StaticOnly){[pscustomobject]@{ok=$true;static_only=$true;task_registered=$false;intake_started=$false;release=$manifest.release_version;path=$releaseDir}|ConvertTo-Json -Compress;exit 0}
$python=(Get-Command python.exe -ErrorAction Stop).Source
$venv=Join-Path $releaseDir '.venv'; & $python -m venv $venv
& (Join-Path $venv 'Scripts\python.exe') -m pip install --disable-pip-version-check --no-input -r (Join-Path $releaseDir 'backend\requirements-email-intake.txt')
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $releaseDir 'scripts\run-cycle.ps1')+'" -InstallRoot "'+$InstallRoot+'"')
$triggers=@((New-ScheduledTaskTrigger -AtStartup),(New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)))
$settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Minutes 9) -StartWhenAvailable
$principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $service -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Force|Out-Null
Disable-ScheduledTask -TaskName $service|Out-Null
[pscustomobject]@{ok=$true;static_only=$false;task_registered=$true;task_enabled=$false;intake_started=$false;release=$manifest.release_version;path=$releaseDir}|ConvertTo-Json -Compress
