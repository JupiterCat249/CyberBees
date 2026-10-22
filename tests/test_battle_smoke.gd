extends GutTest
## G4 回归闸 —— 战斗场景冒烟（headless 实例化真场景）
##
## 边界（与 AGENTS.md「感官归人」一致）：
##   这里只断言**逻辑与结构**事实（节点在、引擎起来、手牌/费用/阶段符合规则）；
##   像素、观感、手感一律不进 CI。
##
## 场景**只 boot 一次**（before_all）：① 省时；② 引擎级警告只发一次。
## ⚠️ before_all 里**不能用 add_child_autofree** —— autofree 在每条测试结束时清空，
##    第二条测试就会拿到 previously freed 引用（本文件首版实测踩到）。

const BattleScene := preload("res://scenes/ui/battle_scene.tscn")

var _scene: Node = null


func before_all() -> void:
	_scene = BattleScene.instantiate()
	add_child(_scene)
	await wait_frames(3)


func after_all() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()


func test_scene_boots_and_engine_starts() -> void:
	assert_not_null(_scene.engine, "arena_view 应建立 BattleEngine")
	assert_not_null(_scene.engine.state, "BattleEngine 应初始化 BattleState")


func test_opening_hand_follows_a500() -> void:
	var st = _scene.engine.state
	# a500 构筑 2：前 4 张常规卡为初始手牌
	assert_eq(st.sides[BattleState.SIDE_ALLY].hand.size(), 4, "绿方初始手牌应为 4 张")
	assert_eq(st.sides[BattleState.SIDE_ENEMY].hand.size(), 4, "红方初始手牌应为 4 张")


func test_green_moves_first_and_starts_in_deploy() -> void:
	var st = _scene.engine.state
	assert_eq(st.active, BattleState.SIDE_ALLY, "绿方先手")
	assert_eq(st.round_no, 1, "开局为第 1 回合")
	assert_eq(st.phase, BattleState.Phase.DEPLOY, "开局结算完回费/场后应停在部署阶段")


func test_cost_after_first_recover() -> void:
	var st = _scene.engine.state
	# 开局日志实测：绿方先手回费 +4（现 4）
	assert_eq(st.cost(BattleState.SIDE_ALLY), 4, "绿方第 1 回合回费后应为 4")


func test_both_queens_assigned() -> void:
	var st = _scene.engine.state
	assert_not_null(st.sides[BattleState.SIDE_ALLY].queen, "绿方蜂王应已入场")
	assert_not_null(st.sides[BattleState.SIDE_ENEMY].queen, "红方蜂王应已入场")
