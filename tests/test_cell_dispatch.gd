extends GutTest
## 棋盘点击**决策**的纯函数回归（迭代100 —— 与 _on_cell_clicked 切分同一批交付）
##
## 为什么能这么测：决策层只读引擎状态、返回"该做什么"，不需要场景树
## ⇒ 这些用例**不起场景**，毫秒级，且能覆盖"提示文案"这类容易在搬家中改坏的细节。

const Fixture := preload("res://tests/support/battle_fixture.gd")
const Dispatch := preload("res://scenes/ui/view_cell_dispatch.gd")

var e: BattleEngine = null


func before_each() -> void:
	e = Fixture.new_engine()


func _to_action() -> void:
	if int(e.state.phase) != 3:
		e.request_end_phase(0)


func test_deploy_preview_decides_deploy() -> void:
	## 选中一张单位卡 ⇒ 预览顶层 kind = DEPLOY
	var idx := Fixture.first_affordable_unit_index(e, 0)
	assert_ne(idx, -1, "前置：应有可负担的单位卡")
	e.select_hand(0, idx)
	var cell: Vector2i = Fixture.empty_own_cell(e)
	var d: Dictionary = Dispatch.decide(e, cell)
	assert_eq(String(d.get("type", "")), "deploy", "选牌后点合法格应判定为部署")


func test_move_preview_decides_move() -> void:
	_to_action()
	var q = Fixture.queen(e, 0)
	e.select_unit(0, q)
	var d: Dictionary = Dispatch.decide(e, Vector2i(2, 2))
	assert_eq(String(d.get("type", "")), "move", "选中单位后点空格应判定为移动")


func test_no_preview_on_opponent_unit_is_rejected_with_message() -> void:
	_to_action()
	var foe := Fixture.place_unit(e, 1, "泥蜂", Vector2i(2, 2))
	assert_not_null(foe, "前置：应能放下敌方单位")
	var d: Dictionary = Dispatch.decide(e, foe.cell)
	assert_eq(String(d.get("type", "")), "msg", "无选中时点敌方单位只应给提示")
	assert_eq(String(d.get("msg", "")), Dispatch.MSG_FOE_UNIT, "提示文案应保持原样")


func test_no_preview_on_own_unit_decides_select() -> void:
	_to_action()
	var q = Fixture.queen(e, 0)
	var d: Dictionary = Dispatch.decide(e, q.cell)
	assert_eq(String(d.get("type", "")), "select_unit", "无选中时点己方单位应判定为选中")
	assert_same(d.get("unit"), q, "应带回该单位")


func test_no_preview_empty_cell_in_deploy_phase_explains() -> void:
	var cell: Vector2i = Fixture.empty_own_cell(e)
	var d: Dictionary = Dispatch.decide(e, cell)
	assert_eq(String(d.get("type", "")), "msg", "部署阶段点空格应给'怎么部署'的提示")
	assert_eq(String(d.get("msg", "")), Dispatch.MSG_DEPLOY_PHASE, "提示文案应保持原样")


## ── 手牌执行路由（execute_hand）的桩测试 ─────────────────────────────
## 用桩对象代替 NetIntent：只验"按模式分派到哪个请求 + 失败时的文案"。

class StubIntent:
	extends RefCounted
	var deploy_calls: Array = []
	var cmd_at_calls: Array = []
	var cmd_calls: Array = []
	var deploy_ok := false

	func request_deploy(side: int, idx: int, cell: Vector2i) -> bool:
		deploy_calls.append([side, idx, cell])
		return deploy_ok

	func request_use_command_at(side: int, idx: int, cell: Vector2i) -> bool:
		cmd_at_calls.append([side, idx, cell])
		return false

	func request_use_command(side: int, idx: int, _u) -> bool:
		cmd_calls.append([side, idx])
		return false


func test_execute_hand_routes_deploy_and_flashes_on_failure() -> void:
	var stub := StubIntent.new()
	var idx := Fixture.first_affordable_unit_index(e, 0)
	assert_ne(idx, -1, "前置：应有可负担的单位卡")
	e.select_hand(0, idx)
	var cell: Vector2i = Fixture.empty_own_cell(e)
	var msgs: Array = []
	Dispatch.execute_hand(e, stub, cell, Callable(func(t): msgs.append(t)))
	assert_eq(stub.deploy_calls.size(), 1, "DEPLOY 模式应调用 request_deploy 一次")
	assert_eq(stub.deploy_calls[0][2], cell, "应把点击格原样传下去")
	assert_eq(msgs.size(), 1, "失败时应给一条提示")
	assert_eq(String(msgs[0]), Dispatch.MSG_DEPLOY, "提示文案应保持原样")


func test_execute_hand_routes_aoe_command_by_cell() -> void:
	## AOE 指令卡 ⇒ 走"以格为中心"（空地也能放），不是按单位
	Fixture.push_card(e, 0, "巡航导弹")
	var idx := 0
	e.select_hand(0, idx)
	assert_eq(int(e.hand_mode), 2, "前置：指令卡应进入 TARGET 模式")
	var stub := StubIntent.new()
	var msgs: Array = []
	Dispatch.execute_hand(e, stub, Vector2i(1, 1), Callable(func(t): msgs.append(t)))
	assert_eq(stub.cmd_at_calls.size(), 1, "AOE 应调用 request_use_command_at")
	assert_eq(stub.cmd_calls.size(), 0, "AOE 不应走按单位的目标请求")
