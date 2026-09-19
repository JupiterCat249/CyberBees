extends Node
## 【验证用 · 非生产】迭代059 补修：三个实测 bug 的回归自检
## 用法：project_run(mode="custom", scene="res://verification/iter059_bugfix_check.tscn")
##
## ① 手牌可出性高亮（可出 = 不压暗；不可出 = 压暗）
## ② 装甲：固定减 1 · **参与防御计算后消失** · 蜂王互攻能造成伤害
## ③ 卡内子节点鼠标透明（否则点击被立绘吃掉，指令卡/单位选择都失效）

const Eng := preload("res://scripts/battle/battle_engine.gd")
const ConfigLib := preload("res://scripts/battle/battle_config.gd")
const StateLib := preload("res://scripts/battle/battle_state.gd")
const Pool := preload("res://scripts/data/card_pool.gd")
const Combat := preload("res://scripts/battle/rules_combat.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _scene: Control = null


func _ready() -> void:
	print("\n===== 迭代059 补修：三个实测 bug 回归 =====")
	await _t_hand_highlight()
	_t_armor()
	await _t_card_clickthrough()
	_report()
	get_tree().quit(0 if _fail == 0 else 1)


# ============ ① 手牌高亮 ============
func _t_hand_highlight() -> void:
	_section("① 手牌可出性高亮")
	_scene = (load("res://scenes/ui/battle_scene.tscn") as PackedScene).instantiate() as Control
	add_child(_scene)
	for _i in 10:
		await get_tree().process_frame
	var eng = _scene.get("engine")
	var st = eng.state
	_chk("开局我方费用 = 4", st.cost(0) == 4)
	var hand: Array = st.hand(0)
	var hr := _scene.get_node("Battle/HandPanelRight/HandRight")
	var dimmed := 0
	var bright := 0
	for i in hand.size():
		var c: CardData = hand[i]
		var can: bool = eng.can_play_hand(0, i)
		var node: Control = hr.get_child(i) if i < hr.get_child_count() else null
		var m: float = node.modulate.r if node != null else -1.0
		print("    %-8s 费%-2d can_play=%-5s modulate.r=%.2f" % [c.display_name, c.cost, str(can), m])
		if can:
			bright += 1
			_chk("%s 可出 → **不压暗**（modulate.r=1.0）" % c.display_name, absf(m - 1.0) < 0.01)
		else:
			dimmed += 1
			_chk("%s 不可出 → 压暗（modulate.r<1）" % c.display_name, m < 0.99)
	_chk("存在可出的牌（否则断言无意义）", bright > 0)
	_chk("存在不可出的牌（否则断言无意义）", dimmed > 0)
	_scene.queue_free()


# ============ ② 装甲 ============
func _t_armor() -> void:
	_section("② 装甲：固定减 1 · 参与防御后消失 · 蜂王互攻能伤")
	var a := Pool.make_armor(2)
	_chk("装甲减伤 = 1（**不随层数放大**）", a.dmg_reduce == 1)
	var e = Eng.new()
	e.start(ConfigLib.make(Pool.build("甲A"), Pool.build("甲B")))
	var st = e.state
	var qa: UnitInstance = st.queen(0)
	var qe: UnitInstance = st.queen(1)
	_chk("蜂王自带装甲", _has(qa, "装甲"))
	# 摆相邻
	st.board.remove(qe)
	qe.cell = Vector2i(3, 1)
	st.board.place(qe)
	st.board.remove(qa)
	qa.cell = Vector2i(3, 2)
	st.board.place(qa)
	st.phase = StateLib.Phase.ACTION
	qa.reset_turn_flags()
	_chk("蜂王攻 2 − 装甲 1 = 原始伤害 1", Combat.raw_damage(qa, qe, st.board) == 1)
	var hp0: int = qe.current_hp
	var ok: bool = e.request_attack(0, qa, qe)
	_chk("蜂王互攻**能造成伤害**（%d → %d）" % [hp0, qe.current_hp], qe.current_hp == hp0 - 1)
	_chk("受击方装甲**参与防御后消失**", not _has(qe, "装甲"))
	_chk("攻击方装甲也被消耗（反击参与）", not _has(qa, "装甲"))
	# 第二击应打满 2（装甲已无）
	qa.reset_turn_flags()
	var hp1: int = qe.current_hp
	e.request_attack(0, qa, qe)
	_chk("装甲消失后第二击伤害 = 2（%d → %d）" % [hp1, qe.current_hp], qe.current_hp == hp1 - 2)


# ============ ③ 卡内子节点鼠标透明 ============
func _t_card_clickthrough() -> void:
	_section("③ 卡内子节点鼠标透明（点击不被立绘吃掉）")
	var s := (load("res://scenes/ui/battle_scene.tscn") as PackedScene).instantiate() as Control
	add_child(s)
	for _i in 10:
		await get_tree().process_frame
	var vp := get_viewport()
	var eng = s.get("engine")
	var q: UnitInstance = eng.state.queen(0)
	var mv := s.get_node("Battle/MapView") as Control
	var pt: Vector2 = mv.get_global_transform() \
		* Vector2(q.cell.y * 250.0 + 125.0, q.cell.x * 250.0 + 125.0)
	var mev := InputEventMouseMotion.new()
	mev.position = pt
	mev.global_position = pt
	Input.parse_input_event(mev)
	for _i in 3:
		await get_tree().process_frame
	var hover: Control = vp.gui_get_hovered_control()
	var path := str(hover.get_path()) if hover != null else "null"
	print("    命中节点 = %s" % path)
	_chk("点击命中**单位卡根节点**（非卡内立绘）", hover != null and String(hover.name).begins_with("Unit_"))
	# 手牌卡根节点也不被子节点遮蔽
	var hr := s.get_node("Battle/HandPanelRight/HandRight")
	print("    手牌容器 mouse_filter=%d 子节点数=%d" % [hr.mouse_filter, hr.get_child_count()])
	for ch in hr.get_children():
		if ch is Control:
			print("      子 %-12s mouse_filter=%d rect=%s" % [ch.name, ch.mouse_filter, str(ch.get_global_rect())])
	var card := hr.get_child(0) as Control
	print("    取第0张卡 = %s  mouse_filter=%d" % [card.name, card.mouse_filter])
	var cpt: Vector2 = card.get_global_rect().get_center()
	var mev2 := InputEventMouseMotion.new()
	mev2.position = cpt
	mev2.global_position = cpt
	Input.parse_input_event(mev2)
	for _i in 3:
		await get_tree().process_frame
	var hover2: Control = vp.gui_get_hovered_control()
	print("    手牌命中 = %s" % (str(hover2.get_path()) if hover2 != null else "null"))
	_chk("手牌点击命中**手牌卡根节点**", hover2 != null and hover2 == card)
	s.queue_free()


# ============ 工具 ============

func _has(u: UnitInstance, nm: String) -> bool:
	for e in u.effects:
		if e.data != null and e.data.display_name == nm:
			return true
	return false


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
	print("\n===== 补修回归结果 =====")
	print("  通过 %d / 失败 %d" % [_pass, _fail])
	for f in _failures:
		print("   X ", f)
	print("========================")
