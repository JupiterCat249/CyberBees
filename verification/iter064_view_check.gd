extends Node
## 迭代064 视图层回归自检（把本轮所有视图修复固化成**可重跑断言**）
## ---------------------------------------------------------------------------
## 运行：`project_run(mode="custom", scene="res://verification/iter064_view_check.tscn")`
##   （或用编辑器 F6 打开本场景运行）。**不需要**联机中继 —— 纯视图层断言。
##
## 覆盖（迭代064 各批次）：
##   B1 效果类三条信号已接线（修 P-21 徽标残存）
##   B3 手牌灰化只压 RGB、不压 alpha（修 P-05）
##   B4 卡上目标标框 set_mark（修 P-13）
##   B7 移除按钮进度条 / 详情区去技能名 / 右下面板不被阶段文案覆盖 /
##      主按钮长文案恒居中 / 费用两位数恒居中且不溢出徽章（修 P-17 · P-04 · P-09 · P-11 · P-06）
##   B8 单位卡电子管特效静止且无色变（修 P-02）
##   B2 HUD 随座位换边且可逆（修 P-07）
##   P-12 地图边框压在卡之上（修 UI-10 边缘蹭线）
##
## ⚠️ GDScript 闭包按值捕获 → 断言计数一律用**成员变量**
## ⚠️ Label 的尺寸在文本变更后**下一帧**才更新（Control 最小尺寸回写）→ 断言前须 await 若干帧
## ⚠️ 全部用例都带判空 —— 缺节点时判 FAIL 而不是崩（崩了整份报告就没了）
## ---------------------------------------------------------------------------
const BATTLE := preload("res://scenes/ui/battle_scene.tscn")
const Bus := preload("res://scripts/battle/battle_signal_bus.gd")
## 预览类型枚举（新断言要判"是否含 ATTACK 格"）
const K := preload("res://scripts/battle/preview_kind.gd")

var _pass := 0
var _fail := 0
var _view: Node = null


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label, detail)
	else:
		_fail += 1
		print("  FAIL  ", label, detail)


func _idle(frames: int = 2) -> void:
	for _i in frames:
		await get_tree().process_frame


func _first_hand_card() -> Control:
	var nodes = _view.get("_hand_nodes")
	if nodes == null:
		return null
	for sidek in nodes.keys():
		var d = nodes[sidek]
		for k in d.keys():
			var n = d[k]
			if n != null and is_instance_valid(n):
				return n
	return null


func _first_unit_card() -> Control:
	var nodes = _view.get("_unit_nodes")
	if nodes == null:
		return null
	for k in nodes.keys():
		var n = nodes[k]
		if n != null and is_instance_valid(n):
			return n
	return null


func _ready() -> void:
	print("=== 迭代064 视图层回归自检 ===")
	_view = BATTLE.instantiate()
	add_child(_view)
	await _idle(4)

	await _check_b1()
	await _check_b3()
	await _check_b4()
	await _check_b7()
	await _check_b8()
	await _check_b2()
	await _check_cell_mirror_data_driven()
	_check_p12()
	## ⚠️ P-03 必须**在任何修改 phase 的新用例之前**跑（它依赖"开局＝部署阶段"，见下）
	await _check_p03()
	## ⭐ 迭代064 遗留四项（人 2026-10-05 报告）—— 顺序：先跑"点自己单位"的防回归，最后才跑"杀死单位"的用例
	await _check_cancel_paths()
	await _check_regression_cell_click()
	await _check_remote_target_marks()
	await _check_remote_ghost()
	## ⭐ 迭代064 遗留（人 2026-10-05 补充两问）
	await _check_tint_preserves_bind_color()
	await _check_detail_autowrap()

	print("=== 结果：%d PASS / %d FAIL ===" % [_pass, _fail])


