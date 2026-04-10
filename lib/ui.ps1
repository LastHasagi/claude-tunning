#Requires -Version 5.1
<#
    ui.ps1 — UX layer: ANSI, banner, spinner, progress, menus, plugin picker.
    Do not run directly; dot-sourced by setup.ps1.
#>

# ── Enable VT processing in conhost (Windows 10 1511+) ───────────────────────
$null = & {
    if ('Z3R0.Win32.Kernel32' -as [type]) { return }
    try {
        Add-Type -Namespace Z3R0.Win32 -Name Kernel32 -MemberDefinition @'
            [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
            [DllImport("kernel32.dll")] public static extern bool   GetConsoleMode(IntPtr h, out uint m);
            [DllImport("kernel32.dll")] public static extern bool   SetConsoleMode(IntPtr h, uint m);
'@ -ErrorAction Stop
    } catch { return }
    try {
        $h = [Z3R0.Win32.Kernel32]::GetStdHandle(-11)
        [uint32]$m = 0
        [void][Z3R0.Win32.Kernel32]::GetConsoleMode($h, [ref]$m)
        [void][Z3R0.Win32.Kernel32]::SetConsoleMode($h, $m -bor [uint32]4)
    } catch {}
}

# ── ANSI palette (caller script scope after dot-source) ────────────────────────
$script:Ansi = @{
    Rst = "$([char]27)[0m"
    Bo  = "$([char]27)[1m"
    Di  = "$([char]27)[2m"
    Re  = "$([char]27)[31m"
    G   = "$([char]27)[32m"
    Y   = "$([char]27)[33m"
    C   = "$([char]27)[36m"
    W   = "$([char]27)[97m"
    Gr  = "$([char]27)[90m"
}

# ── Output helpers ────────────────────────────────────────────────────────────
function Write-Ok   ([string]$Msg) { Write-Host "  $($script:Ansi.G)✓$($script:Ansi.Rst) $Msg" }
function Write-Fail ([string]$Msg) { Write-Host "  $($script:Ansi.Re)✗$($script:Ansi.Rst) $Msg" }
function Write-Info ([string]$Msg) { Write-Host "  $($script:Ansi.C)→$($script:Ansi.Rst) $Msg" }

function Write-StepHeader ([string]$Title) {
    $A   = $script:Ansi
    $bar = '─' * ([Math]::Max(2, 58 - $Title.Length))
    Write-Host ""
    Write-Host "  $($A.Bo)$($A.C)── $Title $($A.Rst)$($A.Di)$($A.C)$bar$($A.Rst)"
    Write-Host ""
}

# ── Banner ────────────────────────────────────────────────────────────────────
function Write-Banner {
    $A = $script:Ansi
    $I = 73  # inner width

    $mkRow = {
        param([string]$Text, [string]$Color = '')
        $pad = $I - $Text.Length
        $l   = [int][Math]::Floor($pad / 2)
        $r   = $pad - $l
        "║${Color}$(' ' * $l)${Text}$(' ' * $r)$($A.Rst)$($A.C)║"
    }

    $lines = @(
        "╔$('═' * $I)╗"
        "║$(' ' * $I)║"
        (& $mkRow 'Z3R0 / CLAUDE CODE'               "$($A.Bo)$($A.W)")
        (& $mkRow 'automated setup  ·  plugins + MCP' "$($A.Di)$($A.C)")
        "║$(' ' * $I)║"
        "╠$('═' * $I)╣"
        (& $mkRow 'Developed by  :  Z3R0'                                        $A.Gr)
        (& $mkRow 'GitHub        :  https://github.com/LastHasagi'               $A.Gr)
        (& $mkRow 'LinkedIn      :  linkedin.com/in/rodrigo-de-souza-graca'      $A.Gr)
        "║$(' ' * $I)║"
        "╚$('═' * $I)╝"
    )

    Write-Host ""
    foreach ($ln in $lines) { Write-Host "  $($A.C)$ln$($A.Rst)" }
    Write-Host ""
}

# ── Spinner (Start-Job — scriptblock must be self-contained) ─────────────────
function Invoke-WithSpinner {
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][scriptblock]$Action,
        [object[]]$ArgumentList = @()
    )

    $A      = $script:Ansi
    $frames = @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏')
    $job    = Start-Job -ScriptBlock $Action -ArgumentList $ArgumentList
    $i      = 0

    [Console]::CursorVisible = $false
    try {
        while ($job.State -in 'NotStarted','Running') {
            $f = $frames[$i % $frames.Count]
            Write-Host "`r  $($A.C)$f$($A.Rst) $Message  " -NoNewline
            $i++
            Start-Sleep -Milliseconds 80
        }
    } finally {
        [Console]::CursorVisible = $true
    }

    if ($job.State -eq 'Failed') {
        Write-Host "`r  $($A.Re)✗$($A.Rst) $Message   "
        $err = Receive-Job -Job $job -ErrorAction SilentlyContinue 2>&1 | Select-Object -Last 1
        Remove-Job -Job $job -Force
        throw "Spinner action failed: $err"
    }

    $result = Receive-Job -Job $job -Wait -ErrorAction Stop
    Remove-Job -Job $job -Force
    Write-Host "`r  $($A.G)✓$($A.Rst) $Message   "
    return $result
}

