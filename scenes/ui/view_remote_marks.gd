extends RefCounted
## 对端操作的视觉提示（自 arena_view 切出 —— 迭代090 · B5 第十二刀）
##
## 人 2026-10-05 的三条硬口径（随代码保留）：
##   · 文本提示条**是错误做法**（占 UI 空间、破坏布局）⇒ 一律用视觉通道；
##   · 提示**不得围绕「玩家基本信息框」**，只标具体对象；
##   · 「两个甚至三个手牌被同时选中」的根因是 %%queue_free%% 延迟释放 ⇒ 必须 %%free%% 立即释放。
##
## 判据：只**读写已存在的控件**（面板/手牌/卡）+ 建描边覆盖层，不碰规则状态。

static func flash_remote_panel(root: Node, panel: Control) -> void:
	if panel == null:
		return
	var mark := panel.get_node_or_null("RemoteMark") as Panel
	if mark == null:
		mark = Panel.new()
		mark.name = "RemoteMark"
		## ⚠️ 实测根因：`PlayerBesaInfo*` 是 **HBoxContainer** ⇒ 子节点会被容器重排（宽度归零 [0,99] ✗）。
		##   ⇒ 用 `top_level = true` 让描边**脱离父级布局**，再按面板的**全局矩形**显式定位 ✓（容器免疫 ✓）
		mark.top_level = true
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.z_index = 2
		panel.add_child(mark)
	var gr := panel.get_global_rect()
	mark.global_position = gr.position
	mark.size = gr.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(5)
	sb.border_color = Color(1, 0.72, 0.26, 1.0)   ## 暖橙：与本地选中（紫）/攻击（红）区分
	sb.set_corner_radius_all(14)
	mark.add_theme_stylebox_override("panel", sb)
	mark.modulate.a = 1.0
	mark.visible = true
	## 淡出（纯视觉、不常驻、不占位 ✓）
	var tw := root.create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(mark, "modulate:a", 0.0, 0.7)


## ⭐ ① 的视觉表达（人授权"都想办法提示" + 明确**禁用文本** ✗）：
##   对手**选中手牌**（无目标）⇒ 描**对手手牌区**（HandPanelLeft=敌方 / HandPanelRight=我方）
##   —— **零新增 UI 空间** ✓，且**无需改协议/信号**（复用现有 SIG_REMOTE_ACTION 的 cell 语义：
##   有目标/落点时 cell ≥ 0，纯选牌时 cell 为 (-1,-1) ✓）
static func flash_opponent_hand(root: Node, is_ally: bool) -> void:
	var path := "Battle/HandPanelRight" if is_ally else "Battle/HandPanelLeft"
	var panel := root.get_node_or_null(path) as Control
	if panel == null:
		return
	var mark := panel.get_node_or_null("RemoteHandMark") as Panel
	if mark == null:
		mark = Panel.new()
		mark.name = "RemoteHandMark"
		mark.top_level = true
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.z_index = 2
		panel.add_child(mark)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(4)
	sb.border_color = Color(0.55, 0.85, 1.0, 1.0)   ## 冷蓝：与"出牌/行动"的暖橙区分
	sb.set_corner_radius_all(12)
	mark.add_theme_stylebox_override("panel", sb)
	var gr := panel.get_global_rect()
	mark.global_position = gr.position
	mark.size = gr.size
	mark.modulate.a = 1.0
	mark.visible = true
	var tw := root.create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(mark, "modulate:a", 0.0, 0.6)


## ⭐ ① 修正（人 2026-10-05）：在**对手手牌区里标记具体那张卡**（不再描整片 HandPanel ✗），
##   且**常驻**（不做 Tween 淡出 ✗）。定位方式＝按**卡名**在对手手牌里找下标
##   （接收端持有对手手牌 ✓ ⇒ 无需改协议 ✓）。清除时机：text 无卡名（对端取消选中）✓
static func mark_opponent_hand(container: Control, engine, side: int, text: String) -> void:
	if container == null:
		return
	for ch in container.get_children():
		var old := ch.get_node_or_null("RemoteHandMark") as Panel
		if old != null:
			## ⚠️ 人 2026-10-05 反馈"两个甚至三个以上手牌被同时选中"：根因是这里用了 `queue_free()`
			##   （**延迟释放** ✗）⇒ 连续多个 `sel` 到达时旧标记仍挂在树上 ⇒ 多个同时可见 ⟹ 改 `free()` 立即释放 ✓
			old.free()
	if text == "" or engine == null or engine.state == null:
		return
	var nm := text.replace("选中手牌 ", "")
	var hand: Array = engine.state.sides[side]["hand"]
	var idx := -1
	for i in hand.size():
		if String(hand[i].display_name) == nm:
			idx = i
			break
	if idx < 0 or idx >= container.get_child_count():
		return
	var card := container.get_child(idx) as Control
	if card == null:
		return
	var mk := Panel.new()
	mk.name = "RemoteHandMark"
	mk.top_level = true
	mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mk.z_index = 3
	card.add_child(mk)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(4)
	sb.border_color = Color(0.55, 0.85, 1.0, 1.0)   ## 冷蓝：与"出牌/行动"的暖橙区分
	sb.set_corner_radius_all(10)
	mk.add_theme_stylebox_override("panel", sb)
	var gr := card.get_global_rect()
	mk.global_position = gr.position
	mk.size = gr.size