## ⭐ 遗留修复（人 2026-10-05「第一回合第一个发起攻击的单位有时会奇怪的变黑」）：
##   `TINT` 类动画（卡牌登场淡入 / 受伤闪红 / 单位退场）**不得改写卡面语义色**——
##   卡面颜色由 `card_unit.bind()`（白 / 已行动冷灰蓝）决定，动画只允许叠色 + 淡入淡出。
##   修前：淡入第 1 帧写 `(1,1,1,0.25)`（＝"变黑"），闪红末帧把已行动色覆盖回纯白（实测）。
func _check_tint_preserves_bind_color() -> void:
	var u := _first_unit_card()
	if u == null:
		_ok("TINT 不覆盖 · 取到单位卡", false)
		return
	## 造一个"语义色"：已行动冷灰蓝（与 card_unit.ACTED_TINT 一致），随后交给**绑定期之外**的动画
	var acted := Color(0.62, 0.68, 0.78, 1)
	u.modulate = acted
	## ⚠️ `anim` 是 arena_view 的**成员变量**（不是方法）⇒ 必须先 get() 取到对象再 call()
	##   （实测踩到：`_view.call("anim")` → Invalid call → 游戏被停进断点）
	var ap = _view.get("anim")
	if ap == null:
		_ok("TINT 不覆盖 · 取到动画播放器", false)
		return
	ap.call("action", "受伤闪红", u, 3)
	await _idle(10)                       ## 闪红共 6 帧，等它播完
	var m: Color = u.modulate
	_ok("TINT 动画不抹掉卡面语义色（受伤闪红后仍为已行动色）",
		absf(m.r - acted.r) < 0.02 and absf(m.g - acted.g) < 0.02 and absf(m.b - acted.b) < 0.02,
		" %s（期望 ≈%s）" % [str(m), str(acted)])
	_ok("TINT 动画不把 alpha 留在中途", is_equal_approx(m.a, 1.0), " a=%.2f" % m.a)
	## 卡牌登场（淡入）只动 alpha：播完必须回到语义色
	ap.call("action", "卡牌登场", u, 0)
	await _idle(8)
	var m2: Color = u.modulate
	_ok("卡牌登场淡入结束后回到语义色",
		absf(m2.r - acted.r) < 0.02 and absf(m2.b - acted.b) < 0.02 and is_equal_approx(m2.a, 1.0),
		" %s" % str(m2))
	u.modulate = Color(1, 1, 1, 1)


## ⭐ 遗留修复（人 2026-10-05「左侧单位技能详细信息栏文本超出边框来到战斗地图而没有自动换行」）：
##   实测根因：`SkillDesc` 框宽 **300px**、技能描述单行可达 **444px+**、`autowrap=0` ⇒ 直接画出框外。
##   判据用**压测文案**（确定会溢出）：换行开启后行数 > 1，且**所需高度随行数增长**（实测 25 → 162）。
func _check_detail_autowrap() -> void:
	var ds := _view.get_node_or_null("HUD/InfoPanel/SkillDesc") as Label
	var panel := _view.get_node_or_null("HUD/InfoPanel") as Control
	if ds == null or panel == null:
		_ok("详情栏换行 · 取到 SkillDesc/InfoPanel", false)
		return
	_ok("详情栏 SkillDesc 已开自动换行",
		int(ds.autowrap_mode) != int(TextServer.AUTOWRAP_OFF), " autowrap=%d" % int(ds.autowrap_mode))
	var keep := ds.text
	ds.text = "[被动]在敌方领地时，攻击造成两倍伤害；若目标为蜂王则额外获得一层护盾，并在下次受击时优先抵挡全部伤害。"
	await _idle(4)
	var need_w := ds.get_theme_font("font").get_string_size(
		ds.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ds.get_theme_font_size("font_size")).x
	var lines: int = ds.get_line_count()
	_ok("详情栏长文案确实折行（行数 > 1）", lines > 1,
		" 行数=%d · 单行所需宽=%.0f · 框宽=%.0f" % [lines, need_w, ds.size.x])
	_ok("详情栏长文案所需高度随行数增长（未被单行高度夹住）",
		ds.size.y > float(ds.get_theme_font_size("font_size")) * 1.5,
		" 高度=%.1f" % ds.size.y)
	ds.text = keep
	await _idle(2)


