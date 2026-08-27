[CmdletBinding()] param(
 [string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging",
 [string]$ReleaseVersion,
 [long]$RecoveryEventId=0,
 [switch]$StaticOnly,
 [switch]$VerifyOnly
)
$ErrorActionPreference='Stop';$env:PYTHONDONTWRITEBYTECODE='1';$env:PYTHONNOUSERSITE='1';$env:PATH=''
Remove-Item Env:PYTHONHOME,Env:PYTHONPATH,Env:PYTHONSTARTUP,Env:PYTHONUSERBASE -ErrorAction SilentlyContinue
function Read-Trust([string]$Root,[string]$Name){$path=Join-Path $Root $Name;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Trust anchor $Name is missing."};return (Get-Content -LiteralPath $path -Raw).Trim()}
function Assert-FileHash([string]$Path,[string]$Expected,[string]$Label){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Label is missing."};$actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant();if($actual -ne $Expected.ToLowerInvariant()){throw "$Label hash mismatch."}}
function Assert-NoReparse([string]$Path,[string]$Label){$probe=[System.IO.Path]::GetFullPath($Path);while(-not[string]::IsNullOrWhiteSpace($probe)){if(Test-Path -LiteralPath $probe){$item=Get-Item -LiteralPath $probe -Force;if(($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){throw "$Label contains a reparse point."}};$parent=[System.IO.Path]::GetDirectoryName($probe);if([string]::IsNullOrWhiteSpace($parent)-or$parent -eq $probe){break};$probe=$parent}}
$current=Join-Path $InstallRoot 'CURRENT';if($ReleaseVersion){$version=$ReleaseVersion}else{if(-not(Test-Path -LiteralPath $current -PathType Leaf)){throw 'CURRENT pointer is missing.'};$version=(Get-Content -LiteralPath $current -Raw).Trim()}
if($version -ne '2026.08.44'){throw 'Authenticated mailbox dispatch requires CURRENT 2026.08.44.'}
$root=Join-Path $InstallRoot ("releases\"+$version);$venv=Join-Path $InstallRoot ("venvs\"+$version);$trust=Join-Path $InstallRoot ("trust\"+$version);$control=Join-Path $InstallRoot ("control\"+$version);$config=Join-Path $InstallRoot ("config\"+$version+'\runtime.env')
$self=Join-Path $control 'run-current.ps1';$bootstrap=Join-Path $InstallRoot 'control\bootstrap.ps1';$preflight=Join-Path $control 'active-preflight-authenticated-mailbox-compatibility.py';$adapter=Join-Path $control 'pdc-authenticated-monitor-runtime-adapter.py';$sealedRunner=Join-Path $control 'run-current-sealed.ps1';$manifest=Join-Path $root 'release-manifest.json';$launcher=Join-Path $root 'runtime_launcher.py'
Assert-NoReparse $root 'Sealed .44 release';Assert-NoReparse $trust 'Protected .44 trust root';Assert-NoReparse $control 'Protected .44 control root'
$manifestHash=Read-Trust $trust 'MANIFEST_SHA256';Assert-FileHash $manifest $manifestHash 'Sealed .44 manifest';$metadata=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
if($metadata.release_name -ne 'pdc-monitor-staging-m502-2026.08.44' -or $metadata.release_version -ne '2026.08.44' -or $metadata.supported_migration_head -ne 503 -or $metadata.active_actor_id -ne 'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' -or $metadata.active_actor_email -ne 'sales@broometoyota.com.au'){throw 'Sealed .44 release binding mismatch.'}
Assert-FileHash $self (Read-Trust $trust 'AUTHENTICATED_DISPATCH_RUNNER_SHA256') 'Authenticated dispatch runner';Assert-FileHash $bootstrap (Read-Trust $trust 'AUTHENTICATED_DISPATCH_BOOTSTRAP_SHA256') 'Authenticated dispatch bootstrap';Assert-FileHash $preflight (Read-Trust $trust 'AUTHENTICATED_MAILBOX_PREFLIGHT_SHA256') 'Authenticated mailbox preflight successor';Assert-FileHash $adapter (Read-Trust $trust 'AUTHENTICATED_RUNTIME_ADAPTER_SHA256') 'External authenticated runtime adapter';Assert-FileHash $sealedRunner (Read-Trust $trust 'SEALED_RUN_CURRENT_SHA256') 'Preserved sealed .44 runner'
$launcherHash=[string]$metadata.files.PSObject.Properties['runtime_launcher.py'].Value.sha256;if($launcherHash -notmatch '^[0-9a-f]{64}$'){throw 'Sealed launcher manifest hash is invalid.'};Assert-FileHash $launcher $launcherHash 'Exact sealed runtime launcher'
if($StaticOnly){[pscustomobject]@{ok=$true;static_verified=$true;release=$version;authenticated_674_preflight=$true;adapter_673_verified=$true;sealed_launcher_verified=$true;sealed_runner_preserved=$true;task_enabled=$false;task_started=$false;mailbox_contacted=$false;uid514_processed=$false;production_contacted=$false}|ConvertTo-Json -Compress;exit 0}
if(-not(Test-Path -LiteralPath $config -PathType Leaf)){throw 'Versioned runtime environment is missing.'}
$venvPython=Join-Path $venv 'Scripts\python.exe';$args=@($preflight,'--release-root',$root,'--trust-root',$trust,'--env-file',$config,'--compatibility-path',$preflight,'--live')
if($VerifyOnly -or $RecoveryEventId -eq 0){$args+='--require-terminal-uid514'}
& $venvPython -B -I -S @args;if($LASTEXITCODE -ne 0){throw 'Authenticated 674 preflight or credential gate failed.'}
# Smoke the exact sealed launcher only. It never opens IMAP or executes a monitor cycle.
& $venvPython -B -I -S $launcher --release-root $root --venv-root $venv --mode smoke;if($LASTEXITCODE -ne 0){throw 'Exact sealed launcher smoke failed.'}
if($VerifyOnly){[pscustomobject]@{ok=$true;verified=$true;release=$version;authenticated_674_preflight=$true;adapter_673_verified=$true;sealed_launcher_verified=$true;sealed_runner_preserved=$true;task_enabled=$false;task_started=$false;mailbox_contacted=$false;uid514_processed=$false;production_contacted=$false}|ConvertTo-Json -Compress;exit 0}
throw 'Authenticated mailbox dispatch is verification-only; the scheduled task remains disabled.'
