#Requires -Version 5.1
<#
    mcp.ps1 — Merge MCP servers into Claude config files.
    Do not run directly; dot-sourced by setup.ps1.

    Uses JavaScriptSerializer instead of ConvertTo-Json to avoid ambiguous-parameter
    bugs in Windows PowerShell 5.1 on nested objects.
#>

# ── Default MCP servers ───────────────────────────────────────────────────────
function Get-DefaultMcpServers {
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
function Get-McpMarketplaceCatalog {
    $docsPath = Join-Path $env:USERPROFILE 'Documents'
    return @{
        'google-search' = @{
            command = 'npx'
            args    = @('-y', '@modelcontextprotocol/server-google-search')
            env     = @{
                GOOGLE_API_KEY = 'REPLACE_WITH_GOOGLE_API_KEY'
                GOOGLE_CSE_ID  = 'REPLACE_WITH_GOOGLE_CSE_ID'
            }
        }
        'github' = @{
            command = 'npx'
            args    = @('-y', '@modelcontextprotocol/server-github')
            env     = @{
                GITHUB_PERSONAL_ACCESS_TOKEN = 'REPLACE_WITH_GITHUB_PAT'
            }
        }
        'filesystem' = @{
            command = 'npx'
            args    = @('-y', '@modelcontextprotocol/server-filesystem', $docsPath)
        }
        'context7' = @{
            command = 'npx'
            args    = @('-y', '@upstash/context7-mcp@latest')
        }
    }
}

# ── Recursive conversion for JavaScriptSerializer-compatible types ────────────
function ConvertTo-JssCompatible {
    param([Parameter(ValueFromPipeline)][object]$Node)
    process {
        if ($null -eq $Node)                              { return $null }
        if ($Node -is [string]  -or
            $Node -is [bool]    -or
            $Node -is [int]     -or
            $Node -is [long]    -or
            $Node -is [double]  -or
            $Node -is [decimal])                          { return $Node }

        if ($Node -is [System.Collections.IDictionary]) {
            $dict = New-Object 'System.Collections.Generic.Dictionary[string,Object]'
            foreach ($k in $Node.Keys) {
                [void]$dict.Add([string]$k, (ConvertTo-JssCompatible $Node[$k]))
            }
            return $dict
        }

        if ($Node -is [System.Collections.IList] -and $Node -isnot [string]) {
            $list = New-Object System.Collections.Generic.List[Object]
            foreach ($item in $Node) { $list.Add((ConvertTo-JssCompatible $item)) | Out-Null }
            return $list.ToArray()
        }

        return $Node
    }
}
function Get-ConfigModel {
    param([Parameter(Mandatory)][string]$ConfigPath)

    Add-Type -AssemblyName System.Web.Extensions
    $jss               = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $jss.MaxJsonLength = [Int32]::MaxValue
    $utf8              = [System.Text.UTF8Encoding]::new($false)

    $dir = [System.IO.Path]::GetDirectoryName($ConfigPath)
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $raw = '{}'
    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $raw = [System.IO.File]::ReadAllText($ConfigPath, $utf8)
        } catch {
            $raw = '{}'
        }
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = '{}' }

    $root = $null
    try {
        $parsed = $jss.DeserializeObject($raw)
        if ($parsed -is [System.Collections.IDictionary]) {
            $root = ConvertTo-JssCompatible $parsed
        }
    } catch {
        $stamp = Get-Date -Format 'yyyyMMddHHmmss'
        $bak   = "$ConfigPath.bak.$stamp"
        if (Test-Path -LiteralPath $ConfigPath) {
            Copy-Item -LiteralPath $ConfigPath -Destination $bak -Force
            Write-Warning "Invalid JSON; backup saved: $bak"
        }
    }

    if ($null -eq $root -or $root -isnot [System.Collections.IDictionary]) {
        $root = New-Object 'System.Collections.Generic.Dictionary[string,Object]'
    }

    return [PSCustomObject]@{
        Root = $root
        Jss  = $jss
        Utf8 = $utf8
    }
}
function Ensure-McpServersNode {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Root)
    if ($Root.ContainsKey('mcpServers') -and $Root['mcpServers'] -is [System.Collections.IDictionary]) {
        return $Root['mcpServers']
    }
    if ($Root.ContainsKey('mcpServers')) { [void]$Root.Remove('mcpServers') }
    $mcp = New-Object 'System.Collections.Generic.Dictionary[string,Object]'
    [void]$Root.Add('mcpServers', $mcp)
    return $mcp
}
function Save-ConfigModel {
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)]$Model
    )
    [System.IO.File]::WriteAllText($ConfigPath, $Model.Jss.Serialize($Model.Root), $Model.Utf8)
}
function Normalize-McpServerNames {
    param([string[]]$Names)
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @($Names)) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        foreach ($part in ($entry -split ',')) {
            $n = $part.Trim().ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($n)) { continue }
            if (-not $result.Contains($n)) { $result.Add($n) }
        }
    }
    return ,$result.ToArray()
}
function Resolve-McpTargetsByName {
    param(
        [string]$Target = 'ClaudeCode',
        [string]$ExplicitPath = ''
    )
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return ,@($ExplicitPath)
    }
    $cliPath     = Join-Path $env:USERPROFILE '.claude\settings.json'
    $desktopPath = Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'
    $normalized  = ([string]$Target).Trim().ToLowerInvariant()
    switch ($normalized) {
        'claudecode' { return ,@($cliPath) }
        'desktop'    { return ,@($desktopPath) }
        'both'       { return ,@($cliPath, $desktopPath) }
        default      { return ,@($cliPath) }
    }
}
function Prompt-McpServerSelection {
    param([Parameter(Mandatory)][hashtable]$Catalog)
    Write-Host ""
    Write-Host '  Available preset MCP servers:'
    $all = @($Catalog.Keys | Sort-Object)
    foreach ($name in $all) {
        Write-Host "  - $name"
    }
    $raw = Read-Host '  Type one or more names separated by comma'
    return ,(Normalize-McpServerNames -Names @($raw))
}
function Get-McpServerNamesFromConfig {
    param([Parameter(Mandatory)][string]$ConfigPath)
    $model = Get-ConfigModel -ConfigPath $ConfigPath
    $mcp   = Ensure-McpServersNode -Root $model.Root
    return ,@($mcp.Keys | Sort-Object)
}
function Remove-McpServersFromConfig {
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string[]]$Names
    )
    $model   = Get-ConfigModel -ConfigPath $ConfigPath
    $mcp     = Ensure-McpServersNode -Root $model.Root
    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $Names) {
        if ($mcp.ContainsKey($name)) {
            [void]$mcp.Remove($name)
            $removed.Add($name) | Out-Null
        }
    }
    Save-ConfigModel -ConfigPath $ConfigPath -Model $model
    return ,$removed.ToArray()
}

