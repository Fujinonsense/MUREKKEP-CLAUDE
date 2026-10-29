# Compiles the iPad's real shape code (ShapeRecognizer.swift, ShapeEditing.swift, the shape tool of
# Instruments.swift, StrokeBuilder.swift) with the Windows Swift toolchain, runs it over deterministic
# hand-drawn strokes and writes what it answers into android/app/src/test/resources/shapes.txt, the
# fixture the Android edition's JUnit tests hold the Kotlin port to.
# usage: powershell -File tools\shapecheck\run.ps1
# Not "Stop": the linker reports "creating library …" on stderr, which PowerShell would treat as fatal.
$ErrorActionPreference = "Continue"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
$env:SDKROOT = [System.Environment]::GetEnvironmentVariable("SDKROOT", "User")
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$app = Join-Path $root "Murekkep.swiftpm"
$out = Join-Path $env:TEMP "murekkep-shapecheck"
New-Item -ItemType Directory -Force $out | Out-Null
# CoreGraphics is Apple-only; Foundation on Windows has CGPoint, CGRect and CGFloat itself.
$files = @()
foreach ($name in @("ShapeRecognizer.swift", "ShapeEditing.swift", "Instruments.swift")) {
    $text = [IO.File]::ReadAllText((Join-Path $app $name))
    $copy = Join-Path $out $name
    [IO.File]::WriteAllText($copy, $text.Replace("import CoreGraphics`r`n", "").Replace("import CoreGraphics`n", ""))
    $files += $copy
}
# Foundation-only as they are: the stroke builder, the pens it reads and MathFormat (the "42,3 mm" labels).
$files += @("StrokeBuilder.swift", "Brushes.swift", "MathEngine.swift") | ForEach-Object { Join-Path $app $_ }
$exe = Join-Path $out "shapecheck.exe"
if (Test-Path $exe) { Remove-Item $exe -Force }
& swiftc -O -swift-version 5 (Join-Path $PSScriptRoot "main.swift") (Join-Path $PSScriptRoot "Stubs.swift") @files -o $exe 2>&1 |
    ForEach-Object { "$_" } | Where-Object { $_ -notmatch "\.lib|\.exp|NativeCommandError|CategoryInfo|At .*run\.ps1|^\s*\+|^\s*$" }
if (-not (Test-Path $exe)) { Write-Output "compile failed"; exit 1 }
& $exe (Join-Path $root "android\app\src\test\resources\shapes.txt")
exit $LASTEXITCODE
