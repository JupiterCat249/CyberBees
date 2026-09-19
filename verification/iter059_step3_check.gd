extends Node
## 【验证用 · 非生产】迭代059 步3：支援双击确认（原设计）+ 地形格渲染 + 提示省略
## 用法：project_run(mode="custom", scene="res://verification/iter059_step3_check.tscn")

const Eng := preload("res://scripts/battle/battle_engine.gd")
const ConfigLib := preload("res://scripts/battle/battle_config.gd")
const StateLib := preload("res://scripts/battle/battle_state.gd")
const Pool := preload("res://scripts/data/card_pool.gd")
const Bus := preload("res://scripts/battle/battle_signal_bus.gd")
const TerrainP := preload("res://scripts/data/terrain_params.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _btn := ""
var _scene: Control = null


func _ready() -> void:
	Bus.shared().connect(Bus.SIG_MAIN_BUTTON,
		func(t: String, _e: bool, _h: String) -> void: _btn = t)
	print("\n===== 迭代059 步3：支援双击确认 + 地形渲染 + 提示省略 =====")
	_t_support_auto()
	_t_support_double_click()
	_t_self_support()
	_t_pending_cleared()
	_t_terrain_render()
	_t_no_hud_msg()
	_report()
	get_tree().quit(0 if _fail == 0 else 1)


# ============ 支援技能自动发现（不需要额外 UI 入口） ============
func _t_support_auto() -> void:
	_section("支援技能自动发现（无额外 UI 入口）")
	var eng = _engine()
	var st = eng.state
	var bumble: UnitData = Pool.card("熊蜂") as UnitData     ## 带 [支援]回复3费
	_chk("熊蜂确实带支援技能", eng.has_support_skill(_mk(bumble, 0, Vector2i(3, 0))))
	var leaf: UnitData = Pool.card("叶蜂") as UnitData
	_chk("叶蜂无支援技能", not eng.has_support_skill(_mk(leaf, 0, Vector2i(3, 1))))
	# 选中带支援的单位 → sel_kind 自动为 3（支援态）。没有单独按钮
	st.phase = StateLib.Phase.ACTION
	var u := _put(st, "熊蜂", 0, Vector2i(3, 0))
	u.reset_turn_flags()
	eng.select_unit(0, u)
	_chk("选中熊蜂 → 自动进入支援态（sel_kind=3）", eng.sel_kind == 3)
	_chk("已自动带上支援技能", eng.sel_support != null)


# ============ 双击确认 ============
## ⚠️ 熊蜂 `support_range = 0` → 只能支援**自身**（Y-5 待确认项）。
##    为验证「双击确认」链路本身，这里把技能的 target_range 临时调到 1（射程内另有目标），
##    并单独保留一条「射程外 → 拒绝且**不**进入待确认」的用例。
func _t_support_double_click() -> void:
	_section("支援：双击确认（第一次=待确认，第二次=执行）")
	var eng = _engine()
	var st = eng.state
	st.phase = StateLib.Phase.ACTION
	var u := _put(st, "熊蜂", 0, Vector2i(3, 0))     ## 支援者
	u.reset_turn_flags()
	var tgt := _put(st, "叶蜂", 0, Vector2i(3, 1))     ## 友方目标（相邻）
	st.sides[0]["cost"] = 2
	eng.select_unit(0, u)
	_chk("选中后有支援技能", eng.sel_support != null)
	# ① 射程外（target_range=0，目标在距离 1）→ 拒绝且**不**进入待确认
	var r0: bool = eng.request_support(0, u, eng.sel_support, tgt)
	_chk("射程外 → 拒绝执行", not r0)
	_chk("射程外 → **不**进入待确认（不误导按钮）", eng.support_pending == null)
	# 把射程调到 1，验证双击确认链路
	eng.sel_support.target_range = 1
	_chk("调整后目标在射程内", st.board.manhattan(u.cell, tgt.cell) <= eng.sel_support.target_range)
	# ② 第一次点击目标
	var r1: bool = eng.request_support(0, u, eng.sel_support, tgt)
	_chk("第一次点击 → **未执行**（r=false）", not r1)
	_chk("进入待确认态（support_pending != null）", eng.support_pending == tgt)
	_chk("待确认时主按钮变「确认」（实际「%s」）" % _btn, _btn == "确认")
	_chk("此时费用未变（2）", st.cost(0) == 2)
	_chk("此时单位仍未行动过", not u.has_acted)
	# ③ 第二次点击同一目标
	var r2: bool = eng.request_support(0, u, eng.sel_support, tgt)
	_chk("第二次点击 → **执行成功**", r2)
	_chk("支援回费 +3（2 → 5）", st.cost(0) == 5)
	_chk("支援后自动结束行动（行动机会 4）", u.has_acted)
	_chk("待确认态已清空", eng.support_pending == null)


# ============ 熊蜂自身支援（射程 0 的真实用法） ============
func _t_self_support() -> void:
	_section("熊蜂支援射程 0 → 只能支援自身（Y-5 口径）")
	var eng = _engine()
	var st = eng.state
	st.phase = StateLib.Phase.ACTION
	var u := _put(st, "熊蜂", 0, Vector2i(3, 0))
	u.reset_turn_flags()
	st.sides[0]["cost"] = 2
	eng.select_unit(0, u)
	_chk("自身在射程内（distance 0 <= range 0）",
		st.board.manhattan(u.cell, u.cell) <= eng.sel_support.target_range)
	# 双击确认 → 自身回费 +3
	eng.request_support(0, u, eng.sel_support, u)
	_chk("第一次点自身 → 待确认", eng.support_pending == u)
	var ok: bool = eng.request_support(0, u, eng.sel_support, u)
	_chk("第二次点自身 → 执行", ok)
	_chk("自身支援回费 +3（2 → 5）", st.cost(0) == 5)


# ============ 待确认的失效路径 ============
func _t_pending_cleared() -> void:
	_section("待确认态失效（改选 / 取消）")
	var eng = _engine()
	var st = eng.state
	st.phase = StateLib.Phase.ACTION
	var u := _put(st, "熊蜂", 0, Vector2i(3, 0))
	u.reset_turn_flags()
	var other := _put(st, "叶蜂", 0, Vector2i(3, 1))
	other.reset_turn_flags()
	eng.select_unit(0, u)
	eng.sel_support.target_range = 1
	eng.request_support(0, u, eng.sel_support, other)
	_chk("已进入待确认", eng.support_pending == other)
	eng.select_unit(0, other)
	_chk("改选其它单位 → 待确认失效", eng.support_pending == null)
	# 再次进入待确认后取消
	eng.select_unit(0, u)
	eng.sel_support.target_range = 1
	eng.request_support(0, u, eng.sel_support, other)
	_chk("再次进入待确认", eng.support_pending == other)
	eng._cancel_selection() if eng.has_method("_cancel_selection") else null
	_chk("取消选中 → 待确认清空", eng.support_pending == null)


# ============ 地形格渲染参数下发 ============
func _t_terrain_render() -> void:
	_section("地形格渲染（人 2026-09-19：代码不再画标记，地形由地图素材自带）")
	var base := FileAccess.get_file_as_string("scenes/ui/board_cell.gd")
	_chk("board_cell 有 set_terrain()", base.contains("func set_terrain"))
	_chk("board_cell 读 TerrainParams（不硬编码）", base.contains("TerrainParams"))
	_chk("**默认不画地形标记**（draw_marker 开关守卫）",
		base.contains("terrain_params.draw_marker"))
	var tpsrc := FileAccess.get_file_as_string("scripts/data/terrain_params.gd")
	_chk("TerrainParams.draw_marker 默认 false（素材自带地形）",
		tpsrc.contains("draw_marker: bool = false"))
	var view := FileAccess.get_file_as_string("scenes/ui/arena_view.gd")
	_chk("视图下发地形给格子（_apply_terrain_to_cells）", view.contains("_apply_terrain_to_cells"))
	_chk("视图持有 terrain_params 资源", view.contains("terrain_params"))
	_chk("默认地图 = 丰饶（无特殊地形格）", view.contains("maps/丰饶.tres"))
	# 参数资源可用
	var p = TerrainP.new()
	_chk("TerrainParams 可实例化", p != null)
	_chk("fill_color_from 控制透明度", p.fill_color_from(Color(1, 1, 1, 0.9)).a == p.fill_alpha)
	_chk("draw_marker 默认关闭", not p.draw_marker)


# ============ 提示文本已省略 ============
func _t_no_hud_msg() -> void:
	_section("橙色提示文本已省略（人要求）")
	var view := FileAccess.get_file_as_string("scenes/ui/arena_view.gd")
	_chk("未创建 OperationMsg 标签", not view.contains("OperationMsg"))
	_chk("未设橙色字色覆盖", not view.contains("0.82, 0.35"))
	_chk("反馈改走控制台输出", view.contains("print(\"[VIEW] \""))
	_chk("未新建 Label 作为提示", not view.contains("Label.new()"))


# ============ 工具 ============

func _engine():
	var e = Eng.new()
	e.start(ConfigLib.make(Pool.build("步3A"), Pool.build("步3B")))
	return e


func _mk(ud: UnitData, side: int, cell: Vector2i) -> UnitInstance:
	return UnitInstance.create(ud, side, cell)


func _put(st, card_name: String, side: int, cell: Vector2i) -> UnitInstance:
	var ud: UnitData = Pool.card(card_name) as UnitData
	var u := UnitInstance.create(ud, side, cell)
	u.instance_id = "t3_%s_%d_%d_%d" % [card_name, side, cell.x, cell.y]
	st.board.place(u)
	return u


func _section(t: String) -> void:
	print("\n--- %s ---" % t)


func _chk(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  [PASS] ", label)
	else:
		_fail += 1
		_failures.append(label)
		print("  [FAIL] ", label)


func _report() -> void:
	print("\n===== 迭代059 步3 结果 =====")
	print("  通过 %d / 失败 %d" % [_pass, _fail])
	for f in _failures:
		print("   X ", f)
	print("==========================")
