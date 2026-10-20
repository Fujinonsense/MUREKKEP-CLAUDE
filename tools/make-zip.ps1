param([string]$Source, [string]$Destination)
# Builds a zip that macOS/iPadOS unpack correctly: forward-slash paths and an entry for every folder,
# like archives made on a Mac (Windows PowerShell's Compress-Archive writes backslashes instead).
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Source = (Resolve-Path $Source).Path
$parent = Split-Path $Source -Parent
if (Test-Path $Destination) { Remove-Item $Destination -Force -Confirm:$false }

$stream = [System.IO.File]::Open($Destination, [System.IO.FileMode]::CreateNew)
$zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $dirs = @(Get-Item $Source) + @(Get-ChildItem $Source -Recurse -Directory | Sort-Object FullName)
    foreach ($d in $dirs) {
        $rel = $d.FullName.Substring($parent.Length + 1).Replace('\', '/') + '/'
        [void]$zip.CreateEntry($rel)
    }
    foreach ($f in (Get-ChildItem $Source -Recurse -File | Sort-Object FullName)) {
        $rel = $f.FullName.Substring($parent.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $zip.Dispose()
    $stream.Dispose()
}
