extends Node
## 迭代060 · 废弃代码标注执行器（**二次运行版**：只处理剩余待标注文件）
## 人裁决（2026-09-21）：机制＝**MCP 写新文件 + 清空旧文件（不删）**；命名＝**追加 `.deprecated`**；内容保真、可逆。
##
## ⚠️ 安全守卫（上一版教训）：若原文件已是「废弃桩」（含 STUB_MARK），**一律跳过**
##   —— 否则二次运行会把桩内容写进 `.deprecated`，**覆盖掉真备份**。
## 本轮新增：`scenes/ui/cost_badge.tscn`（人 2026-09-21 裁决「前者可用标注废弃了」）
## 保留不动：`scenes/ui/crt_fx_general.tscn`（人明示：**电子管/CRT 特效移植的复用场景**，移植后各方取消依赖，但未来再移植必然用到 → 保留）
const STUB_MARK := "已废弃（DEPRECATED"
const GD_STUB := "# ⛔ 已废弃（DEPRECATED · 迭代060 标注）\n# 原内容已移至同名 `.deprecated` 文件；本文件仅占位，不含任何可执行代码（重启编辑器后本脚本不再注册）。\n"
const TSCN_STUB := "[gd_scene format=3]\n\n[node name=\"Deprecated\" type=\"Node\"]\n"

const FILES := [
	"res://scenes/ui/cost_badge.tscn",
]

var _ok := 0
var _skip := 0
var _fail := 0


func _ready() -> void:
	print("=== 迭代060 废弃代码标注（二次运行 · 剩余待标注）===")
	for p in FILES:
		_do(String(p))
	print("=== 结果：%d 标注 / %d 跳过（已是桩）/ %d 失败 ===" % [_ok, _skip, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _do(path: String) -> void:
	if not FileAccess.file_exists(path):
		_fail += 1
		print("  MISS  ", path)
		return
	var txt := FileAccess.get_file_as_string(path)
	if txt.contains(STUB_MARK):
		_skip += 1
		print("  SKIP  ", path, "（已是废弃桩，保护 .deprecated 备份）")
		return
	if txt.is_empty():
		_fail += 1
		print("  EMPTY ", path)
		return
	var dep := path + ".deprecated"
	if not _write(dep, txt):
		return
	var stub := TSCN_STUB if path.ends_with(".tscn") else GD_STUB
	if _write(path, stub):
		_ok += 1
		print("  OK    ", path, " → ", dep)


func _write(path: String, txt: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail += 1
		print("  FAIL  ", path, " err=", FileAccess.get_open_error())
		return false
	f.store_string(txt)
	f.close()
	return true