# ── Merge servers into a config file ──────────────────────────────────────────
function Merge-McpServers {
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][hashtable]$Servers
    )

    $model = Get-ConfigModel -ConfigPath $ConfigPath
    $mcp   = Ensure-McpServersNode -Root $model.Root

    # Merge servers (overwrites existing entries)
    foreach ($k in $Servers.Keys) {
        $v = ConvertTo-JssCompatible $Servers[$k]
        if ($mcp.ContainsKey($k)) { [void]$mcp.Remove($k) }
        [void]$mcp.Add($k, $v)
    }

    Save-ConfigModel -ConfigPath $ConfigPath -Model $model
}

# ── Resolve target config files ───────────────────────────────────────────────
function Resolve-McpTargets {
    param([string]$ExplicitPath)

    if ($ExplicitPath) { return ,@($ExplicitPath) }

    $cliPath     = Join-Path $env:USERPROFILE '.claude\settings.json'
    $desktopPath = Join-Path $env:APPDATA    'Claude\claude_desktop_config.json'

    return ,(Show-McpTargetMenu -ClaudeCodePath $cliPath -DesktopPath $desktopPath)
}
function Invoke-McpMarketplacePhase {
    param(
        [string]$Action = '',
        [string[]]$Server = @(),
        [string]$Target = 'ClaudeCode',
        [string]$ClaudeDesktopConfigPath = ''
    )
    Write-StepHeader 'Phase 3 — MCP marketplace CLI'

    if ([string]::IsNullOrWhiteSpace($Action)) {
        $Action = Show-McpMarketplaceActionMenu
    }
    if ([string]::IsNullOrWhiteSpace($Action)) {
        Write-Info 'MCP marketplace phase skipped.'
        return
    }

    $normalizedAction = $Action.Trim().ToLowerInvariant()
    $targets = Resolve-McpTargetsByName -Target $Target -ExplicitPath $ClaudeDesktopConfigPath
    if ($targets.Count -eq 0) {
        Write-Info 'No target config selected.'
        return
    }

    if ($normalizedAction -eq 'list') {
        foreach ($cfg in $targets) {
            Write-Info "File: $cfg"
            $names = Get-McpServerNamesFromConfig -ConfigPath $cfg
            if ($names.Count -eq 0) {
                Write-Host '  (no MCP servers configured)'
            } else {
                foreach ($n in $names) { Write-Host "  - $n" }
            }
            Write-Host ''
        }
        return
    }

    $catalog = Get-McpMarketplaceCatalog
    $selected = Normalize-McpServerNames -Names $Server
    if ($selected.Count -eq 0) {
        $selected = Prompt-McpServerSelection -Catalog $catalog
    }
    if ($selected.Count -eq 0) {
        Write-Info 'No MCP servers selected.'
        return
    }

    if ($normalizedAction -eq 'install') {
        $pack = @{}
        $unknown = [System.Collections.Generic.List[string]]::new()
        foreach ($name in $selected) {
            if ($catalog.ContainsKey($name)) {
                $pack[$name] = $catalog[$name]
            } else {
                $unknown.Add($name) | Out-Null
            }
        }
        if ($unknown.Count -gt 0) {
            Write-Warning "Unknown server(s): $($unknown -join ', ')"
        }
        if ($pack.Count -eq 0) {
            Write-Info 'No valid preset server selected.'
            return
        }
        foreach ($cfg in $targets) {
            Write-Info "Installing into: $cfg"
            Merge-McpServers -ConfigPath $cfg -Servers $pack
            Write-Ok "Installed: $($pack.Keys -join ', ')"
        }
        Write-Host ''
        Write-Host "  $($script:Ansi.Y)Manual follow-up:$($script:Ansi.Rst)"
        Write-Host "  $($script:Ansi.Gr)→ google-search : set GOOGLE_API_KEY and GOOGLE_CSE_ID$($script:Ansi.Rst)"
        Write-Host "  $($script:Ansi.Gr)→ github        : set GITHUB_PERSONAL_ACCESS_TOKEN$($script:Ansi.Rst)"
        Write-Host ''
        return
    }

    if ($normalizedAction -eq 'remove') {
        foreach ($cfg in $targets) {
            Write-Info "Removing from: $cfg"
            $removed = Remove-McpServersFromConfig -ConfigPath $cfg -Names $selected
            if ($removed.Count -eq 0) {
                Write-Info 'No matching servers found.'
            } else {
                Write-Ok "Removed: $($removed -join ', ')"
            }
        }
        Write-Host ''
        return
    }

    Write-Warning "Unsupported action: $Action"
}

