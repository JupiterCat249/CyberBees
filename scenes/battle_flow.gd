extends Node2D
## ============================================================
## BattleFlow —— 战斗场景协调器（只做「装配 + 接线」，不含规则也不含渲染）
##
## 节点体系（全部通过 Godot 信号交互）：
##   Battle
##   ├── State        BattleState      规则状态机（Model）
##   │                ↑ 发: state_changed / turn_started / phase_changed / log_added /
##   │                     battle_ended / selection_changed
##   ├── Combat       BattleCombat     战斗解算（被 State 调用）
##   ├── InputRouter  BattleInput      输入路由（Controller）
##   │                ↑ 发: hand_clicked / cell_clicked / support_clicked / main_pressed / small_pressed
##   ├── BgFx         BattleBgFx       背景注入 + 各层等比同步
##   ├── BoardView    BattleBoardView  棋盘底图/格子/单位/高亮/地形标记
##   ├── HandView     BattleHandView   手牌 + 费用徽章图集数字
##   ├── DetailView   BattleDetailView 卡牌详情块 + 技能显示区 + 状态数值
##   └── HudView      BattleHudView    顶栏 / 主按钮 / 日志 / 规则帮助
##
## 数据流：InputRouter --语义信号--> State --state_changed--> 各 View 重绘
## ============================================================

const UI_SCENE := preload("res://card-system/card_system/battle_ui.tscn")

var _holder: Node2D = null
var _overlay: Node2D = null


