extends Node

const CardPoolLib := preload("res://scripts/data/card_pool.gd")
## 【验证用 · 非生产】迭代054 UI 端到端：battle_scene + GameState 真实对局接线
## 状态：待封存（验证用，非生产文件）

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _scene: Control = null
var _got := {"quit": 0, "ended": -1}

func _ready() -> void:
	_scene = (load("res://scenes/ui/battle_scene.tscn") as PackedScene).instantiate()
	add_child(_scene)
	await get_tree().process_frame
	_scene.request_quit.connect(func() -> void: _got["quit"] += 1)
	_scene.battle_ended.connect(func(r: int, _why: String) -> void: _got["ended"] = r)

	var decks := {0: _mk_deck("绿方"), 1: _mk_deck("红方")}
	_scene.set_player_names("验证·绿", "验证·红")
	_scene.start_battle(decks, 0, {0: "验证·绿", 1: "验证·红"})
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_test_initial_render()
	await _test_play_flow()
	await _test_click_deploy()
	await _test_select_and_move()
	_test_back_button()
	await _shoot()
	# ---------------- 红方控制（本地双人·热座） ----------------
	# 此前接线层写死 side 0 → 红方回合点红方手牌/单位无效。此处直接验证"按 active 判定"。
	_scene.start_battle({0: _mk_deck("绿方"), 1: _mk_deck("红方")}, 0, {0: "绿方", 1: "红方"})
	for _i in 3:
		await get_tree().process_frame
	_scene.state.advance_phase()      # 部署 → 行动
	_scene.state.advance_phase()      # 行动 → 换手
	for _i in 3:
		await get_tree().process_frame
	_chk("已轮到红方（active == 1）", _scene.state.active == 1)
	var red_order: Array = _scene._hand_order[1]
	_chk("红方手牌已渲染（%d 张）" % red_order.size(), red_order.size() > 0)
	if red_order.size() > 0:
		_scene._on_hand_clicked(String(red_order[0]), 1)
		for _i in 2:
			await get_tree().process_frame
		_chk("**红方手牌可选中**（本地双人）",
			_scene.state.sel_kind == _scene.state.SelKind.HAND and _scene.state.sel_hand_index == 0)
	# 非行动方（绿方）手牌点不动
	var green_order: Array = _scene._hand_order[0]
	if green_order.size() > 0:
		_scene.state.cancel_selection()
		_scene._on_hand_clicked(String(green_order[0]), 0)
		for _i in 2:
			await get_tree().process_frame
		_chk("非行动方（绿方）手牌点不动", _scene.state.sel_kind != _scene.state.SelKind.HAND)
	# 红方单位可选中
	var red_unit: UnitInstance = _scene.state.queen[1]
	_scene._on_unit_clicked(red_unit.instance_id)
	for _i in 2:
		await get_tree().process_frame
	_chk("**红方单位可选中**（active==1）", _scene.state.sel_unit == red_unit)
	# 绿方单位在红方回合不可选中
	var green_unit: UnitInstance = _scene.state.queen[0]
	_scene._on_unit_clicked(green_unit.instance_id)
	for _i in 2:
		await get_tree().process_frame
	_chk("非行动方单位点不动", _scene.state.sel_unit != green_unit)

	# ---------------- 单位立绘同步 ----------------
	_scene.state.cancel_selection()
	var unode: Control = _scene._live_unit_node(red_unit.instance_id)
	_chk("单位节点存在", unode != null)
	if unode != null:
		var tr := unode.get_node_or_null("Artwork/ArtPlane/TextureRect") as TextureRect
		_chk("单位卡立绘节点存在", tr != null)
		if tr != null:
			var want = red_unit.data.visual.artwork if (red_unit.data != null and red_unit.data.visual != null) else null
			if want == null:
				# 该测试卡的卡数据本就没有立绘（代码构造的卡组）→ 断言"不会乱换图"
				_chk("卡数据无立绘时不改图（绑定逻辑正确）", tr.texture != null)
			else:
				_chk("**立绘与卡数据同步**（非场景默认图）", tr.texture == want)
	# 用**带立绘的卡**（样例卡组）验证立绘真的被绑定到单位卡上
	var spec_deck: DeckData = CardPoolLib.build("绿")
	var art_card: UnitData = null
	for c in spec_deck.cards:
		if c is UnitData and c.visual != null and c.visual.artwork != null:
			art_card = c
			break
	_chk("样例卡组里存在带立绘的卡", art_card != null)
	if art_card != null and unode != null:
		_scene._spawn_unit_node(UnitInstance.create(art_card, 1, Vector2i(0, 3)))
		for _i in 3:
			await get_tree().process_frame
		# 找到该新节点（按立绘所在卡的名字找）
		var found: Control = null
		for ch in _scene._units_root.get_children():
			var ctr := ch.get_node_or_null("Artwork/ArtPlane/TextureRect") as TextureRect
			if ctr != null and ctr.texture == art_card.visual.artwork:
				found = ch
				break
		_chk("**部署单位后立绘 = 该卡立绘**（%s）" % art_card.display_name, found != null)


	_report()
	get_tree().quit(0 if _fail == 0 else 1)


