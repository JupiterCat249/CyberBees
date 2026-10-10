# Check worktree files against HEAD for "committed fix was overwritten" (read-only)
# ---------------------------------------------------------------------------
# Why: the Godot editor's script tab keeps an OLD buffer and can write the file
#   back to an older revision AFTER you committed. The result: HEAD contains the
#   fix, the file on disk does not -> the game behaves as if the fix never landed.
#   That kind of write-back raises no error and git only says "modified", so it is
#   easy to misread as "somebody edited the file".
#
# What it does: for each marker below, count occurrences in HEAD's copy and in the
#   working file, and report MISMATCH in red. Also prints the diff size per file.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File verification\check_worktree_vs_head.ps1
# Exit code: 0 = all consistent, 1 = mismatch found (or git error).
# ASCII-only on purpose (Windows PowerShell 5.1 reads .ps1 as ANSI).
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

Write-Host '=== worktree vs HEAD marker check ===' -ForegroundColor Cyan

# Markers are ASCII-only substrings that only exist after the corresponding fix.
$checks = @(
	@{ file = 'scenes/ui/arena_view.gd';      marker = 'art_offset_y' },
	@{ file = 'scenes/ui/arena_view.gd';      marker = '_install_main_button_stroke' },
	@{ file = 'scenes/ui/arena_view.gd';      marker = '_center_badge_value_geometry' },
	@{ file = 'scenes/ui/arena_view.gd';      marker = '_fit_window_to_design' },
	@{ file = 'scenes/ui/arena_view.gd';      marker = 'INFO_DIM' },   # NOTE: removed again on purpose -> keep at 0
	@{ file = 'scripts/diag/net_diag_dump.gd'; marker = '_visible_bounds' },
	@{ file = 'scripts/diag/net_diag_dump.gd'; marker = '_section_turnstate' },
	@{ file = 'scripts/diag/net_diag_dump.gd'; marker = '_section_pixels' },
	@{ file = 'scripts/diag/net_diag_dump.gd'; marker = 'probe_colors' }
)

function Count-InText([string]$text, [string]$needle) {
	if ([string]::IsNullOrEmpty($text)) { return 0 }
	return ([regex]::Matches($text, [regex]::Escape($needle))).Count
}

$bad = 0
foreach ($c in $checks) {
	$f = $c.file
	$mk = $c.marker
	if (-not (Test-Path $f)) {
		Write-Host ("[MISS] {0} : file not found" -f $f) -ForegroundColor Red
		$bad++
		continue
	}
	$headText = ''
	try { $headText = (git show ("HEAD:" + $f) | Out-String) } catch { $headText = '' }
	$diskText = (Get-Content -LiteralPath $f -Raw)
	$h = Count-InText $headText $mk
	$d = Count-InText $diskText $mk
	if ($h -ne $d) {
		Write-Host ("[MISMATCH] {0} :: '{1}'  HEAD={2}  disk={3}" -f $f, $mk, $h, $d) -ForegroundColor Red
		$bad++
	} else {
		Write-Host ("[ok] {0} :: '{1}' = {2}" -f $f, $mk, $d)
	}
}

Write-Host ''
Write-Host '--- per-file diff size (worktree vs HEAD) ---'
$stat = (git diff --stat | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($stat)) {
	Write-Host 'clean: worktree matches HEAD'
} else {
	Write-Host $stat
	Write-Host ''
	Write-Host 'HINT: if the additions are only serialization fields' -ForegroundColor Yellow
	Write-Host '      (anchors_preset / layout_mode / metadata / ext_resource),' -ForegroundColor Yellow
	Write-Host '      the worktree is an older revision re-saved by the editor ->' -ForegroundColor Yellow
	Write-Host '      back it up, then: git restore --source=HEAD -- <files>' -ForegroundColor Yellow
}

Write-Host ''
if ($bad -gt 0) {
	Write-Host ("RESULT: {0} problem(s) - a committed fix may have been written back by the editor." -f $bad) -ForegroundColor Red
	exit 1
}
Write-Host 'RESULT: all markers consistent between worktree and HEAD.' -ForegroundColor Green
exit 0
