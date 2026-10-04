extends Node
## 【验证用 · 非生产】迭代064 遗留四项修复的**验证探针 v5**
## 验证内容：
##   ① 对端视图看到「我方选中单位的攻击范围 + 所选攻击目标」（远端预览含单位卡标框）
##   ② 手牌选中态的三个出口：点地图外 / 点敌方手牌 / 点地图内空格
##   ③ 对端远端预览的单位死亡后：预览/高亮/对端选中格全部清空
##   ④ 防回归：地图内点自己的单位仍能正常进入攻击态（不因上面的改动而失效）
## 运行：project_run(mode="custom", scene="res://verification/iter064_leak_probe.tscn")
## ⚠️ 一律无类型 var
## ---------------------------------------------------------------------------
const BATTLE := preload("res://scenes/ui/battle_scene.tscn")

var _view: Node = null
var _eng = null


func _idle(n: int = 2) -> void:
	for _i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("=== 探针 v5 · 四项修复验证 ===")
	_view = BATTLE.instantiate()
	add_child(_view)
	await _idle(6)
	_eng = _view.get("engine")
	var i := 0
	while int(_eng.state.phase) != 3 and i < 12:
		_eng.call("request_end_phase", 0)
		await _idle(2)
		i += 1
	print("预处理 phase=%d active=%d" % [int(_eng.state.phase), int(_eng.state.active)])
	## ⚠️ 顺序有意：**先跑防回归与取消出口**，最后才跑会"杀死单位"的 ①③（否则我方单位先没了，④无从验起）
	await _case_cancel()
	await _case_regression()
	await _case_remote_attack()
	await _case_ghost()
	print("PROBE DONE")
	get_tree().quit()


# ① 对端视图：范围 + 目标标框
func _case_remote_attack() -> void:
	print("--- ① 对端视图（信息透明：范围 + 所选攻击目标）---")
	var mine = _pick(0)
	var foe = _pick(1)
	_make_adjacent(mine, foe)
	_view.call("set_my_seat", 1)
	_eng.state.active = 0
	_eng.state.phase = 3
	_eng.call("request_clear_selection")
	await _idle(2)
	_view.call("_on_remote_select", 0, mine.cell)
	await _idle(4)
	print("① 【判定】对端视图：预览=%s · 高亮=%s · 带标框单位卡=%d（预期：高亮含 attack、标框≥1）" % [
		_pv_text(), str(_hl_kinds()), _mark_count()])


# ② 手牌选中态的三个出口
func _case_cancel() -> void:
	print("--- ② 手牌选中态的取消出口 ---")
	_view.call("set_my_seat", 0)
	_eng.state.active = 0
	_eng.state.phase = 3
	_eng.call("request_clear_selection")
	await _idle(2)
	## ②-1 点地图外（走视图 `_unhandled_input`，这正是背景层不再吃点击后能收到的路径）
	_eng.call("select_hand", 0, 0)
	await _idle(2)
	_view.call("_unhandled_input", _mb(Vector2(10, 10)))
	await _idle(2)
	print("②-1 点地图外(10,10)：sel_kind=%d %s" % [
		int(_eng.sel_kind), "✓" if int(_eng.sel_kind) == 0 else "✗"])
	## ②-2 点敌方手牌
	_eng.call("select_hand", 0, 0)
	await _idle(2)
	var eid := ""
	var hn = _view.get("_hand_nodes")
	if hn != null and hn.has(1):
		for k in hn[1].keys():
			eid = String(k)
			break
	_view.call("_on_hand_clicked", eid, 1)
	await _idle(2)
	print("②-2 点敌方手牌：sel_kind=%d %s" % [
		int(_eng.sel_kind), "✓" if int(_eng.sel_kind) == 0 else "✗"])
	## ②-3 点地图内空格
	_eng.call("select_hand", 0, 0)
	await _idle(2)
	_view.call("_on_cell_clicked", Vector2i(2, 3))
	await _idle(2)
	print("②-3 点地图内空格(2,3)：sel_kind=%d %s" % [
		int(_eng.sel_kind), "✓" if int(_eng.sel_kind) == 0 else "✗"])


# ③ 远端预览的幽灵范围
func _case_ghost() -> void:
	print("--- ③ 对端远端预览：单位死亡后的残留 ---")
	_view.call("set_my_seat", 1)
	_eng.state.active = 0
	_eng.state.phase = 3
	_eng.call("request_clear_selection")
	await _idle(2)
	var opp = _pick(0)
	if opp == null:
		print("③ 跳过：无绿方单位")
		return
	_view.call("_on_remote_select", 0, opp.cell)
	await _idle(4)
	print("③ 死亡前：预览=%s · 高亮=%d · 标框=%d" % [_pv_text(), _hl_count(), _mark_count()])
	opp.current_hp = 0
	_eng.call("_cleanup_dead")
	await _idle(6)
	print("③ 【判定】死亡后：预览=%s · 残留高亮=%d%s · 残留选中格=%s（预期全空）" % [
		_pv_text(), _hl_count(), str(_hl_kinds()), str(_sel_cell())])


# ④ 防回归：地图内点自己的单位
func _case_regression() -> void:
	print("--- ④ 防回归：地图内点自己单位仍能进入攻击态 ---")
	_view.call("set_my_seat", 0)
	_eng.state.active = 0
	_eng.state.phase = 3
	_eng.call("request_clear_selection")
	await _idle(2)
	var mine = _pick(0)
	if mine == null:
		print("④ 跳过：无我方单位")
		return
	var foe = _pick(1)
	_make_adjacent(mine, foe)
	_view.call("_on_cell_clicked", mine.cell)
	await _idle(4)
	print("④ 【判定】点自己单位格 %s → sel_kind=%d · 高亮=%s · 标框=%d" % [
		str(mine.cell), int(_eng.sel_kind), str(_hl_kinds()), _mark_count()])


# ---------------- 工具 ----------------
func _make_adjacent(mine, foe) -> void:
	if mine == null or foe == null:
		return
	var t := Vector2i(mine.cell.x, mine.cell.y + 1)
	if _eng.state.board.unit_at(t) != null:
		t = Vector2i(mine.cell.x + 1, mine.cell.y)
	_eng.state.board.move_unit(foe, t)


func _pick(side: int):
	for u in _eng.state.board.all_units():
		if u.side == side:
			return u
	return null


func _pv_text() -> String:
	var pv = _view.get("_preview")
	if pv == null:
		return "null"
	return "kind=%d cells=%d units=%d" % [int(pv.kind), pv.cells.size(), pv.units.size()]


func _hl_count() -> int:
	var cells = _view.get("_cells")
	var n := 0
	if cells != null:
		for c in cells.keys():
			if cells[c].highlight != "":
				n += 1
	return n


func _hl_kinds() -> Array[String]:
	var out: Array[String] = []
	var cells = _view.get("_cells")
	if cells != null:
		for c in cells.keys():
			if cells[c].highlight != "":
				out.append("%s@%s" % [String(cells[c].highlight), str(c)])
	return out


func _mark_count() -> int:
	var un = _view.get("_unit_nodes")
	var n := 0
	if un != null:
		for k in un.keys():
			var node = un[k]
			if node != null and is_instance_valid(node):
				var mk = node.get_node_or_null("Mark")
				if mk != null and mk.visible:
					n += 1
	return n


func _sel_cell() -> String:
	var cells = _view.get("_cells")
	if cells != null:
		for c in cells.keys():
			if cells[c].selected:
				return str(c)
	return "<无>"


func _mb(pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	e.global_position = pos
	return e
