extends Control
## ============================================================
## 单位卡（250×250）—— 场景格式 UI 的**自包含组件**
##
## 设计原则（迭代037 重构）：
##   · UI 全部由**节点**构成（在 `ui_unit_card.tscn` 里可直接编辑，无需脚本）
##   · 本脚本**只做两件事**：① 对外发信号 ② 把数据绑定到已存在的节点
##   · 不创建节点、不画图 —— 一切视觉都在场景文件里
##
## 用法：实例化 → 连 `card_pressed(id)` → 调 `bind(data)`
## ============================================================

## 卡片被点击（携带卡片自身 id，由使用方设置）
signal card_pressed(id: int)
## 卡片数据被更新（绑定后发出，便于上层联动）
signal card_changed(id: int)

@export var card_id: int = -1

@onready var _bg: Panel = $Bg
@onready var _rail_left: Panel = $RailLeft
@onready var _rail_right: Panel = $RailRight
@onready var _cost_label: Label = $CostLabel
@onready var _type_label: Label = $TypeLabel
@onready var _art: TextureRect = $Art

## 属性格：[[数值Label, 图标TextureRect], ...] 共 4 格（左列2 / 右列2）
@onready var _cells: Array = [
	{"val": $CellL1/ValL1, "icon": $CellR1/IconR1},
	{"val": $CellL2/ValL2, "icon": $CellR2/IconR2},
]


## 绑定卡片数据（类型色 / 阵营色 / 费用 / 类型名 / 立绘 / 4 项属性）
## data = {base: Color, rail: Color, cost: int, kind: String, art: Texture2D,
##         attrs: [{v: int, icon: Texture2D}, ...] }
func bind(data: Dictionary) -> void:
	_bg.add_theme_stylebox_override("panel", _sb(data.get("base", Color.WHITE), 10.0))
	_rail_left.add_theme_stylebox_override("panel", _sb(data.get("rail", Color("3B816D")), 10.0))
	_rail_right.add_theme_stylebox_override("panel", _sb(data.get("rail", Color("3B816D")), 10.0))
	_cost_label.text = str(data.get("cost", 0))
	_type_label.text = str(data.get("kind", ""))
	var art: Texture2D = data.get("art")
	if art != null:
		_art.texture = art
	var attrs: Array = data.get("attrs", [])
	for i in _cells.size():
		if i >= attrs.size():
			continue
		var a: Dictionary = attrs[i]
		var cell: Dictionary = _cells[i]
		var v: int = int(a.get("v", 0))
		(cell["val"] as Label).text = str(v)
		(cell["val"] as Label).visible = v != 0
		(cell["icon"] as TextureRect).texture = a.get("icon")
	card_changed.emit(card_id)


## 便捷：只改顶部费用区状态（§3.3 默认 50% / 可行动 100% / 支援可用橙）
func set_cost_state(state: String) -> void:
	var c := Color(1, 1, 1, 0.5)
	if state == "ready":
		c = Color(1, 1, 1, 1.0)
	elif state == "support":
		c = Color("FFA300")
	($CostPlate as Panel).add_theme_stylebox_override("panel", _sb(c, 0.0))


func _sb(c: Color, radius: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	var r := int(radius)
	s.corner_radius_top_left = r
	s.corner_radius_top_right = r
	s.corner_radius_bottom_left = r
	s.corner_radius_bottom_right = r
	return s


## ⚠️ 根节点需在场景里设 mouse_filter = 0（STOP），否则收不到 _gui_input
func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		card_pressed.emit(card_id)
