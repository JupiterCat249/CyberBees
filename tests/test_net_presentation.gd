extends GutTest
## 联机呈现回归（迭代090 自 test_battle_smoke 分册：单文件公开方法数控制）
##
## 覆盖「对手动作可视化」：对端选中格、手牌标记唯一性、带格动作清标记、面板描边 top_level。

const BattleScene := preload("res://scenes/ui/battle_scene.tscn")
const NetPanel := preload("res://addons/net_profile_panel/net_panel.gd")
const RemoteState := preload("res://scenes/ui/view_remote_state.gd")
const FixtureLib := preload("res://tests/support/battle_fixture.gd")

var _scene: Node = null


func before_all() -> void:
	## ⚠️ 不能用 add_child_autofree：它在**第一个测试之后**就释放，后续测试会撞 "previously freed instance"
	_scene = BattleScene.instantiate()
	add_child(_scene)
	await wait_frames(3)


func after_all() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()

func test_remote_select_marks_cell() -> void:
	## 对端选中 → 该格 selected，且全局只有一格被选（不得多处同时选中）
	var cells: Dictionary = _scene.get("_cells")
	assert_gt(cells.size(), 0, "前置：应有格子")
	var target := Vector2i(0, 0)
	_scene._on_remote_select(1, target)
	await wait_frames(1)
	assert_eq(_scene.get("_remote").sel_cell, target, "应记住对端选中格")
	var picked := 0
	for c in cells.values():
		if c.selected:
			picked += 1
	assert_eq(picked, 1, "只应有一格处于选中态")


func test_remote_action_without_cell_marks_only_one_hand_card() -> void:
	## 对端"选中手牌 X"（无格）→ 手牌上只留一个 RemoteHandMark（迭代064 修过的"多张同时选中"）
	var engine = _scene.get("engine")
	var nm := String(engine.state.sides[1].hand[0].display_name)
	_scene._on_remote_action(1, "选中手牌 " + nm, Vector2i(-1, -1))
	await wait_frames(1)
	var container := _scene.get("_hand_l") as Control
	assert_not_null(container, "前置：对手手牌容器")
	var marks := 0
	for ch in container.get_children():
		if ch.get_node_or_null("RemoteHandMark") != null:
			marks += 1
	assert_eq(marks, 1, "只应有一张手牌带对端标记")


func test_remote_action_with_cell_clears_hand_marks() -> void:
	## 对端改为选中单位/移动（带格）→ 手牌标记必须清空，格选中生效
	_scene._on_remote_action(1, "移动", Vector2i(1, 1))
	await wait_frames(1)
	var container := _scene.get("_hand_l") as Control
	var marks := 0
	for ch in container.get_children():
		if ch.get_node_or_null("RemoteHandMark") != null:
			marks += 1
	assert_eq(marks, 0, "带格动作应清掉手牌标记")
	assert_eq(_scene.get("_remote").sel_cell, Vector2i(1, 1), "应更新对端选中格")


func test_flash_remote_panel_creates_overlay() -> void:
	## 对端操作提示：面板描边用 top_level 脱离容器布局（否则 HBox 会把宽度归零）
	_scene._flash_remote_panel(1)
	await wait_frames(1)
	var panel := _scene._remote_panel(1) as Control
	assert_not_null(panel, "前置：对手信息面板")
	if panel == null:
		return
	var mark := panel.get_node_or_null("RemoteMark") as Control
	assert_not_null(mark, "应建出 RemoteMark 描边")
	if mark == null:
		return
	assert_true(mark.top_level, "描边必须 top_level（容器会重排子节点）")
	assert_eq(mark.mouse_filter, Control.MOUSE_FILTER_IGNORE, "描边不得挡点击")


