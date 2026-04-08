# claude-tunning

PowerShell helper to tune **Claude Code** (plugins + MCP presets for Claude Desktop).

## Z3R0 Claude (remote one-liner)

`Invoke-Expression` (`iex`) cannot run `setup.ps1` directly (top-level `param` / `CmdletBinding`). Use the bootstrap script or a scriptblock:

```powershell
iex ((Invoke-WebRequest 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/bootstrap.ps1' -UseBasicParsing).Content)
```

To pass parameters (for example `-Mode McpOnly`), use the scriptblock form and append them to the call:

```powershell
& ([scriptblock]::Create((Invoke-WebRequest 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/setup.ps1' -UseBasicParsing).Content)) -Mode McpOnly
```

The bootstrap script forwards `@args` when you invoke it in a context that supplies them (for example saving `bootstrap.ps1` locally and running `.\bootstrap.ps1 -Mode McpOnly`).

Local run (repo checkout):

```powershell
.\setup.ps1
```

Optional: `-Mode Full|PluginsOnly|McpOnly`, `-LocalPluginsPath`, `-PluginsRawUrl`, `-ClaudeDesktopConfigPath`. See comment-based help on `setup.ps1`.

Scripts are saved as **UTF-8 with BOM** so Windows PowerShell 5.1 parses Unicode correctly; run `tools/ensure-utf8bom.ps1` after edits if needed.
