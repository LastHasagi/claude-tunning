# claude-tunning

PowerShell helper to tune **Claude Code** (plugins + MCP presets for Claude Desktop).

## Z3R0 Claude (remote one-liner)

Do **not** run `irm .../setup.ps1 | iex`: the pipeline can execute the script **one line at a time**, so `[CmdletBinding()]` / `param()` are no longer at the top of the parse unit and you get parser errors.

`bootstrap.ps1` is intentionally **one line** and **UTF-8 without BOM** (a leading BOM breaks `iex` on the first token). `tools/ensure-utf8bom.ps1` skips this file. So `irm ... | iex` is safe:

```powershell
irm 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/bootstrap.ps1' | iex
```

Equivalent (no pipe to `iex`):

```powershell
iex ((Invoke-WebRequest 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/bootstrap.ps1' -UseBasicParsing).Content)
```

To pass parameters (for example `-Mode McpOnly`), use the scriptblock form and append them to the call:

```powershell
$t = (Invoke-WebRequest 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/setup.ps1' -UseBasicParsing).Content; if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }; & ([scriptblock]::Create($t)) -Mode McpOnly
```

The bootstrap script forwards `@args` when you invoke it in a context that supplies them (for example saving `bootstrap.ps1` locally and running `.\bootstrap.ps1 -Mode McpOnly`).

Local run (repo checkout):

```powershell
.\setup.ps1
```

Optional: `-Mode Full|PluginsOnly|McpOnly`, `-LocalPluginsPath`, `-PluginsRawUrl`, `-ClaudeDesktopConfigPath`. See comment-based help on `setup.ps1`.

Scripts are saved as **UTF-8 with BOM** (except `bootstrap.ps1`, which must stay BOM-free for remote `iex`); run `tools/ensure-utf8bom.ps1` after edits if needed.