# ── Progress bar inline ───────────────────────────────────────────────────────
function Write-PluginProgress {
    param([int]$Current, [int]$Total, [string]$Name = '')
    $A     = $script:Ansi
    $width = 24
    $pct   = if ($Total -gt 0) { $Current / $Total } else { 0 }
    $fill  = [int]($pct * $width)
    $empty = $width - $fill
    $bar   = "$($A.G)$('█' * $fill)$($A.Rst)$($A.Di)$('░' * $empty)$($A.Rst)"
    $label = if ($Name) { "  $($A.Gr)$Name$($A.Rst)" } else { '' }
    Write-Host "`r  $bar  $($A.C)$Current/$Total$($A.Rst)$label" -NoNewline
}

# ── Generic menu ──────────────────────────────────────────────────────────────
function Read-MenuChoice {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string[]]$Options,
        [string]$Default = '1'
    )

    $A = $script:Ansi

    # Dynamic box width
    $longest = 0
    foreach ($o in $Options) { if ($o.Length -gt $longest) { $longest = $o.Length } }
    $W = [Math]::Max($Title.Length + 4, $longest + 9)

    # Title row
    $tpad = $W - $Title.Length - 2
    Write-Host "  $($A.C)┌$('─' * $W)┐$($A.Rst)"
    Write-Host "  $($A.C)│  $($A.Bo)$($A.W)$Title$($A.Rst)$(' ' * $tpad)$($A.C)│$($A.Rst)"
    Write-Host "  $($A.C)├$('─' * $W)┤$($A.Rst)"

    for ($i = 0; $i -lt $Options.Count; $i++) {
        $n    = $i + 1
        $text = $Options[$i]
        $pad  = $W - $text.Length - 8   # "  [N]  text  " = prefix 7 + trailing 1
        Write-Host "  $($A.C)│  $($A.Y)[$n]$($A.Rst)  $text$(' ' * $pad)$($A.C)│$($A.Rst)"
    }

    Write-Host "  $($A.C)└$('─' * $W)┘$($A.Rst)"
    Write-Host ""

    $raw = (Read-Host "  $($A.Di)Choice [Enter = $Default]$($A.Rst)").Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = $Default }
    return $raw
}

