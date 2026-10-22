$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
git -C $Repo config core.hooksPath qc/hooks
if ($LASTEXITCODE -ne 0) { Write-Host '安装失败' -ForegroundColor Red; exit 1 }
Write-Host ('[qc] core.hooksPath = ' + (git -C $Repo config --get core.hooksPath))
