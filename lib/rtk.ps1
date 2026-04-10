#Requires -Version 5.1
<#
    rtk.ps1 — Install and configure RTK (Windows).
    Do not run directly; dot-sourced by setup.ps1.
#>
function Get-RtkInstallDir {
    return Join-Path $env:USERPROFILE '.local\bin'
}
function Add-UserPathEntry {
    param([Parameter(Mandatory)][string]$PathEntry)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($userPath)) {
        $parts = $userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }
    $exists = $false
    foreach ($p in $parts) {
        if ($p.TrimEnd('\').ToLowerInvariant() -eq $PathEntry.TrimEnd('\').ToLowerInvariant()) {
            $exists = $true
            break
        }
    }
    if (-not $exists) {
        $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $PathEntry } else { "$userPath;$PathEntry" }
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
        if (($env:Path -split ';') -notcontains $PathEntry) {
            $env:Path = "$env:Path;$PathEntry"
        }
        Write-Info "Added '$PathEntry' to User PATH."
    }
}
function Get-RtkExecutablePath {
    $cmd = Get-Command rtk -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    $fallback = Join-Path (Get-RtkInstallDir) 'rtk.exe'
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    return $null
}
function Install-RtkFromGithubRelease {
    $apiUrl = 'https://api.github.com/repos/rtk-ai/rtk/releases/latest'
    $installDir = Get-RtkInstallDir
    if (-not (Test-Path -LiteralPath $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }
    Write-Info 'Downloading RTK latest release metadata...'
    $release = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json
    $asset = $release.assets | Where-Object { $_.name -eq 'rtk-x86_64-pc-windows-msvc.zip' } | Select-Object -First 1
    if (-not $asset) {
        throw 'RTK Windows asset not found in latest GitHub release.'
    }
    $zipPath = Join-Path $env:TEMP ("rtk-{0}.zip" -f [Guid]::NewGuid().ToString('N'))
    $extractDir = Join-Path $env:TEMP ("rtk-{0}" -f [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
    Write-Info "Downloading $($asset.name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
    $binary = Get-ChildItem -LiteralPath $extractDir -Recurse -File -Filter 'rtk.exe' | Select-Object -First 1
    if (-not $binary) {
        throw 'Downloaded RTK package does not contain rtk.exe.'
    }
    $target = Join-Path $installDir 'rtk.exe'
    Copy-Item -LiteralPath $binary.FullName -Destination $target -Force
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Add-UserPathEntry -PathEntry $installDir
    Write-Ok "RTK installed at $target"
    return $target
}
function Invoke-RtkInit {
    param([Parameter(Mandatory)][string[]]$Args)
    & rtk @Args
    if ($LASTEXITCODE -ne 0) {
        throw "rtk $($Args -join ' ') failed with exit code $LASTEXITCODE."
    }
}
function Invoke-RtkPhase {
    Write-StepHeader 'Phase 4 — RTK setup'
    $answer = (Read-Host "  Install/configure RTK for command token compression? (Y/n)").Trim().ToLowerInvariant()
    if ($answer -eq 'n' -or $answer -eq 'no') {
        Write-Info 'RTK phase skipped.'
        return
    }
    $rtkPath = Get-RtkExecutablePath
    if (-not $rtkPath) {
        try {
            $rtkPath = Install-RtkFromGithubRelease
        } catch {
            Write-Fail "Failed to install RTK: $_"
            return
        }
    } else {
        Write-Ok "RTK already installed: $rtkPath"
    }
    try {
        $version = (& rtk --version 2>&1 | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($version)) { Write-Info $version }
    } catch {
        Write-Warning 'Unable to read RTK version, continuing with setup.'
    }
    $choice = Read-MenuChoice -Title 'RTK integration target' -Options @(
        'Claude Code only'
        'Cursor only'
        'Both (Claude Code + Cursor)'
        'Skip configuration'
    ) -Default '3'
    try {
        switch ($choice) {
            '1' { Invoke-RtkInit -Args @('init','-g') }
            '2' { Invoke-RtkInit -Args @('init','-g','--agent','cursor') }
            '3' {
                Invoke-RtkInit -Args @('init','-g')
                Invoke-RtkInit -Args @('init','-g','--agent','cursor')
            }
            default {
                Write-Info 'RTK integration configuration skipped.'
                return
            }
        }
        Write-Ok 'RTK integration configured. Restart Claude/Cursor to apply hooks.'
    } catch {
        Write-Fail "RTK configuration failed: $_"
    }
}
