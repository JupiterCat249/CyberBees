extends Control
## 地图单位卡（250×250）：节点负责外观，脚本只做**数据绑定**与点击信号
##
## ⚠️ 节点路径以 **card_unit.tscn 的真实层级**为准（曾误写成 `$Cost` / `$AttrLA`，
##    实际是 `CostPlate/Cost` / `Attr_Attack/Value` … → 运行时找不到节点）。
##    此处统一用 `_n(path)` 取节点并**判空**，缺节点只跳过、不崩。
##
## 绑定数据（视觉层字典，不含规则判断）：
##   id / cost / atk / hp / move / range / mine / type
##   mine = true → 我方绿(#3B816D) / false → 敌方红(#A84331)（策划案 §五 卡牌侧边）
##   type → 卡牌类型底色：unit #FFFFFF / queen #FFD07E / building #DDC29B / order #D9D9D9

signal unit_pressed(unit_id: String)

const SIDE_ALLY := Color("#3B816D")
const SIDE_ENEMY := Color("#A84331")
const TYPE_COLOR := {
	"unit": "#FFFFFF", "queen": "#FFD07E", "building": "#DDC29B", "order": "#D9D9D9",
}

var unit_id := ""


func bind(data: Dictionary) -> void:
	unit_id = String(data.get("id", ""))
	_n("CostPlate/Cost", "text", str(data.get("cost", 0)))
	_n("Attr_Attack/Value", "text", str(data.get("atk", 0)))
	_n("Attr_Health/Value", "text", str(data.get("hp", 0)))
	_n("Attr_Speed/Value", "text", str(data.get("move", 0)))
	_n("Attr_Range/Value", "text", str(data.get("range", 0)))
	# 阵营色（侧边栏）
	var side_color: Color = SIDE_ALLY if bool(data.get("mine", true)) else SIDE_ENEMY
	_tint("SideLeft", side_color)
	_tint("SideRight", side_color)
	# 卡牌类型底色（本体）
	_tint("Body", Color(TYPE_COLOR.get(String(data.get("type", "unit")), "#FFFFFF")))


## 取节点并设属性（缺节点则跳过，不崩）
func _n(path: String, prop: String, value) -> void:
	var node := get_node_or_null(path)
	if node != null:
		node.set(prop, value)


## 给 Panel 换底色（复制 StyleBoxFlat，避免改到共享资源）
func _tint(path: String, color: Color) -> void:
	var node := get_node_or_null(path) as Control
	if node == null:
		return
	var sb := node.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	sb = sb.duplicate()
	sb.bg_color = color
	node.add_theme_stylebox_override("panel", sb)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		unit_pressed.emit(unit_id)
