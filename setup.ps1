#Requires -Version 5.1
<#
.SYNOPSIS
  Z3R0 Claude — instalação e configuração assistida do Claude Code, plugins e MCP (Windows).

.DESCRIPTION
  Fases: validação (Node + Claude Code), gestão de plugins (ficheiro local ou raw GitHub), fusão de MCP em claude_desktop_config.json.

.EXAMPLE
  irm https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/setup.ps1 | iex

.EXAMPLE
  .\setup.ps1 -LocalPluginsPath .\plugins.txt -SkipMcp
#>
[CmdletBinding()]
param(
    [string]$LocalPluginsPath = '',
    [string]$PluginsRawUrl = 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/plugins.txt',
    [switch]$SkipMcp,
    [switch]$SkipPlugins,
    [string]$ClaudeDesktopConfigPath = ''
)

$ErrorActionPreference = 'Stop'

function Write-Z3R0Banner {
    $innerW = 73
    $rule = ('#' * 75)

    function Get-Z3R0BannerRow {
        param([string]$Text)
        if ($Text.Length -gt $innerW) { $Text = $Text.Substring(0, $innerW) }
        $pad = $innerW - $Text.Length
        $L = [int][Math]::Floor($pad / 2)
        $R = $pad - $L
        return '#' + (' ' * $L) + $Text + (' ' * $R) + '#'
    }

    Write-Host $rule -ForegroundColor Cyan
    Write-Host ('#' + (' ' * $innerW) + '#') -ForegroundColor Cyan
    Write-Host (Get-Z3R0BannerRow 'Z3R0 / CLAUDE CODE') -ForegroundColor Cyan
    Write-Host (Get-Z3R0BannerRow 'automated setup :: plugins + MCP') -ForegroundColor Cyan
    Write-Host ('#' + (' ' * $innerW) + '#') -ForegroundColor Cyan
    Write-Host (Get-Z3R0BannerRow 'Developed by: Z3R0') -ForegroundColor Cyan
    Write-Host (Get-Z3R0BannerRow 'GitHub:  https://github.com/LastHasagi') -ForegroundColor Cyan
    Write-Host (Get-Z3R0BannerRow 'LinkedIn: https://www.linkedin.com/in/rodrigo-de-souza-graca/') -ForegroundColor Cyan
    Write-Host ('#' + (' ' * $innerW) + '#') -ForegroundColor Cyan
    Write-Host $rule -ForegroundColor Cyan
}

function Test-Administrator {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal $id
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-CommandInPath {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-Z3R0PluginLines {
    param([string]$LocalPath, [string]$RemoteUrl, [string]$ScriptDirectory)

    $candidates = @()
    if ($LocalPath -and (Test-Path -LiteralPath $LocalPath)) {
        $candidates += (Get-Content -LiteralPath $LocalPath -Encoding UTF8)
    } elseif ($ScriptDirectory -and (Test-Path -LiteralPath (Join-Path $ScriptDirectory 'plugins.txt'))) {
        $side = Join-Path $ScriptDirectory 'plugins.txt'
        $candidates += (Get-Content -LiteralPath $side -Encoding UTF8)
    } else {
        Write-Host "[*] Fetching remote plugins.txt: $RemoteUrl" -ForegroundColor Yellow
        $candidates += (Invoke-WebRequest -Uri $RemoteUrl -UseBasicParsing).Content -split "`r?`n"
    }

    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $candidates) {
        $t = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        if ($t.StartsWith('#')) { continue }
        $out.Add($t) | Out-Null
    }
    return ,$out.ToArray()
}

function Get-SeniorPluginPack {
    param(
        [string[]]$Lines,
        [string[]]$ExcludeSubstrings = @('railway', 'typescript')
    )
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        $low = $line.ToLowerInvariant()
        $skip = $false
        foreach ($ex in $ExcludeSubstrings) {
            if ($low.Contains($ex.ToLowerInvariant())) { $skip = $true; break }
        }
        if (-not $skip) { $list.Add($line) | Out-Null }
    }
    return ,$list.ToArray()
}

