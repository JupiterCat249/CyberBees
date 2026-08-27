extends Node2D
## 战斗场景根节点：通过信号接线（Board → GameState → UI），体现"一切皆节点 + 信号通信"。

@onready var board: GridContainer = $Board
@onready var game_state: Node = $GameState
@onready var ui: CanvasLayer = $UI

func _ready() -> void:
	board.cell_selected.connect(game_state.on_cell_selected)
	game_state.state_changed.connect(ui.update_status)