func test_resolve_node_exe_is_single_path() -> void:
	## 迭代092：面板曾把 `where node` 的**整段多行输出**当可执行路径 ⇒ 命令里夹换行
	##   ⇒ Windows 报 ERR_CANT_FORK ⇒ 本地双开的中继永远起不来。这条锁住"只能是单条真实路径"。
	var path: String = NetPanel.resolve_node_exe()
	if path == "":
		pending("本机未装 node —— 跳过（中继会用「未找到 node」提示）")
		return
	assert_false(path.contains("\n"), "node 路径不得含换行（含换行必然起不动子进程）")
	assert_true(path.ends_with(".exe"), "应解析到 .exe")
	assert_true(FileAccess.file_exists(path), "解析出的路径必须真实存在：%s" % path)


func test_remote_state_begin_select_drops_old_binding() -> void:
	## 不变式（迭代096）：对端**换选中**必须先作废旧登记，否则会在对手屏幕上留幻影范围
	var st = RemoteState.new()
	st.begin_select(Vector2i(1, 1))
	st.bind_unit("u-1")
	st.bind_command(Vector2i(2, 2))
	assert_eq(st.preview_id, "u-1", "登记后应记住挂载单位")
	st.begin_select(Vector2i(3, 3))
	assert_eq(st.preview_id, "", "换选中必须清掉挂单位的登记")
	assert_eq(st.command_cell, Vector2i(-1, -1), "换选中必须清掉指令待确认格")
	assert_eq(st.sel_cell, Vector2i(3, 3), "应记住新选中格")


func test_remote_state_holds_and_reset() -> void:
	var st = RemoteState.new()
	st.bind_unit("u-9")
	assert_true(st.holds("u-9"), "持有者判定应为真")
	assert_false(st.holds("u-8"), "别的单位不算持有者")
	st.reset()
	assert_false(st.holds("u-9"), "reset 后不再持有")
	assert_eq(st.sel_cell, Vector2i(-1, -1), "reset 后选中格应清")

func test_remote_select_without_remote_unit_clears_binding() -> void:
	## 守卫（迭代096）：本轮切分时**补丁参数多传一位**，把 `else` 分支吞掉 ⇒
	##   "对端选了个空格"时挂载登记没被清掉（幽灵登记）。这条锁住 else 必须存在。
	var st = _scene.get("_remote")
	st.bind_unit("ghost-unit")
	_scene._on_remote_select(1, Vector2i(0, 0))
	assert_eq(st.preview_id, "", "挂载登记必须清空")

func test_remote_select_on_enemy_unit_binds_preview() -> void:
	## 远端选中**对端单位** ⇒ 登记"这条预览挂在谁身上"（死亡时要靠它作废）
	var e = _scene.get("engine")
	var foe := FixtureLib.place_unit(e, 1, "泥蜂", Vector2i(1, 2))
	assert_not_null(foe, "前置：应能放下敌方单位")
	_scene._on_remote_select(1, foe.cell)
	await wait_frames(1)
	var st = _scene.get("_remote")
	assert_eq(st.preview_id, foe.instance_id, "应登记到该敌方单位")
	assert_not_null(_scene.get("_preview"), "应同时算出它的可作用范围预览")


func test_remote_command_action_binds_command_cell() -> void:
	## 对端用**指令卡**并带待确认格 ⇒ 本地算效果范围并**以格为键**登记（幽灵范围防护）
	var e = _scene.get("engine")
	FixtureLib.push_card(e, 1, "电击")
	var target := Vector2i(2, 2)
	_scene._on_remote_action(1, "选中手牌 电击", target)
	await wait_frames(1)
	var st = _scene.get("_remote")
	assert_eq(st.command_cell, target, "应把指令待确认格登记下来")
	assert_not_null(_scene.get("_preview"), "应渲染该指令的效果范围/目标预览")

## ── HUD 左右面板的阵营映射（迭代132：历史上曾左右写反，故补读数网兜）─────────────