## ⭐ 迭代064 遗留②（人 2026-10-05）：手牌选中态的**取消出口必须齐全**。
##   三个入口：① 点战斗地图之外（`_unhandled_input`）② 点敌方手牌（非交互区域）③ 点地图内空格。
##   背景：④ 曾因**全屏背景层吃掉左键**而完全收不到事件（已用 mouse_filter=2 修）、
##        ② 曾因"对手手牌不可点"的权限门直接 return 而卡死。
func _check_cancel_paths() -> void:
	var eng = _view.get("engine")
	if eng == null:
		_ok("取消出口 · 取到引擎", false)
		return
	eng.call("select_hand", 0, 0)
	await _idle(2)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(10, 10)
	ev.global_position = Vector2(10, 10)
	_view.call("_unhandled_input", ev)
	await _idle(2)
	_ok("取消出口 ①点战斗地图之外 → 取消选中", int(eng.sel_kind) == 0,
		" sel_kind=%d" % int(eng.sel_kind))
	## ② 点敌方手牌 = 非交互区域 ⇒ 同样取消（权限门保持不变：仍不可操作）
	eng.call("select_hand", 0, 0)
	await _idle(2)
	var eid := ""
	var hn = _view.get("_hand_nodes")
	if hn != null and hn.has(1):
		for k in hn[1].keys():
			eid = String(k)
			break
	if eid == "":
		_ok("取消出口 ②取到敌方手牌", false)
	else:
		_view.call("_on_hand_clicked", eid, 1)
		await _idle(2)
		_ok("取消出口 ②点敌方手牌 → 取消选中（且仍未选中该牌）",
			int(eng.sel_kind) == 0, " sel_kind=%d" % int(eng.sel_kind))
	## ③ 点地图内空格（原设计稿 §5.1：点击不可交互区域取消选中）
	## ⚠️ **修正（2026-10-10 实测：本断言原为 flaky，且深层原因不止"写死格子"）**：
	##   原写法把格子**写死成 `(2,3)`**，并假设"部署阶段 0 号手牌的布署范围不含它" ——
	##   实测发现这**取决于手上是哪张卡**：
	##     · 0 号 = 蜂王时，`hand_range_has_cell()` 对**全部 16 格都返回 true**
	##       （"选蜂王时每格都可部署"是**设计行为**）⇒ **"范围外格"在该卡下根本不存在** ⇒ 断言恒 FAIL ✗
	##     · 0 号是别的卡时范围有界 ⇒ 恰好 PASS（纯运气，非稳定）
	##   修法：**动态找一张"布署范围不覆盖目标格"的手牌**（含"单位选中"这条同类取消路径的兜底），
	##        把"取消出口"这件事**与牌库/回合解耦** —— 断言才有确定的判据。
	var target_cell := Vector2i(2, 3)
	var pick := -1
	var hand_size: int = (eng.state.sides[0]["hand"] as Array).size()
	for hi in hand_size:
		eng.call("select_hand", 0, hi)
		await _idle(1)
		if not eng.hand_range_has_cell(target_cell):
			pick = hi
			break
	if pick < 0:
		## 兜底：单位选中态的取消出口（`_on_cell_clicked` 在 MOVE/ATTACK 之外同样清选中）
		var mine_u = _first_ally_unit()
		if mine_u != null:
			eng.state.phase = 3          ## ACTION
			eng.state.active = 0
			eng.call("select_unit", 0, mine_u)
			await _idle(1)
			_view.call("_on_cell_clicked", target_cell)
			await _idle(2)
			_ok("取消出口 ③（兜底：单位选中态）点范围外格 → 取消选中",
				int(eng.sel_kind) == 0,
				" sel_kind=%d（该牌库下每张手牌布署范围均覆盖该格，故走单位态）" % int(eng.sel_kind))
	else:
		eng.call("select_hand", 0, pick)
		await _idle(2)
		_view.call("_on_cell_clicked", target_cell)
		await _idle(2)
		_ok("取消出口 ③点地图内（手牌范围外）空格 → 取消选中",
			int(eng.sel_kind) == 0,
			" 手牌索引=%d · 点的是 %s · sel_kind=%d" % [pick, str(target_cell), int(eng.sel_kind)])


