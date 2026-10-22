extends GutTest
## 规则层回归 —— 指令卡三条路径（链式 / 范围 / 治疗）与双步确认
##
## 依据 a500：指令卡在「部署与行动阶段均可使用」；
## 迭代064 人裁定：**全部指令卡走「阶段1 挂待确认 / 阶段2 确认执行」双步**。
##
## ⚠️ 血量口径：set_hp() 会 clamp 到 max_hp —— 断言一律相对 max_hp() 表达，
##    不要写「先设 20 血再扣」（首版这样写，全部误判）。

const Fixture := preload("res://tests/support/battle_fixture.gd")

var e: BattleEngine = null


func before_each() -> void:
	e = Fixture.new_engine()


func _enemy(cell: Vector2i, card: String = "泥蜂") -> UnitInstance:
	return Fixture.place_unit(e, 1, card, cell)


func _cast(idx: int, cell: Vector2i) -> Array:
	var first: bool = e.request_use_command_at(0, idx, cell)
	var second: bool = e.request_use_command_at(0, idx, cell)
	return [first, second]


# ---------------------------------------------------------------- 双步确认

func test_command_needs_two_steps() -> void:
	assert_eq(Fixture.push_card(e, 0, "电击"), 0, "前置：应能取到电击卡")
	_enemy(Vector2i(1, 0))
	var before_cost: int = e.state.cost(0)
	var hand_before: int = e.state.sides[0].hand.size()

	assert_false(e.request_use_command_at(0, 0, Vector2i(1, 0)), "阶段 1 应返回 false")
	assert_eq(e.state.cost(0), before_cost, "阶段 1 不得扣费")
	assert_eq(e.state.sides[0].hand.size(), hand_before, "阶段 1 不得消耗手牌")

	assert_true(e.request_use_command_at(0, 0, Vector2i(1, 0)), "阶段 2 应执行")
	assert_eq(e.state.cost(0), before_cost - 2, "电击费用 2 应被扣除")


func test_changing_pending_cell_restarts_stage_one() -> void:
	assert_eq(Fixture.push_card(e, 0, "电击"), 0, "前置：取电击")
	var a := _enemy(Vector2i(1, 0))
	var b := _enemy(Vector2i(1, 1))

	assert_false(e.request_use_command_at(0, 0, a.cell), "先挂 a 为待确认")
	assert_false(e.request_use_command_at(0, 0, b.cell), "换目标格应重新进入阶段 1（返回 false）")
	assert_eq(a.current_hp, a.max_hp(), "换目标不应结算 a")
	assert_eq(b.current_hp, b.max_hp(), "换目标也不应结算 b")


# ---------------------------------------------------------------- 链式

func test_chain_hits_adjacent_and_indirect() -> void:
	assert_eq(Fixture.push_card(e, 0, "电击"), 0, "前置：取电击")
	var a := _enemy(Vector2i(1, 0))
	var b := _enemy(Vector2i(1, 1))            # 与 a 相邻（接触）
	var far := _enemy(Vector2i(0, 3))          # 远离（曼哈顿 4）
	var far_hp: int = far.current_hp

	assert_true(_cast(0, Vector2i(1, 0))[1], "电击应成功施放")
	assert_eq(a.current_hp, a.max_hp() - 2, "主目标应受 2 点伤害")
	assert_eq(b.current_hp, b.max_hp() - 2, "接触单位应同受 2 点伤害（链式）")
	assert_eq(far.current_hp, far_hp, "不接触的单位不应受伤")


func test_chain_hits_all_units_including_own_side() -> void:
	## a500 原文：「与目标**接触及间接接触的所有单位**都会受到相同伤害」
	##   → 次级目标**不区分阵营**（这是文档口径，不是缺陷）；主目标才受"伤害类作用于敌方"约束
	assert_eq(Fixture.push_card(e, 0, "电击"), 0, "前置：取电击")
	_enemy(Vector2i(1, 0))
	var own := Fixture.place_unit(e, 0, "泥蜂", Vector2i(1, 1))
	var own_hp: int = own.current_hp

	_cast(0, Vector2i(1, 0))

	assert_eq(own.current_hp, own_hp - 2, "链式次级目标含己方单位（a500：所有单位）")


# ---------------------------------------------------------------- 范围（AOE）

