@tool
extends GridContainer
## 棋盘容器节点：由 16 个显式 BoardCell(Button) 格子节点组成；仅做 ButtonGroup 单选 + 汇总信号 + 范围高亮。

signal cell_selected(cell: Vector2i)

const COLS := 4

var _group := ButtonGroup.new()

func _ready() -> void:
	columns = COLS
	for child in get_children():
		if child is BoardCell:
			child.button_group = _group
			child.cell_selected.connect(_on_cell_selected)

func _on_cell_selected(cell: Vector2i) -> void:
	cell_selected.emit(cell)

## 高亮 可移动/可攻击/选中 格子（由 Battle 在 ranges_changed 时调用）
func set_ranges(move_cells: Array, attack_cells: Array, selected_cell: Vector2i) -> void:
	for child in get_children():
		if child is BoardCell:
			child.set_range("")
	for cell in move_cells:
		var c := _cell_at(cell)
		if c:
			c.set_range("move")
	for cell in attack_cells:
		var c := _cell_at(cell)
		if c:
			c.set_range("attack")
	var sc := _cell_at(selected_cell)
	if sc:
		sc.set_range("selected")

func _cell_at(cell: Vector2i) -> BoardCell:
	for child in get_children():
		if child is BoardCell and child.cell == cell:
			return child
	return null
