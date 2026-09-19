extends Node
## 【验证用 · 非生产】迭代059 步2：弃牌机制（G-6）+ 主按钮弃牌态（人裁决 Q-3）
## 用法：project_run(mode="custom", scene="res://verification/iter059_discard_check.tscn")

const Eng := preload("res://scripts/battle/battle_engine.gd")
const ConfigLib := preload("res://scripts/battle/battle_config.gd")
const StateLib := preload("res://scripts/battle/battle_state.gd")
const Pool := preload("res://scripts/data/card_pool.gd")
const Bus := preload("res://scripts/battle/battle_signal_bus.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _last_btn_text := ""
var _last_btn_enabled := true


func _ready() -> void:
	Bus.shared().connect(Bus.SIG_MAIN_BUTTON,
		func(t: String, e: bool, _h: String) -> void:
			_last_btn_text = t
			_last_btn_enabled = e)
	print("\n===== 迭代059 步2：弃牌机制验收 =====")
	_t_cost()
	_t_discard_basic()
	_t_insufficient()
	_t_x_cost_discard()
	_t_button_toggle()
	_t_regression()
	_report()
	get_tree().quit(0 if _fail == 0 else 1)


# ============ 弃牌消耗 ============
func _t_cost() -> void:
	_section("弃牌消耗（a500 抽卡 6）")
	var eng = _engine()
	var leaf: CardData = Pool.card("叶蜂")          ## 费 2
	var hive: CardData = Pool.card("蜂巢")          ## 费 3
	_chk("叶蜂（费2）弃牌消耗 = 2", eng.discard_cost_of(leaf) == 2)
	_chk("蜂巢（费3）弃牌消耗 = 3", eng.discard_cost_of(hive) == 3)
	_chk("null 卡返回 0", eng.discard_cost_of(null) == 0)


# ============ 基本弃牌 ============
func _t_discard_basic() -> void:
	_section("弃牌基本行为")
	var eng = _engine()
	var st = eng.state
	st.phase = StateLib.Phase.DEPLOY
	st.sides[0]["cost"] = 10
	var hand0: int = st.hand(0).size()
	var disc0: int = st.discard(0).size()
	var idx: int = _find_card(st, 0, "叶蜂")          ## 费 2
	_chk("手牌里找到叶蜂", idx >= 0)
	var before_card: CardData = st.hand(0)[idx]
	var ok: bool = eng.request_discard(0, idx)
	_chk("弃牌请求成功", ok)
	_chk("手牌 -1（%d → %d）" % [hand0, st.hand(0).size()], st.hand(0).size() == hand0 - 1)
	_chk("墓地 +1（%d → %d）" % [disc0, st.discard(0).size()], st.discard(0).size() == disc0 + 1)
	_chk("墓地里有那张牌", st.discard(0).has(before_card))
	_chk("费用扣 2（10 → %d）" % st.cost(0), st.cost(0) == 8)
	_chk("弃牌后选中被取消", eng.sel_kind == 0 and eng.sel_hand_index == -1)


# ============ 费用不足 ============
func _t_insufficient() -> void:
	_section("费用不足应被拒")
	var eng = _engine()
	var st = eng.state
	st.phase = StateLib.Phase.DEPLOY
	st.sides[0]["cost"] = 1                    ## 不够弃一张费 2 的牌
	var idx: int = _find_card(st, 0, "叶蜂")
	var hand0: int = st.hand(0).size()
	var ok: bool = eng.request_discard(0, idx)
	_chk("费用不足 → 拒绝", not ok)
	_chk("手牌不变", st.hand(0).size() == hand0)
	_chk("费用不变", st.cost(0) == 1)


# ============ X 费卡弃牌 = 10 ============
func _t_x_cost_discard() -> void:
	_section("X 费卡弃牌消耗 = 10（a500 明确）")
	var eng = _engine()
	var st = eng.state
	var xc := CommandData.new()
	xc.id = Uuid.generate()
	xc.display_name = "测试·X费"
	xc.cost = -1
	xc.dmg = 1
	_chk("X 费卡弃牌消耗 = 10", eng.discard_cost_of(xc) == 10)
	st.phase = StateLib.Phase.DEPLOY
	st.sides[0]["cost"] = 9
	st.hand(0).append(xc)
	var idx: int = st.hand(0).size() - 1
	_chk("9 费时弃 X 费卡 → 拒绝", not eng.request_discard(0, idx))
	st.sides[0]["cost"] = 10
	_chk("10 费时弃 X 费卡 → 成功", eng.request_discard(0, idx))
	_chk("费用清空为 0", st.cost(0) == 0)


# ============ 主按钮弃牌态（Q-3） ============
func _t_button_toggle() -> void:
	_section("主按钮：选中手牌 → 弃牌（文案同步改变）；取消 → 恢复")
	var eng = _engine()
	var st = eng.state
	st.phase = StateLib.Phase.DEPLOY
	st.sides[0]["cost"] = 10
	# 未选中时 = 原设计
	_last_btn_text = ""
	eng.select_hand(-1, -1) if false else null
	_last_btn_text = ""
	eng._emit_button()
	_chk("未选中 → 按钮为「完成部署」（原设计）", _last_btn_text == "完成部署")
	# 选中手牌 → 弃牌
	_last_btn_text = ""
	var idx: int = _find_card(st, 0, "叶蜂")     ## 费 2
	eng.select_hand(0, idx)
	_chk("选中费2 手牌 → 按钮含「弃牌」与消耗 2（实际「%s」）" % _last_btn_text,
		_last_btn_text.contains("弃牌") and _last_btn_text.contains("2"))
	_chk("按钮可用（费用足够）", _last_btn_enabled)
	# 费用不足时按钮变灰
	st.sides[0]["cost"] = 0
	eng._emit_button()
	_chk("费用不足 → 弃牌按钮置灰", not _last_btn_enabled)
	# 取消选中 → 恢复原文案
	st.sides[0]["cost"] = 10
	eng.select_unit(0, st.queen(0))
	_chk("选中单位（非手牌）→ 按钮恢复「完成部署」", _last_btn_text == "完成部署")


# ============ 回归：使用卡仍正常 ============
func _t_regression() -> void:
	_section("回归：弃牌不影响正常出牌")
	var eng = _engine()
	var st = eng.state
	st.phase = StateLib.Phase.DEPLOY
	st.sides[0]["cost"] = 10
	var Preview := preload("res://scripts/battle/rules_preview.gd")
	var leaf: UnitData = Pool.card("叶蜂") as UnitData
	var cells: Array = Preview.deploy_cells(st, 0, leaf)
	var ok: bool = eng.request_deploy(0, _find_card(st, 0, "叶蜂"), cells[0])
	_chk("部署仍成功", ok)
	_chk("部署扣费 = 卡费 2（10 → %d）" % st.cost(0), st.cost(0) == 8)


# ============ 工具 ============

func _engine():
	var e = Eng.new()
	e.start(ConfigLib.make(Pool.build("弃A"), Pool.build("弃B")))
	return e


func _find_card(st, side: int, nm: String) -> int:
	var hand: Array = st.sides[side]["hand"]
	for i in hand.size():
		if hand[i] != null and hand[i].display_name == nm:
			return i
	return -1


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
	print("\n===== 迭代059 步2 结果 =====")
	print("  通过 %d / 失败 %d" % [_pass, _fail])
	for f in _failures:
		print("   X ", f)
	print("==========================")
