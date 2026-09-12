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


const INFO_POS := Vector2(452.0, 4.0)     ## 信息栏起点
const INFO_FS := 26                      ## 信息栏字号

func _bind() -> void:
	# 方案A：信息栏保持 Label 不变；把"阵营词"拆成**独立的小 Label** 叠放，只对它上阵营色
	_labels["info"] = _mk_label("InfoBar", INFO_POS, INFO_FS, Color(1, 1, 1), false)          # 前缀：第N回合 · 阶段:X ·
	_labels["faction"] = _mk_label("FactionText", INFO_POS, INFO_FS, Color(1, 1, 1), false)   # 阵营词：N方（上阵营色）
	_labels["suf"] = _mk_label("InfoSuffix", INFO_POS, INFO_FS, Color(1, 1, 1), false)        # 后缀：· 提示
	_labels["btn"] = _mk_label("BtnText", D.BTN_MAIN + Vector2(250.0, 26.0), 34, Color(0.14, 0.14, 0.14), true)
	_labels["log"] = _mk_label("LogText", Vector2(1494.0, 674.0), 17, Color(0.86, 0.86, 0.86), false)
	# 方案B1：日志同时用一个 RichTextLabel 承载"可染色版"；旧 Label 保留但隐藏（便于回退）
	_labels["logrich"] = _mk_log_rich()
	var oldlog := overlay.get_node_or_null(NodePath("LogText"))
	if oldlog != null and oldlog is CanvasItem:
		(oldlog as CanvasItem).visible = false
	_labels["help"] = _mk_label("HelpText", Vector2(452.0, 120.0), 20, Color(1.0, 0.95, 0.75), false)


## 文本宽度测量（用于把"阵营词"小 Label 精确摆在前后缀之间，避免位置抖动）
func _measure(text: String, fsize: int) -> float:
	var f: Font = _labels["info"].get_theme_font("font")
	if f == null:
		return 0.0
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x


## 方案B1：日志改用 RichTextLabel（多行 + 行内染色）
## ⚠️ 三点必须显式设置（V-004-25/27 教训）：**显式尺寸**（Node2D 下不会自动撑开）、**清空底板**（防遮挡）、**不拦点击**
func _mk_log_rich() -> RichTextLabel:
	var r := overlay.get_node_or_null(NodePath("LogRich")) as RichTextLabel
	if r == null:
		r = RichTextLabel.new()
		r.name = "LogRich"
		r.bbcode_enabled = true
		r.scroll_active = false
		r.fit_content = false
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		overlay.add_child(r)
	r.position = Vector2(1494.0, 674.0)
	r.size = Vector2(760.0, 150.0)
	r.add_theme_font_size_override("normal_font_size", 17)
	r.add_theme_color_override("default_color", Color(0.86, 0.86, 0.86))
	return r


## 只把"阵营相关文字"包成阵营色标签（绿方 #499169 / 红方 #A84331），其余保持默认色
func _faction_bb(text: String) -> String:
	if state == null or state.anim == null:
		return text
	var out := text
	for pair in [["绿方", state.anim.turn_color(true)], ["红方", state.anim.turn_color(false)]]:
		var hex: String = (pair[1] as Color).to_html(false)
		out = out.replace(str(pair[0]), "[color=#%s]%s[/color]" % [hex, str(pair[0])])
	return out


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
	# 方案A：信息栏拆三段 —— **只给中间的"阵营词"上阵营色**（其余保持默认色，不加底色）
	var pre := "第%d回合 · 阶段:%s · " % [state.round_no, D.PHASE_NAME[state.phase]]
	var fac := "%s方" % state.cn(state.current)
	var suf := " · %s" % _hint()
	_labels["info"].text = pre
	_labels["faction"].text = fac
	_labels["suf"].text = suf
	if state.anim != null:
		# 我方 #499169 / 敌方 #A84331（结束态用半透明白提示不可操作）
		if state.winner != "":
			_labels["faction"].add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		else:
			_labels["faction"].add_theme_color_override("font_color", state.anim.turn_color(state.current == "green"))
	# 用测量把三段无缝拼接（位置随文本实际宽度变化，避免抖动）
	var w1: float = _measure(pre, INFO_FS)
	var w2: float = _measure(fac, INFO_FS)
	_labels["faction"].position = INFO_POS + Vector2(w1, 0.0)
	_labels["suf"].position = INFO_POS + Vector2(w1 + w2, 0.0)
	# 主按钮文字
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
	# 日志与帮助
	var n: int = state.log_lines.size()
	_labels["log"].text = "\n".join(state.log_lines.slice(maxi(0, n - 6), n))
	# 方案B1：把同样的日志文本交给可行内染色的版本（仍以 _labels["log"] 为唯一数据源，避免两套逻辑分叉）
	if _labels.has("logrich"):
		_labels["logrich"].text = _faction_bb(_labels["log"].text)
	_labels["help"].text = ("a500 规则速览：蜂王被击败即负 | 第12回合比蜂王血量 | 第4回合起可投降\n"
		+ "兵蜂→蜂王相邻格 · 建筑→己方领地 · 指令→任意目标(蜂王免疫)\n"
		+ "每单位每回合：1 次移动 + 1 次攻击或支援 · 反击射程外无效 · 移动会被单位阻挡") if state.help_on else ""


## 确保回合背景条存在（**只做创建**）
## ⚠️ 历史缺陷（V-004-26 定位）：btn/log/help 的赋值曾被误并入本函数，
##    导致"不调用本函数时，主按钮与日志文本全空" ✗ —— 已拆分还原到 _on_state_changed ✅
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
