#Requires -Version 5.1
# Re-write all repo .ps1 files as UTF-8 with BOM (PS 5.1 -File needs BOM for Unicode literals).
$root = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $root 'setup.ps1'))) { throw "setup.ps1 not found under $root" }
$encBom = New-Object System.Text.UTF8Encoding $true
$encNoBom = New-Object System.Text.UTF8Encoding $false
Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' -File | ForEach-Object {
    $text = [System.IO.File]::ReadAllText($_.FullName, $encNoBom)
    [System.IO.File]::WriteAllText($_.FullName, $text, $encBom)
}
Write-Host "UTF-8 BOM applied under: $root"
