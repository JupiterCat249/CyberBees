# Collect local diagnostic artifacts (for external pickup / cross-machine diff)
# ---------------------------------------------------------------------------
# What it does: copies the diagnostics that Godot auto-downloaded to THIS machine
#   into one folder, and (by default) zips it.
#   The `NetDiagDump` autoload writes a report automatically when an online match
#   starts / 2s after entering the battle scene / periodically / on detected drift /
#   on Ctrl+F9.
#
# Usage (either works):
#   powershell -NoProfile -ExecutionPolicy Bypass -File verification\collect_diag.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File verification\collect_diag.ps1 -OutDir D:\diag-out
#   (right-click -> "Run with PowerShell" also works)
#
# Output: <OutDir>  (default: Desktop\diag-export)
#   containing diag*.txt / selfcheck*.txt / *.png  plus a zip archive.
# NOTE: ASCII-only on purpose -- Windows PowerShell 5.1 reads .ps1 as ANSI,
#   so non-ASCII text in a UTF-8 file gets mangled and can break parsing.
# ---------------------------------------------------------------------------
param(
	[string]$OutDir = "$([Environment]::GetFolderPath('Desktop'))\diag-export",
	[switch]$NoZip
)

$ErrorActionPreference = 'Stop'

# Godot's user:// location on Windows (project name is a CJK string)
$project = [char]0x7535 + [char]0x5B50 + [char]0x8702   # dian-zi-feng
$src = Join-Path $env:APPDATA ("Godot\app_userdata\{0}\diag" -f $project)

if (-not (Test-Path $src)) {
	Write-Host ("[X] diag dir not found: {0}" -f $src) -ForegroundColor Yellow
	Write-Host "    Run the game once on THIS code first (the autoload creates it)." -ForegroundColor Yellow
	exit 1
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Write-Host ("[>] source: {0}" -f $src)
Write-Host ("[>] output: {0}" -f $OutDir)

$files = @(Get-ChildItem -Path $src -Recurse -File | Where-Object {
	$_.Name -like 'diag*.txt' -or $_.Name -like 'selfcheck*.txt' -or $_.Extension -eq '.png'
})
if ($files.Count -eq 0) {
	Write-Host "[!] nothing to collect yet (no dump triggered)" -ForegroundColor Yellow
	exit 0
}

foreach ($f in $files) { Copy-Item $f.FullName -Destination $OutDir -Force }
Write-Host ("[OK] copied {0} file(s)" -f $files.Count)

$latest = Join-Path $src 'LATEST.txt'
if (Test-Path $latest) {
	Write-Host '--- LATEST.txt ---'
	Get-Content $latest | ForEach-Object { Write-Host $_ }
	Copy-Item $latest -Destination $OutDir -Force
}

if (-not $NoZip) {
	$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
	$zip = Join-Path $OutDir ("diag-{0}-{1}.zip" -f $env:COMPUTERNAME, $stamp)
	if (Test-Path $zip) { Remove-Item $zip -Force }
	Compress-Archive -Path (Join-Path $OutDir '*') -DestinationPath $zip -Force
	Write-Host ("[OK] zip: {0}" -f $zip) -ForegroundColor Green
}
Write-Host "Done. Send the OutDir contents back for comparison." -ForegroundColor Green
