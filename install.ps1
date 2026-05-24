$f = Join-Path $env:TEMP 'adir_rtl_patch.ps1'
Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/adirbenmeir/claude-rtl/main/patch.ps1' -OutFile $f
Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$f`""
