extends Control
## 结算浮层（迭代063 · 人 2026-09-23 裁定：**战斗场景内浮层**，保留战场画面作背景）
## ---------------------------------------------------------------------------
## ⚠️ 在**代码里构建**（不往 battle_scene.tscn 加节点 —— 迭代060 实测：编辑器持有旧内存副本，
##    node_create + scene_save 会把整个场景回退）；层高 z_index=200，出招栏在 HUD 内不受影响
## 信号：rematch_pressed（再来一局 → 回大厅并自动重新入队）/ lobby_pressed（返回大厅）
## ---------------------------------------------------------------------------
signal rematch_pressed
signal lobby_pressed

var title_text := ""
var reason_text := ""
var lines: Array[String] = []


## 在 add_child 之前调用：填内容
func setup(p_title: String, p_reason: String, p_lines: Array) -> void:
	title_text = p_title
	reason_text = p_reason
	lines.clear()
	for l in p_lines:
		lines.append(String(l))


func _ready() -> void:
	## ⚠️ 挂在 CanvasLayer 下时锚点**没有参照**（实测 0×0）→ 一律**显式给视口尺寸**
	var vs := get_viewport_rect().size
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = vs
	position = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.position = Vector2.ZERO
	dim.size = vs
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var cc := CenterContainer.new()
	cc.position = Vector2.ZERO
	cc.size = vs
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(640, 0)
	cc.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)
	var t := Label.new()
	t.text = title_text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 34)
	vb.add_child(t)
	var r := Label.new()
	r.text = reason_text
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(r)
	for l in lines:
		var lb := Label.new()
		lb.text = l
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(lb)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)
	var b1 := Button.new()
	b1.text = "再来一局"
	b1.pressed.connect(func() -> void: rematch_pressed.emit())
	hb.add_child(b1)
	var b2 := Button.new()
	b2.text = "返回大厅"
	b2.pressed.connect(func() -> void: lobby_pressed.emit())
	hb.add_child(b2)
	print("[RESULT] %s（%s）" % [title_text, reason_text])
