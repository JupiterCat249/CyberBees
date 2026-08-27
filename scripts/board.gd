@tool
extends GridContainer
## 棋盘容器节点：由 16 个显式的 BoardCell（格子节点）子节点组成（"一切皆节点"）。
## 本节点只负责：分配共享 ButtonGroup（单选）+ 汇总各格子的 cell_selected 信号。
## 边界：T4 无物理、T5 鼠标（Button 自带）、D6 上红下绿、D7 自绘样式盒。

signal cell_selected(cell: Vector2i)

const COLS := 4

var _group := ButtonGroup.new()

func _ready() -> void:
	columns = COLS
	for child in get_children():
		if child is BoardCell:
			var cell: BoardCell = child
			cell.button_group = _group
			cell.cell_selected.connect(_on_cell_selected)

func _on_cell_selected(cell: Vector2i) -> void:
	cell_selected.emit(cell)
