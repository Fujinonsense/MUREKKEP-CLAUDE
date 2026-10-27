# Compiles the break corner's game logic (MiniGameLogic, FlyerLogic, ShooterLogic, SudokuLogic, EbruLogic, LivingInkLogic, DotsLogic;
# Foundation only) with the Windows Swift toolchain and checks the mandala's mirror, the bubbles'
# rise and score, the XOX moves at each difficulty, the progression, the flyer's levels, the bubble
# shooter's levels and shots, the Sudoku maker and solver, the ebru tray's marbling and the living ink's pond, and the dots-and-boxes board and its three minds. usage: powershell -File tools\gamescheck\run.ps1
$ErrorActionPreference = "Continue"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
$env:SDKROOT = [System.Environment]::GetEnvironmentVariable("SDKROOT", "User")
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$app = Join-Path $root "Murekkep.swiftpm"
$files = @("MiniGameLogic.swift", "FlyerLogic.swift", "ShooterLogic.swift", "SudokuLogic.swift", "EbruLogic.swift", "LivingInkLogic.swift", "DotsLogic.swift") | ForEach-Object { Join-Path $app $_ }
$out = Join-Path $env:TEMP "murekkep-gamescheck"
New-Item -ItemType Directory -Force $out | Out-Null
$exe = Join-Path $out "check.exe"
if (Test-Path $exe) { Remove-Item $exe -Force }
& swiftc -O -swift-version 5 (Join-Path $PSScriptRoot "main.swift") @files -o $exe 2>&1 |
    ForEach-Object { "$_" } | Where-Object { $_ -notmatch "\.lib|\.exp|NativeCommandError|CategoryInfo|At .*run\.ps1|^\s*\+|^\s*$" }
if (-not (Test-Path $exe)) { Write-Output "compile failed"; exit 1 }
& $exe
exit $LASTEXITCODE
