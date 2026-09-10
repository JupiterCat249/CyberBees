extends Node2D
## ============================================================
## BattleDetailView —— 详情视图
##   ① 左下卡牌详情块：把"当前查看的卡"用框架 card_auto 放大 1.2 倍渲染
##   ② 技能详情显示区：编辑器里建好的 Overlay/SkillBox 三个 Label，代码只写文本
##   ③ 状态数值：框架 shader 已画好 4 个图标（剑/盾/速度/准星），这里补旁边的数字
##   只读 BattleState，不做规则判断。
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

var holder: Node2D = null
var overlay: Node2D = null
var state: Node = null

var _detail_node: Node2D = null
var _labels := {}


func setup(h: Node2D, ov: Node2D, st: Node) -> void:
	holder = h
	overlay = ov
	state = st
	_detail_node = Node2D.new()
	_detail_node.name = "Detail"
	holder.add_child(_detail_node)
	_bind_labels()
	state.state_changed.connect(_on_state_changed)


func _on_state_changed() -> void:
	render_detail()
	update_skill_box()
	update_stats()


# ---------------- ① 卡牌详情块 ----------------
func render_detail() -> void:
	for n in _detail_node.get_children():
		n.queue_free()
	var d: Dictionary = state.current_detail_card()
	if d.is_empty():
		return
	var node := D.make_card(d, D.DETAIL_SCALE)
	node.position = D.DETAIL_POS
	_detail_node.add_child(node)


# ---------------- ② 技能详情显示区 ----------------
func _bind_labels() -> void:
	# 技能区：节点与样式都在编辑器（Overlay/SkillBox/*），代码只取用
	for k in ["Title", "Desc", "Tags"]:
		_labels["sk_" + str(k).to_lower()] = overlay.get_node_or_null(
			NodePath("SkillBox/Skill" + str(k))) as Label
	# 状态数值：位置/字号/颜色沿用代码设定（框架 shader 已画图标）
	_labels["st0"] = _stat_label("StatAtk", D.STAT_Y0)
	_labels["st1"] = _stat_label("StatDef", D.STAT_Y0 + D.STAT_DY)
	_labels["st2"] = _stat_label("StatSpd", D.STAT_Y0 + D.STAT_DY * 2)
	_labels["st3"] = _stat_label("StatRange", D.STAT_Y0 + D.STAT_DY * 3)


func _stat_label(node_name: String, y: float) -> Label:
	var l := overlay.get_node_or_null(NodePath(node_name)) as Label
	if l == null:
		l = Label.new()
		l.name = node_name
		overlay.add_child(l)
	l.position = Vector2(D.STAT_X + 26.0, y - 16.0)
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	return l


func update_skill_box() -> void:
	var d: Dictionary = state.current_detail_card()
	for key in ["sk_title", "sk_desc", "sk_tags"]:
		var l := _labels.get(key, null) as Label
		if l == null:
			continue
		if d.is_empty():
			l.text = ""
		elif key == "sk_title":
			l.text = str(d.get("sk", "（无技能）"))
		elif key == "sk_desc":
			l.text = str(d.get("sdesc", ""))
		else:
			l.text = "关键词：" + str(d.get("stags", "—"))


# ---------------- ③ 状态数值（当前查看对象；无则当前方蜂王） ----------------
func update_stats() -> void:
	var sid: int = state.focus_unit_id()
	var vals := ["-", "-", "-", "-"]
	if sid >= 0:
		vals = [str(state.final_atk(sid)), str(state.final_reduce(sid)),
			str(state.final_spd(sid)), str(state.final_range(sid))]
	for i in 4:
		var l := _labels.get("st" + str(i), null) as Label
		if l != null:
			l.text = vals[i]
