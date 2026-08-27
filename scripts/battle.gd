extends Control
## 战斗场景根节点（Control）：接线 棋盘点击/结束回合按钮 → 全局 GameState(Autoload) 状态机；
## 监听其信号刷新 单位节点/范围高亮/UI/胜负。输入交给 Control 控件，核心是事件驱动。

@onready var board: GridContainer = $Board
@onready var ui: Control = $UILayer
@onready var units_layer: Node2D = $UnitsLayer
@onready var end_turn_btn: Button = $UILayer/EndTurnButton

var _unit_nodes := {}   # unit_id -> BeeUnit

func _ready() -> void:
	board.cell_selected.connect(_on_cell_selected)
	end_turn_btn.pressed.connect(_on_end_turn)
	GameState.unit_deployed.connect(_on_unit_deployed)
	GameState.unit_moved.connect(_on_unit_moved)
	GameState.unit_damaged.connect(_on_unit_damaged)
	GameState.unit_died.connect(_on_unit_died)
	GameState.ranges_changed.connect(_on_ranges_changed)
	GameState.state_changed.connect(ui.update_status)
	GameState.game_over.connect(_on_game_over)
	ui.update_status()

func _on_cell_selected(cell: Vector2i) -> void:
	if GameState.mode == GameState.IMode.DEPLOY:
		GameState.confirm_place(cell)
	elif GameState.mode == GameState.IMode.UNIT_ACTION:
		if cell in GameState.move_range:
			GameState.confirm_move(cell)
		elif cell in GameState.attack_range:
			GameState.confirm_attack(cell)
		else:
			GameState.cancel()
	else:
		if not GameState.select_unit(cell):
			GameState.cancel()

func _on_end_turn() -> void:
	GameState.advance_phase()

func _on_ranges_changed() -> void:
	board.set_ranges(GameState.move_range, GameState.attack_range, GameState.selected_cell)

func _on_unit_deployed(id: int, cell: Vector2i, faction: String) -> void:
	var u := BeeUnit.new()
	u.setup(id, faction, cell, GameState.DEF_ATK, GameState.DEF_HP)
	_unit_nodes[id] = u
	units_layer.add_child(u)

func _on_unit_moved(id: int, cell: Vector2i) -> void:
	if _unit_nodes.has(id):
		_unit_nodes[id].move_to(cell)

func _on_unit_damaged(id: int, hp: int) -> void:
	if _unit_nodes.has(id):
		_unit_nodes[id].set_hp(hp)

func _on_unit_died(id: int) -> void:
	if _unit_nodes.has(id):
		_unit_nodes[id].queue_free()
		_unit_nodes.erase(id)

func _on_game_over(winner: String) -> void:
	ui.show_game_over(winner)
