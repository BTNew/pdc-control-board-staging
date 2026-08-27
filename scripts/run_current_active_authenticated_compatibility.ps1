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
if($version -ne '2026.08.44'){throw 'Authenticated compatibility requires CURRENT 2026.08.44.'}
$root=Join-Path $InstallRoot ("releases\"+$version);$venv=Join-Path $InstallRoot ("venvs\"+$version);$trust=Join-Path $InstallRoot ("trust\"+$version);$control=Join-Path $InstallRoot ("control\"+$version);$config=Join-Path $InstallRoot ("config\"+$version+'\runtime.env')
$manifest=Join-Path $root 'release-manifest.json';Assert-FileHash $manifest (Read-Trust $trust 'MANIFEST_SHA256') 'Release manifest'
$compatibility=Join-Path $control 'active-preflight-authenticated-compatibility.py';Assert-FileHash $compatibility (Read-Trust $trust 'ACTIVE_PREFLIGHT_AUTHENTICATED_COMPATIBILITY_SHA256') 'External authenticated active preflight successor';Assert-NoReparse $compatibility 'External authenticated active preflight successor'
if($StaticOnly){[pscustomobject]@{ok=$true;static_verified=$true;release=$version;authenticated_successor=$true;network_contacted=$false;intake_started=$false}|ConvertTo-Json -Compress;exit 0}
if(-not(Test-Path -LiteralPath $config -PathType Leaf)){throw 'Versioned runtime environment is missing.'}
$venvPython=Join-Path $venv 'Scripts\python.exe';$args=@($compatibility,'--release-root',$root,'--trust-root',$trust,'--env-file',$config,'--compatibility-path',$compatibility,'--live')
if($VerifyOnly -or $RecoveryEventId -eq 0){$args+='--require-terminal-uid514'}
& $venvPython -B -I -S @args;if($LASTEXITCODE -ne 0){throw 'Authenticated active compatibility or credential preflight failed.'}
if($VerifyOnly){[pscustomobject]@{ok=$true;verified=$true;release=$version;authenticated_successor=$true;intake_started=$false}|ConvertTo-Json -Compress;exit 0}
throw 'Authenticated successor is verification-only; task execution remains disabled.'
