#Requires -Version 5.1
<#
.SYNOPSIS
    Z3R0 Claude — guided setup for Claude Code, plugins, and MCP (Windows).

.DESCRIPTION
    Phases: environment check (Node + Claude Code), plugin management, and MCP server merge.
    Direct: .\setup.ps1
    Remote: never pipe setup.ps1 to iex (multiline scripts may run line-by-line; param/CmdletBinding then breaks).
    Use bootstrap.ps1 (single line, UTF-8 without BOM, strips BOM from downloaded setup.ps1):
      irm 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/bootstrap.ps1' | iex
    Or: iex ((Invoke-WebRequest '.../bootstrap.ps1' -UseBasicParsing).Content)
    Parameters: download setup.ps1 to $t, strip leading U+FEFF if present, then & ([scriptblock]::Create($t)) -Mode McpOnly

.PARAMETER Mode
    Full        — environment check, install plugins, configure MCP.
    PluginsOnly — install Claude Code plugins only.
    McpOnly     — configure MCP servers only.
    (Omit to show the interactive menu.)

.PARAMETER LocalPluginsPath
    Path to an alternate local plugins.txt file.

.PARAMETER PluginsRawUrl
    Raw GitHub URL for a remote plugins.txt file.

.PARAMETER ClaudeDesktopConfigPath
    Overrides automatic detection of claude_desktop_config.json.

.EXAMPLE
    iex ((Invoke-WebRequest 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/bootstrap.ps1' -UseBasicParsing).Content)

.EXAMPLE
    $t = (Invoke-WebRequest 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/setup.ps1' -UseBasicParsing).Content; if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }; & ([scriptblock]::Create($t)) -Mode McpOnly

.EXAMPLE
    .\setup.ps1 -Mode McpOnly

.EXAMPLE
    .\setup.ps1 -Mode PluginsOnly -LocalPluginsPath .\my-plugins.txt
#>
[CmdletBinding()]
param(
    [ValidateSet('Full', 'PluginsOnly', 'McpOnly')]
    [string]$Mode                    = '',
    [string]$LocalPluginsPath        = '',
    [string]$PluginsRawUrl           = 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/plugins.txt',
    [string]$ClaudeDesktopConfigPath = ''
)

$ErrorActionPreference = 'Stop'

# ── Resolve script root (.\setup.ps1 or scriptblock from bootstrap) ────────────
$root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($root)) {
    $root = Join-Path $env:TEMP "z3r0-claude-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path (Join-Path $root 'lib') -Force | Out-Null

    Write-Host '  Downloading libraries...' -ForegroundColor Cyan
    $base = 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main'
    foreach ($lib in 'lib/ui.ps1','lib/plugins.ps1','lib/mcp.ps1') {
        $dest = Join-Path $root ($lib -replace '/','\')
        Invoke-WebRequest -Uri "$base/$lib" -OutFile $dest -UseBasicParsing -ErrorAction Stop
    }
}

# ── Dot-source libraries ──────────────────────────────────────────────────────
. (Join-Path $root 'lib\ui.ps1')
. (Join-Path $root 'lib\plugins.ps1')
. (Join-Path $root 'lib\mcp.ps1')

# ── Startup ───────────────────────────────────────────────────────────────────
Write-Banner

# Phase 0 — main menu (only if -Mode was not passed explicitly)
if (-not $PSBoundParameters.ContainsKey('Mode') -or [string]::IsNullOrWhiteSpace($Mode)) {
    $menuPick = Show-MainMenu
    if ($menuPick -eq 'Exit') { exit 0 }
    $Mode = $menuPick
}

# ── Phase 1 — environment (required for plugins; optional for MCP-only) ────────
if ($Mode -ne 'McpOnly') {
    Assert-Environment
}

# ── Phase 2 — plugins ─────────────────────────────────────────────────────────
if ($Mode -in 'Full','PluginsOnly') {
    Invoke-PluginPhase `
        -LocalPluginsPath $LocalPluginsPath `
        -PluginsRawUrl    $PluginsRawUrl    `
        -ScriptRoot       $root
}

# ── Phase 3 — MCP ────────────────────────────────────────────────────────────
if ($Mode -in 'Full','McpOnly') {
    Invoke-McpPhase -ClaudeDesktopConfigPath $ClaudeDesktopConfigPath
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ("  $($script:Ansi.Bo)$($script:Ansi.G)" + [char]0x2713 + " Done." + $script:Ansi.Rst)
Write-Host ""
