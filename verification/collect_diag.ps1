# Collect local diagnostic artifacts (for external pickup / cross-machine diff)
# ---------------------------------------------------------------------------
# What it does:
#   1. copies everything the game auto-wrote under  %APPDATA%\Godot\app_userdata\<project>\diag
#      into one folder (default: Desktop\diag-export)
#   2. prints the newest report's info (LATEST.txt)
#   3. records the original arguments used (so a complex call is reproducible)
#   4. zips the folder (unless -NoZip)
#
# The `NetDiagDump` autoload writes those reports automatically when an online match
# starts / 2s after entering the battle scene / periodically / on detected drift / on Ctrl+F9.
#
# Usage (any of these):
#   powershell -NoProfile -ExecutionPolicy Bypass -File verification\collect_diag.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File verification\collect_diag.ps1 -OutDir D:\diag-out
#   powershell -NoProfile -ExecutionPolicy Bypass -File verification\collect_diag.ps1 -NoZip
#   (or just double-click verification\collect_diag.cmd)
#
# NOTE: ASCII-only on purpose -- Windows PowerShell 5.1 reads .ps1 as ANSI,
#   so non-ASCII text in a UTF-8 file gets mangled and can break parsing.
#   CJK project name is therefore built from char codes, not typed literally.
# ---------------------------------------------------------------------------
param(
	[string]$OutDir = "$([Environment]::GetFolderPath('Desktop'))\diag-export",
	[switch]$NoZip
)

$ErrorActionPreference = 'Stop'

Write-Host ("[i] args: OutDir='{0}' NoZip={1}" -f $OutDir, [bool]$NoZip)

# Godot's user:// location on Windows. Project display name is CJK -> build from code points.
$project = [string]([char]0x7535) + [string]([char]0x5B50) + [string]([char]0x8702)   # dian-zi-feng
$src = Join-Path $env:APPDATA ("Godot\app_userdata\{0}\diag" -f $project)

if (-not (Test-Path $src)) {
	Write-Host ("[X] diag dir not found: {0}" -f $src) -ForegroundColor Yellow
	Write-Host "    Run the game once on THIS code first (the autoload creates it)." -ForegroundColor Yellow
	exit 1
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Write-Host ("[>] source: {0}" -f $src)
Write-Host ("[>] output: {0}" -f $OutDir)

# --- 1. copy reports / self-checks / screenshots -----------------------------
$files = @(Get-ChildItem -Path $src -Recurse -File | Where-Object {
	$_.Name -like 'diag*.txt' -or $_.Name -like 'selfcheck*.txt' -or $_.Extension -eq '.png'
})
if ($files.Count -eq 0) {
	Write-Host "[!] nothing to collect yet (no dump triggered)" -ForegroundColor Yellow
	exit 0
}
foreach ($f in $files) { Copy-Item $f.FullName -Destination $OutDir -Force }
Write-Host ("[OK] copied {0} file(s)" -f $files.Count)

# --- 2. newest-report info ---------------------------------------------------
$latest = Join-Path $src 'LATEST.txt'
if (Test-Path $latest) {
	Write-Host '--- LATEST.txt (newest report) ---'
	Get-Content -LiteralPath $latest -Encoding UTF8 | ForEach-Object { Write-Host $_ }
	Copy-Item -LiteralPath $latest -Destination $OutDir -Force
	# keep a single-line copy (easy to grep / paste back)
	$flat = ((Get-Content -LiteralPath $latest -Raw) -replace '\s+', ' ').Trim()
	Set-Content -LiteralPath (Join-Path $OutDir 'LATEST-path.txt') -Value $flat -Encoding UTF8
}

# --- 2b. record the collector switch state (so the two machines' configs are comparable) ---
$repoRoot = Split-Path -Parent $PSScriptRoot
$flagLines = @()
foreach ($n in @('diag.flag', 'diag_period.flag', 'auto.flag')) {
	$p = Join-Path $repoRoot ("net_config\{0}" -f $n)
	if (Test-Path $p) {
		$v = (Get-Content -LiteralPath $p -Raw).Trim()
		$flagLines += ("{0} = {1}" -f $n, $v)
	} else {
		$flagLines += ("{0} = <missing> (defaults apply)" -f $n)
	}
}
Write-Host '--- collector switches (net_config) ---'
$flagLines | ForEach-Object { Write-Host $_ }
Set-Content -LiteralPath (Join-Path $OutDir 'collector-flags.txt') -Value $flagLines -Encoding UTF8

# --- 3. record the original invocation (reproducibility) ---------------------
$extra = $(if ($NoZip) { ' -NoZip' } else { '' })
$invocation = "powershell -NoProfile -ExecutionPolicy Bypass -File collect_diag.ps1 -OutDir `"$OutDir`"$extra"
Set-Content -LiteralPath (Join-Path $OutDir 'invocation.txt') -Value $invocation -Encoding UTF8

# --- 4. zip ------------------------------------------------------------------
if (-not $NoZip) {
	$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
	$zip = Join-Path $OutDir ("diag-{0}-{1}.zip" -f $env:COMPUTERNAME, $stamp)
	if (Test-Path $zip) { Remove-Item $zip -Force }
	Compress-Archive -Path (Join-Path $OutDir '*') -DestinationPath $zip -Force
	Write-Host ("[OK] zip: {0}" -f $zip) -ForegroundColor Green
}

Write-Host "Done. Send the OutDir contents back for comparison." -ForegroundColor Green
exit 0
