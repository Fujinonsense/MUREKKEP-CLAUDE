# Compiles the app's InkCodec.swift and SafeFiles.swift (an ink file this build cannot read is told
# apart from one a newer build wrote, a file is copied aside once, a JSON list is read entry by entry)
# with the Windows Swift toolchain and checks them. usage: powershell -File tools\safefilescheck\run.ps1
$ErrorActionPreference = "Continue"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
$env:SDKROOT = [System.Environment]::GetEnvironmentVariable("SDKROOT", "User")
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$app = Join-Path $root "Murekkep.swiftpm"
$files = @("InkCodec.swift", "SafeFiles.swift") | ForEach-Object { Join-Path $app $_ }
$out = Join-Path $env:TEMP "murekkep-safefilescheck"
New-Item -ItemType Directory -Force $out | Out-Null
$exe = Join-Path $out "check.exe"
if (Test-Path $exe) { Remove-Item $exe -Force }
& swiftc -O -swift-version 5 (Join-Path $PSScriptRoot "main.swift") (Join-Path $PSScriptRoot "Stubs.swift") @files -o $exe 2>&1 |
    ForEach-Object { "$_" } | Where-Object { $_ -notmatch "\.lib|\.exp|NativeCommandError|CategoryInfo|At .*run\.ps1|^\s*\+|^\s*$" }
if (-not (Test-Path $exe)) { Write-Output "compile failed"; exit 1 }
& $exe
exit $LASTEXITCODE
