param(
    [string]$OutputPath = "KojoStream-sideload.zip"
)

$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$outputFullPath = Join-Path $projectRoot $OutputPath

if (Test-Path -LiteralPath $outputFullPath) {
    Remove-Item -LiteralPath $outputFullPath -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$sourceItems = @("manifest", "source", "components", "images")

$zip = [System.IO.Compression.ZipFile]::Open($outputFullPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $rootUri = New-Object System.Uri(($projectRoot.TrimEnd("\") + "\"))

    foreach ($item in $sourceItems) {
        $absItemPath = Join-Path $projectRoot $item
        if (-not (Test-Path -LiteralPath $absItemPath)) {
            throw "Missing required path: $item"
        }

        if ((Get-Item -LiteralPath $absItemPath).PSIsContainer) {
            Get-ChildItem -LiteralPath $absItemPath -Recurse -File | ForEach-Object {
                $fileUri = New-Object System.Uri($_.FullName)
                $relative = [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($fileUri).ToString())
                $entryName = $relative -replace "\\", "/"
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
            }
        } else {
            $entryName = $item -replace "\\", "/"
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $absItemPath, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    }
}
finally {
    $zip.Dispose()
}

Write-Host "Created Roku sideload zip: $outputFullPath"
