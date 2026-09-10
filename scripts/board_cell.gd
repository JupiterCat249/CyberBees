##@tool
class_name BoardCell
extends Button
## 棋盘格子节点：extends Button（引擎自带输入组件）；pressed→cell_selected 信号。
## set_range(kind) 用 modulate 淡淡高亮（移动/攻击/选中），不清不选中时还原。

signal cell_selected(cell: Vector2i)

@export var cell := Vector2i(-1, -1)

const TOP := Color("#A84331")
const BOTTOM := Color("#3B816D")
const SELECT_BORDER := Color("#ffd166")

func _ready() -> void:
	custom_minimum_size = Vector2(100, 100)
	toggle_mode = true
	_apply_style()
	pressed.connect(_on_pressed)

func _apply_style() -> void:
	var color := _territory()
	add_theme_stylebox_override("normal", _style(color))
	add_theme_stylebox_override("hover", _style(color.lightened(0.08)))
	var sel := _style(color.lightened(0.2))
	sel.border_color = SELECT_BORDER
	sel.set_border_width_all(4)
	add_theme_stylebox_override("pressed", sel)

func _style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(6)
	return sb

func _territory() -> Color:
	return TOP if cell.x < 2 else BOTTOM

func set_range(kind: String) -> void:
	match kind:
		"move":     modulate = Color(0.8, 1.25, 0.95)
		"attack":   modulate = Color(1.3, 0.9, 0.85)
		"selected": modulate = Color(1.25, 1.15, 0.8)
		_:          modulate = Color.WHITE

func _on_pressed() -> void:
	cell_selected.emit(cell)
