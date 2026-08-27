[CmdletBinding()] param([string]$InstallRoot="$env:ProgramData\PDCMonitor\Staging")
$ErrorActionPreference='Stop'
function Hash([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Missing protected file: $Path"};return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Assert-NoReparse([string]$Path,[string]$Label){$probe=[System.IO.Path]::GetFullPath($Path);while(-not[string]::IsNullOrWhiteSpace($probe)){if(Test-Path -LiteralPath $probe){$item=Get-Item -LiteralPath $probe -Force;if(($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){throw "$Label contains a reparse point."}};$parent=[System.IO.Path]::GetDirectoryName($probe);if([string]::IsNullOrWhiteSpace($parent)-or$parent -eq $probe){break};$probe=$parent}}
$current=Join-Path $InstallRoot 'CURRENT';if(-not(Test-Path -LiteralPath $current -PathType Leaf)){throw 'CURRENT pointer is missing.'};if((Get-Content -LiteralPath $current -Raw).Trim() -ne '2026.08.44'){throw 'Dispatch requires CURRENT 2026.08.44.'}
$control=Join-Path $InstallRoot 'control\2026.08.44';$trust=Join-Path $InstallRoot 'trust\2026.08.44';$runner=Join-Path $control 'run-current.ps1';$anchor=Join-Path $trust 'AUTHENTICATED_DISPATCH_RUNNER_SHA256'
Assert-NoReparse $control 'Protected dispatch control';Assert-NoReparse $trust 'Protected dispatch trust';if(-not(Test-Path -LiteralPath $anchor -PathType Leaf)){throw 'Dispatch runner trust anchor is missing.'};if((Hash $runner) -ne (Get-Content -LiteralPath $anchor -Raw).Trim().ToLowerInvariant()){throw 'Dispatch runner trust anchor mismatch.'}
& $runner -InstallRoot $InstallRoot -VerifyOnly
exit $LASTEXITCODE