func test_turn_tint_follows_active_side() -> void:
	## 口径（人 2026-10-14 重定）：**按行动方对称** —— 该侧是行动方则全白，否则变黑。
	##   ⚠️ 左右与阵营的映射：右 = 我方(ALLY)、左 = 敌方(ENEMY)（迭代059 曾左右写反）
	var e = _scene.get("engine")
	var right = _scene.get_node("Battle/PlayerBesaInfoRight") as Control
	var left = _scene.get_node("Battle/PlayerBesaInfoLift") as Control
	e.state.active = 0
	_scene._set_turn(0, 1)
	await wait_frames(1)
	assert_eq(right.modulate, Color(1, 1, 1, 1), "我方行动 ⇒ 右面板（我方）应全白")
	assert_eq(left.modulate, Color(0.22, 0.22, 0.22, 1), "我方行动 ⇒ 左面板（敌方）应变黑")
	e.state.active = 1
	_scene._set_turn(1, 2)
	await wait_frames(1)
	assert_eq(right.modulate, Color(0.22, 0.22, 0.22, 1), "敌方行动 ⇒ 右面板（我方）应变黑")
	assert_eq(left.modulate, Color(1, 1, 1, 1), "敌方行动 ⇒ 左面板（敌方）应全白")


func test_cost_label_written_to_correct_panel() -> void:
	## 费用文本必须写到**对应阵营**的面板（历史上左右反了会让"自己费用"写到对手栏）
	_scene._on_cost_changed(0, 7, 0)
	await wait_frames(1)
	var right_val = _scene.get_node("Battle/PlayerBesaInfoRight/BadgeImage/Value") as Label
	assert_eq(String(right_val.text), "7", "我方费用应写右面板")
	_scene._on_cost_changed(1, 3, 0)
	await wait_frames(1)
	var left_val = _scene.get_node("Battle/PlayerBesaInfoLift/BadgeImage/Value") as Label
	assert_eq(String(left_val.text), "3", "敌方费用应写左面板")

## ── 单位离场时的"远端登记释放"（迭代133：自 _on_unit_removed 切出的纯状态方法）───

func test_release_if_holds_clears_both_bindings() -> void:
	var st = RemoteState.new()
	st.bind_unit("u1")
	st.bind_command(Vector2i(2, 2))
	assert_true(st.release_if_holds("u1"), "持有该单位 ⇒ 应释放并返回 true")
	assert_eq(st.preview_id, "", "单位挂载应清空")
	assert_eq(st.command_cell, Vector2i(-1, -1), "指令待确认格也应清空（否则留幽灵范围）")


func test_release_if_holds_ignores_other_unit() -> void:
	var st = RemoteState.new()
	st.bind_unit("u1")
	assert_false(st.release_if_holds("u2"), "不是它 ⇒ 不释放")
	assert_eq(st.preview_id, "u1", "登记应原样保留")


func test_unit_removed_clears_remote_preview_and_white_frame() -> void:
	## 端到端：单位离场 ⇒ 远端预览作废 + 格白框清掉（迭代064 遗留③ 的实测补漏）
	var e = _scene.get("engine")
	## ⚠️ 本文件共享同一个场景实例 ⇒ 不能写死格子（前面的用例可能已占）
	var empty := Vector2i(-1, -1)
	for x in 4:
		for y in 4:
			if e.state.board.is_empty(Vector2i(x, y)):
				empty = Vector2i(x, y)
				break
		if empty.x >= 0:
			break
	assert_true(empty.x >= 0, "前置：棋盘应有空格")
	var foe := FixtureLib.place_unit(e, 1, "泥蜂", empty)
	assert_not_null(foe, "前置：放一个敌方单位")
	assert_eq(e.state.board.unit_at(empty), foe, "前置：该格确实属于这个新单位")
	_scene._on_remote_select(1, foe.cell)
	await wait_frames(1)
	var st = _scene.get("_remote")
	assert_eq(st.preview_id, foe.instance_id, "前置：远端预览已挂在它身上")
	e.state.board.remove(foe)
	_scene._on_unit_removed(foe, "死亡")
	await wait_frames(1)
	assert_eq(st.preview_id, "", "离场后应清空单位挂载")
	assert_null(_scene.get("_preview"), "离场后预览应作废")
	var cells: Dictionary = _scene.get("_cells")
	assert_false(cells[foe.cell].selected, "该格白框应清掉")