# The text pen check: compiles the app's own InkLine.swift, HandwritingModel.swift and InkDeskew.swift
# with Windows Swift (Apple-only imports replaced by Shims.swift), reads the cases of gen_cases.py and
# compares every step with the Python twins.
# usage: powershell -File tools\textpencheck\run.ps1 <cases.json> [limit]
param([string]$Cases, [string]$Limit = "")
$ErrorActionPreference = "Continue"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
$env:SDKROOT = [System.Environment]::GetEnvironmentVariable("SDKROOT", "User")
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$app = Join-Path $root "Murekkep.swiftpm"
$out = Join-Path $env:TEMP "murekkep-textpencheck"
New-Item -ItemType Directory -Force $out | Out-Null
# The app's files as they are, minus the imports Windows does not have.
foreach ($name in @("HandwritingModel.swift", "InkLine.swift")) {
    $text = [IO.File]::ReadAllText((Join-Path $app $name))
    $text = $text -replace "(?m)^import (Accelerate|UIKit|CoreGraphics)\r?\n", ""
    [IO.File]::WriteAllText((Join-Path $out $name), $text)
}
$exe = Join-Path $out "textpen.exe"
if (Test-Path $exe) { Remove-Item $exe -Force }
$sources = @((Join-Path $PSScriptRoot "main.swift"), (Join-Path $PSScriptRoot "Shims.swift"),
             (Join-Path $out "HandwritingModel.swift"), (Join-Path $out "InkLine.swift"), (Join-Path $app "InkDeskew.swift"))
& swiftc -O -swift-version 5 @sources -o $exe 2>&1 |
    ForEach-Object { "$_" } | Where-Object { $_ -notmatch "\.lib|\.exp|NativeCommandError|CategoryInfo|At .*run\.ps1|^\s*\+|^\s*$" }
if (-not (Test-Path $exe)) { Write-Output "compile failed"; exit 1 }
$model = Join-Path $app "Assets.xcassets\hwmodel.dataset\hwmodel.bin"
if ($Limit) { & $exe $Cases $model $Limit } else { & $exe $Cases $model }
exit $LASTEXITCODE
