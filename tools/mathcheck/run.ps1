# Compiles the app's math engine (MathEngine.swift, ExactMath.swift, PageMath.swift), MathText.swift
# and Questions.swift with the Windows Swift toolchain and runs them against a page of textbook
# exercises: the exact answers, the check of a model's answer by substitution, the filler dropped from
# the shown steps. usage: powershell -File tools\mathcheck\run.ps1
$ErrorActionPreference = "Continue"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
$env:SDKROOT = [System.Environment]::GetEnvironmentVariable("SDKROOT", "User")
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$app = Join-Path $root "Murekkep.swiftpm"
$files = @("MathEngine.swift", "ExactMath.swift", "PageMath.swift", "MathText.swift", "Questions.swift") | ForEach-Object { Join-Path $app $_ }
$out = Join-Path $env:TEMP "murekkep-mathcheck"
New-Item -ItemType Directory -Force $out | Out-Null
$exe = Join-Path $out "check.exe"
if (Test-Path $exe) { Remove-Item $exe -Force }
& swiftc -O -swift-version 5 (Join-Path $PSScriptRoot "main.swift") (Join-Path $PSScriptRoot "Stubs.swift") @files -o $exe 2>&1 |
    ForEach-Object { "$_" } | Where-Object { $_ -notmatch "\.lib|\.exp|NativeCommandError|CategoryInfo|At .*run\.ps1|^\s*\+|^\s*$" }
if (-not (Test-Path $exe)) { Write-Output "compile failed"; exit 1 }
& $exe
exit $LASTEXITCODE
