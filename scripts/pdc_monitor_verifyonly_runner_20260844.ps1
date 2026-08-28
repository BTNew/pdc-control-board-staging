[CmdletBinding()]
param([string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging")
$ErrorActionPreference='Stop'
$ExpectedVersion='2026.08.44'
$ExpectedRelease='pdc-monitor-staging-m502-2026.08.44'
$ExpectedProject='cdsmnqxtyyoeoznmbidd'
$ExpectedActorId='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'
$ExpectedActorEmail='sales@broometoyota.com.au'
$ExpectedSealedMigrationHead=503
$ExpectedCompatibilityHead=674
function Fail([string]$Code){throw $Code}
function Hash([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){Fail 'PDC_MONITOR_VERIFYONLY_MISSING_FILE'};return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Read-Trust([string]$Name){$path=Join-Path $trust $Name;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Fail 'PDC_MONITOR_VERIFYONLY_TRUST_MISSING'};return (Get-Content -LiteralPath $path -Raw).Trim().ToLowerInvariant()}
function Assert-Hash([string]$Path,[string]$Expected,[string]$Code){if((Hash $Path) -ne $Expected.ToLowerInvariant()){Fail $Code}}
try{
 $env:PYTHONDONTWRITEBYTECODE='1';$env:PYTHONNOUSERSITE='1';$env:PATH='';Remove-Item Env:PYTHONHOME,Env:PYTHONPATH,Env:PYTHONSTARTUP,Env:PYTHONUSERBASE -ErrorAction SilentlyContinue
 if((Get-Content -LiteralPath (Join-Path $InstallRoot 'CURRENT') -Raw).Trim() -ne $ExpectedVersion){Fail 'PDC_MONITOR_VERIFYONLY_CURRENT_MISMATCH'}
 $root=Join-Path $InstallRoot ("releases\"+$ExpectedVersion);$trust=Join-Path $InstallRoot ("trust\"+$ExpectedVersion);$control=Join-Path $InstallRoot ("control\"+$ExpectedVersion);$venv=Join-Path $InstallRoot ("venvs\"+$ExpectedVersion);$venvPython=Join-Path $venv 'Scripts\python.exe';$manifest=Join-Path $root 'release-manifest.json'
 Assert-Hash $manifest (Read-Trust 'MANIFEST_SHA256') 'PDC_MONITOR_VERIFYONLY_MANIFEST_MISMATCH'
 $metadata=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json;if($metadata.release_version -ne $ExpectedVersion -or $metadata.release_name -ne $ExpectedRelease -or [int]$metadata.supported_migration_head -ne $ExpectedSealedMigrationHead -or $metadata.expected_staging_project_ref -ne $ExpectedProject -or $metadata.active_actor_id -ne $ExpectedActorId -or $metadata.active_actor_email -ne $ExpectedActorEmail){Fail 'PDC_MONITOR_VERIFYONLY_SEALED_RELEASE_BINDING_MISMATCH'}
 $self=Join-Path $control 'run-current-verifyonly-20260844.ps1';$legacy=Join-Path $control 'bootstrap-verifyonly-20260828.ps1';$preflight=Join-Path $control 'active-preflight-authenticated-mailbox-compatibility.py';$adapter=Join-Path $control 'pdc-authenticated-monitor-runtime-adapter.py';$sealed=Join-Path $control 'run-current-sealed.ps1';$config=Join-Path $InstallRoot ("config\"+$ExpectedVersion+'\runtime.env');$launcher=Join-Path $root 'runtime_launcher.py'
 Assert-Hash $self (Read-Trust 'VERIFYONLY_RUNNER_SHA256') 'PDC_MONITOR_VERIFYONLY_RUNNER_HASH_MISMATCH';Assert-Hash $legacy (Read-Trust 'AUTHENTICATED_DISPATCH_BOOTSTRAP_SHA256') 'PDC_MONITOR_VERIFYONLY_LEGACY_BOOTSTRAP_HASH_MISMATCH';Assert-Hash $preflight (Read-Trust 'AUTHENTICATED_MAILBOX_PREFLIGHT_SHA256') 'PDC_MONITOR_VERIFYONLY_PREFLIGHT_HASH_MISMATCH';Assert-Hash $adapter (Read-Trust 'AUTHENTICATED_RUNTIME_ADAPTER_SHA256') 'PDC_MONITOR_VERIFYONLY_ADAPTER_HASH_MISMATCH';Assert-Hash $sealed (Read-Trust 'SEALED_RUN_CURRENT_SHA256') 'PDC_MONITOR_VERIFYONLY_SEALED_RUNNER_HASH_MISMATCH'
 if(-not(Test-Path -LiteralPath $config -PathType Leaf)){Fail 'PDC_MONITOR_VERIFYONLY_RUNTIME_ENV_MISSING'}
 $preflightArgs=@($preflight,'--release-root',$root,'--trust-root',$trust,'--env-file',$config,'--compatibility-path',$preflight,'--live','--require-terminal-uid514');$preflightOutput=& $venvPython -B -I -S @preflightArgs 2>&1|Out-String;if($LASTEXITCODE -ne 0){Fail 'PDC_MONITOR_VERIFYONLY_PREFLIGHT_DENIED'};try{$preflightResult=(($preflightOutput.Trim()-split "`r?`n")[-1]|ConvertFrom-Json)}catch{Fail 'PDC_MONITOR_VERIFYONLY_PREFLIGHT_OUTPUT_INVALID'};if($preflightResult.release_version -ne $ExpectedVersion -or [int]$preflightResult.migration_head -ne $ExpectedSealedMigrationHead -or [int]$preflightResult.compatibility_successor_head -ne $ExpectedCompatibilityHead -or $preflightResult.mailbox_contacted -ne $false -or $preflightResult.uid514_processed -ne $false -or $preflightResult.production_contacted -ne $false){Fail 'PDC_MONITOR_VERIFYONLY_HEAD_SEPARATION_MISMATCH'}
 $null=& $venvPython -B -I -S $launcher --release-root $root --venv-root $venv --mode smoke 2>&1|Out-String;if($LASTEXITCODE -ne 0){Fail 'PDC_MONITOR_VERIFYONLY_LAUNCHER_SMOKE_FAILED'}
 [Console]::WriteLine('{"ok":true,"verified":true,"verifyonly":true,"task_enabled":false,"task_started":false,"mailbox_contacted":false,"uid514_processed":false,"production_contacted":false}');exit 0
}catch{[Console]::Error.WriteLine('PDC_MONITOR_VERIFYONLY_DENIED');exit 1}
