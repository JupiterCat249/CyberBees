extends Control
## UI 层：监听全局 GameState(Autoload) 的 state_changed 信号，更新状态标签。

func update_status() -> void:
	var label: Label = $StatusLabel
	var player := GameState.current_player
	if GameState.selected_unit_id >= 0:
		var u: Dictionary = GameState.units[GameState.selected_unit_id]
		label.text = "回合: %s   选中单位#%d (%d,%d) HP=%d  可移动范围≥%d格" % [
			player, GameState.selected_unit_id, GameState.selected_cell.x, GameState.selected_cell.y, u["hp"], GameState.DEF_MOVE]
	else:
		label.text = "回合: %s   (绿方空格=部署兵蜂; 点单位=选中; 再点高亮格=移动)" % player