# ── Phase menus ───────────────────────────────────────────────────────────────
function Show-MainMenu {
    $choice = Read-MenuChoice -Title 'What do you want to configure?' -Options @(
        'Full setup       — environment check + plugins + MCP'
        'Plugins only     — install Claude Code plugins'
        'MCP only         — configure MCP servers'
        'MCP marketplace  — list/install/remove MCP servers'
        'Exit'
    ) -Default '1'

    switch ($choice) {
        '1' { return 'Full'        }
        '2' { return 'PluginsOnly' }
        '3' { return 'McpOnly'     }
        '4' { return 'McpMarketplace' }
        '5' { return 'Exit'        }
        default { return 'Full'    }
    }
}

function Show-PluginModeMenu {
    $choice = Read-MenuChoice -Title 'Plugin installation mode' -Options @(
        'Senior Pack        — curated recommended subset'
        'Pick plugins       — choose manually'
        'Install all'
        'Back'
    ) -Default '1'
    return $choice
}

function Show-McpTargetMenu {
    param([string]$ClaudeCodePath, [string]$DesktopPath)
    $A = $script:Ansi

    $codeExists    = Test-Path -LiteralPath $ClaudeCodePath
    $desktopExists = Test-Path -LiteralPath $DesktopPath

    $fmtPath = {
        param([string]$p, [bool]$exists)
        $tag = if ($exists) { "$($A.G)(exists)$($A.Rst)" } else { "$($A.Gr)(not found)$($A.Rst)" }
        "$p  $tag"
    }

    Write-Host ""
    $choice = Read-MenuChoice -Title 'Where should MCP servers be merged?' -Options @(
        "Claude Code CLI   — $ClaudeCodePath"
        "Claude Desktop    — $DesktopPath"
        'Both'
        'Back'
    ) -Default '1'

    $targets = [System.Collections.Generic.List[string]]::new()
    switch ($choice) {
        '1' { $targets.Add($ClaudeCodePath) }
        '2' { $targets.Add($DesktopPath) }
        '3' { $targets.Add($ClaudeCodePath); $targets.Add($DesktopPath) }
    }
    return ,$targets.ToArray()
}
function Show-McpMarketplaceActionMenu {
    $choice = Read-MenuChoice -Title 'MCP marketplace action' -Options @(
        'List installed MCP servers'
        'Install preset MCP servers'
        'Remove MCP servers'
        'Back'
    ) -Default '1'
    switch ($choice) {
        '1' { return 'List' }
        '2' { return 'Install' }
        '3' { return 'Remove' }
        default { return '' }
    }
}