function Get-MarketplaceIdFromGitHub {
    param([string]$Owner, [string]$Repo)
    return "$Owner-$Repo" -replace '/', '-'
}

function Get-ClaudeMarketplaceCachePath {
    param([string]$Owner, [string]$Repo)
    $slug = Get-MarketplaceIdFromGitHub -Owner $Owner -Repo $Repo
    return (Join-Path $env:USERPROFILE (Join-Path '.claude\plugins\marketplaces' $slug))
}

function Get-ClaudeMarketplaceJsonPath {
    param([string]$Owner, [string]$Repo)

    $primary = Join-Path (Get-ClaudeMarketplaceCachePath -Owner $Owner -Repo $Repo) '.claude-plugin\marketplace.json'
    if (Test-Path -LiteralPath $primary) {
        return $primary
    }

    $marketBase = Join-Path $env:USERPROFILE '.claude\plugins\marketplaces'
    if (-not (Test-Path -LiteralPath $marketBase)) {
        return $null
    }

    $pat = '(?i)github\.com[:/]' + [regex]::Escape($Owner) + '/' + [regex]::Escape($Repo) + '(\.git)?/?$'
    foreach ($d in Get-ChildItem -LiteralPath $marketBase -Directory -ErrorAction SilentlyContinue) {
        $candidate = Join-Path $d.FullName '.claude-plugin\marketplace.json'
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $d.FullName '.git'))) { continue }
        try {
            $remote = (& git -C $d.FullName remote get-url origin 2>$null | Select-Object -First 1)
        } catch {
            $remote = $null
        }
        if ($remote -and [regex]::IsMatch([string]$remote, $pat)) {
            return $candidate
        }
    }

    return $null
}

function Invoke-ClaudePluginCommand {
    <#
    Executa o CLI claude com argumentos; em EPERM/rename (cache bloqueada por outra sessao), reintenta.
    #>
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$MaxAttempts = 4,
        [int]$DelaySeconds = 4
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $lines = @(& claude @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        if ($lines.Count -gt 0) {
            Write-Host ($lines -join [Environment]::NewLine)
        }
        $text = ($lines -join "`n").ToLowerInvariant()
        if ($text -match 'eperm|operation not permitted|errno:\s*-4048|rename') {
            if ($attempt -lt $MaxAttempts) {
                Write-Warning "Plugin cache lock (try $attempt / $MaxAttempts). Close other interactive 'claude' sessions, then retry in ${DelaySeconds}s..."
                Start-Sleep -Seconds $DelaySeconds
                continue
            }
        }
        break
    }
}

