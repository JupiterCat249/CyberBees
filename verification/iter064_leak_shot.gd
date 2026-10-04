extends Node
## 【验证用 · 非生产】迭代064 遗留项 · **视觉取证**探针（AI 自动截图）
## 目的：把「联机信息透明」的结果（对端看到我方选中单位的攻击范围 + 攻击目标框）
##       与「鬼影范围消失」的现场自动截成 PNG，供 read_image 复核（不依赖真实鼠标）。
## 运行：project_run(mode="custom", scene="res://verification/iter064_leak_shot.tscn")
## 产物：user://shot_remote_info.png · user://shot_ghost.png
## ---------------------------------------------------------------------------
const BATTLE := preload("res://scenes/ui/battle_scene.tscn")
var _view: Node = null
var _eng = null


func _idle(n: int = 2) -> void:
	for _i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("=== 遗留项修复 · 视觉取证开始 ===")
	_view = BATTLE.instantiate()
	add_child(_view)
	await _idle(6)
	_eng = _view.get("engine")
	var i := 0
	while int(_eng.state.phase) != 3 and i < 12:
		_eng.call("request_end_phase", 0)
		await _idle(2)
		i += 1

	## ── ① 对端视图：信息透明（范围 + 所选攻击目标）──
	var mine = _pick(0)
	var foe = _pick(1)
	var t := Vector2i(mine.cell.x, mine.cell.y + 1)
	if _eng.state.board.unit_at(t) != null:
		t = Vector2i(mine.cell.x + 1, mine.cell.y)
	_eng.state.board.move_unit(foe, t)
	_view.call("set_my_seat", 1)
	_eng.state.active = 0
	_eng.state.phase = 3
	_eng.call("request_clear_selection")
	await _idle(2)
	_view.call("_on_remote_select", 0, mine.cell)
	await _idle(8)
	await _shot("user://shot_remote_info.png")

	## ── ③ 鬼影：对端无人单位死亡后，范围/高亮/选中框必须全空 ──
	_eng.state.active = 0
	_eng.state.phase = 3
	_eng.call("request_clear_selection")
	await _idle(2)
	_view.call("_on_remote_select", 0, mine.cell)
	await _idle(6)
	await _shot("user://shot_ghost_before.png")
	mine.current_hp = 0
	_eng.call("_cleanup_dead")
	await _idle(10)
	await _shot("user://shot_ghost_after.png")

	print("=== 视觉取证完成 ===")
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var e := img.save_png(path)
	print("SHOT %s err=%d size=%dx%d" % [path, e, img.get_width(), img.get_height()])


func _pick(side: int):
	for u in _eng.state.board.all_units():
		if u.side == side:
			return u
	return null
