#Requires -Version 5.1
# Re-write all repo .ps1 files as UTF-8 with BOM (PS 5.1 -File needs BOM for Unicode literals).
$root = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $root 'setup.ps1'))) { throw "setup.ps1 not found under $root" }
$encBom = New-Object System.Text.UTF8Encoding $true
$encNoBom = New-Object System.Text.UTF8Encoding $false
Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -ne 'bootstrap.ps1' } | ForEach-Object {
    $text = [System.IO.File]::ReadAllText($_.FullName, $encNoBom)
    [System.IO.File]::WriteAllText($_.FullName, $text, $encBom)
}
$bootstrapPath = Join-Path $root 'bootstrap.ps1'
if (Test-Path -LiteralPath $bootstrapPath) {
    $boot = [System.IO.File]::ReadAllText($bootstrapPath, $encNoBom)
    if ($boot.Length -gt 0 -and $boot[0] -eq [char]0xFEFF) { $boot = $boot.Substring(1) }
    $boot = $boot.TrimEnd("`r", "`n") + [Environment]::NewLine
    [System.IO.File]::WriteAllText($bootstrapPath, $boot, $encNoBom)
    Write-Host "bootstrap.ps1: UTF-8 without BOM (remote iex)."
}
Write-Host "UTF-8 BOM applied under: $root (except bootstrap.ps1)"