func _ready() -> void:
	# 框架场景（card-system 的 battle_ui）由编辑器实例化在本场景下；这里只取用其 Holder
	var ui := get_node_or_null("BattleUI")
	if ui == null:
		ui = UI_SCENE.instantiate()
		add_child(ui)
	_holder = ui.get_node("Holder") as Node2D
	_overlay = get_node_or_null("Overlay") as Node2D

	var state := get_node_or_null("State")
	var combat := get_node_or_null("Combat")
	if state == null or combat == null:
		push_error("BattleFlow: 缺少 State / Combat 节点，无法装配")
		return

	# ---- 依赖注入（Model 侧）----
	state.combat = combat
	combat.state = state
	# 结构化技能系统（迭代003）：RefCounted，无需场景节点
	var skills_script := load("res://scenes/battle/battle_skills.gd")
	if skills_script != null:
		var sk = skills_script.new()
		sk.state = state
		state.skills = sk

	# 棋盘几何与范围计算（重构第1块）：RefCounted，无需场景节点
	var grid_script := load("res://scenes/battle/battle_grid.gd")
	if grid_script != null:
		var gd = grid_script.new()
		gd.state = state
		state.grid = gd
	else:
		push_warning("BattleGrid 载入失败，范围计算不可用")

	# 待确认（二次点击确认）（重构第2块）：RefCounted，无需场景节点
	var pending_script := load("res://scenes/battle/battle_pending.gd")
	if pending_script != null:
		var pd = pending_script.new()
		pd.state = state
		state.pending = pd
	else:
		push_warning("BattlePending 载入失败，二次确认不可用")

	# 手牌/牌库/起手与换牌（重构第3块）：RefCounted，无需场景节点
	var deck_script := load("res://scenes/battle/battle_deck.gd")
	if deck_script != null:
		var dk = deck_script.new()
		dk.state = state
		state.deck = dk
	else:
		push_warning("BattleDeck 载入失败，手牌/牌库不可用")

	# 部署与指令（重构第4块）：RefCounted，无需场景节点
	var deploy_script := load("res://scenes/battle/battle_deploy.gd")
	if deploy_script != null:
		var dp = deploy_script.new()
		dp.state = state
		state.deploy = dp
	else:
		push_warning("BattleDeploy 载入失败，部署与指令不可用")

	# 行动：选中/移动/攻击/支援（重构第5块）：RefCounted，无需场景节点
	var action_script := load("res://scenes/battle/battle_action.gd")
	if action_script != null:
		var ac = action_script.new()
		ac.state = state
		state.action = ac
	else:
		push_warning("BattleAction 载入失败，行动/支援不可用")

	# 开局准备/地图/生成（重构第6块·上）：RefCounted，无需场景节点
	var setup_script := load("res://scenes/battle/battle_setup.gd")
	if setup_script != null:
		var su = setup_script.new()
		su.state = state
		state.setup = su
	else:
		push_warning("BattleSetup 载入失败，开局准备不可用")

	# 胜负判定（重构第6块·下）：RefCounted，无需场景节点
	var victory_script := load("res://scenes/battle/battle_victory.gd")
	if victory_script != null:
		var vt = victory_script.new()
		vt.state = state
		state.victory = vt
	else:
		push_warning("BattleVictory 载入失败，胜负判定不可用")

	# 回合流程/地形/投降（重构第6块·下之二）：RefCounted，无需场景节点
	var turn_script := load("res://scenes/battle/battle_turn.gd")
	if turn_script != null:
		var tn = turn_script.new()
		tn.state = state
		state.turn = tn
	else:
		push_warning("BattleTurn 载入失败，回合流程不可用")

	# 显式交互状态机（重构节点7）：RefCounted，无需场景节点
	var interact_script := load("res://scenes/battle/battle_interaction.gd")
	if interact_script != null:
		var it = interact_script.new()
		it.state = state
		state.interaction = it
	else:
		push_warning("BattleInteraction 载入失败，点击裁决不可用")

	# ---- 依赖注入（View 侧）----
	var bgfx := get_node_or_null("BgFx")
	var board := _ci("BoardView")
	if bgfx != null:
		bgfx.setup(_holder, get_node_or_null("BgLayer"), get_node_or_null("FxLayer"), _overlay)
	board.setup(_holder, state)
	_ci("HandView").setup(_holder, _overlay, state)
	var detail := _ci("DetailView")
	detail.setup(_holder, _overlay, state)
	_ci("HudView").setup(_overlay, state)

	# ---- 接线：输入路由 → 状态机（语义信号）----
	var inp := get_node_or_null("InputRouter")
	if inp != null:
		inp.holder = _holder
		inp.hand_clicked.connect(state.on_hand_clicked)
		inp.cell_clicked.connect(state.on_cell_clicked)
		inp.support_clicked.connect(state.on_support_clicked)
		inp.click_empty.connect(state.on_click_empty)
		# A5 UI：长按查看卡牌详情浮窗（点击任意处关闭）
		inp.long_pressed.connect(detail.open_popup_at)
		inp.popup_dismiss.connect(detail.close_popup)
		inp.popup_dismiss.connect(state.cancel_surrender)
		inp._popup_open = Callable(detail, "is_popup_open")
		inp._long_press_allowed = Callable(state, "can_long_press")
		# a500 胜利条件 4：投降需二次确认（复用同一浮窗节点显示纯文本）
		state.popup_requested.connect(detail.show_text_popup)
		inp.main_pressed.connect(state.advance_phase)
		inp.small_pressed.connect(state.on_small_pressed)

		# ---- 启动自检（G-01 防护）----
		# 编辑器脚本缓冲曾把本文件旧版本写回磁盘、抹掉上述接线，导致功能**静默失效**。
		# 此处逐一核验关键接线是否存在；缺失即大声报错，避免再次静默。
		var missing: Array[String] = []
		if state.grid == null:
			missing.append("棋盘几何注入 state.grid")
		if state.interaction == null:
			missing.append("交互状态机注入 state.interaction")
		if state.turn == null:
			missing.append("回合流程注入 state.turn")
		if state.victory == null:
			missing.append("胜负判定注入 state.victory")
		if state.setup == null:
			missing.append("开局准备注入 state.setup")
		if state.action == null:
			missing.append("行动注入 state.action")
		if state.deploy == null:
			missing.append("部署指令注入 state.deploy")
		if state.deck == null:
			missing.append("手牌牌库注入 state.deck")
		if state.pending == null:
			missing.append("待确认注入 state.pending")
		if state.skills == null:
			missing.append("技能系统注入 state.skills")
		if state.combat == null:
			missing.append("战斗结算注入 state.combat")
		if not inp.click_empty.is_connected(state.on_click_empty):
			missing.append("取消选中接线")
		if not inp.long_pressed.is_connected(detail.open_popup_at):
			missing.append("长按详情浮窗接线")
		if not inp.popup_dismiss.is_connected(detail.close_popup):
			missing.append("浮窗关闭接线")
		if not inp.popup_dismiss.is_connected(state.cancel_surrender):
			missing.append("投降取消接线")
		if not state.popup_requested.is_connected(detail.show_text_popup):
			missing.append("浮窗文本接线")
		if missing.is_empty():
			print("[BattleFlow] 接线自检通过（16 项）")
		else:
			push_error("[BattleFlow] 接线缺失 %d 项（疑似编辑器回退 G-01）：%s" % [missing.size(), str(missing)])

	# ---- 启动对局（_prepare 会自动开启首回合并 emit state_changed）----
	state.start()
	state.refresh()


## 取子节点（缺失时明确报错，便于装配问题定位）
func _ci(n: String) -> Node:
	var x := get_node_or_null(NodePath(n))
	if x == null:
		push_error("BattleFlow: 缺少视图节点 %s" % n)
	return x