## ⭐ 防回归（与上面同批改动强相关）：棋盘格仍是"点自己单位"的有效入口。
##   曾担心把全屏背景层设为 mouse_filter=2 会连带削掉棋盘点击 —— 这条就是那个守卫。
func _check_regression_cell_click() -> void:
	var eng = _view.get("engine")
	var mine = _first_ally_unit()
	if eng == null or mine == null:
		_ok("防回归 · 取到引擎与我方单位", false)
		return
	eng.state.phase = 3              ## ACTION
	eng.state.active = 0
	eng.call("request_clear_selection")
	await _idle(2)
	_view.call("_on_cell_clicked", mine.cell)
	await _idle(3)
	_ok("防回归：点地图内我方单位格 → 进入选中态（sel_kind=2）",
		int(eng.sel_kind) == 2, " sel_kind=%d" % int(eng.sel_kind))


## ⭐ 迭代064 遗留①（**人口径：这是「应该」**）：联机信息透明 ——
##   对端视图必须看到「我方选中单位进入攻击状态后的**攻击范围**」+「**所选攻击目标**（卡上标框）」。
func _check_remote_target_marks() -> void:
	var eng = _view.get("engine")
	var mine = _first_ally_unit()
	var foe = _first_enemy_unit()
	if eng == null or mine == null or foe == null:
		_ok("① · 取到双方单位", false)
		return
	## 造"贴脸"（只挪位置，不改规则）⇒ 攻击范围内确有目标，预览才会含 attack 格
	var t := Vector2i(mine.cell.x, mine.cell.y + 1)
	if eng.state.board.unit_at(t) != null:
		t = Vector2i(mine.cell.x + 1, mine.cell.y)
	eng.state.board.move_unit(foe, t)
	_view.call("set_my_seat", 1)          ## 我 = 红方 ⇒ 绿方就是"对端"
	eng.state.active = 0
	eng.state.phase = 3
	eng.call("request_clear_selection")
	await _idle(2)
	_view.call("_on_remote_select", 0, mine.cell)
	await _idle(4)
	var pv = _view.get("_preview")
	var has_attack := false
	if pv != null:
		for pc in pv.cells:
			if int(pc.kind) == K.Kind.ATTACK:
				has_attack = true
	_ok("① 对端视图含**攻击范围**格", has_attack,
		" cells=%d" % (0 if pv == null else pv.cells.size()))
	_ok("① 对端视图含**所选攻击目标**的单位卡标框", _visible_mark_count() >= 1,
		" marks=%d" % _visible_mark_count())
	_view.call("set_my_seat", 0)


## ⭐ 迭代064 遗留③（人 2026-10-05）：对端远端预览挂在某单位上时，
##   该单位在本方回合死亡 ⇒ **范围/高亮/对端选中框必须立即全部消失**（不得有幽灵残留）。
func _check_remote_ghost() -> void:
	var eng = _view.get("engine")
	var opp = _first_ally_unit()
	if eng == null or opp == null:
		_ok("③ · 取到引擎与我方单位", false)
		return
	_view.call("set_my_seat", 1)          ## 我 = 红方 ⇒ 绿方(0) 是"对端"
	eng.state.active = 0
	eng.state.phase = 3
	eng.call("request_clear_selection")
	await _idle(2)
	_view.call("_on_remote_select", 0, opp.cell)
	await _idle(3)
	var before := _highlight_count()
	opp.current_hp = 0
	eng.call("_cleanup_dead")
	await _idle(6)
	_ok("③ 远端预览的单位死亡前确有范围高亮（对照）", before > 0, " before=%d" % before)
	_ok("③ 死亡后：预览被作废", _view.get("_preview") == null)
	_ok("③ 死亡后：棋盘零残留高亮", _highlight_count() == 0,
		" 残留=%d" % _highlight_count())
	_ok("③ 死亡后：对端选中框也清掉", _selected_cell_count() == 0,
		" 残留选中格=%d" % _selected_cell_count())
	_view.call("set_my_seat", 0)


# ---------------- 读数工具（新断言专用） ----------------
func _first_ally_unit():
	return _view.call("_find_unit", _first_unit_id_of_side(0))


func _first_enemy_unit():
	return _view.call("_find_unit", _first_unit_id_of_side(1))


func _first_unit_id_of_side(side: int) -> String:
	var eng = _view.get("engine")
	if eng == null:
		return ""
	for u in eng.state.board.all_units():
		if int(u.side) == side:
			return String(u.instance_id)
	return ""


func _visible_mark_count() -> int:
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