function Read-ClaudeMarketplaceInstallSpec {
    <#
    Lê .claude-plugin/marketplace.json no cache (pasta pode ser owner-repo OU outro nome após cleanup do Claude).
    O ID do marketplace e o campo "name" do JSON (ex.: superpowers-dev).
    #>
    param([string]$Owner, [string]$Repo)

    $known = @{
        'obra/superpowers'       = @{ MarketplaceId = 'superpowers-dev'; PluginName = 'superpowers' }
        'thedotmack/claude-mem'  = @{ MarketplaceId = 'thedotmack'; PluginName = 'claude-mem' }
    }
    $key = "$Owner/$Repo"
    if ($known.ContainsKey($key)) {
        return [PSCustomObject]$known[$key]
    }

    $mf = Get-ClaudeMarketplaceJsonPath -Owner $Owner -Repo $Repo
    if (-not $mf) {
        return $null
    }
    try {
        $j = Get-Content -LiteralPath $mf -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
    $marketId = [string]$j.name
    if ([string]::IsNullOrWhiteSpace($marketId)) {
        return $null
    }
    $plist = @($j.plugins)
    if ($plist.Count -eq 0) {
        return $null
    }
    $pick = $plist | Where-Object { $_.name -eq $Repo } | Select-Object -First 1
    if (-not $pick) {
        $pick = $plist[0]
    }
    $pname = [string]$pick.name
    if ([string]::IsNullOrWhiteSpace($pname)) {
        return $null
    }
    return [PSCustomObject]@{ MarketplaceId = $marketId; PluginName = $pname }
}

function Invoke-ClaudePluginInstallLine {
    param([string]$Line)

    if ($Line -match 'https?://claude\.com/plugins/([^/\s?#]+)') {
        $slug = $Matches[1]
        Write-Host "  -> claude plugin install ${slug}@claude-plugins-official" -ForegroundColor DarkGray
        Invoke-ClaudePluginCommand -Arguments @('plugin', 'install', "$slug@claude-plugins-official", '--scope', 'user')
        return
    }

    if ($Line -match 'https?://github\.com/([^/]+)/([^/\s?#]+)') {
        $owner = $Matches[1]
        $repo = $Matches[2]
        Write-Host "  -> claude plugin marketplace add $owner/$repo" -ForegroundColor DarkGray
        Invoke-ClaudePluginCommand -Arguments @('plugin', 'marketplace', 'add', "$owner/$repo", '--scope', 'user')

        $spec = Read-ClaudeMarketplaceInstallSpec -Owner $owner -Repo $repo
        if (-not $spec) {
            Write-Warning "No .claude-plugin/marketplace.json in Claude cache for $owner/$repo."
            Write-Warning 'Repo may not be a Claude marketplace (e.g. no marketplace.json), or git clone failed.'
            Write-Warning 'If SSH failed: run once: ssh -T git@github.com'
            Write-Warning 'Or force GitHub HTTPS: git config --global url.https://github.com/.insteadOf git@github.com:'
            return
        }

        Write-Host "  -> claude plugin install $($spec.PluginName)@$($spec.MarketplaceId)" -ForegroundColor DarkGray
        Invoke-ClaudePluginCommand -Arguments @('plugin', 'install', "$($spec.PluginName)@$($spec.MarketplaceId)", '--scope', 'user')
        return
    }

    Write-Warning "Unrecognized plugin line (skipped): $Line"
}

function Show-Z3R0PluginModeMenu {
    Write-Host ""
    Write-Host " === Plugins Claude Code ===" -ForegroundColor Green
    Write-Host "  [1] Senior Package"
    Write-Host "  [2] Pick lines manually"
    Write-Host "  [3] Install all plugins"
    Write-Host "  [4] Skip plugins"
    $c = Read-Host "Option (1-4)"
    return $c.Trim()
}

function Select-LinesInteractive {
    param([string[]]$Lines)

    $objects = foreach ($ln in $Lines) { [PSCustomObject]@{ Plugin = $ln } }

    if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
        $picked = $objects | Out-GridView -Title 'Z3R0 Claude - pick plugins' -PassThru
        if ($picked) { return @($picked | ForEach-Object { $_.Plugin }) }
        return @()
    }

    Write-Host "Out-GridView unavailable; enter numbers (e.g. 1,3,5) or 'a' for all:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $Lines[$i])
    }
    $r = Read-Host "Numbers (e.g. 1,2) or 'a'"
    if ($r -eq 'a') { return ,$Lines }
    $nums = $r -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    $sel = New-Object System.Collections.Generic.List[string]
    foreach ($n in $nums) {
        if ($n -ge 1 -and $n -le $Lines.Count) { $sel.Add($Lines[$n - 1]) | Out-Null }
    }
    return ,$sel.ToArray()
}

function Get-Z3R0DefaultMcpServers {
    return @{
        'context7' = @{
            command = 'npx'
            args    = @('-y', '@upstash/context7-mcp@latest')
        }
        'langchain-docs' = @{
            url = 'https://docs.langchain.com/mcp'
        }
        '21st-dev-magic' = @{
            command = 'npx'
            args    = @('-y', '@21st-dev/magic@latest')
            env     = @{
                TWENTY_FIRST_API_KEY = 'REPLACE_WITH_KEY_FROM_https://21st.dev_magic_console'
            }
        }
    }
}

