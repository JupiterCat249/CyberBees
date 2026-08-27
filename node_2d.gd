@tool
extends Node2D

# 电子蜂 战斗棋盘骨架（Godot 迭代001 · 检查点1）
# 交互基础：4×4 网格坐标 + 鼠标选中高亮 + 阵营回合状态显示
# 边界：T4 无物理（纯网格/坐标）、T5 鼠标输入、D6 上8红/下8绿、D7 游戏观感

const COLS := 4
const ROWS := 4
const CELL := 100.0
const TOP := Color("#A84331")     # 红方（上半场，敌方）
const BOTTOM := Color("#3B816D")  # 绿方（下半场，我方）
const GRID := Color("#c8cdd4")
const BG := Color("#20242b")
const SELECT := Color("#ffd166")  # 选中高亮（粗描边）
const HOVER := Color(1, 1, 1, 0.18)

var selected := Vector2i(-1, -1)  # 选中的格子 (r, c)；-1 = 未选中
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
			queue_redraw()

func _cell_from_pos(pos: Vector2) -> Vector2i:
	# 棋盘原点在 (-CELL/2, -CELL/2)；格 (r,c) 位于 (c*CELL, r*CELL)
	var local := pos - Vector2(-CELL * 0.5, -CELL * 0.5)
	var c := int(local.x / CELL)
	var r := int(local.y / CELL)
	if r < 0 or r >= ROWS or c < 0 or c >= COLS:
		return Vector2i(-1, -1)
	return Vector2i(r, c)

func _territory(r: int) -> Color:
	return TOP if r < ROWS / 2 else BOTTOM

func _draw() -> void:
	# 棋盘底板
	draw_rect(Rect2(-CELL * 0.5, -CELL * 0.5, COLS * CELL, ROWS * CELL), BG, true)
	# 4×4 格（上红下绿）
	for r in ROWS:
		for c in COLS:
			var rect := Rect2(c * CELL, r * CELL, CELL, CELL)
			draw_rect(rect, _territory(r), true)
			draw_rect(rect, GRID, false, 2.0)
	# 悬停高亮
	if hover.x >= 0:
		var hrect := Rect2(hover.y * CELL, hover.x * CELL, CELL, CELL)
		draw_rect(hrect, HOVER, true)
	# 选中高亮（粗描边）
	if selected.x >= 0:
		var srect := Rect2(selected.y * CELL, selected.x * CELL, CELL, CELL)
		draw_rect(srect, SELECT, false, 5.0)
	# 状态文字（回合 + 选中格）
	var status := "回合: 绿方    点击棋盘格选中"
	if selected.x >= 0:
		status = "回合: 绿方    选中: (%d,%d)  领地: %s" % [selected.x, selected.y, ("红方" if _territory(selected.x) == TOP else "绿方")]
	draw_string(ThemeDB.fallback_font, Vector2(14, 28), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#e8e8e8"))