func _highlight_count() -> int:
	var cells = _view.get("_cells")
	var n := 0
	if cells != null:
		for c in cells.keys():
			if String(cells[c].highlight) != "":
				n += 1
	return n


func _selected_cell_count() -> int:
	var cells = _view.get("_cells")
	var n := 0
	if cells != null:
		for c in cells.keys():
			if bool(cells[c].selected):
				n += 1
	return n


## P-03（清单 UI-3/UI-4/UI-18）：**部署阶段点单位不给范围**（视图侧应为零高亮）；
## 而**可用的手牌**在部署阶段应给出部署格 —— 两条对照，确保不是"一律不显示"。
func _check_p03() -> void:
	var eng = _view.get("engine")
	var nodes = _view.get("_unit_nodes")
	var cells = _view.get("_cells")
	if eng == null or nodes == null or cells == null:
		_ok("P-03 取到引擎/单位表/格子表", false)
		return
	var u = null
	for k in nodes.keys():
		var iu = _view.call("_find_unit", String(k))
		if iu != null:
			u = iu
			break
	if u == null:
		_ok("P-03 取到场上单位", false)
		return
	## 回合 1 开局应为**部署阶段**（phase=2）；若已被推进则明确报出，避免误判
	if int(eng.state.phase) != 2:
		_ok("P-03 开局处于部署阶段", false, " phase=%d" % int(eng.state.phase))
		return
	eng.call("select_unit", 0, u)
	await _idle(3)
	var pv = _view.get("_preview")
	_ok("P-03 部署阶段选单位 → 预览为空（UI-3/UI-18）",
		pv == null or pv.cells.size() == 0,
		" cells=%d" % (0 if pv == null else pv.cells.size()))
	var any_hl := false
	for c in cells.keys():
		if cells[c].highlight != "":
			any_hl = true
			break
	_ok("P-03 部署阶段选单位 → 棋盘零高亮（UI-3）", not any_hl)
	## 对照组：可用的手牌必须仍给部署格（否则说明把该显示的也关掉了）
	var idx := -1
	var hand: Array = eng.state.sides[0]["hand"]
	for i in hand.size():
		if eng.call("can_play_hand", 0, i):
			idx = i
			break
	if idx < 0:
		_ok("P-03 找到一张可用手牌（对照组）", false)
		return
	eng.call("select_hand", 0, idx)
	await _idle(3)
	var pv2 = _view.get("_preview")
	_ok("P-03 对照：可用手牌仍给部署格（UI-4 反向）",
		pv2 != null and pv2.cells.size() > 0,
		" cells=%d" % (0 if pv2 == null else pv2.cells.size()))


## B1：效果类三条信号必须已接线（否则"引擎变了界面没变"会复发）
func _check_b1() -> void:
	var b := Bus.shared()
	_ok("B1 已订阅 effect_granted",
		b.is_connected(Bus.SIG_EFFECT_GRANTED, Callable(_view, "_on_effect_granted")))
	_ok("B1 已订阅 effect_expired",
		b.is_connected(Bus.SIG_EFFECT_EXPIRED, Callable(_view, "_on_effect_expired")))
	_ok("B1 已订阅 unit_stats_changed",
		b.is_connected(Bus.SIG_UNIT_STATS, Callable(_view, "_on_unit_stats_changed")))


## B3：手牌灰化**只压 RGB、alpha 恒 1**（费用图标/数字不得半透明）
func _check_b3() -> void:
	var c := _first_hand_card()
	if c == null:
		_ok("B3 取到手牌卡", false, "（无手牌节点）")
		return
	c.call("set_playable", false)
	var m: Color = c.modulate
	_ok("B3 灰化后 alpha 仍为 1（费用标记不半透明）", is_equal_approx(m.a, 1.0), " a=%.2f" % m.a)
	_ok("B3 灰化确实压了 RGB", m.r < 1.0 and is_equal_approx(m.r, m.g), " r=%.2f" % m.r)
	c.call("set_playable", true)
	_ok("B3 set_playable(true) 复原", is_equal_approx(c.modulate.a, 1.0) and is_equal_approx(c.modulate.r, 1.0))


