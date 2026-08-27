@tool
extends Node2D
## 棋盘节点：绘制 4×4 网格 + 处理鼠标输入，选中时发 cell_selected 信号。
## 边界：T4 无物理（纯坐标）、T5 鼠标输入、D6 上红下绿、D7 游戏观感（自绘）。

signal cell_selected(cell: Vector2i)

const COLS := 4
const ROWS := 4
const CELL := 100.0
const TOP := Color("#A84331")     # 红方（上半，敌方）
const BOTTOM := Color("#3B816D")  # 绿方（下半，我方）
const GRID := Color("#c8cdd4")
const BG := Color("#20242b")
const SELECT := Color("#ffd166")
const HOVER := Color(1, 1, 1, 0.18)

var selected := Vector2i(-1, -1)
var hover := Vector2i(-1, -1)

func _ready() -> void:
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover = _cell_from_pos(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _cell_from_pos(event.position)
		if cell.x >= 0:
			selected = cell
			cell_selected.emit(cell)
			queue_redraw()

func _cell_from_pos(pos: Vector2) -> Vector2i:
	var local := pos - Vector2(-CELL * 0.5, -CELL * 0.5)
	var c := int(local.x / CELL)
	var r := int(local.y / CELL)
	if r < 0 or r >= ROWS or c < 0 or c >= COLS:
		return Vector2i(-1, -1)
	return Vector2i(r, c)

func _territory(r: int) -> Color:
	return TOP if r < ROWS / 2 else BOTTOM

func _draw() -> void:
	draw_rect(Rect2(-CELL * 0.5, -CELL * 0.5, COLS * CELL, ROWS * CELL), BG, true)
	for r in ROWS:
		for c in COLS:
			var rect := Rect2(c * CELL, r * CELL, CELL, CELL)
			draw_rect(rect, _territory(r), true)
			draw_rect(rect, GRID, false, 2.0)
	if hover.x >= 0:
		draw_rect(Rect2(hover.y * CELL, hover.x * CELL, CELL, CELL), HOVER, true)
	if selected.x >= 0:
		draw_rect(Rect2(selected.y * CELL, selected.x * CELL, CELL, CELL), SELECT, false, 5.0)
