# Compiles the app's pure Swift files (Foundation only) with the Windows Swift toolchain and runs
# them against the Python twins' answers. usage: powershell -File tools\swiftcheck\run.ps1
# Not "Stop": the linker reports "creating library …" on stderr, which PowerShell would treat as fatal.
$ErrorActionPreference = "Continue"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
$env:SDKROOT = [System.Environment]::GetEnvironmentVariable("SDKROOT", "User")
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$app = Join-Path $root "Murekkep.swiftpm"
$files = @("InkDeskew.swift", "ChapterFinder.swift", "Questions.swift", "SpeechNumbers.swift", "ReadingOrder.swift", "Exercises.swift", "InkMeshPlan.swift", "InkLayer.swift", "PenSoundEnvelope.swift", "RecordingSync.swift", "ZoomBox.swift", "SpacedRepetition.swift", "StudyModels.swift", "StudyOffline.swift", "MindMapLayout.swift", "LocalServerFinder.swift", "TextSearch.swift", "BrainCatalog.swift", "TextPenBatch.swift", "BrainDownloadPlan.swift") | ForEach-Object { Join-Path $app $_ }
$out = Join-Path $env:TEMP "murekkep-swiftcheck"
New-Item -ItemType Directory -Force $out | Out-Null
$exe = Join-Path $out "check.exe"
if (Test-Path $exe) { Remove-Item $exe -Force }
& swiftc -O -swift-version 5 (Join-Path $PSScriptRoot "main.swift") (Join-Path $PSScriptRoot "Stubs.swift") @files -o $exe 2>&1 |
    ForEach-Object { "$_" } | Where-Object { $_ -notmatch "\.lib|\.exp|NativeCommandError|CategoryInfo|At .*run\.ps1|^\s*\+|^\s*$" }
if (-not (Test-Path $exe)) { Write-Output "compile failed"; exit 1 }
& $exe $root
exit $LASTEXITCODE
