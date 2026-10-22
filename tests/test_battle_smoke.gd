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
const ViewDiag := preload("res://scenes/ui/view_diagnostics.gd")

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


# ---------------------------------------------------------------- B5 切片后的回归守护

func test_diag_dump_delegate_works() -> void:
	## 迭代073 把诊断实现切到 scenes/ui/view_diagnostics.gd，arena_view 只留 delegate
	var info: Dictionary = await _scene.dump_runtime_geometry(false)
	assert_true(info.has("viewport_size"), "dump 应返回视口尺寸")
	assert_true(info.has("design_size"), "dump 应返回设计分辨率")
	assert_true(info.has("canvas_transform"), "dump 应返回 canvas 变换")


func test_diag_nodes_table_still_exposed() -> void:
	## net_diag_dump.gd 以 arena_view 的 DIAG_NODES 作静态指纹 —— 切片后必须仍可取到
	var nodes: Array = _scene.DIAG_NODES
	assert_true(nodes.size() > 0, "DIAG_NODES 不应为空")
	var first := String(nodes[0])
	assert_not_null(_scene.get_node_or_null(first), "DIAG_NODES 首个路径应能在场景里解析：%s" % first)


# ---------------------------------------------------------------- B5 第三刀后的回归守护（鼠标穿透族）

func test_crtfx_overlays_are_click_through() -> void:
	## 迭代076 把穿透族切到 scenes/ui/view_input_utils.gd —— 这段断言它真的跑过了
	var found := 0
	var stack: Array[Node] = [_scene]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			if ch is Control and String(ch.name).begins_with("CrtFx"):
				found += 1
				assert_eq((ch as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE,
					"扫描线层 %s 应鼠标穿透" % String(ch.name))
			stack.push_back(ch)
	assert_true(found > 0, "场景里应至少有一个 CrtFx 扫描线层")


func test_card_root_stays_clickable_but_inner_art_is_transparent() -> void:
	## 卡根必须仍能收点击（STOP）；卡内立绘必须穿透 —— 二者都被切片的实现保证
	var units := _scene.get_node_or_null("Battle/MapView/Units")
	assert_not_null(units, "前置：应有 Units 容器")
	var card: Node = null
	for ch in units.get_children():
		if ch is Control:
			card = ch
			break
	assert_not_null(card, "场上有单位卡时应能找到一张")
	if card == null:
		return
	assert_eq((card as Control).mouse_filter, Control.MOUSE_FILTER_STOP, "卡根应可点（STOP）")
	var inner := card.get_node_or_null("Artwork")
	if inner is Control:
		assert_eq((inner as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"卡内立绘应鼠标穿透")


# ---------------------------------------------------------------- B5 第五刀后的回归守护（FX 播放族）

func test_float_text_spawns_and_is_recycled() -> void:
	## 迭代078 把飘字/抖动/播动画/收尾切到 scenes/ui/view_fx.gd —— 这段证明它真的还会跑
	var fx_root = _scene.get("_fx_root")
	assert_not_null(fx_root, "前置：飘字层 EffectsTop 应已建立")
	var before_n: int = fx_root.get_child_count()
	var anchor := _scene.get_node_or_null("Battle/MapView") as Control
	assert_not_null(anchor, "前置：取一个锚点控件")

	_scene._float_at(anchor, "测试+3", Color.WHITE, 3)
	assert_eq(fx_root.get_child_count(), before_n + 1, "应生成一个飘字节点")

	## 动画播完 → on_anim_finished 里 queue_free（否则淡到 α=0 永久滞留＝泄漏）
	var waited := 0
	while waited < 240 and fx_root.get_child_count() > before_n:
		await wait_frames(1)
		waited += 1
	assert_eq(fx_root.get_child_count(), before_n, "飘字播完应被回收")


# ---------------------------------------------------------------- 诊断入口（F8 管线）

func test_f8_key_reaches_diag_handler() -> void:
	## 用 Viewport.push_input 走**完整输入管线**（_input → GUI → shortcut → unhandled_key），
	## 用来回答「F8 到底有没有到达视图」——不依赖真机焦点。
	var hits_before: int = int(_scene.get("_diag_hits"))
	var ev := InputEventKey.new()
	ev.keycode = KEY_F8
	ev.pressed = true
	_scene.get_viewport().push_input(ev)
	await wait_frames(1)
	assert_eq(int(_scene.get("_diag_hits")), hits_before + 1, "F8 应命中诊断入口")


func test_diag_key_accepts_physical_keycode() -> void:
	## 笔记本 F8 可能只带 physical_keycode —— 两种都要认
	var a := InputEventKey.new()
	a.keycode = KEY_F8
	a.pressed = true
	assert_true(ViewDiag.is_diag_key(a), "keycode 路径应识别")

	var b := InputEventKey.new()
	b.physical_keycode = KEY_F8
	b.pressed = true
	assert_true(ViewDiag.is_diag_key(b), "physical_keycode 路径也应识别")

	var c := InputEventKey.new()
	c.keycode = KEY_F9
	c.pressed = true
	assert_false(ViewDiag.is_diag_key(c), "其它键不应识别")


func test_diag_flag_trigger_consumes_flag() -> void:
	## 文件触发器的端到端验证：建 flag → NetDiagDump 每帧轮询 → flag 被消费
	##   （这条不依赖键盘与焦点，正是它存在的理由）
	var f := FileAccess.open("user://diag_now.flag", FileAccess.WRITE)
	if f == null:
		pending("无法写入 user:// —— 跳过")
		return
	f.store_line("1")
	f.close()
	assert_true(FileAccess.file_exists("user://diag_now.flag"), "前置：flag 应已创建")

	var waited := 0
	while waited < 30 and FileAccess.file_exists("user://diag_now.flag"):
		await wait_frames(1)
		waited += 1
	assert_false(FileAccess.file_exists("user://diag_now.flag"), "NetDiagDump 应消费掉 flag（无需键盘焦点）")
