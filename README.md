# claude-tunning

PowerShell helper to tune **Claude Code** (plugins + MCP presets for Claude Desktop).

## Z3R0 Claude (remote one-liner)

Do **not** run `irm .../setup.ps1 | iex`: the pipeline can execute the script **one line at a time**, so `[CmdletBinding()]` / `param()` are no longer at the top of the parse unit and you get parser errors.

`bootstrap.ps1` is **one line**, must stay **UTF-8 without BOM** (a leading U+FEFF breaks `iex` before `$ErrorActionPreference`). After `tools/ensure-utf8bom.ps1`, `bootstrap.ps1` is re-saved **without** BOM automatically. `.gitattributes` keeps `eol=lf` on that file.

If you still see `The term '﻿$ErrorActionPreference...'` (proxy/editor added a BOM), strip it before `iex`:

```powershell
iex ((irm 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/bootstrap.ps1').TrimStart([char]0xFEFF))
```

Normal case:

```powershell
irm 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/bootstrap.ps1' | iex
```

Equivalent (no pipe to `iex`):

```powershell
iex ((Invoke-WebRequest 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/bootstrap.ps1' -UseBasicParsing).Content.TrimStart([char]0xFEFF))
```

To pass parameters (for example `-Mode McpOnly`), use the scriptblock form (strip BOM from downloaded text; `TrimStart` is enough):

```powershell
$t = (Invoke-WebRequest 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/setup.ps1' -UseBasicParsing).Content.TrimStart([char]0xFEFF); & ([scriptblock]::Create($t)) -Mode McpOnly
```

The bootstrap script forwards `@args` when you invoke it in a context that supplies them (for example saving `bootstrap.ps1` locally and running `.\bootstrap.ps1 -Mode McpOnly`).

Local run (repo checkout):

```powershell
.\setup.ps1
```

Optional: `-Mode Full|PluginsOnly|McpOnly`, `-LocalPluginsPath`, `-PluginsRawUrl`, `-ClaudeDesktopConfigPath`. See comment-based help on `setup.ps1`.

Scripts use **UTF-8 with BOM** for PS 5.1 Unicode; `bootstrap.ps1` is forced to **UTF-8 without BOM** at the end of `tools/ensure-utf8bom.ps1`. Run that script after edits if needed.
