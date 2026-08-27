extends Node2D

const COLS := 4
const ROWS := 4
const CELL := 100
const TOP := Color("#A84331")  # 红方（上半场）
const BOTTOM := Color("#3B816D")  # 绿方（下半场）
const GRID := Color("#c8cdd4")
const BG := Color("#20242b")

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-CELL * 0.5, -CELL * 0.5, COLS * CELL, ROWS * CELL), BG, true)
	for r in ROWS:
		for c in COLS:
			var rect := Rect2(c * CELL, r * CELL, CELL, CELL)
			var color := TOP if r < ROWS / 2 else BOTTOM
			draw_rect(rect, color, true)
			draw_rect(rect, GRID, false, 2.0)
