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
	if state.winner != "":
		_labels["btn"].text = "游戏结束"
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
	if state.can_discard():
		return "主按钮=弃卡过牌 / 点高亮格放置或使用指令"
	match state.mode:
		D.Mode.DEPLOY_TARGET:
			return "点高亮格放置"
		D.Mode.CMD_TARGET:
			return "点目标格使用指令"
		_:
			return "点牌选中 / 点己方单位行动"
