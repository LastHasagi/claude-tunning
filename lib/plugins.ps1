#Requires -Version 5.1
<#
    plugins.ps1 — Environment check, fetch/parse/install for Claude Code plugins.
    Do not run directly; dot-sourced by setup.ps1.
#>

# ── Environment validation ────────────────────────────────────────────────────
function Assert-Environment {
    Write-StepHeader 'Phase 1 — Environment check'

    foreach ($cmd in 'node','npm') {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            Write-Fail "$cmd not found on PATH."
            if ($cmd -eq 'node') {
                Write-Info 'Install Node.js LTS from https://nodejs.org/ and reopen the terminal.'
            }
            exit 1
        }
    }

    $nodeVer = & node --version 2>&1
    $npmVer  = & npm  --version 2>&1
    Write-Ok "Node $nodeVer  /  npm $npmVer"

    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudeCmd) {
        $ver = (& claude --version 2>&1 | Out-String).Trim()
        Write-Ok "Claude Code: $ver"
        return
    }

    Write-Host "  $($script:Ansi.Y)⚠$($script:Ansi.Rst)  Claude Code not found."
    $ans = (Read-Host "  Install now via global npm? (y/N)").Trim().ToLower()
    if ($ans -ne 'y') {
        Write-Fail 'Claude Code is required for the plugin phase. Aborted.'
        exit 1
    }

    Write-Info 'Installing @anthropic-ai/claude-code...'
    & npm install -g @anthropic-ai/claude-code
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "npm install failed (exit $LASTEXITCODE)."
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                  [Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Info 'Tip: run PowerShell as Administrator or set a user-level npm prefix:'
            Write-Host "        npm config set prefix $env:APPDATA\npm"
        }
        exit 1
    }

    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Fail 'claude is still not on PATH. Restart the terminal or fix your npm prefix.'
        exit 1
    }

    Write-Ok 'Claude Code installed successfully.'
}

# ── Fetch and parse plugins.txt ───────────────────────────────────────────────
function Get-PluginLines {
    param(
        [string]$LocalPath,
        [string]$RemoteUrl,
        [string]$ScriptRoot
    )

    $rawLines = $null

    if ($LocalPath -and (Test-Path -LiteralPath $LocalPath)) {
        Write-Verbose "plugins.txt: local file '$LocalPath'"
        $rawLines = Get-Content -LiteralPath $LocalPath -Encoding UTF8
    } else {
        $sidePath = Join-Path $ScriptRoot 'plugins.txt'
        if (Test-Path -LiteralPath $sidePath) {
            Write-Verbose "plugins.txt: local file next to script"
            $rawLines = Get-Content -LiteralPath $sidePath -Encoding UTF8
        } else {
            $rawLines = Invoke-WithSpinner -Message 'Downloading plugins.txt...' -Action {
                param($url)
                (Invoke-WebRequest -Uri $url -UseBasicParsing).Content -split "`r?`n"
            } -ArgumentList @($RemoteUrl)
        }
    }

    $clean = [System.Collections.Generic.List[string]]::new()
    foreach ($ln in $rawLines) {
        $t = $ln.Trim()
        if ([string]::IsNullOrWhiteSpace($t) -or $t.StartsWith('#')) { continue }
        $clean.Add($t)
    }

    return ,$clean.ToArray()
}

# ── Selection filters ─────────────────────────────────────────────────────────
function Get-SeniorPluginPack {
    param(
        [string[]]$Lines,
        [string[]]$ExcludePatterns = @('railway','typescript')
    )
    return ,@($Lines | Where-Object {
        $low = $_.ToLowerInvariant()
        $exclude = $false
        foreach ($p in $ExcludePatterns) {
            if ($low.Contains($p.ToLowerInvariant())) { $exclude = $true; break }
        }
        -not $exclude
    })
}

# ── Claude CLI wrapper with EPERM retry ───────────────────────────────────────
function Invoke-ClaudeCommand {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$MaxAttempts  = 4,
        [int]$DelaySeconds = 4
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $lines = @(& claude @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        if ($lines.Count -gt 0) {
            Write-Host ($lines -join [Environment]::NewLine)
        }

        $combined = ($lines -join "`n").ToLowerInvariant()
        if ($combined -match 'eperm|operation not permitted|errno:\s*-4048|rename') {
            if ($attempt -lt $MaxAttempts) {
                Write-Warning "Plugin cache locked (attempt $attempt/$MaxAttempts). Close other 'claude' sessions and wait ${DelaySeconds}s..."
                Start-Sleep -Seconds $DelaySeconds
                continue
            }
        }
        break
    }
}

# ── Resolve marketplace.json in Claude cache ──────────────────────────────────
function Resolve-MarketplaceCachePath {
    param([string]$Owner, [string]$Repo)
    $slug = "$Owner-$Repo"
    return Join-Path $env:USERPROFILE ".claude\plugins\marketplaces\$slug"
}

function Find-MarketplaceJsonPath {
    param([string]$Owner, [string]$Repo)

    $primary = Join-Path (Resolve-MarketplaceCachePath -Owner $Owner -Repo $Repo) '.claude-plugin\marketplace.json'
    if (Test-Path -LiteralPath $primary) { return $primary }

    $marketBase = Join-Path $env:USERPROFILE '.claude\plugins\marketplaces'
    if (-not (Test-Path -LiteralPath $marketBase)) { return $null }

    $pattern = '(?i)github\.com[:/]' + [regex]::Escape($Owner) + '/' + [regex]::Escape($Repo) + '(\.git)?/?$'

    foreach ($dir in Get-ChildItem -LiteralPath $marketBase -Directory -ErrorAction SilentlyContinue) {
        $candidate = Join-Path $dir.FullName '.claude-plugin\marketplace.json'
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName '.git'))) { continue }

        try {
            $remote = & git -C $dir.FullName remote get-url origin 2>$null | Select-Object -First 1
        } catch {
            $remote = $null
        }

        if ($remote -and [regex]::IsMatch([string]$remote, $pattern)) { return $candidate }
    }

    return $null
}

