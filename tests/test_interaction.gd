extends GutTest
## 交互回归网兜（迭代097）—— **在切 `_on_cell_clicked` 之前先钉住行为**
##
## 为什么需要：B5 前十二刀都是"等价搬家"（纯结构），而交互函数不一样 —— 它们**会改行为**。
##   项目规矩：先补交互回归，再动交互大函数。本册只断言**引擎状态与可见读数**，不断言观感。
##
## 覆盖（人物点击 → 请求 → 状态变化）：
##   1. 点手牌 → 选中 + 出预览
##   2. 选牌后点合法格 → 真的部署（棋盘出现单位 / 费用扣 / 手牌少一张）
##   3. 点己方单位 → 选中 + 详情栏换人
##   4. 攻击**双步**：第一次只挂待确认（血量不变），第二次才结算
##   5. 对手手牌：不可操作，但**必须可看**（迭代067 人定口径）
##   6. 非我方回合：棋盘点击一律无效（联机-2 权限门）
##
## ⚠️ **实测路径分工（写测试前必须知道）**：
##   · 空格点击 → `_on_cell_clicked`（部署/移动落点走这条）；
##   · **占格**上有单位卡（250×250，mouse_filter=STOP 把格子整片盖住）⇒ 玩家点下去命中的是
##     `_on_unit_clicked(instance_id)`，**不是** `_on_cell_clicked`。
##     ⇒ 选单位 / 攻击目标 / 支援目标 的真实入口都是 `_on_unit_clicked`；
##     `_on_cell_clicked` 里 ATTACK/SUPPORT 分支实际只有"经程序调用"才会走到（首版测试因此误判成"攻击坏了"）。

const BattleScene := preload("res://scenes/ui/battle_scene.tscn")
const PreviewLib := preload("res://scripts/battle/rules_preview.gd")

var _scene: Node = null


## ⚠️ 必须**每例一个新场景**：交互测试会改引擎状态（选中/棋盘/阶段），
##   共用一个场景会让"上一例的选中态"串到下一例（首版就是这么把攻击测试搞挂的）。
func before_each() -> void:
	_scene = BattleScene.instantiate()
	add_child(_scene)
	await wait_frames(3)


func after_each() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()
		_scene = null
	await wait_frames(1)


func _engine():
	return _scene.get("engine")


func _first_hand_id(side: int) -> String:
	var order: Dictionary = _scene.get("_hand_order")
	var ids: Array = order[side]
	return String(ids[0]) if ids.size() > 0 else ""


## 找一张"费用够 + 有可部署格"的单位卡（返回 {idx, cell}；找不到则 idx=-1）
func _find_deployable() -> Dictionary:
	var e = _engine()
	var hand: Array = e.state.sides[0]["hand"]
	for i in hand.size():
		var c = hand[i]
		if not (c is UnitData):
			continue
		if int(c.cost) > e.state.cost(0):
			continue
		var cells: Array = PreviewLib.deploy_cells(e.state, 0, c)
		if cells.is_empty():
			continue
		return {"idx": i, "cell": cells[0]}
	return {"idx": -1, "cell": Vector2i(-1, -1)}


func test_hand_click_selects_card_and_builds_preview() -> void:
	var card_id := _first_hand_id(0)
	assert_ne(card_id, "", "前置：应有手牌")
	_scene._on_hand_clicked(card_id, 0)
	await wait_frames(1)
	var e = _engine()
	assert_eq(int(e.sel_kind), 1, "点手牌应进入'选中手牌'态")
	assert_eq(int(e.sel_hand_index), 0, "应选中第 0 张")
	assert_not_null(_scene.get("_preview"), "选中手牌后应有预览（否则玩家看不到可放哪）")


