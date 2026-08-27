extends Control
## UI 层：监听全局 GameState(Autoload) 的 state_changed 信号，更新 回合/阶段/费用/手牌/选中 状态标签。

func update_status() -> void:
	var label: Label = $StatusLabel
	var phase_name: String = ["回费", "部署", "行动"][GameState.phase]
	var sel_info := ""
	if GameState.selected_unit_id >= 0:
		var u: Dictionary = GameState.units[GameState.selected_unit_id]
		sel_info = "  选中#%d(%d,%d)HP=%d" % [GameState.selected_unit_id, GameState.selected_cell.x, GameState.selected_cell.y, u["hp"]]
	label.text = "回合%d [%s] 费用%d/%d 手牌%d%s" % [GameState.turn_number, phase_name, GameState.cost, GameState.MAX_COST, GameState.hand.size(), sel_info]