function Convert-Z3R0ToJssObject {
    <#
    Converte Hashtable/listas PowerShell para tipos que JavaScriptSerializer serializa de forma fiavel.
    Evita ConvertTo-Json no Windows PowerShell 5.1 (erros de "conjunto de parametros" em alguns casos).
    #>
    param($Node)
    if ($null -eq $Node) { return $null }
    if ($Node -is [string] -or $Node -is [bool] -or $Node -is [int] -or $Node -is [long] -or $Node -is [double] -or $Node -is [decimal]) {
        return $Node
    }
    if ($Node -is [hashtable]) {
        $d = New-Object 'System.Collections.Generic.Dictionary[string,Object]'
        foreach ($k in $Node.Keys) {
            # Nao usar $d['k']= no PS: associa ETS e JavaScriptSerializer.Serialize() falha (referencia circular).
            [void]$d.Add([string]$k, (Convert-Z3R0ToJssObject $Node[$k]))
        }
        return $d
    }
    if ($Node -is [System.Collections.IDictionary]) {
        $d = New-Object 'System.Collections.Generic.Dictionary[string,Object]'
        foreach ($k in $Node.Keys) {
            [void]$d.Add([string]$k, (Convert-Z3R0ToJssObject $Node[$k]))
        }
        return $d
    }
    if ($Node -is [System.Collections.IList] -and $Node -isnot [string]) {
        $arr = New-Object System.Collections.Generic.List[Object]
        foreach ($it in $Node) {
            $arr.Add((Convert-Z3R0ToJssObject $it)) | Out-Null
        }
        return $arr.ToArray()
    }
    return $Node
}

function Merge-McpIntoClaudeDesktopConfig {
    param(
        [string]$ConfigPath,
        [hashtable]$AddServers
    )

    Add-Type -AssemblyName System.Web.Extensions
    $jss = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $jss.MaxJsonLength = [Int32]::MaxValue

    # PS 5.1: Split-Path -LiteralPath e -Parent nao podem ir juntos (AmbiguousParameterSet).
    $dir = [System.IO.Path]::GetDirectoryName($ConfigPath)
    if ([string]::IsNullOrWhiteSpace($dir)) {
        throw "ClaudeDesktopConfigPath must include a directory (got: '$ConfigPath')."
    }
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $raw = '{}'
    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $raw = [System.IO.File]::ReadAllText($ConfigPath, $utf8)
        } catch {
            $raw = '{}'
        }
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = '{}' }

    try {
        $parsed = $jss.DeserializeObject($raw)
        # PS envolve Dictionary em ETS; Serialize() rebenta com referencia circular (PSParameterizedProperty).
        if ($parsed -is [System.Collections.IDictionary]) {
            $root = (Convert-Z3R0ToJssObject $parsed)
        } else {
            $root = New-Object 'System.Collections.Generic.Dictionary[string,Object]'
        }
    } catch {
        $bak = "$ConfigPath.bak.z3r0-$(Get-Date -Format 'yyyyMMddHHmmss')"
        if (Test-Path -LiteralPath $ConfigPath) {
            Copy-Item -LiteralPath $ConfigPath -Destination $bak -Force
            Write-Warning "Invalid JSON; backup: $bak"
        }
        $root = (New-Object 'System.Collections.Generic.Dictionary[string,Object]')
    }

    if ($null -eq $root -or $root -isnot [System.Collections.IDictionary]) {
        $root = New-Object 'System.Collections.Generic.Dictionary[string,Object]'
    }

    $mcp = $null
    if ($root.ContainsKey('mcpServers') -and $null -ne $root['mcpServers'] -and $root['mcpServers'] -is [System.Collections.IDictionary]) {
        $mcp = $root['mcpServers']
    } else {
        if ($root.ContainsKey('mcpServers')) {
            [void]$root.Remove('mcpServers')
        }
        $mcp = New-Object 'System.Collections.Generic.Dictionary[string,Object]'
        [void]$root.Add('mcpServers', $mcp)
    }

    foreach ($k in @($AddServers.Keys)) {
        $plain = (Convert-Z3R0ToJssObject $AddServers[$k])
        if ($mcp.ContainsKey($k)) {
            [void]$mcp.Remove($k)
        }
        [void]$mcp.Add($k, $plain)
    }

    $json = $jss.Serialize($root)
    [System.IO.File]::WriteAllText($ConfigPath, $json, $utf8)
}