func test_cell_click_deploys_selected_card() -> void:
	var pick := _find_deployable()
	assert_ne(int(pick["idx"]), -1, "前置：手牌里应有一张可部署的单位卡")
	var e = _engine()
	var hand_before: int = e.state.sides[0]["hand"].size()
	var cost_before: int = e.state.cost(0)
	var card = e.state.sides[0]["hand"][int(pick["idx"])]
	## 先点手牌（进选中态），再点目标格 —— 这正是玩家路径
	_scene._on_hand_clicked(String(card.id), 0)
	await wait_frames(1)
	_scene._on_cell_clicked(pick["cell"])
	await wait_frames(1)
	assert_not_null(e.state.board.unit_at(pick["cell"]), "点合法格后棋盘上应出现该单位")
	assert_eq(e.state.cost(0), cost_before - maxi(0, int(card.cost)), "费用应扣掉部署费")
	assert_eq(e.state.sides[0]["hand"].size(), hand_before - 1, "手牌应少一张")


func test_cell_click_on_own_unit_selects_and_shows_detail() -> void:
	var e = _engine()
	if int(e.state.phase) != 3:
		e.request_end_phase(0)                     # 部署 → 行动
	var q = e.state.queen(0)
	assert_not_null(q, "前置：应有己方蜂王")
	_scene._on_unit_clicked(q.instance_id)
	await wait_frames(1)
	assert_same(e.sel_unit, q, "点己方单位卡应选中它")
	var name_node = _scene.get_node_or_null("HUD/InfoPanel/CardName")
	assert_not_null(name_node, "前置：详情栏应存在")
	assert_eq(String(name_node.text), String(q.data.display_name), "详情栏应换成本单位")


func test_attack_takes_two_clicks() -> void:
	## 规则口径：移动/攻击与指令卡同构 —— 第一次只挂待确认（返回 false），第二次执行
	var e = _engine()
	var Pool := preload("res://scripts/data/card_pool.gd")
	var atk = UnitInstance.create(Pool.card("泥蜂"), 0, Vector2i(2, 1))
	e.state.board.place(atk)
	_scene._on_unit_spawned(atk, atk.cell)
	var foe = UnitInstance.create(Pool.card("泥蜂"), 1, Vector2i(2, 2))
	e.state.board.place(foe)
	_scene._on_unit_spawned(foe, foe.cell)
	if int(e.state.phase) != 3:
		e.request_end_phase(0)
	_scene._on_unit_clicked(atk.instance_id)      # 选中攻击者（真实入口：点单位卡）
	await wait_frames(1)
	assert_same(e.sel_unit, atk, "前置：应选中攻击者")
	var hp_before: int = foe.current_hp
	_scene._on_unit_clicked(foe.instance_id)      # 第一次：挂待确认
	await wait_frames(1)
	assert_eq(String(e.pending_action), "attack", "第一次点击应挂'待确认攻击'")
	assert_eq(foe.current_hp, hp_before, "第一次点击**不应**结算（双步语义）")
	_scene._on_unit_clicked(foe.instance_id)      # 第二次：执行
	await wait_frames(1)
	assert_lt(foe.current_hp, hp_before, "第二次点击应真的造成伤害")


func test_opponent_hand_is_readonly_but_readable() -> void:
	var e = _engine()
	var opp_id := _first_hand_id(1)
	assert_ne(opp_id, "", "前置：对手应有手牌")
	var opp_hand: Array = e.state.sides[1]["hand"]
	var idx: int = (_scene.get("_hand_order")[1] as Array).find(opp_id)
	assert_true(idx >= 0, "前置：应能在顺序表里找到这张牌")
	var want_name := String(opp_hand[idx].display_name)
	_scene._on_hand_clicked(opp_id, 1)
	await wait_frames(1)
	assert_eq(int(e.sel_kind), 0, "对手手牌不得被选中（权限门）")
	var name_node = _scene.get_node_or_null("HUD/InfoPanel/CardName")
	assert_eq(String(name_node.text), want_name, "但详情栏必须显示这张牌（详情恒开放）")


func test_board_click_ignored_on_opponent_turn() -> void:
	var e = _engine()
	var saved: int = int(e.state.active)
	e.state.active = 1 if saved == 0 else 0        # 造"不是我的回合"
	var q = e.state.queen(0)
	_scene._on_unit_clicked(q.instance_id)
	await wait_frames(1)
	assert_null(e.sel_unit, "非我方回合时，点单位卡不得产生选中")
	e.state.active = saved
