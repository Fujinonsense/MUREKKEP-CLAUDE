# Compiles the iPad's real drafting instruments (Instruments.swift: Instrument, EdgeSnap) with the
# Windows Swift toolchain, runs them over seeded points round each instrument and writes what they
# answer into android/app/src/test/resources/instruments.txt, the fixture the Android edition's
# InstrumentsTest holds ink/Instruments.kt to.
# usage: powershell -File tools\instrumentcheck\run.ps1
# Not "Stop": the linker reports "creating library …" on stderr, which PowerShell would treat as fatal.
$ErrorActionPreference = "Continue"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
$env:SDKROOT = [System.Environment]::GetEnvironmentVariable("SDKROOT", "User")
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$app = Join-Path $root "Murekkep.swiftpm"
$out = Join-Path $env:TEMP "murekkep-instrumentcheck"
New-Item -ItemType Directory -Force $out | Out-Null
# CoreGraphics is Apple-only; Foundation on Windows has CGPoint, CGRect and CGFloat itself.
$text = [IO.File]::ReadAllText((Join-Path $app "Instruments.swift"))
$copy = Join-Path $out "Instruments.swift"
[IO.File]::WriteAllText($copy, $text.Replace("import CoreGraphics`r`n", "").Replace("import CoreGraphics`n", ""))
# The shape half of the file reads MathFormat and MathExpr (MathEngine.swift) and the stroke font,
# which tools/shapecheck's stubs stand in for.
$files = @($copy, (Join-Path $app "MathEngine.swift"), (Join-Path $root "tools\shapecheck\Stubs.swift"))
$exe = Join-Path $out "instrumentcheck.exe"
if (Test-Path $exe) { Remove-Item $exe -Force }
& swiftc -O -swift-version 5 (Join-Path $PSScriptRoot "main.swift") @files -o $exe 2>&1 |
    ForEach-Object { "$_" } | Where-Object { $_ -notmatch "\.lib|\.exp|NativeCommandError|CategoryInfo|At .*run\.ps1|^\s*\+|^\s*$" }
if (-not (Test-Path $exe)) { Write-Output "compile failed"; exit 1 }
& $exe (Join-Path $root "android\app\src\test\resources\instruments.txt")
exit $LASTEXITCODE
