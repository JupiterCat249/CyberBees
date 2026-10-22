extends GutTest
## 规则层回归 —— 开局 / 费用 / 部署 / 移动 / 攻击（a500 主干账本）
##
## 判据来源：《电子蜂a500规则.md》（规则权威，T10）与《边界约束》T8/T9。
## 只断言**读数**，不断言观感。
##
## ⚠️ 两条实测到的引擎口径（写测试前必须知道）：
##   ① **移动与攻击也是双步**（阶段1 挂待确认返回 false / 阶段2 执行）——与指令卡同构；
##   ② UnitInstance.set_hp() 会 **clamp 到 max_hp**，所以测试里不能把 hp 设成超过上限，
##      否则后续扣血会先被 clamp 掉（首版测试因此误判过）。

const Fixture := preload("res://tests/support/battle_fixture.gd")
const CombatLib := preload("res://scripts/battle/rules_combat.gd")
const Pool := preload("res://scripts/data/card_pool.gd")

var e: BattleEngine = null


func before_each() -> void:
	e = Fixture.new_engine()


func _to_action() -> void:
	e.request_end_phase(0)                      # DEPLOY -> ACTION


# ---------------------------------------------------------------- 开局

func test_engine_starts() -> void:
	assert_not_null(e.state, "state 应已建立")
	assert_eq(e.state.round_no, 1, "开局为第 1 回合")
	assert_eq(e.state.active, BattleState.SIDE_ALLY, "绿方先手")


func test_queens_placed_at_documented_cells() -> void:
	# a500 对战准备 9：我方 (行3,列2) / 红方 (行0,列1)，严格中心对称
	assert_eq(Fixture.queen_cell(e, 0), Vector2i(3, 2), "绿方蜂王应在 (3,2)")
	assert_eq(Fixture.queen_cell(e, 1), Vector2i(0, 1), "红方蜂王应在 (0,1)")
	assert_same(e.state.board.unit_at(Vector2i(3, 2)), Fixture.queen(e, 0), "棋盘上应查得到绿方蜂王")


func test_opening_hand_and_deck_sizes() -> void:
	# a500 构筑 2：前 4 张为初始手牌、后 4 张进牌库
	assert_eq(e.state.sides[0].hand.size(), 4, "绿方初始手牌 4")
	assert_eq(e.state.sides[1].hand.size(), 4, "红方初始手牌 4")
	assert_eq(e.state.sides[0].deck.size(), 4, "绿方备卡 4")
	assert_eq(e.state.sides[0].discard.size(), 0, "开局墓地应为空")


func test_first_side_recover_and_second_side_bonus() -> void:
	# 开局日志实测：绿方回费 +4；后手红方初始费用 +2
	assert_eq(e.state.cost(0), 4, "第 1 回合回费后绿方为 4")
	assert_eq(e.state.cost(1), 2, "红方后手初始费用 +2")


# ---------------------------------------------------------------- 费用口径

func test_hand_affordability_only_looks_at_cost() -> void:
	# 人 2026-09-19 口径：亮/灰只看部署费；不看阶段、不看是否当前行动方
	e.state.sides[0]["cost"] = 0
	assert_false(e.hand_affordable(0, 1), "费用 0 时不应可负担")
	e.state.sides[0]["cost"] = 10
	assert_true(e.hand_affordable(0, 1), "费用充足时应可负担")


func test_can_play_hand_adds_phase_and_side_gates() -> void:
	# 执行口径比「可负担」更严：还要当前行动方 + 部署/行动阶段
	e.state.sides[0]["cost"] = 10
	assert_true(e.can_play_hand(0, 1), "部署阶段、行动方、费用足 → 可出")
	e.state.phase = BattleState.Phase.RECOVER
	assert_false(e.can_play_hand(0, 1), "回费阶段不可出手牌")


# ---------------------------------------------------------------- 部署

func test_deploy_building_costs_and_moves_card_to_discard() -> void:
	# 手牌第 2 张是「蜂巢」（建筑，费用 3）—— 建筑可放己方领地任意空格
	var idx := 1
	var card = e.state.sides[0].hand[idx]
	var before_cost: int = e.state.cost(0)
	var cell := Fixture.empty_own_cell(e)

	var ok: bool = e.request_deploy(0, idx, cell)

	assert_true(ok, "建筑应可部署到己方领地空格 %s" % str(cell))
	assert_eq(e.state.cost(0), before_cost - int(card.cost), "费用应扣掉部署费")
	assert_eq(e.state.sides[0].hand.size(), 3, "手牌应少一张")
	assert_eq(e.state.sides[0].discard.size(), 1, "使用过的单位卡应进墓地")
	assert_not_null(e.state.board.unit_at(cell), "棋盘上应出现该单位")


