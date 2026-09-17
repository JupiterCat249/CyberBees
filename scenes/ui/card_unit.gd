extends Control
## 地图单位卡（250×250）：节点负责外观，脚本只做**数据绑定**与点击信号
signal unit_pressed(unit_id: String)

var unit_id := ""

func bind(data: Dictionary) -> void:
	unit_id = String(data.get("id", ""))
	$Cost.text = str(data.get("cost", 0))
	$AttrLA/Value.text = str(data.get("atk", 0))
	$AttrLB/Value.text = str(data.get("hp", 0))
	$AttrLC/Value.text = str(data.get("move", 0))
	$AttrLD/Value.text = str(data.get("range", 0))
	# 阵营色：绿=我 / 红=敌（策划案 §五 卡牌侧边）
	var side_color: Color = Color("#3B816D") if bool(data.get("mine", true)) else Color("#A84331")
	for n in [$SideLeft, $SideRight]:
		var sb: StyleBoxFlat = (n.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
		sb.bg_color = side_color
		n.add_theme_stylebox_override("panel", sb)
	# 卡牌类型底色（策划案 §五 卡牌类型）
	var type_color := {"unit": "#FFFFFF", "queen": "#FFD07E", "building": "#DDC29B", "order": "#D9D9D9"}
	var sb2: StyleBoxFlat = ($Body.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	sb2.bg_color = Color(type_color.get(String(data.get("type", "unit")), "#FFFFFF"))
	$Body.add_theme_stylebox_override("panel", sb2)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		unit_pressed.emit(unit_id)
