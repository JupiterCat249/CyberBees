extends GutTest
## 规则层回归 —— 弃牌 / 换手 / 补牌（自 test_rules_core 分册：单文件公开方法数控制）
##
## 判据来源：a500 抽卡 4~6（补手牌 / 洗回 / 弃牌）、回合流程 1~8。

const Fixture := preload("res://tests/support/battle_fixture.gd")
const Pool := preload("res://src/data/card_pool.gd")

var e: BattleEngine = null


func before_each() -> void:
	e = Fixture.new_engine()


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


# ---------------------------------------------------------------- 弃牌 / 换手 / 补牌（迭代077 补网）

func test_discard_pays_cost_and_moves_card_to_discard() -> void:
	var idx := 1                                   ## 蜂巢：费 3
	var card = e.state.sides[0].hand[idx]
	var before: int = e.state.cost(0)
	var expect_pay: int = e.discard_cost_of(card)

	assert_true(e.request_discard(0, idx), "部署阶段应可弃牌")
	assert_eq(e.state.cost(0), before - expect_pay, "应按弃牌费扣费")
	assert_eq(e.state.sides[0].hand.size(), 3, "手牌应少一张")
	assert_eq(e.state.sides[0].discard.size(), 1, "弃掉的牌应进墓地")


func test_discard_rejected_in_recover_phase() -> void:
	e.state.phase = BattleState.Phase.RECOVER
	assert_false(e.request_discard(0, 1), "回费阶段不得弃牌")


func test_end_phase_passes_turn_to_other_side() -> void:
	var first_active: int = e.state.active
	e.request_end_phase(0)                          ## DEPLOY -> ACTION
	e.request_end_phase(0)                          ## ACTION -> 换手
	assert_eq(e.state.active, 1 - first_active, "应轮到对手")
	assert_eq(e.state.round_no, 1, "半回合轮换不该推进回合数")
	assert_eq(e.state.phase, BattleState.Phase.DEPLOY, "对手的前两阶段应已自动推进到部署")


func test_full_round_increments_round_no() -> void:
	e.request_end_phase(0)
	e.request_end_phase(0)                          ## 绿方结束
	e.request_end_phase(1)
	e.request_end_phase(1)                          ## 红方结束 → 新回合
	assert_eq(e.state.round_no, 2, "双方都走完应进入第 2 回合")
	assert_eq(e.state.active, BattleState.SIDE_ALLY, "第 2 回合仍由绿方先手")


func test_hand_refills_to_four_at_turn_end() -> void:
	assert_true(e.request_deploy(0, 1, Fixture.empty_own_cell(e)), "先部署一张让手牌变 3")
	assert_eq(e.state.sides[0].hand.size(), 3, "前置：手牌 3 张")
	e.request_end_phase(0)
	e.request_end_phase(0)                          ## 换手 → 回合结束时补牌
	assert_eq(e.state.sides[0].hand.size(), 4, "回合结束应补手牌到 4 张")