# --- main ---
Write-Z3R0Banner

# Phase 1
Write-Host "`n[Phase 1] Environment check" -ForegroundColor Green

if (-not (Test-CommandInPath -Name 'node')) {
    Write-Host "ERROR: Node.js is not on PATH. Install Node.js LTS and reopen the terminal." -ForegroundColor Red
    Write-Host "       https://nodejs.org/" -ForegroundColor Yellow
    exit 1
}
if (-not (Test-CommandInPath -Name 'npm')) {
    Write-Host "ERROR: npm is not on PATH." -ForegroundColor Red
    exit 1
}

Write-Host "  Node: ok ($(node -v)) / npm: ok ($(npm -v))" -ForegroundColor DarkGreen

$claudeOk = Test-CommandInPath -Name 'claude'
if ($claudeOk) {
    $ver = (& claude --version 2>&1 | Out-String).Trim()
    Write-Host "  Claude Code: $ver" -ForegroundColor DarkGreen
}

if (-not $claudeOk) {
    Write-Host "Claude Code not found (claude command)." -ForegroundColor Yellow
    if ($SkipPlugins) {
        Write-Host "  (-SkipPlugins: continuing without Claude Code CLI.)" -ForegroundColor DarkYellow
    } else {
        $ans = Read-Host "Install now with npm global? (y/n)"
        if ($ans -eq 'y' -or $ans -eq 'Y') {
            npm install -g @anthropic-ai/claude-code
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Global npm install failed (exit $LASTEXITCODE)." -ForegroundColor Red
                if (-not (Test-Administrator)) {
                    Write-Host "Tip: run PowerShell as Administrator OR set a user npm prefix:" -ForegroundColor Yellow
                    Write-Host "  npm config set prefix $env:APPDATA\npm" -ForegroundColor Gray
                    Write-Host "  and add $env:APPDATA\npm to PATH." -ForegroundColor Gray
                }
                exit 1
            }
            if (-not (Test-CommandInPath -Name 'claude')) {
                Write-Host "ERROR: claude is still not on PATH. Restart the terminal or fix npm prefix." -ForegroundColor Red
                exit 1
            }
        } else {
            Write-Host "Aborted: Claude Code is required for the plugin phase." -ForegroundColor Red
            exit 1
        }
    }
}

# Phase 2
if (-not $SkipPlugins) {
    Write-Host "`n[Phase 2] Plugins" -ForegroundColor Green
    $allLines = Get-Z3R0PluginLines -LocalPath $LocalPluginsPath -RemoteUrl $PluginsRawUrl -ScriptDirectory $PSScriptRoot
    if ($allLines.Count -eq 0) {
        Write-Warning "No valid plugin lines found."
    } else {
        $mode = Show-Z3R0PluginModeMenu
        $toInstall = @()
        switch ($mode) {
            '1' { $toInstall = Get-SeniorPluginPack -Lines $allLines }
            '2' { $toInstall = Select-LinesInteractive -Lines $allLines }
            '3' { $toInstall = $allLines }
            '4' { $toInstall = @() }
            default {
                Write-Warning "Invalid option; skipping plugins."
                $toInstall = @()
            }
        }

        if ($toInstall.Count -gt 0) {
            if (-not (Test-CommandInPath -Name 'claude')) {
                Write-Warning "claude CLI not on PATH; cannot install plugins. Install Claude Code and re-run."
            } else {
                Write-Host "Tip: close other interactive 'claude' sessions to avoid EPERM / cache rename errors during installs." -ForegroundColor DarkYellow
                Write-Host "Installing $($toInstall.Count) item(s)..." -ForegroundColor Cyan
                foreach ($ln in $toInstall) {
                    Write-Host "`n[*] $ln" -ForegroundColor White
                    try {
                        Invoke-ClaudePluginInstallLine -Line $ln
                    } catch {
                        Write-Warning "Failed: $_"
                    }
                }
            }
        } else {
            Write-Host "No plugins selected to install." -ForegroundColor DarkYellow
        }
    }
} else {
    Write-Host "`n[Phase 2] Plugins skipped (-SkipPlugins)." -ForegroundColor DarkYellow
}

