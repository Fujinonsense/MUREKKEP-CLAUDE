param([string]$Source, [string]$Destination, [switch]$ContentsOnly)
# Builds a zip that macOS/iPadOS unpack correctly: forward-slash paths and an entry for every folder,
# like archives made on a Mac (Windows PowerShell's Compress-Archive writes backslashes instead).
# -ContentsOnly: the folder's contents are the zip's root (for a staged repository layout).
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Source = (Resolve-Path $Source).Path
$parent = if ($ContentsOnly) { $Source } else { Split-Path $Source -Parent }
if (Test-Path $Destination) { Remove-Item $Destination -Force -Confirm:$false }

$stream = [System.IO.File]::Open($Destination, [System.IO.FileMode]::CreateNew)
$zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $top = if ($ContentsOnly) { @() } else { @(Get-Item $Source) }
    $dirs = $top + @(Get-ChildItem $Source -Recurse -Directory -Force | Sort-Object FullName)
    foreach ($d in $dirs) {
        $rel = $d.FullName.Substring($parent.Length + 1).Replace('\', '/') + '/'
        [void]$zip.CreateEntry($rel)
    }
    foreach ($f in (Get-ChildItem $Source -Recurse -File -Force | Sort-Object FullName)) {
        $rel = $f.FullName.Substring($parent.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $zip.Dispose()
    $stream.Dispose()
}
