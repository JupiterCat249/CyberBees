class_name BeeUnit
extends Node2D
## 单位节点：每个单位 = 一个节点（一切皆节点）。
## 视觉由 ColorRect(阵营色) + Label(HP) 节点组成；位置按格子坐标由 Battle 摆放。

var unit_id := 0
var faction := "green"
var cell := Vector2i(-1, -1)
var atk := 2
var hp := 4

const GREEN_COL := Color("#3B816D")
const RED_COL := Color("#A84331")
const CELL_PX := 100.0
const OFFSET_Y := 60.0   # 棋盘 GridContainer 的 position.y，用于对齐格子

var _rect: ColorRect
var _label: Label

func _ready() -> void:
	_rect = ColorRect.new()
	_rect.name = "UnitRect"
	_rect.size = Vector2(CELL_PX * 0.7, CELL_PX * 0.7)
	_rect.position = Vector2(CELL_PX * 0.15, CELL_PX * 0.15)
	add_child(_rect)

	_label = Label.new()
	_label.name = "UnitLabel"
	_label.text = "蜂"
	_label.add_theme_font_size_override("font_size", 26)
	_label.position = Vector2(CELL_PX * 0.32, CELL_PX * 0.30)
	add_child(_label)

	_apply()


func setup(id: int, f: String, c: Vector2i, a: int, h: int) -> void:
	unit_id = id
	faction = f
	cell = c
	atk = a
	hp = h
	if is_inside_tree():
		_apply()


func move_to(c: Vector2i) -> void:
	cell = c
	if is_inside_tree():
		_apply()


func set_hp(h: int) -> void:
	hp = h
	if is_inside_tree():
		_apply()


func _apply() -> void:
	if _rect == null:
		return
	_rect.color = GREEN_COL if faction == "green" else RED_COL
	_label.text = str(hp)
	position = Vector2(cell.y * CELL_PX, OFFSET_Y + cell.x * CELL_PX)