# Phase 3
if (-not $SkipMcp) {
    Write-Host "`n[Phase 3] MCP" -ForegroundColor Green

    $claudeCodeSettingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
    $claudeDesktopPath      = Join-Path $env:APPDATA   'Claude\claude_desktop_config.json'

    # Decide targets
    $targets = [System.Collections.Generic.List[string]]::new()

    if ($ClaudeDesktopConfigPath) {
        # Explicit override via param - use as-is
        $targets.Add($ClaudeDesktopConfigPath)
    } else {
        $claudeCodeExists  = Test-Path -LiteralPath $claudeCodeSettingsPath
        $claudeDesktopExists = Test-Path -LiteralPath $claudeDesktopPath

        Write-Host ""
        Write-Host "  Detected Claude configs:" -ForegroundColor Cyan
        Write-Host ("  [1] Claude Code CLI : {0} {1}" -f $claudeCodeSettingsPath, $(if ($claudeCodeExists) {'(exists)'} else {'(will create)'})) -ForegroundColor White
        Write-Host ("  [2] Claude Desktop  : {0} {1}" -f $claudeDesktopPath, $(if ($claudeDesktopExists) {'(exists)'} else {'(not found)'})) -ForegroundColor White
        Write-Host "  [3] Both" -ForegroundColor White
        Write-Host "  [4] Skip MCP" -ForegroundColor White
        $mcpChoice = (Read-Host "  Target (1-4) [default: 1]").Trim()
        if ([string]::IsNullOrWhiteSpace($mcpChoice)) { $mcpChoice = '1' }

        switch ($mcpChoice) {
            '1' { $targets.Add($claudeCodeSettingsPath) }
            '2' { $targets.Add($claudeDesktopPath) }
            '3' { $targets.Add($claudeCodeSettingsPath); $targets.Add($claudeDesktopPath) }
            '4' { $targets = [System.Collections.Generic.List[string]]::new() }
            default { Write-Warning "Invalid option; skipping MCP."; $targets = [System.Collections.Generic.List[string]]::new() }
        }
    }

    if ($targets.Count -gt 0) {
        $presets = Get-Z3R0DefaultMcpServers
        foreach ($cfgPath in $targets) {
            Write-Host "  File: $cfgPath" -ForegroundColor DarkGray
            try {
                Merge-McpIntoClaudeDesktopConfig -ConfigPath $cfgPath -AddServers $presets
                Write-Host "  MCP merged successfully -> $cfgPath" -ForegroundColor DarkGreen
            } catch {
                Write-Warning "MCP phase failed for '$cfgPath': $_"
            }
        }
        Write-Host ""
        Write-Host "  -> Set TWENTY_FIRST_API_KEY for 21st-dev-magic after creating an account at https://21st.dev" -ForegroundColor Yellow
        Write-Host "  -> Context7: optional CONTEXT7_API_KEY for higher limits (https://context7.com/dashboard)" -ForegroundColor Yellow
        Write-Host "  -> Python SDK MCP via Docker is not automated here; see https://github.com/modelcontextprotocol/python-sdk" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n[Phase 3] MCP skipped (-SkipMcp)." -ForegroundColor DarkYellow
}

Write-Host "`nZ3R0 Claude - done.`n" -ForegroundColor Cyan