## B4：卡上目标标框（因 PITCH=250 而卡正好 250×250，格高亮会被整片盖住）
func _check_b4() -> void:
	var u := _first_unit_card()
	if u == null:
		_ok("B4 取到单位卡", false, "（无单位卡节点）")
		return
	u.call("set_mark", "attack")
	var mark := u.get_node_or_null("Mark") as Control
	_ok("B4 set_mark 生成标框且可见", mark != null and mark.visible)
	if mark != null:
		_ok("B4 标框 z_index 高于卡面内容", mark.z_index >= 2, " z=%d" % mark.z_index)
		var sb := mark.get_theme_stylebox("panel")
		_ok("B4 攻击标框用红橙 #e8663c",
			sb is StyleBoxFlat and (sb as StyleBoxFlat).border_color.to_html(false) == "e8663c")
		_ok("B4 标框与卡面等大重合",
			mark.get_global_rect().size.is_equal_approx(u.get_global_rect().size))
	u.call("set_mark", "")
	var m2 := u.get_node_or_null("Mark") as Control
	_ok("B4 set_mark(\"\") 隐藏标框", m2 != null and not m2.visible)


## B7：文本与参数（进度条 / 技能名 / 地图机制面板 / 两处居中）
func _check_b7() -> void:
	var bar := _view.get_node_or_null("HUD/ActionBar") as Control
	var lb := _view.get_node_or_null("HUD/ActionBar/Label") as Control
	_ok("B7 主按钮进度条 MainButtonSeg 已移除",
		_view.get_node_or_null("HUD/ActionBar/MainButtonSeg") == null)
	if bar != null and lb != null:
		lb.text = "绿方胜（蜂王被击杀）"
		await _idle(3)
		_ok("B7 长文案下按钮文案仍居中",
			absf(lb.position.x - (bar.size.x - lb.size.x) * 0.5) < 1.0,
			" x=%.1f box=%.1f bar=%.1f" % [lb.position.x, lb.size.x, bar.size.x])
		lb.text = "完成部署"
		await _idle(2)

	## 详情区不再拼技能名（描述正文自带 [被动] 等前缀）
	var c := _first_hand_card()
	if c != null:
		var cd = c.get("card_data")
		if cd != null:
			_view.call("show_detail", cd)
			await _idle(2)
			var desc := _view.get_node_or_null("HUD/InfoPanel/SkillDesc") as Label
			var sn := String(cd.skill_name)
			_ok("B7 详情区不显示技能名",
				desc != null and (sn == "" or not desc.text.contains(sn)),
				" skill_name=「%s」" % sn)
	else:
		_ok("B7 取到手牌卡（详情区检查用）", false, "（无手牌节点）")

	## 右下面板不得被阶段文案覆盖（应保留地图机制）
	var se := _view.get_node_or_null("HUD/MatchInfo/SiteEffect") as Label
	if se != null:
		var before := se.text
		_view.call("_on_phase_started", 0, 2, 1)
		_ok("B7 阶段文案不再覆盖地图机制面板", se.text == before, " 「%s」" % se.text)
	else:
		_ok("B7 取到 SiteEffect", false)

	## 费用两位数：恒居中且不溢出徽章
	for sidep in ["Battle/PlayerBesaInfoRight", "Battle/PlayerBesaInfoLift"]:
		var badge := _view.get_node_or_null(sidep + "/BadgeImage") as Control
		if badge == null:
			_ok("B7 取到费用徽章 %s" % sidep, false)
			continue
		var v := badge.get_node_or_null("Value") as Control
		if v == null:
			_ok("B7 取到费用数字 %s" % sidep, false)
			continue
		v.text = "10"
		await _idle(3)
		_ok("B7 两位数费用恒居中 %s" % sidep,
			absf(v.position.x - (badge.size.x - v.size.x) * 0.5) < 1.0,
			" x=%.1f w=%.1f badge=%.1f" % [v.position.x, v.size.x, badge.size.x])
		_ok("B7 两位数费用不溢出徽章 %s" % sidep,
			v.get_global_rect().end.x <= badge.get_global_rect().end.x + 0.5,
			" text_end=%.1f badge_end=%.1f" % [v.get_global_rect().end.x, badge.get_global_rect().end.x])


