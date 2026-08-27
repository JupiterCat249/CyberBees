@tool
extends GridContainer
## 棋盘节点：由 4×4 个 Button 格子节点组成（"一切皆节点"）。
## 交互完全用 Godot 内置 Button.pressed 信号 + ButtonGroup 单选，不手动处理输入/坐标。
## 边界：T4 无物理、T5 鼠标（Button 自带）、D6 上红下绿、D7 游戏观感（自绘样式盒）。

signal cell_selected(cell: Vector2i)

const COLS := 4
const ROWS := 4
const CELL_MIN := Vector2(100, 100)
const TOP := Color("#A84331")      # 红方（上半，敌方）
const BOTTOM := Color("#3B816D")   # 绿方（下半，我方）
const SELECT_BORDER := Color("#ffd166")

var _group := ButtonGroup.new()

func _ready() -> void:
	columns = COLS
	for r in ROWS:
		for c in COLS:
			add_child(_make_cell(r, c))

func _make_cell(r: int, c: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = CELL_MIN
	btn.toggle_mode = true          # 点击后保持选中
	btn.button_group = _group       # 单选：同一时刻只有一格选中
	btn.set_meta("cell", Vector2i(r, c))
	var color := _territory(r)
	btn.add_theme_stylebox_override("normal", _style(color))
	btn.add_theme_stylebox_override("hover", _style(color.lightened(0.08)))
	var sel := _style(color.lightened(0.2))
	sel.border_color = SELECT_BORDER
	sel.set_border_width_all(4)
	btn.add_theme_stylebox_override("pressed", sel)  # 选中格描边高亮
	btn.pressed.connect(_on_cell_pressed.bind(r, c))
	return btn

func _style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(6)
	return sb

func _territory(r: int) -> Color:
	# D6：上 2 行红方 / 下 2 行绿方
	return TOP if r < 2 else BOTTOM

func _on_cell_pressed(r: int, c: int) -> void:
	cell_selected.emit(Vector2i(r, c))
