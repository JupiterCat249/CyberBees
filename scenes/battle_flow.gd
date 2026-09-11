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
		# a500 胜利条件 4：投降需二次确认（复用同一浮窗节点显示纯文本）
		state.popup_requested.connect(detail.show_text_popup)
		inp.main_pressed.connect(state.advance_phase)
		inp.small_pressed.connect(state.on_small_pressed)

	# ---- 启动对局（_prepare 会自动开启首回合并 emit state_changed）----
	state.start()
	state.refresh()


## 取子节点（缺失时明确报错，便于装配问题定位）
func _ci(n: String) -> Node:
	var x := get_node_or_null(NodePath(n))
	if x == null:
		push_error("BattleFlow: 缺少视图节点 %s" % n)
	return x