## B8：单位卡电子管/扫描线叠加层 —— **静止 + 无色变**（P-02 = 清单 UI-2）
## ⚠️ 断言已按**现行场景结构**更新（2026-10-05，本次遗留修复时发现该条已陈旧）：
##   人工提交 `e5f78f6`「单位卡移除旧 CrtFx 扫描线子树」把 `CrtFx/{CrtAnim,Mover,Sheet1..3}`
##   改成 **`CrtFx/Sheet2`（单个静态 TextureRect，`modulate.a = 0.1`）**；本断言原查
##   `CrtFx/CrtAnim` + `CrtFx/Mover` ⇒ 在当前 HEAD 上**必然 FAIL**（不是我本轮改动引入的回归）。
##   新口径（仍守住 P-02 的语义）：**叠加层存在、静止、无颜色变换、且没有自动播放的动画子树**。
func _check_b8() -> void:
	var u := _first_unit_card()
	if u == null:
		_ok("B8 取到单位卡", false)
		return
	var crt := u.get_node_or_null("Artwork/ArtPlane/CrtFx") as Control
	if crt == null:
		_ok("B8 取到 CrtFx 叠加层", false, " card=%s" % str(u.name))
		return
	_ok("B8 CrtFx 叠加层存在（P-02 前提）", crt != null)
	## ① **不得残留自动播放的动画节点**（旧结构里 `CrtAnim.autoplay = "scan"` 正是"运动"的来源）
	var anim_nodes: Array[String] = []
	_collect_anim_players(crt, anim_nodes)
	var playing := false
	for path in anim_nodes:
		var ap = crt.get_node_or_null(path) as AnimationPlayer
		if ap != null and ap.is_playing():
			playing = true
	_ok("B8 叠加层内无运动动画（无 AnimationPlayer 或均未播放）",
		not playing, " anim_players=%s" % str(anim_nodes))
	## ② **静止**：叠加层自身与其纹理子节点位置在若干帧内不变
	var sheet := crt.get_node_or_null("Sheet2") as TextureRect
	if sheet != null:
		var p0 := sheet.position
		var m0 := sheet.modulate
		await _idle(10)
		_ok("B8 扫描线叠加层不运动",
			(sheet.position - p0).length() < 0.01,
			" Δ=%.3f" % (sheet.position - p0).length())
		## ③ **无颜色变换**：颜色由**美术参数**（0.1 透明度条纹）决定，运行期不得再被改写 ⇒ 保持恒定
		_ok("B8 扫描线叠加层颜色稳定（无色变换）",
			sheet.modulate.is_equal_approx(m0),
			" %s → %s" % [str(m0), str(sheet.modulate)])
	else:
		_ok("B8 取到扫描线叠加层 Sheet2", false,
			" children=%d" % crt.get_child_count())


## 收集某节点下的所有 AnimationPlayer 相对路径（判"有没有会自动播放的动画子树"）
func _collect_anim_players(n: Node, out: Array[String], prefix: String = "") -> void:
	for ch in n.get_children():
		var p: String = prefix + String(ch.name)
		if ch is AnimationPlayer:
			out.append(p)
		_collect_anim_players(ch, out, p + "/")


## B2：HUD 随座位换边，且切回座位 0 能精确还原
func _check_b2() -> void:
	var hl := _view.get_node_or_null("Battle/HandPanelLeft") as Control
	var hr := _view.get_node_or_null("Battle/HandPanelRight") as Control
	if hl == null or hr == null:
		_ok("B2 取到手牌面板", false)
		return
	var l0 := hl.position.x
	var r0 := hr.position.x
	_view.call("set_my_seat", 1)
	_ok("B2 镜像后我方（左面板）换到右侧", hl.position.x > hr.position.x,
		" L=%.0f R=%.0f" % [hl.position.x, hr.position.x])
	_view.call("set_my_seat", 0)
	_ok("B2 切回座位 0 精确还原", is_equal_approx(hl.position.x, l0) and is_equal_approx(hr.position.x, r0),
		" L=%.0f(原 %.0f) R=%.0f(原 %.0f)" % [hl.position.x, l0, hr.position.x, r0])


