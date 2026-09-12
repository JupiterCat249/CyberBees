extends Node2D
## ============================================================
## BattleHudView —— HUD 视图
##   ① 顶部信息栏：回合 / 阶段 / 当前方 / 操作提示
##   ② 主按钮文字：进入行动 / 结束回合 / 游戏结束
##   ③ 右下日志：最近若干条
##   ④ 规则帮助：切换显示（由 State.help_on 驱动）
##   文字节点全部由编辑器创建在 Overlay 下，代码只设置位置/字号/颜色与文本。
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

var overlay: Node2D = null
## 迭代004 · 检查点10：UI 回合背景条（我方 #499169 / 敌方 #A84331 / 结束态 #FFFFFF-50%）
var _turn_bg: ColorRect = null
var state: Node = null

var _labels := {}


func setup(ov: Node2D, st: Node) -> void:
	overlay = ov
	state = st
	_bind()
	state.state_changed.connect(_on_state_changed)


func _bind() -> void:
	_labels["info"] = _mk_label("InfoBar", Vector2(452.0, 4.0), 26, Color(1, 1, 1), false)
	_labels["btn"] = _mk_label("BtnText", D.BTN_MAIN + Vector2(250.0, 26.0), 34, Color(0.14, 0.14, 0.14), true)
	_labels["log"] = _mk_label("LogText", Vector2(1494.0, 674.0), 17, Color(0.86, 0.86, 0.86), false)
	_labels["help"] = _mk_label("HelpText", Vector2(452.0, 120.0), 20, Color(1.0, 0.95, 0.75), false)


func _mk_label(node_name: String, pos: Vector2, size: int, col: Color, centered: bool) -> Label:
	var l := overlay.get_node_or_null(NodePath(node_name)) as Label
	if l == null:
		l = Label.new()
		l.name = node_name
		overlay.add_child(l)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(96.0, 0.0)
		l.position = pos - Vector2(48.0, 0.0)
	else:
		l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _on_state_changed() -> void:
	_labels["info"].text = "第%d回合 · 阶段:%s · %s方 · %s" % [
		state.round_no, D.PHASE_NAME[state.phase], state.cn(state.current), _hint()]
	# 迭代004 · 检查点10：UI 回合色 —— 文本态 + **背景态**
	#   我方 #499169 / 敌方 #A84331 / 结束态 #FFFFFF-50%
	if state.anim != null:
		var _over: bool = state.winner != ""
		var _tcol: Color = Color(1, 1, 1, 0.5) if _over else state.anim.turn_color(state.current == "green")
		_labels["info"].add_theme_color_override("font_color", _tcol)
		_ensure_turn_bg()
		if _turn_bg != null and is_instance_valid(_turn_bg):
			# 背景条取同色、半透明，作为"回合背景"而不压过文字
			_turn_bg.color = Color(_tcol.r, _tcol.g, _tcol.b, 0.2 if _over else 0.5)


## 确保回合背景条存在（置于 Overlay 最底层，作为 info 信息条背景）
func _ensure_turn_bg() -> void:
	if _turn_bg != null and is_instance_valid(_turn_bg):
		return
	if overlay == null:
		return
	_turn_bg = ColorRect.new()
	_turn_bg.name = "TurnBg"
	_turn_bg.position = Vector2(440.0, 0.0)
	_turn_bg.size = Vector2(700.0, 54.0)
	_turn_bg.color = Color(1, 1, 1, 0.0)
	_turn_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 绝不拦截点击
	overlay.add_child(_turn_bg)
	overlay.move_child(_turn_bg, 0)
	if state.winner != "":
		_labels["btn"].text = "游戏结束"
	elif state.surrender_pending:
		_labels["btn"].text = "确认投降"
	elif state.pending_kind != "":
		# A5：待确认态主按钮 = 确认
		_labels["btn"].text = "确认"
	elif state.phase == D.Phase.PREPARE:
		# a500 对战准备 5/9：选中手牌时=换牌，否则=开始对局
		_labels["btn"].text = "换牌" if state.can_exchange() else "开始对局"
	elif state.can_discard():
		_labels["btn"].text = "弃卡过牌"
	elif state.phase == D.Phase.DEPLOY:
		_labels["btn"].text = "进入行动"
	elif state.phase == D.Phase.ACTION:
		_labels["btn"].text = "结束回合"
	else:
		_labels["btn"].text = "——"
	var n: int = state.log_lines.size()
	_labels["log"].text = "\n".join(state.log_lines.slice(maxi(0, n - 6), n))
	_labels["help"].text = ("a500 规则速览：蜂王被击败即负 | 第12回合比蜂王血量 | 第4回合起可投降\n"
		+ "兵蜂→蜂王相邻格 · 建筑→己方领地 · 指令→任意目标(蜂王免疫)\n"
		+ "每单位每回合：1 次移动 + 1 次攻击或支援 · 反击射程外无效 · 移动会被单位阻挡") if state.help_on else ""


func _hint() -> String:
	if state.surrender_pending:
		return "投降确认中：点主按钮「确认投降」执行，或点任意处取消"
	if state.pending_kind != "":
		return "待确认：%s @(%d,%d) —— 再次点击同一目标，或按主按钮「确认」" % [state.pending_kind, state.pending_cell.x, state.pending_cell.y]
	if state.phase == D.Phase.PREPARE:
		return "对战准备：点手牌选中 → 主按钮换牌（每方 %d 次）/ 或直接点「开始对局」" % D.EXCHANGE_MAX
	if state.can_discard():
		return "主按钮=弃卡过牌 / 点高亮格放置或使用指令"
	match state.mode:
		D.Mode.DEPLOY_TARGET:
			return "点高亮格放置"
		D.Mode.CMD_TARGET:
			return "点目标格使用指令"
		D.Mode.SUPPORT_TARGET:
			return "选择支援对象（蓝色高亮）/ 点别处退出"
		_:
			return "点牌选中 / 点己方单位行动（再点自身=支援）"
