@tool
class_name BoardCell
extends Button
## 棋盘格子节点：extends Button（引擎自带 UI/输入组件）。
## 每个格子 = 一个场景节点；交互用 Button.pressed 信号，发 cell_selected。
## 边界：T4 无物理、T5 鼠标（Button 自带）、D6 上2行红/下2行绿、D7 自绘样式盒。

signal cell_selected(cell: Vector2i)

@export var cell := Vector2i(-1, -1)  # 格坐标 (row, col)；row<2 红方

const TOP := Color("#A84331")
const BOTTOM := Color("#3B816D")
const SELECT_BORDER := Color("#ffd166")

func _ready() -> void:
	custom_minimum_size = Vector2(100, 100)
	toggle_mode = true          # 点击后保持选中（配合 ButtonGroup 单选）
	_apply_style()
	pressed.connect(_on_pressed)

func _apply_style() -> void:
	var color := _territory()
	add_theme_stylebox_override("normal", _style(color))
	add_theme_stylebox_override("hover", _style(color.lightened(0.08)))
	var sel := _style(color.lightened(0.2))
	sel.border_color = SELECT_BORDER
	sel.set_border_width_all(4)
	add_theme_stylebox_override("pressed", sel)  # 选中格描边高亮

func _style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(6)
	return sb

func _territory() -> Color:
	# D6：上 2 行（cell.x<2）红方 / 下 2 行绿方
	return TOP if cell.x < 2 else BOTTOM

func _on_pressed() -> void:
	cell_selected.emit(cell)
