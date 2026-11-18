# export.ps1
# Exports the addon folder as a zip with a proper root folder, excluding .git and export.ps1.
# Usage: .\export.ps1 [-Destination "C:\path\to\output"]

param(
    [string]$Destination = "$PSScriptRoot\.."
)

$Source    = $PSScriptRoot
$AddonName = Split-Path $Source -Leaf
$ZipPath   = Join-Path $Destination "$AddonName.zip"
$TempDir   = Join-Path $env:TEMP "RW_export_temp"
$StagingDir = Join-Path $TempDir $AddonName

# Copy into staging, excluding .git and export.ps1 from the start
if (Test-Path $TempDir) { Remove-Item -Recurse -Force $TempDir }
New-Item -ItemType Directory -Force -Path $StagingDir | Out-Null
robocopy $Source $StagingDir /E /XD ".git" ".github" ".vscode" "tests" "tools" "media" /XF "export.ps1" "run.ps1" ".luacheckrc" ".busted" ".luacov" ".stylua.toml" ".styluaignore" ".gitignore" ".pkgmeta" "luacov.stats.out" "luacov.report.out" | Out-Null

# Zip the named folder so the archive contains RankWarden/ at the root.
# Entries use forward slashes: Windows PowerShell 5.1's Compress-Archive writes
# backslashes, which some extractors (and addon managers) mishandle.
if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$ZipPath = [System.IO.Path]::GetFullPath($ZipPath)
$zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -Path $StagingDir -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($TempDir.Length + 1) -replace '\\', '/'
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $relative) | Out-Null
    }
} finally {
    $zip.Dispose()
}

# Clean up
Remove-Item -Recurse -Force $TempDir

Write-Host "Export complete: $ZipPath"
