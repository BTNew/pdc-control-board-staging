[CmdletBinding()] param([string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging")
$ErrorActionPreference='Stop';$version=(Get-Content (Join-Path $InstallRoot 'CURRENT') -Raw).Trim();$root=Join-Path $InstallRoot ("releases\"+$version)
$expected=(Get-Content (Join-Path $InstallRoot 'MANIFEST_SHA256') -Raw).Trim();& (Join-Path $root 'scripts\verify.ps1') -BundleRoot $root -ExpectedManifestSha256 $expected
if($LASTEXITCODE -ne 0){throw 'Installed release verification failed.'}
$envFile=Join-Path $InstallRoot 'config\runtime.env';if(-not(Test-Path $envFile)){throw 'runtime.env is missing.'}
$python=Join-Path $root '.venv\Scripts\python.exe';if(-not(Test-Path $python)){throw 'release virtual environment is missing.'}
& $python (Join-Path $root 'backend\pdc_email_intake_monitor.py') --env-file $envFile
exit $LASTEXITCODE