# ── Interactive plugin picker (↑↓ + SPACE + ENTER) ────────────────────────────
function Select-PluginsInteractive {
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string[]]$Lines)

    if ($Lines.Count -eq 0) { return @() }

    $A           = $script:Ansi
    $esc         = [char]27
    $maxViewport = 12
    $viewport    = [Math]::Min($maxViewport, $Lines.Count)
    $viewStart   = 0
    $cursor      = 0
    $boxInner    = 70
    $maxTextLen  = $boxInner - 8
    # top-border(1) + title(1) + hint(1) + separator(1) + items($viewport) + scroll-row(1) + bottom-border(1) + counter(1)
    $fixedHeight = $viewport + 7
    $drawnOnce   = $false

    $selected = New-Object bool[] $Lines.Count
    for ($si = 0; $si -lt $Lines.Count; $si++) { $selected[$si] = $true }

    # dot-sourced (. $drawFrame) so writes to $drawnOnce stay in this scope
    $drawFrame = {
        if ($drawnOnce) {
            # cursor previous line (relative, works in VS Code / Cursor terminal) + clear to end
            [Console]::Write("${esc}[${fixedHeight}F${esc}[J")
        }
        $drawnOnce = $true

        Write-Host "  $($A.C)┌$('─' * $boxInner)┐$($A.Rst)"
        $h1 = ' Z3R0 Claude — Plugin selection'
        Write-Host "  $($A.C)│$($A.Bo)$($A.W)$h1$(' ' * ($boxInner - $h1.Length))$($A.Rst)$($A.C)│$($A.Rst)"
        $h2 = ' ↑↓ Navigate   SPACE Toggle   A All/None   ENTER Confirm   ESC Cancel'
        if ($h2.Length -gt $boxInner) { $h2 = $h2.Substring(0, $boxInner) }
        Write-Host "  $($A.C)│$($A.Di)$($A.Gr)$h2$(' ' * ($boxInner - $h2.Length))$($A.Rst)$($A.C)│$($A.Rst)"
        Write-Host "  $($A.C)├$('─' * $boxInner)┤$($A.Rst)"
        for ($vi = 0; $vi -lt $viewport; $vi++) {
            $idx   = $viewStart + $vi
            $arrow = if ($idx -eq $cursor) { "$($A.Y)►$($A.Rst)" } else { ' ' }
            $chk   = if ($selected[$idx])  { "$($A.G)✓$($A.Rst)" } else { "$($A.Gr) $($A.Rst)" }
            $text  = $Lines[$idx]
            if ($text.Length -gt $maxTextLen) { $text = $text.Substring(0, $maxTextLen - 1) + '…' }
            $pad = ' ' * ($maxTextLen - $text.Length)
            Write-Host "  $($A.C)│$($A.Rst) $arrow [$chk] $text$pad $($A.C)│$($A.Rst)"
        }
        # scroll row always rendered to keep height fixed
        $hasMore   = ($viewStart + $viewport) -lt $Lines.Count
        $hasAbove  = $viewStart -gt 0
        $scrollTxt = if ($hasAbove -and $hasMore) { ' ▲▼ more above and below' }
                     elseif ($hasMore)             { ' ▼ more items below'      }
                     elseif ($hasAbove)            { ' ▲ more items above'      }
                     else                          { ''                         }
        Write-Host "  $($A.C)│$($A.Gr)$($A.Di)$scrollTxt$(' ' * ($boxInner - $scrollTxt.Length))$($A.Rst)$($A.C)│$($A.Rst)"
        Write-Host "  $($A.C)└$('─' * $boxInner)┘$($A.Rst)"
        $selCount = 0
        foreach ($sv in $selected) { if ($sv) { $selCount++ } }
        Write-Host "  $($A.Gr)Selected: $($A.G)$selCount$($A.Gr) of $($Lines.Count)$($A.Rst)   "
    }

    [Console]::CursorVisible = $false
    try {
        . $drawFrame

        while ($true) {
            $key     = [Console]::ReadKey($true)
            $keyName = $key.Key.ToString()

            if ($keyName -eq 'UpArrow') {
                if ($cursor -gt 0) {
                    $cursor--
                    if ($cursor -lt $viewStart) { $viewStart = $cursor }
                }
            } elseif ($keyName -eq 'DownArrow') {
                if ($cursor -lt ($Lines.Count - 1)) {
                    $cursor++
                    if ($cursor -ge ($viewStart + $viewport)) {
                        $viewStart = $cursor - $viewport + 1
                    }
                }
            } elseif ($keyName -eq 'Spacebar') {
                $selected[$cursor] = -not $selected[$cursor]
            } elseif ($keyName -eq 'Escape') {
                Write-Host ""
                return @()
            } elseif ($keyName -eq 'Enter') {
                Write-Host ""
                $result = [System.Collections.Generic.List[string]]::new()
                for ($ri = 0; $ri -lt $Lines.Count; $ri++) {
                    if ($selected[$ri]) { $result.Add($Lines[$ri]) }
                }
                return ,$result.ToArray()
            } elseif ($key.KeyChar -eq 'a' -or $key.KeyChar -eq 'A') {
                $anyOn = $false
                foreach ($sv in $selected) { if ($sv) { $anyOn = $true; break } }
                for ($ri = 0; $ri -lt $selected.Count; $ri++) { $selected[$ri] = -not $anyOn }
            }

            . $drawFrame
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}
