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
	_t_queen_global_design()
	_t_no_stacking_any()
	await _t_discard_state_switch()
	await _t_hand_state_machine()
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
	_section("电击连锁：**连通分量**（ABCDE 相连即全波及）· 空格/蜂王格中断")
	var RC := preload("res://scripts/battle/rules_command.gd")
	var card: CommandData = Pool.card("电击")

	# ── 链 1：一条直线 A(1,0)-B(1,1)-C(1,2)（上下左右相连）→ 首目标 A 应波及 B、C
	var e = Eng.new()
	e.start(ConfigLib.make(Pool.build("链A"), Pool.build("链B")))
	var st = e.state
	var A := _place(st, "泥蜂", 1, Vector2i(1, 0))
	var B := _place(st, "泥蜂", 1, Vector2i(1, 1))
	var C := _place(st, "泥蜂", 1, Vector2i(1, 2))
	var tg: Array = RC.collect_targets(st, card, A)
	print("    直线 A-B-C 波及 = %s" % str(_cells(tg)))
	_chk("首目标 A 入选", tg.has(A))
	_chk("相连的 B 入选", tg.has(B))
	_chk("**首目标不相邻但相连的 C 也入选**（连锁是连续的）", tg.has(C))

	# ── 链 2：ABCDE 例子 —— E 只连一个单位，但整链连在一起 → E 也被波及
	#    A(2,0) B(2,1) C(1,1) D(1,2) E(0,2)：E 只与 D 相连
	var e2 = Eng.new()
	e2.start(ConfigLib.make(Pool.build("链C"), Pool.build("链D")))
	var st2 = e2.state
	var uA := _place(st2, "泥蜂", 1, Vector2i(2, 0))
	var uB := _place(st2, "泥蜂", 1, Vector2i(2, 1))
	var uC := _place(st2, "泥蜂", 1, Vector2i(1, 1))
	var uD := _place(st2, "泥蜂", 1, Vector2i(1, 2))
	var uE := _place(st2, "泥蜂", 1, Vector2i(0, 2))     ## 仅与 D 相连
	var tg2: Array = RC.collect_targets(st2, card, uA)
	print("    ABCDE 波及 = %s" % str(_cells(tg2)))
	_chk("ABCDE **全部入选**（E 只与 D 相连也照样波及）",
		tg2.has(uA) and tg2.has(uB) and tg2.has(uC) and tg2.has(uD) and tg2.has(uE))

	# ── 链 3：空格中断（远处孤立单位不被波及）
	var e3 = Eng.new()
	e3.start(ConfigLib.make(Pool.build("链E"), Pool.build("链F")))
	var st3 = e3.state
	var p1 := _place(st3, "泥蜂", 1, Vector2i(1, 1))
	var far := _place(st3, "泥蜂", 1, Vector2i(0, 3))    ## 与 (1,1) 不相邻
	var tg3: Array = RC.collect_targets(st3, card, p1)
	print("    孤立场景波及 = %s（far@%s）" % [str(_cells(tg3)), str(far.cell)])
	_chk("**不相邻的孤立单位不波及**（不是全局伤害）", not tg3.has(far))
	_chk("波及总数 = 1（只有自身，无相连单位）", tg3.size() == 1)


func _cells(arr: Array) -> Array:
	var o: Array = []
	for u in arr:
		if u != null:
			o.append(str(u.cell))
	return o


# ============ 全局设计：蜂王对指令卡「不存在」 ============
func _t_queen_global_design() -> void:
	_section("全局设计：蜂王可作首选目标，但**永不纳入指令卡判定计算**（连锁在蜂王处中断）")
	var RC := preload("res://scripts/battle/rules_command.gd")
	var card: CommandData = Pool.card("电击")
	# 布局（列 0 . 1 . 2 . 3）：
	#   行 0：  (0,0)蜂巢   (0,1)红蜂王   (0,2)泥蜂_后   (0,3)空
	#   行 1：  (1,0)泥蜂_前（与红蜂王相邻，与泥蜂_后不相邻）
	var e = Eng.new()
	e.start(ConfigLib.make(Pool.build("通A"), Pool.build("通B")))
	var st = e.state
	var qe: UnitInstance = st.queen(1)
	st.board.remove(qe)
	qe.cell = Vector2i(0, 1)
	st.board.place(qe)
	var before := _place(st, "泥蜂", 1, Vector2i(1, 1))     ## 紧邻蜂王（下方）
	var behind := _place(st, "泥蜂", 1, Vector2i(0, 2))     ## 蜂王右侧（只能穿过蜂王到达）
	print("    布阵：红蜂王@%s · 泥蜂_前@%s · 泥蜂_后@%s" % [
		str(qe.cell), str(before.cell), str(behind.cell)])
	var tg: Array = RC.collect_targets(st, card, before)
	var cells: Array = []
	for u in tg:
		cells.append(str(u.cell))
	print("    从「泥蜂_前」起连锁波及 = %s" % str(cells))
	_chk("首选目标照常入选", tg.has(before))
	_chk("**蜂王不入选**（不作为扩散目标）", not tg.has(qe))
	_chk("**连锁在蜂王处中断** —— 蜂王另一侧的泥蜂_后**不入选**", not tg.has(behind))

	# 反向验证：以蜂王为**首选目标**时，蜂王自身照常受伤
	var e2 = Eng.new()
	e2.start(ConfigLib.make(Pool.build("通C"), Pool.build("通D")))
	var st2 = e2.state
	var q2: UnitInstance = st2.queen(1)
	var tg2: Array = RC.collect_targets(st2, card, q2)
	_chk("蜂王可作为**首选目标**（自身入选）", tg2.has(q2))
	# ⚠️ 伤害口径待裁决：代码里 `immune_command = (kind == QUEEN)` → 蜂王免疫指令伤害；
	#    而人明确「蜂王可作为首选目标」。两者需人确认（见记录 §十八）。
	#    本处只断言"可选作首选目标"这一项（不臆测伤害）。
	_chk("蜂王可被选为**首选目标**（target_legal 通过）",
		RC.target_legal(card, q2, 0))
	_chk("已知口径：蜂王 immune_command（免疫指令伤害）—— 待人与「可作首选目标」对齐",
		q2.data.immune_command)
	# 代码层面：只剩一个公开入口 is_queen（避免两处实现漂移）
	var src := FileAccess.get_file_as_string("scripts/battle/rules_command.gd")
	_chk("公开入口名统一为 is_queen（无旧 _is_queen 残留）",
		src.contains("static func is_queen(") and not src.contains("_is_queen("))
	_chk("源码写明「蜂王格视作空单位 → 该处中断」",
		src.contains("蜂王格视作空单位") and src.contains("该方向中断"))