func test_deploy_rejected_in_enemy_territory() -> void:
	var cell := Vector2i(0, 3)
	assert_true(e.state.board.is_empty(cell), "测试前置：该格为空")
	assert_false(e.request_deploy(0, 1, cell), "建筑不得部署到敌方领地")


func test_deploy_rejected_on_occupied_cell() -> void:
	var cell := Fixture.empty_own_cell(e)
	assert_true(e.request_deploy(0, 1, cell), "第一次部署应成功")
	assert_false(e.request_deploy(0, 1, cell), "同格第二次部署应被拒")


func test_deployed_unit_has_no_action_this_turn() -> void:
	# 行动机会 3：部署当回合没有行动机会
	var cell := Fixture.empty_own_cell(e)
	assert_true(e.request_deploy(0, 1, cell), "部署应成功")
	var inst: UnitInstance = e.state.board.unit_at(cell)
	assert_true(inst.has_moved, "新部署单位应视为已移动")
	assert_true(inst.has_acted, "新部署单位应视为已行动")


func test_deploy_rejected_outside_deploy_phase() -> void:
	_to_action()
	assert_eq(e.state.phase, BattleState.Phase.ACTION, "前置：应已进入行动阶段")
	assert_false(e.request_deploy(0, 1, Fixture.empty_own_cell(e)), "行动阶段不得部署")


# ---------------------------------------------------------------- 移动（双步）

func test_move_is_two_step() -> void:
	_to_action()
	var q: UnitInstance = Fixture.queen(e, 0)
	var cells := e.state.board.move_range(q)
	assert_true(cells.size() > 0, "蜂王移动范围内应有可达格")
	var target: Vector2i = cells.keys()[0]
	var from: Vector2i = q.cell

	assert_false(e.request_move(0, q, target), "阶段 1 只挂待确认，应返回 false")
	assert_eq(q.cell, from, "阶段 1 不得真的移动")

	assert_true(e.request_move(0, q, target), "阶段 2 应执行移动")
	assert_eq(q.cell, target, "单位应落在目标格")
	assert_true(q.has_moved, "移动后 has_moved 应为 true")


func test_move_only_once_per_turn() -> void:
	_to_action()
	var q: UnitInstance = Fixture.queen(e, 0)
	var cells := e.state.board.move_range(q)
	var target: Vector2i = cells.keys()[0]
	e.request_move(0, q, target)
	e.request_move(0, q, target)                # 双步走完，已移动

	var another := Vector2i(-1, -1)
	for c in e.state.board.move_range(q).keys():
		another = c
		break
	if another != Vector2i(-1, -1):
		assert_false(e.request_move(0, q, another), "同回合不得移动两次")


# ---------------------------------------------------------------- 攻击（双步 + 结算同源）

func test_attack_is_two_step_and_matches_preview() -> void:
	_to_action()
	var q: UnitInstance = Fixture.queen(e, 0)
	var foe := Fixture.place_unit(e, 1, "泥蜂", Vector2i(2, 2))
	assert_not_null(foe, "前置：敌方单位应放到蜂王正上方")

	var forecast: Dictionary = CombatLib.preview_attack(q, foe, e.state.board)
	var expect_hp: int = int(forecast["defender_hp_after"])

	assert_false(e.request_attack(0, q, foe), "阶段 1 应返回 false")
	assert_eq(foe.current_hp, foe.max_hp(), "阶段 1 不得结算伤害")

	assert_true(e.request_attack(0, q, foe), "阶段 2 应执行攻击")
	assert_eq(foe.current_hp, expect_hp, "实际伤害应与 preview_attack 同源")
	assert_true(q.has_acted, "攻击后 has_acted 应为 true")


# ---------------------------------------------------------------- 弃牌费用（迭代075 切出的纯查询）

func test_discard_cost_matches_deploy_cost() -> void:
	## a500 抽卡 6：弃牌消耗 = 部署费用
	var card = Pool.card("电击")
	assert_eq(e.discard_cost_of(card), int(card.cost), "弃牌费应等于部署费")


func test_discard_cost_of_x_cost_card_is_ten() -> void:
	## a500：X 费卡（cost < 0）弃牌消耗 10 点
	var xc := CommandData.new()
	xc.cost = -1
	assert_eq(e.discard_cost_of(xc), 10, "X 费卡弃牌应消耗 10 点")
	assert_eq(e.discard_cost_of(null), 0, "空卡应返回 0（防御）")
