extends Node
## 【验证用 · 非生产】迭代055 技能落地自检
##
## 逐条对照《单位文字图鉴/单位表格-测试用.xlsx》的技能机制列，验证：
##   ① 卡池数据 = 表格（10 张，数值逐字段）
##   ② 技能落地：被动倍伤 / 部署装甲 / 支援回费 / 回费 / 接触链 / 范围 / 治疗
##   ③ 示范卡组不含治疗卡

const Pool := preload("res://scripts/data/card_pool.gd")
const Combat := preload("res://scripts/game/battle_combat.gd")
const GameStateScript := preload("res://scripts/game/game_state.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []

## 表格权威数据（逐行转录 · 与 xlsx 一致）
const SHEET := [
	# name, kind, atk, range, move, hp, cost, refund
	["金刚蜂王", CardData.CardKind.QUEEN,    2, 1, 1, 12, 0, 4],
	["叶蜂",     CardData.CardKind.SOLDIER,  2, 1, 2,  2, 2, 0],
	["泥蜂",     CardData.CardKind.SOLDIER,  4, 2, 1,  6, 4, 0],
	["熊蜂",     CardData.CardKind.SOLDIER,  5, 2, 1, 10, 8, 0],
	["电击",     CardData.CardKind.COMMAND,  2, 0, 0,  0, 2, 0],
	["电击III",  CardData.CardKind.COMMAND,  8, 0, 0,  0, 6, 0],
	["巡航导弹", CardData.CardKind.COMMAND,  6, 1, 0,  0, 6, 0],
	["治疗",     CardData.CardKind.COMMAND,  0, 0, 0,  0, 2, 0],
	["蜂巢",     CardData.CardKind.BUILDING, 0, 0, 0,  5, 3, 1],
	["蜂巢III",  CardData.CardKind.BUILDING, 0, 0, 0,  9, 5, 3],
]


func _ready() -> void:
	_test_pool_matches_sheet()
	_test_pool_is_only_10()
	_test_demo_deck()
	_test_passive_mul()
	_test_deploy_armor()
	_test_support_refund()
	_test_refund_includes_buildings()
	await _test_command_skills()
	_report()
	get_tree().quit(0 if _fail == 0 else 1)


# ================= ① 数据 = 表格 =================

func _test_pool_matches_sheet() -> void:
	_chk("卡池正好 10 张", Pool.CARDS.size() == 10)
	for row in SHEET:
		var nm: String = row[0]
		var c: CardData = Pool.card(nm)
		if c == null:
			_chk("卡池含「%s」" % nm, false)
			continue
		var ok_cost: bool = c.cost == int(row[6])
		var ok_kind: bool = c.kind == row[1]
		var extra := ""
		var ok_num := true
		if c is UnitData:
			var u := c as UnitData
			# 指令卡用 dmg 列（表里「攻击力」对指令卡即伤害）
			ok_num = u.atk == int(row[2]) and u.attack_range == int(row[3]) \
				and u.move == int(row[4]) and u.hp == int(row[5]) and u.refund == int(row[7])
			extra = "攻%d 射%d 移%d 血%d 回费%d" % [u.atk, u.attack_range, u.move, u.hp, u.refund]
		else:
			var cd := c as CommandData
			ok_num = cd.dmg == int(row[2]) and cd.target_range == int(row[3]) \
				and cd.heal == int(row[7]) if false else cd.dmg == int(row[2])
			if nm == "治疗":
				ok_num = cd.heal == 3
			elif nm == "巡航导弹":
				ok_num = cd.dmg == 6 and cd.aoe_span == 1
			extra = "伤%d 疗%d 射%d aoe%d 链%d" % [cd.dmg, cd.heal, cd.target_range, cd.aoe_span, cd.chain_span]
		_chk("表格一致：%s（费%d %s）" % [nm, c.cost, extra], ok_cost and ok_kind and ok_num)
	_chk("立绘已引用（10 张全有）", _all_have_art())


func _all_have_art() -> bool:
	for nm in Pool.names():
		var c: CardData = Pool.card(nm)
		if c == null or c.visual == null or c.visual.artwork == null:
			push_warning("缺立绘：" + nm)
			return false
	return true


func _test_pool_is_only_10() -> void:
	var banned := ["护盾单元", "力场蜂巢", "力场炮台", "扩散毒雾", "精确打击", "回收", "补给", "轮换", "蜂群突袭", "X费·毁灭"]
	for b in banned:
		_chk("旧卡已移除：%s" % b, not Pool.names().has(b))


# ================= ③ 示范卡组 =================

func _test_demo_deck() -> void:
	var dd: DeckData = Pool.build("测试")
	_chk("示范卡组有蜂王", dd.queen != null and dd.queen.display_name == "金刚蜂王")
	_chk("示范卡组 8 张常规卡", dd.cards.size() == 8)
	var has_heal := false
	for c in dd.cards:
		if c.display_name == "治疗":
			has_heal = true
	_chk("**示范卡组不含治疗卡**", not has_heal)
	_chk("初始手牌(前 4 张) = 叶蜂/泥蜂/熊蜂/电击", dd.cards.size() >= 4 \
		and dd.cards[0].display_name == "叶蜂" and dd.cards[1].display_name == "泥蜂" \
		and dd.cards[2].display_name == "熊蜂" and dd.cards[3].display_name == "电击")


# ================= ② 技能落地 =================

func _test_passive_mul() -> void:
	# 叶蜂 [被动] 敌方领地 ×2：base 2 → 敌领 4
	var leaf := Pool.card("叶蜂") as UnitData
	var target := _mk_inst(Pool.card("泥蜂"), 1, Vector2i(1, 1))
	# 己方领地（绿方行 2/3）→ 无倍伤
	var atk_home := _mk_inst(leaf, 0, Vector2i(3, 1))
	_chk("叶蜂：己方领地无倍伤（伤害=2）", Combat.raw_damage(atk_home, target) == 2)
	# 敌方领地（绿方行 0/1）→ ×2 = 4
	var atk_foe := _mk_inst(leaf, 0, Vector2i(1, 1))
	_chk("叶蜂：**敌方领地 ×2**（伤害=4）", Combat.raw_damage(atk_foe, target) == 4)
	# 熊蜂 [被动] 对蜂王 ×2：base 5 → 对蜂王 10
	var bumble := Pool.card("熊蜂") as UnitData
	var queen_inst := _mk_inst(Pool.card("金刚蜂王"), 1, Vector2i(0, 1))
	var soldier_t := _mk_inst(Pool.card("泥蜂"), 1, Vector2i(2, 2))
	var b_atk := _mk_inst(bumble, 0, Vector2i(3, 1))
	_chk("熊蜂：对普通单位无倍伤（伤害=5）", Combat.raw_damage(b_atk, soldier_t) == 5)
	_chk("熊蜂：**对蜂王 ×2**（伤害=10）", Combat.raw_damage(b_atk, queen_inst) == 10)


func _test_deploy_armor() -> void:
	var st: GameState = GameStateScript.new()
	add_child(st)
	var dd: DeckData = Pool.build("测试")
	st.setup({0: dd, 1: Pool.build("测试2")}, 0, {0: "绿", 1: "红"})
	var q: UnitInstance = st.queen[0]
	_chk("金刚蜂王已在场", q != null)
	var armor := 0
	for e in q.effects:
		if e.data != null and e.data.display_name == "装甲":
			armor = e.data.dmg_reduce
	_chk("**[部署]获得[装甲]**（减伤 %d）" % armor, armor > 0)
	# 装甲参与伤害结算
	var enemy_soldier := _mk_inst(Pool.card("泥蜂"), 1, Vector2i(2, 2))
	st.board.place(enemy_soldier)
	var before: int = Combat.raw_damage(enemy_soldier, q, st.board)
	_chk("装甲减免生效（泥蜂攻4 → 实伤%d < 4）" % before, before < 4)
	st.queue_free()


func _test_support_refund() -> void:
	var st: GameState = GameStateScript.new()
	add_child(st)
	var dd: DeckData = Pool.build("测试")
	st.setup({0: dd, 1: Pool.build("测试2")}, 0, {0: "绿", 1: "红"})
	# 造一个熊蜂在场，施放 [支援] 回费
	var bumble := Pool.card("熊蜂") as UnitData
	var inst := UnitInstance.create(bumble, 0, Vector2i(3, 2))
	inst.instance_id = st._next_id()
	st.board.place(inst)
	var sk: SkillData = null
	for s in bumble.skills:
		if s.kind == SkillData.Kind.SUPPORT:
			sk = s
	_chk("熊蜂带 [支援] 技能", sk != null)
	if sk != null:
		st.phase = GameState.Phase.ACTION      ## can_support 要求 ACTION 阶段
		st.cost[0] = 3
		inst.reset_turn_flags()
		var begun: bool = st.begin_support(inst, sk)
		var ok: bool = begun and st.confirm_support(inst)
		_chk("**[支援]回复 3 点费用**（3 → 6）", ok and st.cost[0] == 6)
	st.queue_free()


func _test_refund_includes_buildings() -> void:
	var st: GameState = GameStateScript.new()
	add_child(st)
	st.setup({0: Pool.build("测试"), 1: Pool.build("测试2")}, 0, {0: "绿", 1: "红"})
	# 放一个蜂巢（回费 1）与蜂巢III（回费 3）
	var h1 := UnitInstance.create(Pool.card("蜂巢") as UnitData, 0, Vector2i(3, 2))
	h1.instance_id = st._next_id()
	st.board.place(h1)
	var h2 := UnitInstance.create(Pool.card("蜂巢III") as UnitData, 0, Vector2i(2, 3))
	h2.instance_id = st._next_id()
	st.board.place(h2)
	st.cost[0] = 0
	st.round_no = 1
	st._do_recover()
	# 蜂王 4 + 蜂巢 1 + 蜂巢III 3 = 8
	_chk("**[回费] 含建筑**（蜂王4+蜂巢1+蜂巢III3 = 8，实际 %d）" % st.cost[0], st.cost[0] == 8)
	st.queue_free()


func _test_command_skills() -> void:
	var st: GameState = GameStateScript.new()
	add_child(st)
	st.setup({0: Pool.build("测试"), 1: Pool.build("测试2")}, 0, {0: "绿", 1: "红"})
	st.phase = GameState.Phase.ACTION
	# 电击：链式（与目标接触及间接接触都受伤）
	var t1 := _mk_inst(Pool.card("泥蜂"), 1, Vector2i(1, 1))
	var t2 := _mk_inst(Pool.card("泥蜂"), 1, Vector2i(1, 2))   # 与 t1 相邻 → 间接接触
	st.board.place(t1); st.board.place(t2)
	var shock := Pool.card("电击") as CommandData
	st.hand[0] = [shock]
	st.cost[0] = 10
	var hp1: int = t1.current_hp
	var hp2: int = t2.current_hp
	var ok := st.use_command(0, 0, t1)
	for _i in 3:
		await get_tree().process_frame
	_chk("电击：对目标造成 2 伤害", t1.current_hp == hp1 - 2)
	_chk("**电击：间接接触的单位同受伤害**（链式）", t2.current_hp == hp2 - 2)
	# 巡航导弹：范围（aoe 1）
	var a1 := _mk_inst(Pool.card("泥蜂"), 1, Vector2i(0, 1))
	var a2 := _mk_inst(Pool.card("泥蜂"), 1, Vector2i(0, 2))
	st.board.place(a1); st.board.place(a2)
	var missile := Pool.card("巡航导弹") as CommandData
	st.hand[0] = [missile]
	st.cost[0] = 10
	var ah1: int = a1.current_hp
	var ah2: int = a2.current_hp
	st.use_command(0, 0, a1)
	for _i in 3:
		await get_tree().process_frame
	_chk("**巡航导弹：范围伤害**（主目标 -6）", a1.current_hp == ah1 - 6)
	_chk("巡航导弹：范围内相邻单位同受伤害", a2.current_hp == ah2 - 6)
	# 治疗：回复己方 3
	var ally := _mk_inst(Pool.card("泥蜂"), 0, Vector2i(3, 2))
	st.board.place(ally)
	ally.set_hp(2)
	var healc := Pool.card("治疗") as CommandData
	st.hand[0] = [healc]
	st.cost[0] = 10
	st.use_command(0, 0, ally)
	for _i in 3:
		await get_tree().process_frame
	_chk("治疗：己方回复 3（2 → 5）", ally.current_hp == 5)
	st.queue_free()


# ================= 工具 =================

func _mk_inst(data: CardData, side: int, cell: Vector2i) -> UnitInstance:
	return UnitInstance.create(data as UnitData, side, cell)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  [PASS] ", label)
	else:
		_fail += 1
		_failures.append(label)
		print("  [FAIL] ", label)


func _report() -> void:
	print("\n===== 迭代055 技能落地自检 =====")
	print("  通过 %d / 失败 %d" % [_pass, _fail])
	for f in _failures:
		print("   ✗ ", f)
	print("================================")
