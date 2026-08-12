[CmdletBinding()] param([string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging")
$ErrorActionPreference='Stop';$service='PDC-PMB-Email-Monitor-Staging';$version=(Get-Content (Join-Path $InstallRoot 'CURRENT') -Raw).Trim();$root=Join-Path $InstallRoot ("releases\"+$version);$expected=(Get-Content (Join-Path $InstallRoot 'MANIFEST_SHA256') -Raw).Trim()
& (Join-Path $root 'scripts\verify.ps1') -BundleRoot $root -ExpectedManifestSha256 $expected
$envFile=Join-Path $InstallRoot 'config\runtime.env';if(-not(Test-Path $envFile)){throw 'runtime.env is missing.'}
$values=@{};Get-Content $envFile|Where-Object{$_ -match '^[A-Za-z_][A-Za-z0-9_]*='}|ForEach-Object{$k,$v=$_.Split('=',2);$values[$k]=$v}
if($values['SUPABASE_URL'] -ne 'https://cdsmnqxtyyoeoznmbidd.supabase.co'){throw 'Exact staging Supabase URL required.'}
if([int]$values['IMAP_BRIDGE_MINIMUM_UID'] -lt 471){throw 'Mailbox UID floor must be at least 471.'}
foreach($name in @('SUPABASE_ANON_KEY','PDC_MONITOR_ACCESS_TOKEN','IMAP_BRIDGE_USERNAME','IMAP_BRIDGE_PASSWORD','PDC_MONITOR_GATEWAY_INSTANCE_ID')){if([string]::IsNullOrWhiteSpace($values[$name])){throw "$name is missing."}}
Enable-ScheduledTask -TaskName $service|Out-Null;Start-ScheduledTask -TaskName $service
[pscustomobject]@{ok=$true;task=$service;enabled=$true;started=$true;release=$version}|ConvertTo-Json -Compress