# ============ 任何效果都不叠加 ============
func _t_no_stacking_any() -> void:
	_section("任何效果都不叠加（通用单层）")
	var e = Eng.new()
	e.start(ConfigLib.make(Pool.build("叠A"), Pool.build("叠B")))
	var st = e.state
	var u := _place(st, "泥蜂", 0, Vector2i(3, 0))
	var a1 := _mk_effect("灼烧", 2)
	var a2 := _mk_effect("灼烧", 5)
	Effects.grant(u, a1)
	var n1: int = u.effects.size()
	var applied: bool = Effects.grant(u, a2)
	_chk("同名效果第二次**不加层**（%d → %d）" % [n1, u.effects.size()], u.effects.size() == n1)
	_chk("第二次赋予返回 false", not applied)
	_chk("保留原有单层效果（不产生第二层、不复写语义）",
		u.effects.size() == 1 and u.effects[0].data.display_name == "灼烧")
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
	eng.select_hand(0, 0)
	await _tick(3)
	_chk("选中手牌 → sel_kind = 1（弃牌态）", eng.sel_kind == 1)
	_chk("引擎有公开 cancel_selection 入口", eng.has_method("cancel_selection"))
	eng.cancel_selection()
	await _tick(3)
	_chk("点非手牌位置 → 选中被清除", eng.sel_kind == 0 and eng.sel_hand_index == -1)
	s.queue_free()


# ============ ⭐ 手牌状态机（人 2026-09-19 要求） ============
func _t_hand_state_machine() -> void:
	_section("手牌状态机：按卡种进入不同交互模式 · 脱范围自动切换 · **选中后可部署**")
	var s := (load("res://scenes/ui/battle_scene.tscn") as PackedScene).instantiate() as Control
	add_child(s)
	for _i in 10:
		await get_tree().process_frame
	var eng = s.get("engine")
	var st = eng.state
	st.phase = 2
	st.sides[0]["cost"] = 10
	var HM := preload("res://scripts/battle/battle_engine.gd").HandMode
	_chk("引擎暴露 HandMode 状态机", HM.size() == 4)

	# ① 选单位卡 → DEPLOY 模式；交互范围 = 合法部署格
	var i_leaf: int = _find_card(st, 0, "叶蜂")
	eng.select_hand(0, i_leaf)
	_chk("选单位卡 → hand_mode = DEPLOY", int(eng.hand_mode) == int(HM.DEPLOY))
	var cells: Array = preload("res://scripts/battle/rules_preview.gd") 		.deploy_cells(st, 0, st.hand(0)[i_leaf])
	_chk("该卡有合法部署格（否则断言无意义）", cells.size() > 0)
	var ok_cell: Vector2i = cells[0]
	_chk("**合法部署格在交互范围内**（→ 可部署）", eng.hand_range_has_cell(ok_cell))
	_chk("**棋盘无关格不在交互范围内**（→ 自动切换）", not eng.hand_range_has_cell(Vector2i(0, 0)))
	# 关键回归：在范围内点击应**真正部署**（曾因无条件取消选中而失败）
	var n0: int = st.units(0).size()
	var deployed: bool = eng.request_deploy(0, i_leaf, ok_cell)
	_chk("**手牌选中后可部署**（单位数 %d → %d）" % [n0, st.units(0).size()],
		deployed and st.units(0).size() == n0 + 1)

	# ② 选指令卡 → TARGET 模式；交互范围 = 合法目标所在格
	var i_shock: int = _find_card(st, 0, "电击")
	eng.select_hand(0, i_shock)
	_chk("选指令卡 → hand_mode = TARGET", int(eng.hand_mode) == int(HM.TARGET))
	var foe: UnitInstance = st.queen(1)
	_chk("敌方蜂王所在格在交互范围内（可作首选目标）", eng.hand_range_has_cell(foe.cell))
	_chk("己方蜂王所在格**不在**伤害类指令范围内",
		not eng.hand_range_has_cell(st.queen(0).cell))

	# ③ 脱范围 → 自动切换（退出选中）
	eng.hand_range_leave()
	_chk("脱范围 → 选中态清空", eng.sel_kind == 0)
	_chk("脱范围 → hand_mode 回到 IDLE", int(eng.hand_mode) == int(HM.IDLE))
	_chk("脱范围 → sel_hand_card 清空", eng.sel_hand_card == null)
	s.queue_free()


# ============ 工具 ============

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


func _find_card(st, side: int, nm: String) -> int:
	var hand: Array = st.sides[side]["hand"]
	for i in hand.size():
		if hand[i] != null and hand[i].display_name == nm:
			return i
	return 0


func _tick(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