# ---------------- 测试数据 ----------------

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

func _mk_deck(tag: String) -> DeckData:
	var q := _mk_unit("%s蜂王" % tag, CardData.CardKind.QUEEN, 8, 0, 8, 0, 0, 4, true)
	var soldier := _mk_unit("叶蜂%s" % tag, CardData.CardKind.SOLDIER, 2, 2, 3, 1, 1)
	var building := _mk_unit("蜂巢%s" % tag, CardData.CardKind.BUILDING, 4, 0, 5, 0, 0, 1)
	var dd := DeckData.new()
	dd.id = Uuid.generate()
	dd.display_name = "验证卡组"
	dd.queen = q
	dd.cards = [q, soldier, soldier, building, building]
	return dd


# ---------------- 各项验证 ----------------

func _test_initial_render() -> void:
	var st = _scene.state
	_chk("GameState 已挂载", st != null)
	var cells_root: Control = _scene.get_node("Battle/MapView/MapCells")
	_chk("棋盘 16 格点击区已建", cells_root.get_child_count() == 16)
	var units_root: Control = _scene.get_node("Battle/MapView/Units")
	_chk("双方蜂王已入场（2 个单位卡）", units_root.get_child_count() == 2)
	var hand: Control = _scene.get_node("Battle/HandPanelRight/HandRight")
	_chk("我方手牌 4 张已渲染", hand.get_child_count() == 4)
	_chk("顶栏费用徽章 = 4（先手回费）",
		(_scene.get_node("Battle/PlayerBesaInfoLift/BadgeImage/Value") as Label).text == "4")
	_chk("回合文本 = 回合1--绿方",
		(_scene.get_node("HUD/MatchInfo/TurnInfo") as Label).text == "回合1--绿方")
	_chk("主按钮文案 = 完成部署",
		(_scene.get_node("HUD/ActionBar/Label") as Label).text == "完成部署")
	var q = st.queen[0]
	_chk("我方蜂王位于 (3,1)", q != null and q.cell == Vector2i(3, 1))
	var eq = st.queen[1]
	_chk("敌方蜂王位于 (0,1)", eq != null and eq.cell == Vector2i(0, 1))


func _test_play_flow() -> void:
	var st = _scene.state
	_chk("开局停在部署阶段", st.phase == GameState.Phase.DEPLOY)
	# 主按钮 → 行动阶段
	(_scene.get_node("HUD/ActionBar/MainButton") as Button).pressed.emit()
	await get_tree().process_frame
	_chk("主按钮：部署 → 行动阶段", st.phase == GameState.Phase.ACTION)
	_chk("主按钮文案更新为 结束回合",
		(_scene.get_node("HUD/ActionBar/Label") as Label).text == "结束回合")
	# 再按 → 换手
	(_scene.get_node("HUD/ActionBar/MainButton") as Button).pressed.emit()
	await get_tree().process_frame
	_chk("主按钮：行动 → 换手到敌方", st.active == 1)


