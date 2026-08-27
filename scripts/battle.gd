extends Control
## 战斗场景根节点（Control）：接线 棋盘点击 → 全局 GameState(Autoload) 的交互状态机，监听其信号生成/更新单位与 UI。
## 边界：T4 无物理(网格)、T5 鼠标(Button)、D1 蜂主题、D6 4×4。

@onready var board: GridContainer = $Board
@onready var ui: Control = $UILayer
@onready var units_layer: Node2D = $UnitsLayer

var _unit_nodes := {}   # unit_id -> BeeUnit

func _ready() -> void:
	board.cell_selected.connect(_on_cell_selected)
	GameState.unit_deployed.connect(_on_unit_deployed)
	GameState.unit_moved.connect(_on_unit_moved)
	GameState.unit_damaged.connect(_on_unit_damaged)
	GameState.state_changed.connect(ui.update_status)
	ui.update_status()

func _on_cell_selected(cell: Vector2i) -> void:
	if GameState.mode == GameState.IMode.DEPLOY:
		GameState.confirm_place(cell)
	elif GameState.mode == GameState.IMode.UNIT_ACTION:
		if cell in GameState.move_range:
			GameState.confirm_move(cell)
		elif GameState.unit_at(cell) >= 0:
			GameState.confirm_attack(cell)
		else:
			GameState.cancel()
	else:
		# IDLE：点己方未行动单位→选中；否则取消
		if not GameState.select_unit(cell):
			GameState.cancel()

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