func test_aoe_hits_every_unit_in_span() -> void:
	assert_eq(Fixture.push_card(e, 0, "巡航导弹"), 0, "前置：取巡航导弹")
	e.state.sides[0]["cost"] = 10
	var a := _enemy(Vector2i(1, 1), "蜂巢III")   # 血量 9，扛得住 6 点
	var b := _enemy(Vector2i(0, 2), "蜂巢III")
	assert_true(e.state.board.is_empty(Vector2i(1, 2)), "前置：中心格应为空")

	assert_true(_cast(0, Vector2i(1, 2))[1], "空地中心也应可施放（效果范围不以单位为中心）")
	assert_eq(a.current_hp, a.max_hp() - 6, "范围内单位应受 6 点伤害")
	assert_eq(b.current_hp, b.max_hp() - 6, "范围内另一单位同样受伤")


func test_aoe_hits_all_units_but_excludes_queens() -> void:
	## a500 原文：「对效果范围内**所有单位**造成伤害」→ 含己方；
	## 但实现按 a500「蜂王免疫指令卡伤害」把**蜂王排除在 AOE 收集之外**（is_queen → skip）
	assert_eq(Fixture.push_card(e, 0, "巡航导弹"), 0, "前置：取巡航导弹")
	e.state.sides[0]["cost"] = 10
	_enemy(Vector2i(1, 1), "蜂巢III")
	var own := Fixture.place_unit(e, 0, "蜂巢III", Vector2i(1, 2))
	var own_hp: int = own.current_hp

	_cast(0, Vector2i(1, 2))

	assert_eq(own.current_hp, own_hp - 6, "范围伤害同样作用于己方单位（a500：所有单位）")


func test_queen_is_immune_to_area_command_damage() -> void:
	## a500：蜂王免疫指令卡伤害与减益；AOE 收集阶段直接跳过蜂王
	assert_eq(Fixture.push_card(e, 0, "巡航导弹"), 0, "前置：取巡航导弹")
	e.state.sides[0]["cost"] = 10
	var q: UnitInstance = Fixture.queen(e, 0)   # 蜂王在 (3,2)
	var q_hp: int = q.current_hp

	assert_true(_cast(0, q.cell)[1], "以蜂王所在格为中心施放应可执行")
	assert_eq(q.current_hp, q_hp, "蜂王不应受到指令范围伤害")


func test_damage_command_rejects_own_unit_as_primary_target() -> void:
	## 单位目标路径：伤害类指令**主目标**必须是敌方（a500「伤害类作用于敌方」）
	assert_eq(Fixture.push_card(e, 0, "电击"), 0, "前置：取电击")
	var own := Fixture.place_unit(e, 0, "泥蜂", Vector2i(1, 1))
	assert_false(e.request_use_command(0, 0, own), "以己方单位为指令主目标应被拒")


# ---------------------------------------------------------------- 治疗

func test_heal_restores_own_unit() -> void:
	assert_eq(Fixture.push_card(e, 0, "治疗"), 0, "前置：取治疗")
	var q: UnitInstance = Fixture.queen(e, 0)
	q.set_hp(2)
	assert_eq(q.current_hp, 2, "前置：蜂王血量压到 2")

	assert_true(_cast(0, q.cell)[1], "治疗应成功施放")
	assert_eq(q.current_hp, 5, "应回复 3 点生命")


func test_heal_cannot_exceed_max_hp() -> void:
	assert_eq(Fixture.push_card(e, 0, "治疗"), 0, "前置：取治疗")
	var q: UnitInstance = Fixture.queen(e, 0)
	q.set_hp(q.max_hp())

	_cast(0, q.cell)

	assert_eq(q.current_hp, q.max_hp(), "满血治疗不得溢出上限")


# ---------------------------------------------------------------- 门禁

func test_command_rejected_outside_deploy_or_action() -> void:
	assert_eq(Fixture.push_card(e, 0, "电击"), 0, "前置：取电击")
	_enemy(Vector2i(1, 0))
	e.state.phase = BattleState.Phase.RECOVER
	assert_false(e.request_use_command_at(0, 0, Vector2i(1, 0)), "回费阶段不得使用指令卡")


func test_command_rejected_when_cost_insufficient() -> void:
	assert_eq(Fixture.push_card(e, 0, "巡航导弹"), 0, "前置：取巡航导弹")
	e.state.sides[0]["cost"] = 0
	_enemy(Vector2i(1, 1), "蜂巢III")
	assert_false(e.request_use_command_at(0, 0, Vector2i(1, 1)), "费用不足应被拒")
