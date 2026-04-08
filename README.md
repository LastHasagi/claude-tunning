# claude-tunning

PowerShell helper to tune **Claude Code** (plugins + MCP presets for Claude Desktop).

## Z3R0 Claude (one-liner)

```powershell
irm https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/setup.ps1 | iex
```

Local run (repo checkout):

```powershell
.\setup.ps1
```

Optional: `-Mode Full|PluginsOnly|McpOnly`, `-LocalPluginsPath`, `-PluginsRawUrl`, `-ClaudeDesktopConfigPath`. See comment-based help on `setup.ps1`.

Scripts are saved as **UTF-8 with BOM** so Windows PowerShell 5.1 parses Unicode correctly; run `tools/ensure-utf8bom.ps1` after edits if needed.
