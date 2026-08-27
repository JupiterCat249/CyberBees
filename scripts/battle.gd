extends Control
## 战斗场景根节点（Control 根，供 UI 控件布局）；通过信号接线（Board → GameState → UI）。
## 边界：T4 无物理、T5 鼠标（Button 自带）、D6 上红下绿、D7 游戏观感。

@onready var board: GridContainer = $Board
@onready var game_state: Node = $GameState
@onready var ui: Control = $UILayer

func _ready() -> void:
	board.cell_selected.connect(game_state.on_cell_selected)
	game_state.state_changed.connect(ui.update_status)
