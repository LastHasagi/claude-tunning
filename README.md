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

Optional: `-LocalPluginsPath .\plugins.txt`, `-SkipMcp`, `-SkipPlugins`. See header comment block in `setup.ps1`.

The startup banner is **ASCII-only** so it renders correctly in Windows PowerShell 5.1 without UTF-8/BOM tricks.