function Read-MarketplaceSpec {
    param([string]$Owner, [string]$Repo)

    # Known overrides (avoid depending on clone for verified repos)
    $known = @{
        'obra/superpowers'      = [PSCustomObject]@{ MarketplaceId = 'superpowers-dev'; PluginName = 'superpowers' }
        'thedotmack/claude-mem' = [PSCustomObject]@{ MarketplaceId = 'thedotmack';      PluginName = 'claude-mem'  }
    }
    $key = "$Owner/$Repo"
    if ($known.ContainsKey($key)) { return $known[$key] }

    $mf = Find-MarketplaceJsonPath -Owner $Owner -Repo $Repo
    if (-not $mf) { return $null }

    try {
        $j = Get-Content -LiteralPath $mf -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }

    $marketId = [string]$j.name
    if ([string]::IsNullOrWhiteSpace($marketId)) { return $null }

    $plugins = @($j.plugins)
    if ($plugins.Count -eq 0) { return $null }

    $pick = $plugins | Where-Object { $_.name -eq $Repo } | Select-Object -First 1
    if (-not $pick) { $pick = $plugins[0] }

    $pluginName = [string]$pick.name
    if ([string]::IsNullOrWhiteSpace($pluginName)) { return $null }

    return [PSCustomObject]@{ MarketplaceId = $marketId; PluginName = $pluginName }
}

# ── Install one plugin line ───────────────────────────────────────────────────
function Invoke-PluginLine {
    param([Parameter(Mandatory)][string]$Line)

    # Format: claude.com/plugins URL
    if ($Line -match 'https?://claude\.com/plugins/([^/\s?#]+)') {
        $slug = $Matches[1]
        Write-Verbose "  → claude plugin install $slug@claude-plugins-official"
        Invoke-ClaudeCommand -Arguments @('plugin','install',"$slug@claude-plugins-official",'--scope','user')
        return
    }

    # Format: GitHub repository
    if ($Line -match 'https?://github\.com/([^/]+)/([^/\s?#]+)') {
        $owner = $Matches[1]
        $repo  = $Matches[2]

        Write-Verbose "  → claude plugin marketplace add $owner/$repo"
        Invoke-ClaudeCommand -Arguments @('plugin','marketplace','add',"$owner/$repo",'--scope','user')

        $spec = Read-MarketplaceSpec -Owner $owner -Repo $repo
        if (-not $spec) {
            Write-Warning "No marketplace.json in cache for $owner/$repo."
            Write-Warning 'The repo may not be a Claude marketplace, or the git clone failed.'
            Write-Warning 'If you use SSH, run once: ssh -T git@github.com'
            Write-Warning 'To force HTTPS: git config --global url.https://github.com/.insteadOf git@github.com:'
            return
        }

        Write-Verbose "  → claude plugin install $($spec.PluginName)@$($spec.MarketplaceId)"
        Invoke-ClaudeCommand -Arguments @('plugin','install',"$($spec.PluginName)@$($spec.MarketplaceId)",'--scope','user')
        return
    }

    Write-Warning "Unrecognized plugin line (skipped): $Line"
}

# ── Plugin phase orchestration ────────────────────────────────────────────────
function Invoke-PluginPhase {
    param(
        [string]$LocalPluginsPath,
        [string]$PluginsRawUrl,
        [string]$ScriptRoot
    )

    Write-StepHeader 'Phase 2 — Plugins'

    $allLines = Get-PluginLines -LocalPath $LocalPluginsPath -RemoteUrl $PluginsRawUrl -ScriptRoot $ScriptRoot

    if ($allLines.Count -eq 0) {
        Write-Warning 'No valid plugin lines found.'
        return
    }

    $modeChoice = Show-PluginModeMenu

    $toInstall = switch ($modeChoice) {
        '1' { Get-SeniorPluginPack -Lines $allLines }
        '2' {
            Write-Host ""
            Select-PluginsInteractive -Lines $allLines
        }
        '3' { $allLines }
        '4' { @() }
        default { Write-Warning 'Invalid option; plugins skipped.'; @() }
    }

    if ($toInstall.Count -eq 0) {
        Write-Info 'No plugins selected.'
        return
    }

    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Warning 'claude CLI is not on PATH; cannot install plugins.'
        return
    }

    Write-Host ""
    Write-Info "Close other interactive 'claude' sessions to avoid cache errors (EPERM)."
    Write-Host ""

    $total = $toInstall.Count
    for ($idx = 0; $idx -lt $total; $idx++) {
        $ln = $toInstall[$idx]
        Write-PluginProgress -Current ($idx + 1) -Total $total -Name ($ln -replace 'https?://[^/]+/', '')
        Write-Host ""
        Write-Host "  $($script:Ansi.Bo)$ln$($script:Ansi.Rst)"
        try {
            Invoke-PluginLine -Line $ln
            Write-Ok 'Installed'
        } catch {
            Write-Fail "Failed: $_"
        }
        Write-Host ""
    }

    Write-Progress -Activity 'Installing plugins' -Completed
    Write-Ok "$total plugin(s) processed."
}
