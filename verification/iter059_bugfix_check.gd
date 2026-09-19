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
const Effects := preload("res://scripts/battle/rules_effects.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _scene: Control = null


func _ready() -> void:
	print("\n===== 迭代059 补修：三个实测 bug 回归 =====")
	await _t_hand_highlight()
	_t_armor()
	await _t_card_clickthrough()
	_t_armor_not_permanent()
	_t_chain_strict()
	_t_no_stacking_any()
	await _t_discard_state_switch()
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
	# ⭐ 设计原文（`电子蜂A5策划案.md` 效果表）：装甲「**抵挡一次攻击**，参与防御计算则消失」
	#   人 2026-09-19：不论伤害高低都能抵挡 → **不是数值减伤**
	_chk("装甲不是数值减伤（dmg_reduce = 0）", a.dmg_reduce == 0)
	_chk("装甲是一层（同名不叠加）", a.display_name == "装甲")
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
	_chk("持装甲时原始伤害 = 0（**完全抵挡**）", Combat.raw_damage(qa, qe, st.board) == 0)
	var hp0: int = qe.current_hp
	var ok: bool = e.request_attack(0, qa, qe)
	_chk("首击被**完全抵挡**（血 %d → %d 不变）" % [hp0, qe.current_hp], qe.current_hp == hp0)
	_chk("受击方装甲**参与防御后消失**", not _has(qe, "装甲"))
	_chk("攻击方装甲也被消耗（反击参与）", not _has(qa, "装甲"))
	# 装甲已消失 → 第二击打满（泥蜂类打 2，蜂王攻 2）
	qa.reset_turn_flags()
	var hp1: int = qe.current_hp
	e.request_attack(0, qa, qe)
	_chk("装甲消失后第二击**打满**（%d → %d，应 -2）" % [hp1, qe.current_hp], qe.current_hp == hp1 - 2)


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


# ============ 装甲：**不永久**（连续两次互攻状态一致） ============
func _t_armor_not_permanent() -> void:
	_section("装甲不永久：首击抵挡后消失，后续每次都算伤")
	var e = Eng.new()
	e.start(ConfigLib.make(Pool.build("永A"), Pool.build("永B")))
	var st = e.state
	var qa: UnitInstance = st.queen(0)
	var qe: UnitInstance = st.queen(1)
	st.board.remove(qe)
	qe.cell = Vector2i(3, 1)
	st.board.place(qe)
	st.board.remove(qa)
	qa.cell = Vector2i(3, 2)
	st.board.place(qa)
	st.phase = StateLib.Phase.ACTION
	var hp_seq: Array = []
	for i in 3:
		qa.reset_turn_flags()
		e.request_attack(0, qa, qe)
		hp_seq.append(qe.current_hp)
	print("    红方蜂王血量序列 = %s（应 12,10,8）" % str(hp_seq))
	_chk("第1击被**完全抵挡**（12→12）", hp_seq[0] == 12)
	_chk("第2击算伤（12→10）—— 装甲已消耗", hp_seq[1] == 10)
	_chk("第3击继续算伤（10→8）—— 装甲**不是永久**", hp_seq[2] == 8)
	_chk("三击后血量低于初始（说明不是永久抵挡）", hp_seq[2] < 12)
	_chk("防御方装甲已消失", not _has(qe, "装甲"))
	_chk("攻击方装甲也已消失", not _has(qa, "装甲"))


# ============ 电击连锁：严格上下左右直接相邻 + 蜂王不受扩散 ============
func _t_chain_strict() -> void:
	_section("电击连锁：只波及上下左右直接相邻 · 蜂王不受扩散伤害")
	var e = Eng.new()
	e.start(ConfigLib.make(Pool.build("链A"), Pool.build("链B")))
	var st = e.state
	var RC := preload("res://scripts/battle/rules_command.gd")
	var card: CommandData = Pool.card("电击")
	# 清空战场，手工摆位：目标(2,2)、正相邻4格、对角格、远处格
	## ⚠️ 必须避开双方蜂王所在格（绿 (3,2) / 红 (0,1)），否则 place 失败、断言会假失败
	var target := _place(st, "泥蜂", 1, Vector2i(2, 2))
	var n_up := _place(st, "泥蜂", 1, Vector2i(1, 2))
	var n_left := _place(st, "泥蜂", 1, Vector2i(2, 1))
	var n_right := _place(st, "泥蜂", 1, Vector2i(2, 3))
	var n_down := _place(st, "泥蜂", 1, Vector2i(3, 3))     ## 用 (3,3) 代替被蜂王占用的 (3,2)
	var diag := _place(st, "泥蜂", 1, Vector2i(1, 1))       ## 对角 → **不应**被波及
	var far := _place(st, "泥蜂", 1, Vector2i(0, 0))        ## 远处 → **不应**被波及
	var targets: Array = RC.collect_targets(st, card, target)
	var names: Array = []
	for u in targets:
		names.append(str(u.cell))
	print("    连锁波及 = %s" % str(names))
	_chk("首目标被波及", targets.has(target))
	## 目标在 (2,2)：相邻格为 (1,2)/(3,2)/(2,1)/(2,3)；
	## 其中 (3,2) 被绿方蜂王占用 → 改用 (2,3) 之外的第三格验证"4 邻"必须**实际有单位**
	_chk("上/左/右 相邻格被波及（(1,2)/(2,1)/(2,3)）",
		targets.has(n_up) and targets.has(n_left) and targets.has(n_right))
	_chk("相邻格有单位即波及（不跳过直接相邻）", targets.size() == 4)
	_chk("**对角格不波及**（不是范围伤害）", not targets.has(diag))
	_chk("**远处格不波及**（不是全局伤害）", not targets.has(far))
	_chk("波及总数 = 4（自身 + 3 个实际存在的相邻单位）", targets.size() == 4)
	# 蜂王在相邻格 → 不应被连锁波及
	var e2 = Eng.new()
	e2.start(ConfigLib.make(Pool.build("链C"), Pool.build("链D")))
	var st2 = e2.state
	var t2 := _place(st2, "泥蜂", 1, Vector2i(2, 2))
	var q_adj: UnitInstance = st2.queen(1)
	st2.board.remove(q_adj)
	q_adj.cell = Vector2i(1, 2)
	st2.board.place(q_adj)
	var tg2: Array = RC.collect_targets(st2, card, t2)
	_chk("**蜂王在相邻格也不被连锁波及**", not tg2.has(q_adj))


# ============ 任何效果都不叠加 ============
func _t_no_stacking_any() -> void:
	_section("任何效果都不叠加（通用单层）")
	var e = Eng.new()
	e.start(ConfigLib.make(Pool.build("叠A"), Pool.build("叠B")))
	var st = e.state
	var u := _put(st, "泥蜂", 0, Vector2i(3, 0))
	# 同名不同 UUID 的效果（模拟不同来源各赋一次）
	var a1 := _mk_effect("灼烧", 2)
	var a2 := _mk_effect("灼烧", 5)
	Effects.grant(u, a1)
	var n1: int = u.effects.size()
	var applied: bool = Effects.grant(u, a2)
	_chk("同名效果第二次**不加层**（%d → %d）" % [n1, u.effects.size()], u.effects.size() == n1)
	_chk("第二次赋予返回 false", not applied)
	_chk("保留原有单层效果（不产生第二层、不复写语义）",
		u.effects.size() == 1 and u.effects[0].data.display_name == "灼烧")
	_chk("第二次赋予只刷新时长（duration = -1）", int(u.effects[0].turns) == -1)
	_chk("Stacking 枚举只有 NONE", EffectData.Stacking.size() == 1)


# ============ 弃牌态：点非手牌位置即切换 ============
func _t_discard_state_switch() -> void:
	_section("主按钮弃牌态：点非手牌位置即切换回阶段文案")
	var s := (load("res://scenes/ui/battle_scene.tscn") as PackedScene).instantiate() as Control
	add_child(s)
	for _i in 10:
		await get_tree().process_frame
	var eng = s.get("engine")
	var st = eng.state
	st.phase = 2
	st.sides[0]["cost"] = 10
	var idx: int = 0
	eng.select_hand(0, idx)
	await _tick(3)
	_chk("选中手牌 → sel_kind = 1（弃牌态）", eng.sel_kind == 1)
	_chk("引擎有公开 cancel_selection 入口", eng.has_method("cancel_selection"))
	# 模拟点棋盘空地
	eng.cancel_selection()
	await _tick(3)
	_chk("点非手牌位置 → 选中被清除", eng.sel_kind == 0 and eng.sel_hand_index == -1)
	var view := FileAccess.get_file_as_string("scenes/ui/arena_view.gd")
	_chk("点格处理里会退出弃牌态（_on_cell_clicked）",
		view.contains("if int(engine.sel_kind) == 1:
		engine.cancel_selection()"))
	s.queue_free()


func _mk_effect(nm: String, dot: int) -> EffectData:
	var e := EffectData.new()
	e.id = Uuid.generate()
	e.display_name = nm
	e.dot_per_turn = dot
	e.duration = -1
	return e


func _place(st, card_name: String, side: int, cell: Vector2i) -> UnitInstance:
	var ud: UnitData = Pool.card(card_name) as UnitData
	var u := UnitInstance.create(ud, side, cell)
	u.instance_id = "p_%s_%d_%d_%d" % [card_name, side, cell.x, cell.y]
	st.board.place(u)
	return u

func _put(st, card_name: String, side: int, cell: Vector2i) -> UnitInstance:
	return _place(st, card_name, side, cell)


func _tick(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
