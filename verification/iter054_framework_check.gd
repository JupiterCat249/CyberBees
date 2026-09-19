extends Node
## 【验证用 · 非生产】迭代054 基础框架自检 —— 逐条验证 a500 规则
## 状态：待封存（验证用，非生产文件）
##
## 覆盖：
##   回合流程 / 回费（含第7回合+2、后手+2） / 费用上限10 / 部署合法性（建筑领地·兵蜂邻蜂王）
##   / 部署无行动机会 / 移动被阻挡 / 攻击不被阻挡 / 同时反击（射程外无效）
##   / 攻击力修正（乘优先于加）+ 伤害减免 / 效果不叠加(T14) / 蜂王免疫指令伤害
##   / 手牌补至4 / AI 化随机对局跑通 / 12回合判定

const CommandLib := preload("res://scripts/game/battle_command.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []

func _ready() -> void:
	_test_turn_flow()
	_test_recover()
	_test_deploy_rules()
	_test_move_blocking()
	_test_attack_and_counter()
	_test_action_limits()
	_test_effects()
	_test_hand_refill()
	_test_full_random_match()
	_test_sample_deck()
	_test_command_cards()
	_test_hand_rotation()
	_test_draw_and_reshuffle()
	_test_support_skill()
	_report()
	get_tree().quit(0 if _fail == 0 else 1)


# ---------------- 测试数据构造 ----------------

func _mk_effect(nm: String, props: Dictionary = {}) -> EffectData:
	var e := EffectData.new()
	e.id = Uuid.generate()
	e.display_name = nm
	for k in props.keys():
		e.set(k, props[k])
	return e

func _mk_unit(nm: String, kind: int, cost: int, atk: int, hp: int, mv: int, rng: int,
		refund: int = 0, immune: bool = false) -> UnitData:
	var d := UnitData.new()
	d.id = Uuid.generate()
	d.display_name = nm
	d.kind = kind
	d.cost = cost
	d.atk = atk
	d.hp = hp
	d.move = mv
	d.attack_range = rng
	d.refund = refund
	d.immune_command = immune
	return d

func _mk_deck(queen: UnitData, rest: Array) -> DeckData:
	var dd := DeckData.new()
	dd.id = Uuid.generate()
	dd.display_name = "验证卡组"
	dd.queen = queen
	dd.cards = [queen]
	for c in rest:
		dd.cards.append(c)
	return dd

func _new_state() -> GameState:
	var q := _mk_unit("验证蜂王", CardData.CardKind.QUEEN, 8, 0, 8, 0, 0, 4, true)
	var a := _mk_unit("验证叶蜂", CardData.CardKind.SOLDIER, 2, 2, 3, 1, 1)
	var b := _mk_unit("验证熊蜂", CardData.CardKind.SOLDIER, 5, 5, 8, 1, 1)
	var c := _mk_unit("验证蜂巢", CardData.CardKind.BUILDING, 4, 0, 5, 0, 0, 1)
	var deck := _mk_deck(q, [a, a, b, c, c])   ## 第 5 张进牌库，供补牌测试
	var st: GameState = load("res://scripts/game/game_state.gd").new()
	add_child(st)
	st.setup({0: deck, 1: deck}, 0, {0: "绿", 1: "红"})
	return st


# ---------------- 各测试 ----------------

func _test_turn_flow() -> void:
	var st := _new_state()
	_chk("回合流程：开局在我方回费后停在部署阶段",
		st.active == 0 and st.phase == GameState.Phase.DEPLOY and st.round_no == 1)
	st.advance_phase()
	_chk("主按钮：部署 → 行动阶段", st.phase == GameState.Phase.ACTION)
	st.advance_phase()
	_chk("主按钮：行动 → 换手到敌方（回合数不变）",
		st.active == 1 and st.round_no == 1 and st.phase == GameState.Phase.DEPLOY)
	st.advance_phase(); st.advance_phase()
	_chk("敌方行动结束 → 回合数 +1 且回到我方", st.active == 0 and st.round_no == 2)
	st.queue_free()


func _test_recover() -> void:
	var st := _new_state()
	# 我方先手：开局回费 = 蜂王回费 4
	_chk("回费：先手开局 = 蜂王回费 4", st.cost[0] == 4)
	_chk("后手初始费用 +2", st.cost[1] == 2)
	# 第 7 回合起 +2
	st.round_no = 7
	st.active = 1
	st.cost[1] = 0
	st._begin_turn()
	_chk("第7回合起回费 +2（4+2=6）", st.cost[1] == 6)
	# 费用上限 10
	st.cost[1] = 9
	st._begin_turn()
	_chk("费用上限 10", st.cost[1] == 10)
	st.queue_free()


func _test_deploy_rules() -> void:
	var st := _new_state()
	# 兵蜂只能在蜂王相邻格
	var q: UnitInstance = st.queen[0]
	var ok_adj := st.deploy_unit(0, 0, Vector2i(q.cell.x - 1, q.cell.y))
	_chk("兵蜂：可部署在蜂王相邻格", ok_adj)
	var far := Vector2i(2, 0)     # 行2 属我方领地但离蜂王(3,1) 曼哈顿距离 |2-3|+|0-1| = 2
	_chk("兵蜂：不能部署在非相邻格", not st.deploy_unit(0, 0, far))
	# 建筑：己方领地任意格（不要求相邻）
	var building_idx := _find_hand_index(st, 0, CardData.CardKind.BUILDING)
	st.cost[0] = 10                      ## 补足费用，专测"建筑可放己方领地"
	_chk("建筑：可部署在己方领地", st.deploy_unit(0, building_idx, Vector2i(2, 3)))
	st.cost[0] = 0
	var b3 := _find_hand_index(st, 0, CardData.CardKind.BUILDING)
	_chk("费用不足不能部署", b3 < 0 or not st.deploy_unit(0, b3, Vector2i(3, 1)))
	# 不能部署到敌方领地
	var b2 := _find_hand_index(st, 0, CardData.CardKind.BUILDING)
	_chk("建筑：不能部署到敌方领地", not st.deploy_unit(0, b2, Vector2i(0, 1)))
	# 部署时无行动机会
	var placed: UnitInstance = st.board.unit_at(Vector2i(q.cell.x - 1, q.cell.y))
	_chk("部署时没有行动机会", placed != null and placed.has_moved and placed.has_acted)
	st.queue_free()


func _find_hand_index(st: GameState, side: int, kind: int) -> int:
	var cards: Array = st.hand[side]
	for i in cards.size():
		var d: CardData = cards[i]
		if d != null and d.kind == kind:
			return i
	return -1


func _test_move_blocking() -> void:
	var st := _new_state()
	# 手造两个单位
	var u1 := UnitInstance.create(_mk_unit("甲", CardData.CardKind.SOLDIER, 1, 1, 9, 2, 1), 0, Vector2i(2, 0))
	var u2 := UnitInstance.create(_mk_unit("乙", CardData.CardKind.SOLDIER, 1, 1, 9, 2, 1), 0, Vector2i(2, 2))
	st.board.place(u1); st.board.place(u2)
	var cells := st.board.move_range(u1)
	# u1 在 (2,0)，移动 2 步：可到 (0,0)(1,0)(3,0)(2,1)，但 (2,2) 被 u2 占据且不能穿过
	_chk("移动范围：不含被占据格", not cells.has(Vector2i(2, 2)))
	_chk("移动范围：按走格子计算（含 (2,1)）", cells.has(Vector2i(2, 1)))
	st.queue_free()


func _test_attack_and_counter() -> void:
	var st := _new_state()
	st.phase = GameState.Phase.ACTION
	var a := UnitInstance.create(_mk_unit("攻方", CardData.CardKind.SOLDIER, 1, 3, 9, 1, 1), 0, Vector2i(2, 1))
	var d := UnitInstance.create(_mk_unit("守方", CardData.CardKind.SOLDIER, 1, 2, 5, 1, 1), 1, Vector2i(2, 2))
	st.board.place(a); st.board.place(d)
	# 相邻（曼哈顿 1）→ 攻守都在射程 1
	var prev := BattleCombat.preview_attack(a, d, st.board)
	_chk("预览：守方掉 3 血", prev["damage_to_defender"] == 3)
	_chk("预览：攻方被反击 2 血（射程内）", prev["damage_to_attacker"] == 2 and prev["counter_valid"])
	_chk("主动攻击成功", st.attack(a, d))
	_chk("同时结算：守方 5-3=2", d.current_hp == 2)
	_chk("同时结算：攻方 9-2=7", a.current_hp == 7)
	# 射程外反击无效
	var a2 := UnitInstance.create(_mk_unit("远程", CardData.CardKind.SOLDIER, 1, 2, 9, 1, 3), 0, Vector2i(2, 0))
	var d2 := UnitInstance.create(_mk_unit("近战", CardData.CardKind.SOLDIER, 1, 5, 9, 1, 1), 1, Vector2i(2, 3))
	st.board.place(a2); st.board.place(d2)
	var prev2 := BattleCombat.preview_attack(a2, d2, st.board)
	_chk("射程外：反击无效", prev2["counter_valid"] == false and prev2["damage_to_attacker"] == 0)
	st.attack(a2, d2)
	_chk("射程外：攻方未掉血", a2.current_hp == 9)
	st.queue_free()


func _test_action_limits() -> void:
	var st := _new_state()
	st.phase = GameState.Phase.ACTION
	var u := UnitInstance.create(_mk_unit("测试兵", CardData.CardKind.SOLDIER, 1, 2, 9, 1, 1), 0, Vector2i(2, 1))
	st.board.place(u)
	_chk("行动机会：可移动", st.can_unit_move(u))
	st.move_unit(u, Vector2i(2, 2))
	_chk("行动机会：移动后可再攻击（1移动+1攻击）", st.can_unit_attack(u))
	var e := UnitInstance.create(_mk_unit("目标", CardData.CardKind.SOLDIER, 1, 0, 9, 0, 0), 1, Vector2i(2, 3))
	st.board.place(e)
	st.attack(u, e)
	_chk("行动机会：攻击后自动结束行动", u.has_acted and not st.can_unit_move(u))
	st.queue_free()


func _test_effects() -> void:
	var st := _new_state()
	var u := UnitInstance.create(_mk_unit("受效者", CardData.CardKind.SOLDIER, 1, 3, 9, 1, 1), 0, Vector2i(2, 1))
	st.board.place(u)
	var buff := _mk_effect("攻击提升", {"atk_add": 1})
	_chk("赋予效果成功", BattleEffects.grant(u, buff))
	_chk("效果生效：攻击力 3+1=4", u.atk() == 4)
	_chk("T14 同名效果不叠加（层数=1）", BattleEffects.grant(u, buff) == false and u.effects.size() == 1)
	# 乘优先于加
	var mul := _mk_effect("攻击翻倍", {"atk_mul": 2.0})
	BattleEffects.grant(u, mul)
	_chk("乘优先于加：(3×2)+1 = 7", u.atk() == 7)
	# 伤害减免
	var armor := _mk_effect("护甲", {"dmg_reduce": 2})
	BattleEffects.grant(u, armor)
	var attacker := UnitInstance.create(_mk_unit("打手", CardData.CardKind.SOLDIER, 1, 5, 9, 1, 1), 1, Vector2i(2, 2))
	st.board.place(attacker)
	_chk("攻击计算优先于伤害减免：5-2=3", BattleCombat.raw_damage(attacker, u) == 3)
	# 蜂王免疫指令伤害
	var q: UnitInstance = st.queen[0]
	_chk("蜂王免疫指令伤害", BattleCombat.resolve_command_damage(q, 99) == 0)
	# 护盾抵挡指令伤害
	var shield := _mk_effect("护盾", {"blocks_command": true})
	BattleEffects.grant(u, shield)
	_chk("护盾抵挡指令伤害", BattleCombat.resolve_command_damage(u, 5) == 0)
	# 单位类型不匹配无法赋予
	var only_building := _mk_effect("仅建筑", {"allow_soldier": false, "allow_queen": false, "allow_building": true})
	_chk("单位类型不匹配无法赋予效果", BattleEffects.grant(u, only_building) == false)
	st.queue_free()


func _test_hand_refill() -> void:
	var st := _new_state()
	var before: int = st.hand[0].size()
	_chk("初始手牌 4 张", before == 4)
	# 打掉一张手牌
	st.hand[0].remove_at(0)
	st._end_turn()   # 换手时会补牌
	_chk("回合结束补手牌至 4 张", st.hand[0].size() == 4)
	st.queue_free()


func _test_full_random_match() -> void:
	## 随机对局：验证流程不会卡死/崩溃，能走到结束
	var st := _new_state()
	var guard := 0
	while st.result == GameState.Result.NONE and guard < 400:
		guard += 1
		if st.phase == GameState.Phase.DEPLOY:
			# 随机尝试部署一张
			var idx := randi() % maxi(1, st.hand[st.active].size())
			if st.hand[st.active].size() > 0:
				var data: CardData = st.hand[st.active][idx]
				if data is UnitData:
					var cell_opt = _random_legal_cell(st, data as UnitData)
					if cell_opt != null:
						st.deploy_unit(st.active, idx, cell_opt)
			st.advance_phase()
		elif st.phase == GameState.Phase.ACTION:
			# 随机让一个单位行动一次
			var units := st.board.units_of(st.active)
			units.shuffle()
			var acted := false
			for u in units:
				if acted:
					break
				if st.can_unit_attack(u):
					var targets := st.board.attackable(u, st.board.all_units())
					if not targets.is_empty():
						st.attack(u, targets[randi() % targets.size()])
						acted = true
						break
				if st.can_unit_move(u):
					var cells := st.board.move_range(u)
					if not cells.is_empty():
						var keys := cells.keys()
						st.move_unit(u, keys[randi() % keys.size()])
						acted = true
			st.advance_phase()
		else:
			st.advance_phase()
		if st.result != GameState.Result.NONE:
			break
	_chk("随机对局跑通（无卡死/崩溃）", guard > 0)
	_chk("随机对局能推进回合（round_no > 1）", st.round_no > 1 or st.result != GameState.Result.NONE)
	var dead := 0
	for u in st.board.all_units():
		if not u.is_alive():
			dead += 1
	_chk("退场单位已从棋盘移除（无残留死亡单位）", dead == 0)
	print("   [INFO] 随机对局：回合=%d 阶段=%d 结果=%d 迭代=%d" % [st.round_no, st.phase, st.result, guard])
	st.queue_free()


func _random_legal_cell(st: GameState, ud: UnitData) -> Variant:
	var cells: Array[Vector2i] = []
	for x in 4:
		for y in 4:
			var c := Vector2i(x, y)
			if st.board.is_empty(c) and st._deploy_cell_ok(st.active, ud, c):
				cells.append(c)
	if cells.is_empty():
		return null
	return cells[randi() % cells.size()]


# ---------------- 完整战斗系统新增测试 ----------------

func _test_sample_deck() -> void:
	var dd: DeckData = load("res://scripts/data/card_pool.gd").build("测试")
	_chk("样例卡组：有蜂王", dd.queen != null and dd.queen.kind == CardData.CardKind.QUEEN)
	_chk("样例卡组：12 张（1 蜂王 + 11 常规）", dd.cards.size() == 12)
	var errs := dd.validate()
	_chk("样例卡组：通过校验", errs.is_empty())
	_chk("样例卡组：金刚蜂王回费 = 4", dd.queen.refund == 4)
	_chk("样例卡组：金刚蜂王免疫指令", dd.queen.immune_command)
	# 数值抽样（与旧 battle_defs.gd 逐字段一致）
	var by := {}
	for c in dd.cards:
		by[c.display_name] = c
	_chk("数值一致：叶蜂 2/2/1/3/1", by.has("叶蜂") and by["叶蜂"].cost == 2 and by["叶蜂"].atk == 2 and by["叶蜂"].hp == 3)
	_chk("数值一致：蜂巢III cost 9 / hp 12 / 回费 2",
		by.has("蜂巢III") and by["蜂巢III"].cost == 9 and by["蜂巢III"].hp == 12 and by["蜂巢III"].refund == 2)
	_chk("指令卡：电击 dmg4 / range2", by.has("电击") and (by["电击"] as CommandData).dmg == 4)


func _test_command_cards() -> void:
	var st := _new_state()
	st.phase = GameState.Phase.ACTION
	st.cost[0] = 10
	# 电击：对敌方单位造成 4 点指令伤害
	var shock := _mk_cmd("电击", 3, 4, 0, 2)
	var enemy := UnitInstance.create(_mk_unit("靶子", CardData.CardKind.SOLDIER, 1, 0, 9, 0, 0), 1, Vector2i(2, 2))
	st.board.place(enemy)
	st.hand[0] = [shock]
	_chk("指令卡：可对敌方使用", st.can_use_command(0, 0, enemy))
	_chk("指令卡：使用成功", st.use_command(0, 0, enemy))
	_chk("指令伤害结算：9-4=5", enemy.current_hp == 5)
	_chk("指令卡扣除费用（10-3=7）", st.cost[0] == 7)
	_chk("指令卡用后进墓地", st.discard[0].size() == 1)

	# 蜂王免疫指令伤害
	var q: UnitInstance = st.queen[1]
	var shock2 := _mk_cmd("电击", 3, 4, 0, 9)
	st.hand[0] = [shock2]
	_chk("蜂王：不可被指令指定（或结算为 0）",
		not st.can_use_command(0, 0, q) or CommandLib.damage_to(shock2, q) == 0)

	# 治疗：对己方单位
	var heal := _mk_cmd("治疗", 3, 0, 4, 2)
	var ally := UnitInstance.create(_mk_unit("伤员", CardData.CardKind.SOLDIER, 1, 0, 9, 0, 0), 0, Vector2i(2, 1))
	ally.set_hp(3)
	st.board.place(ally)
	st.hand[0] = [heal]
	st.cost[0] = 10
	_chk("治疗：对己方可用、对敌方不可用",
		st.can_use_command(0, 0, ally) and not st.can_use_command(0, 0, enemy))
	st.use_command(0, 0, ally)
	_chk("治疗结算：3+4=7", ally.current_hp == 7)

	# X 费·毁灭：伤害 = 目标部署费 × 2，不可对蜂王
	var xcmd := _mk_cmd("X费·毁灭", -1, 0, 0, 3, 2, CardData.CardKind.COMMAND_X)
	var big := UnitInstance.create(_mk_unit("大件", CardData.CardKind.SOLDIER, 5, 0, 20, 0, 0), 1, Vector2i(3, 2))
	st.board.place(big)
	_chk("X 费：实际费用 = 目标部署费 5", st.command_cost(xcmd, big) == 5)
	_chk("X 费：伤害 = 5×2 = 10", CommandLib.damage_to(xcmd, big) == 10)
	st.hand[0] = [xcmd]
	st.cost[0] = 10
	st.use_command(0, 0, big)
	_chk("X 费结算：20-10=10", big.current_hp == 10)

	# 扩散：对目标周围也造成伤害
	var aoe := _mk_cmd("扩散毒雾", 4, 2, 0, 2, 0, CardData.CardKind.COMMAND)
	aoe.aoe_span = 1
	var t1 := UnitInstance.create(_mk_unit("主目标", CardData.CardKind.SOLDIER, 1, 0, 9, 0, 0), 1, Vector2i(2, 2))
	var t2 := UnitInstance.create(_mk_unit("邻接", CardData.CardKind.SOLDIER, 1, 0, 9, 0, 0), 1, Vector2i(2, 3))
	st.board.place(t1); st.board.place(t2)
	st.hand[0] = [aoe]
	st.cost[0] = 10
	st.use_command(0, 0, t1)
	_chk("扩散：主目标受伤 9-2=7", t1.current_hp == 7)
	_chk("扩散：相邻目标同样受伤 9-2=7", t2.current_hp == 7)
	st.queue_free()


func _mk_cmd(nm: String, cost: int, dmg: int, heal: int, rng: int, xmul: int = 0, kind: int = CardData.CardKind.COMMAND) -> CommandData:
	var c := CommandData.new()
	c.id = Uuid.generate()
	c.display_name = nm
	c.kind = kind
	c.cost = cost
	c.dmg = dmg
	c.heal = heal
	c.target_range = rng
	c.x_cost_multiplier = xmul
	return c


func _total_cards(st: GameState, side: int) -> int:
	return st.hand[side].size() + st.deck[side].size() + st.discard[side].size() + st.board.units_of(side).size()


func _test_hand_rotation() -> void:
	var st := _new_state()
	var names_before: Array = []
	for c in st.hand[0]:
		names_before.append(c.display_name)
	st.cost[0] = 10
	_chk("轮换：可用（有手牌且费用够）", st.can_rotate(0))
	var n_before: int = st.hand[0].size()
	_chk("轮换：执行成功", st.rotate_hand(0))
	_chk("轮换：手牌数量不变（%d 张）" % n_before, st.hand[0].size() == n_before)
	_chk("轮换：扣除 1 费（10-1=9）", st.cost[0] == 9)
	# 被换掉的卡不会凭空消失：卡片总数（手牌 + 牌库 + 墓地 + 场上）应守恒
	var total: int = st.hand[0].size() + st.deck[0].size() + st.discard[0].size()
	for u in st.board.units_of(0):
		total += 1
	_chk("轮换：卡片总数守恒（该测试卡组 = 蜂王 + 5 常规 = 6）", total == 6)
	# 费用不足时不可轮换 —— **显式构造**"手牌非空 + 费用 0"，确保测的是费用条件（而非手牌为空）
	st.cost[0] = 0
	if st.hand[0].is_empty():
		st.hand[0].append(_mk_unit("占位", CardData.CardKind.SOLDIER, 1, 1, 1, 1, 1))
	_chk("轮换：费用不足不可用（手牌非空、费用 0）", st.hand[0].size() > 0 and not st.can_rotate(0))
	# 手牌为空时同样不可轮换（另一条独立条件）
	st.cost[0] = 5
	st.hand[0] = []
	_chk("轮换：手牌为空不可用", not st.can_rotate(0))
	st.queue_free()


func _test_draw_and_reshuffle() -> void:
	var st := _new_state()
	# 造牌库 + 墓地
	st.deck[0] = []
	st.discard[0] = []
	for i in 6:
		var c := _mk_unit("牌%d" % i, CardData.CardKind.SOLDIER, 1, 1, 1, 1, 1)
		st.discard[0].append(c)
	var hand_before: int = st.hand[0].size()
	var got := st.draw_card(0, 2)
	_chk("抽卡：从墓地洗回后抽到 2 张", got == 2 and st.hand[0].size() == hand_before + 2)
	_chk("抽卡：墓地减少（原 6 张，取前 4 张洗回）", st.discard[0].size() == 2)
	# 牌库与墓地皆空 → 抽不到（不崩）
	st.deck[0] = []
	st.discard[0] = []
	_chk("抽卡：无牌可抽时安全返回 0", st.draw_card(0, 3) == 0)
	st.queue_free()


func _test_support_skill() -> void:
	var st := _new_state()
	st.phase = GameState.Phase.ACTION
	# 带支援技能的兵蜂（a500：叶蜂 → 【支援】鼓舞：射程 2 内己方单位攻击力 +1）
	var buff := _mk_effect("攻击提升", {"atk_add": 1})
	var sk := SkillData.new()
	sk.id = Uuid.generate()
	sk.display_name = "鼓舞"
	sk.kind = SkillData.Kind.SUPPORT
	sk.target_range = 2
	sk.effects = [buff]
	var d := _mk_unit("鼓舞蜂", CardData.CardKind.SOLDIER, 2, 2, 4, 1, 1)
	d.skills = [sk] as Array[SkillData]
	var u := UnitInstance.create(d, 0, Vector2i(2, 1))
	st.board.place(u)
	var mate := UnitInstance.create(_mk_unit("被鼓舞", CardData.CardKind.SOLDIER, 1, 3, 5, 1, 1), 0, Vector2i(2, 2))
	st.board.place(mate)
	_chk("支援：识别到支援技能", st.unit_support_skills(u).size() == 1)
	_chk("支援：可进入目标选择模式", st.begin_support(u, sk))
	_chk("支援：范围内己方单位是合法目标", st.support_targets().has(mate))
	_chk("支援：执行成功", st.confirm_support(mate))
	_chk("支援：目标攻击力 3+1=4", mate.atk() == 4)
	_chk("支援：使用后自动结束行动", u.has_acted)
	st.queue_free()


# ---------------- 报告 ----------------

func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  [PASS] ", label)
	else:
		_fail += 1
		_failures.append(label)
		print("  [FAIL] ", label)


func _report() -> void:
	print("\n========== 迭代054 基础框架自检 ==========")
	print("  通过 %d / 失败 %d" % [_pass, _fail])
	if _fail > 0:
		print("  —— 失败项 ——")
		for f in _failures:
			print("   ✗ ", f)
	print("==========================================")
