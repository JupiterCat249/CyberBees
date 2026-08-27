extends Control
## UI 层：监听 state_changed 更新状态标签。

func update_status(selected_cell: Vector2i, current_player: String) -> void:
	var label: Label = $StatusLabel
	if selected_cell.x >= 0:
		label.text = "回合: %s    选中: (%d,%d)  领地: %s" % [current_player, selected_cell.x, selected_cell.y, _territory_text(selected_cell.x)]
	else:
		label.text = "回合: %s    点击棋盘格选中" % current_player

func _territory_text(r: int) -> String:
	return "红方" if r < 2 else "绿方"
