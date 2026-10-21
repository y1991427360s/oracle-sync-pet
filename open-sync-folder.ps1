$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'oracle-sync-common.ps1')
Open-OracleSyncFolder (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
