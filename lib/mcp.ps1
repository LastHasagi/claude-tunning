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

# ── Merge servers into a config file ──────────────────────────────────────────
function Merge-McpServers {
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][hashtable]$Servers
    )

    Add-Type -AssemblyName System.Web.Extensions
    $jss                = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $jss.MaxJsonLength  = [Int32]::MaxValue
    $utf8               = [System.Text.UTF8Encoding]::new($false)

    # Ensure directory exists
    $dir = [System.IO.Path]::GetDirectoryName($ConfigPath)
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Read existing JSON (backup on parse error)
    $raw = '{}'
    if (Test-Path -LiteralPath $ConfigPath) {
        try   { $raw = [System.IO.File]::ReadAllText($ConfigPath, $utf8) }
        catch { $raw = '{}' }
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = '{}' }

    # Deserialize and normalize
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

    # Get or create 'mcpServers' key
    $mcp = $null
    if ($root.ContainsKey('mcpServers') -and $root['mcpServers'] -is [System.Collections.IDictionary]) {
        $mcp = $root['mcpServers']
    } else {
        if ($root.ContainsKey('mcpServers')) { [void]$root.Remove('mcpServers') }
        $mcp = New-Object 'System.Collections.Generic.Dictionary[string,Object]'
        [void]$root.Add('mcpServers', $mcp)
    }

    # Merge servers (overwrites existing entries)
    foreach ($k in $Servers.Keys) {
        $v = ConvertTo-JssCompatible $Servers[$k]
        if ($mcp.ContainsKey($k)) { [void]$mcp.Remove($k) }
        [void]$mcp.Add($k, $v)
    }

    [System.IO.File]::WriteAllText($ConfigPath, $jss.Serialize($root), $utf8)
}

# ── Resolve target config files ───────────────────────────────────────────────
function Resolve-McpTargets {
    param([string]$ExplicitPath)

    if ($ExplicitPath) { return ,@($ExplicitPath) }

    $cliPath     = Join-Path $env:USERPROFILE '.claude\settings.json'
    $desktopPath = Join-Path $env:APPDATA    'Claude\claude_desktop_config.json'

    return ,(Show-McpTargetMenu -ClaudeCodePath $cliPath -DesktopPath $desktopPath)
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