# ── MCP phase orchestration ───────────────────────────────────────────────────
function Invoke-McpPhase {
    param([string]$ClaudeDesktopConfigPath = '')

    Write-StepHeader 'Phase 3 — MCP servers'

    $targets = Resolve-McpTargets -ExplicitPath $ClaudeDesktopConfigPath

    if ($targets.Count -eq 0) {
        Write-Info 'MCP phase skipped.'
        return
    }

    $servers = Get-DefaultMcpServers

    foreach ($cfg in $targets) {
        Write-Info "File: $cfg"
        try {
            Merge-McpServers -ConfigPath $cfg -Servers $servers
            Write-Ok "MCP merged successfully → $cfg"
        } catch {
            Write-Fail "Failed for '$cfg': $_"
        }
    }

    Write-Host ""
    Write-Host "  $($script:Ansi.Y)Manual follow-up:$($script:Ansi.Rst)"
    Write-Host "  $($script:Ansi.Gr)→ 21st-dev-magic : set TWENTY_FIRST_API_KEY (https://21st.dev/magic/console)$($script:Ansi.Rst)"
    Write-Host "  $($script:Ansi.Gr)→ Context7       : optional CONTEXT7_API_KEY for higher limits (https://context7.com/dashboard)$($script:Ansi.Rst)"
    Write-Host "  $($script:Ansi.Gr)→ Python SDK MCP : Docker install not automated — see https://github.com/modelcontextprotocol/python-sdk$($script:Ansi.Rst)"
    Write-Host ""
}
