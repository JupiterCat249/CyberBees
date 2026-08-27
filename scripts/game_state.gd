extends Node
## 游戏状态节点：持有当前回合与选中格；收 Board 的 cell_selected 信号，更新后发 state_changed。
## 后续（迭代001 检查点2/3）承载单位/手牌/费用/回合等的状态与规则。

signal state_changed(selected_cell: Vector2i, current_player: String)

var current_player := "绿方"
var selected_cell := Vector2i(-1, -1)

func on_cell_selected(cell: Vector2i) -> void:
	selected_cell = cell
	state_changed.emit(selected_cell, current_player)
