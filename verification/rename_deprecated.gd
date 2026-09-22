extends Node
## 迭代060 · 废弃代码标注工具（**一次性迁移**；T12：验证/工具产物，生产代码禁止引用）
##
## 人裁决（2026-09-21）：机制＝**MCP 写新文件 + 清空旧文件（不删）**；命名＝**追加 `.deprecated`**；范围＝**全量（先救 Board）**
## 判定依据：可达性审计（`系统维护/tools/audit_reach.ps1` + `verification/archive/iter060_reach_audit.json`）
##
## 做法：
##   ① **先救 Board** —— `archive/legacy/scripts_game/board.gd` 是全仓唯一 `class_name Board`，
##      而生产规则层（`scripts/battle/rules_preview.gd` 等）在用 `Board.ROWS/COLS`；
##      它自包含（无 preload）→ 复制到生产目录 `scripts/battle/board.gd`，归档原件转废弃桩。
##   ② 其余 39 个废弃文件 → 内容复制到 `<path>.deprecated`，原文件写**废弃桩**
##      （`.gd` → 纯注释；`.tscn` → 最小空场景 → Godot 不再解析、注销其 class_name）。
## 运行：F6 或 project_run(mode="custom", scene="res://verification/rename_deprecated.tscn")
const RESCUE_SRC := "res://archive/legacy/scripts_game/board.gd"
const RESCUE_DST := "res://scripts/battle/board.gd"
const GD_STUB := "# ⛔ 已废弃（DEPRECATED · 迭代060 标注）\n# 原内容已移至同名 `.deprecated` 文件；本文件仅占位，不含任何可执行代码（重启编辑器后本脚本不再注册）。\n"
const TSCN_STUB := "[gd_scene format=3]\n\n[node name=\"Deprecated\" type=\"Node\"]\n"

const FILES := [
	## 归档区 · scenes_battle（20）
	"res://archive/legacy/scenes_battle/battle_action.gd",
	"res://archive/legacy/scenes_battle/battle_anim.gd",
	"res://archive/legacy/scenes_battle/battle_bgfx.gd",
	"res://archive/legacy/scenes_battle/battle_board_view.gd",
	"res://archive/legacy/scenes_battle/battle_combat.gd",
	"res://archive/legacy/scenes_battle/battle_deck.gd",
	"res://archive/legacy/scenes_battle/battle_defs.gd",
	"res://archive/legacy/scenes_battle/battle_deploy.gd",
	"res://archive/legacy/scenes_battle/battle_detail_view.gd",
	"res://archive/legacy/scenes_battle/battle_grid.gd",
	"res://archive/legacy/scenes_battle/battle_hand_view.gd",
	"res://archive/legacy/scenes_battle/battle_hud_view.gd",
	"res://archive/legacy/scenes_battle/battle_input.gd",
	"res://archive/legacy/scenes_battle/battle_interaction.gd",
	"res://archive/legacy/scenes_battle/battle_pending.gd",
	"res://archive/legacy/scenes_battle/battle_setup.gd",
	"res://archive/legacy/scenes_battle/battle_skills.gd",
	"res://archive/legacy/scenes_battle/battle_state.gd",
	"res://archive/legacy/scenes_battle/battle_turn.gd",
	"res://archive/legacy/scenes_battle/battle_victory.gd",
	## 归档区 · scripts_game（8；board 单独救）
	"res://archive/legacy/scripts_game/action_unit.gd",
	"res://archive/legacy/scripts_game/anim_presets.gd",
	"res://archive/legacy/scripts_game/battle_action.gd",
	"res://archive/legacy/scripts_game/battle_anim_driver.gd",
	"res://archive/legacy/scripts_game/battle_combat.gd",
	"res://archive/legacy/scripts_game/battle_command.gd",
	"res://archive/legacy/scripts_game/battle_effects.gd",
	"res://archive/legacy/scripts_game/game_state.gd",
	## 非归档区 · 已作废的 card-system（9）
	"res://card-system/card_system/battle_ui.gd",
	"res://card-system/card_system/battle_ui.tscn",
	"res://card-system/card_system/card.gd",
	"res://card-system/card_system/card_auto.gd",
	"res://card-system/card_system/card_auto.tscn",
	"res://card-system/card_system/card_base.tscn",
	"res://card-system/card_system/card_demo.gd",
	"res://card-system/card_system/card_demo.tscn",
	"res://card-system/card_system/tools/bake_card_atlas.gd",
	## 非归档区 · 旧主场景对（2；主场景已改指 battle_scene.tscn）
	"res://scenes/battle_flow.gd",
	"res://scenes/unuseful_battle_card.tscn",
]

var _ok := 0
var _fail := 0


func _ready() -> void:
	print("=== 迭代060 废弃代码标注（.deprecated + 废弃桩）===")
	_do(RESCUE_SRC, true)
	for p in FILES:
		_do(String(p), false)
	print("=== 结果：%d 成功 / %d 失败 ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _do(path: String, rescue_as_board: bool) -> void:
	if not FileAccess.file_exists(path):
		_fail += 1
		print("  MISS  ", path)
		return
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		_fail += 1
		print("  EMPTY ", path)
		return
	var dep := path + ".deprecated"
	if not _write(dep, txt):
		return
	var extra := ""
	if rescue_as_board:
		if not _write(RESCUE_DST, txt):
			return
		extra = "  ＋救出 " + RESCUE_DST
	var stub := TSCN_STUB if path.ends_with(".tscn") else GD_STUB
	if _write(path, stub):
		_ok += 1
		print("  OK    ", path, " → ", dep, extra)


func _write(path: String, txt: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail += 1
		print("  FAIL  ", path, " err=", FileAccess.get_open_error())
		return false
	f.store_string(txt)
	f.close()
	return true