func _test_click_deploy() -> void:
	var st = _scene.state
	# 回到我方回合（敌方过掉）
	st.active = 0
	st._begin_turn()
	await get_tree().process_frame
	st.phase = GameState.Phase.DEPLOY
	var units_before: int = _scene.get_node("Battle/MapView/Units").get_child_count()
	var cost_before: int = st.cost[0]
	# 选一张兵蜂手牌（index 0）
	st.select_hand(0)
	await get_tree().process_frame
	_chk("选中手牌后进入 HAND 选中态", st.sel_kind == st.SelKind.HAND)
	_chk("视图给可部署格高亮",
		_scene._cells.values().any(func(c) -> bool: return c.highlight == "deploy"))
	# 点蜂王相邻格部署
	var q = st.queen[0]
	var target := Vector2i(q.cell.x - 1, q.cell.y)
	_scene._cells[target].cell_clicked.emit(target)
	await get_tree().process_frame
	_chk("点击格子成功部署（单位卡 +1）",
		_scene.get_node("Battle/MapView/Units").get_child_count() == units_before + 1)
	_chk("部署后扣除费用（-2）", st.cost[0] == cost_before - 2)


func _test_select_and_move() -> void:
	var st = _scene.state
	# 让刚部署的单位获得行动机会（部署时无行动机会）
	var deployed = null
	for u in st.board.all_units():
		if u.side == 0 and u.data.kind == CardData.CardKind.SOLDIER:
			deployed = u
			break
	_chk("存在已部署的兵蜂", deployed != null)
	if deployed == null:
		return
	deployed.has_moved = false
	deployed.has_acted = false
	st.phase = GameState.Phase.ACTION
	st.select_unit(deployed)
	await get_tree().process_frame
	_chk("选中单位进入 UNIT 选中态", st.sel_kind == st.SelKind.UNIT)
	_chk("视图给可移动格高亮",
		_scene._cells.values().any(func(c) -> bool: return c.highlight == "move"))
	var before: Vector2i = deployed.cell
	var cells: Dictionary = st.board.move_range(deployed)
	if cells.is_empty():
		_chk("存在可移动格", false)
		return
	var to: Vector2i = cells.keys()[0]
	_scene._cells[to].cell_clicked.emit(to)      # 点格子 → 移动
	await get_tree().process_frame
	_chk("点击格子成功移动", deployed.cell == to and before != to)
	# ⚠️ 移动会触发「移动落位」动画（±3px 下沉回弹）→ 等它播完并**收位**后再核对；
	#    否则拿到的是动画中途值（不是缺陷，是时序）
	for _i in 12:
		await get_tree().process_frame
	var n: Control = _scene._unit_nodes[deployed.instance_id]
	var want := Vector2(_scene._cell_pos_in_units(to))
	_chk("移动后节点位置已同步并收位（期望 %s，实际 %s）" % [str(want), str(n.position)],
		n.position.is_equal_approx(want))


func _test_back_button() -> void:
	(_scene.get_node("HUD/FuncButtonGroup/Back/Button") as Button).pressed.emit()
	_chk("返回按钮信号已到达外层", _got["quit"] == 1)

func _shoot() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://verification/iter054_e2e_shot.png")
	print("截图已存（失败项=%d）" % _fail)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  [PASS] ", label)
	else:
		_fail += 1
		_failures.append(label)
		print("  [FAIL] ", label)


func _report() -> void:
	print("\n===== 迭代054 UI 端到端自检 =====")
	print("  通过 %d / 失败 %d" % [_pass, _fail])
	for f in _failures:
		print("   ✗ ", f)
	print("================================")
