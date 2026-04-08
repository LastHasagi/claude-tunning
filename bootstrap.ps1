$ErrorActionPreference='Stop'; & ([scriptblock]::Create((Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/LastHasagi/claude-tunning/main/setup.ps1' -UseBasicParsing).Content)) @args