## ⭐ 迭代065 专用断言：**数据镜像**（无节点旋转）契约
##   人 2026-10-10 口径：「需要的不是旋转，而是根据数据还原出对面视角下应该看到的对称的内容」
##   判据三条：① `MapView` 恒无旋转 ② 16 格位置 = `N·PITCH − 规范局部坐标`（seat1）/ 恒等（seat0）
##            ③ 单位卡恒无旋转（不再反向自转抵父节点旋转）
func _check_cell_mirror_data_driven() -> void:
	var mv := _view.get_node_or_null("Battle/MapView") as Control
	var cells_root := _view.get_node_or_null("Battle/MapView/MapCells") as Control
	if mv == null or cells_root == null:
		_ok("065 取到 MapView / MapCells", false)
		return
	var pitch := 250.0
	var ext := pitch * 4.0
	var cells := []
	for ch in cells_root.get_children():
		var ctl := ch as Control
		if ctl != null and ctl.has_method("get") and ctl.get("cell") != null:
			cells.append(ctl)
	if cells.size() < 16:
		_ok("065 取到 16 个格节点（实际 %d）" % cells.size(), false)
		return
	# ② seat0 = 恒等；seat1 = N·PITCH - 规范局部坐标
	## ⚠️ 每个座位只切一次再统一核对（在循环里切会让 `set_my_seat` 的日志刷屏，也拖慢用例）
	var bad0 := 0
	var bad1 := 0
	_view.call("set_my_seat", 0)
	for ctl in cells:
		var canon0: Vector2i = ctl.get("cell")
		var canon_p0 := Vector2(float(canon0.y) * pitch, float(canon0.x) * pitch)
		if not canon_p0.is_equal_approx(ctl.position):
			bad0 += 1
	_view.call("set_my_seat", 1)
	for ctl in cells:
		var canon1: Vector2i = ctl.get("cell")
		var canon_p1 := Vector2(float(canon1.y) * pitch, float(canon1.x) * pitch)
		var mirror_p := Vector2(ext, ext) - canon_p1
		if not mirror_p.is_equal_approx(ctl.position):
			bad1 += 1
	_ok("065 seat0：16 格 = 规范坐标（恒等）", bad0 == 0, " 不符 %d 格" % bad0)
	_ok("065 seat1：16 格 = N·PITCH − 规范坐标（数据镜像）", bad1 == 0, " 不符 %d 格" % bad1)
	# ① 旋转必须恒为 0（含 pivot —— 旧实现靠 pivot + rotation 做镜像）
	_view.call("set_my_seat", 1)
	var rot_ok := is_zero_approx(mv.rotation) and mv.pivot_offset.is_equal_approx(Vector2.ZERO)
	var unit_rot_bad := 0
	var units_root := _view.get_node_or_null("Battle/MapView/Units") as Control
	if units_root != null:
		for u in units_root.get_children():
			var uc := u as Control
			if uc != null and not is_zero_approx(uc.rotation):
				unit_rot_bad += 1
	_ok("065 seat1：MapView 无旋转（rotation=0 · pivot=ZERO）", rot_ok,
		" rot=%.4f pivot=%s" % [mv.rotation, str(mv.pivot_offset)])
	_ok("065 seat1：单位卡无反向自转", unit_rot_bad == 0, " 异常 %d 个" % unit_rot_bad)
	# ③ 回到 seat0 必须精确还原
	var back_bad := 0
	_view.call("set_my_seat", 0)
	for ctl in cells:
		var canon2: Vector2i = ctl.get("cell")
		var p2 := Vector2(float(canon2.y) * pitch, float(canon2.x) * pitch)
		if not p2.is_equal_approx(ctl.position):
			back_bad += 1
	_ok("065 切回 seat0 精确还原全部 16 格", back_bad == 0, " 不符 %d 格" % back_bad)


## P-12：地图边框（纯描边无填充）必须压在单位卡之上，否则边缘卡会截断框线
func _check_p12() -> void:
	var mf := _view.get_node_or_null("Battle/MapView/MapFrame") as Control
	var un := _view.get_node_or_null("Battle/MapView/Units") as Control
	if mf == null or un == null:
		_ok("P-12 取到 MapFrame / Units", false)
		return
	_ok("P-12 地图边框 z_index 高于单位卡容器", mf.z_index > un.z_index,
		" frame=%d units=%d" % [mf.z_index, un.z_index])
