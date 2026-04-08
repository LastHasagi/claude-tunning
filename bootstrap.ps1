#Requires -Version 5.1
# Bootstrap for irm | iex — no param() here (iex cannot parse param/CmdletBinding blocks).
# Forwards arguments to the real setup.ps1 loaded via scriptblock.
$ErrorActionPreference = 'Stop'
$Z3R0SetupUrl = 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/setup.ps1'
$scriptText = (Invoke-WebRequest -Uri $Z3R0SetupUrl -UseBasicParsing).Content
& ([scriptblock]::Create($scriptText)) @args
