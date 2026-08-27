extends Control
## 战斗场景根节点（Control）：接线 棋盘点击 → 全局 GameState(Autoload)，监听其信号生成/更新单位与 UI。
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
	ui.update_status()   # 初始化状态标签（Autoload 在场景_ready前已发 start_turn 的 state_changed）

func _on_cell_selected(cell: Vector2i) -> void:
	var id: int = GameState.unit_at(cell)
	if id >= 0:
		# 点在已有单位：若处于移动态且在范围则移动，否则选中
		if GameState.selected_unit_id >= 0 and cell in GameState.move_range:
			GameState.try_move(GameState.selected_cell, cell)
		else:
			GameState.select(cell)
	elif GameState.selected_unit_id >= 0 and cell in GameState.move_range:
		# 已选单位 + 点在可移动空格 → 移动
		GameState.try_move(GameState.selected_cell, cell)
	elif cell.y >= 2 and GameState.is_cell_free(cell):
		# 下方(绿方领地)空格 → 部署一个绿色兵蜂（演示部署）
		GameState.deploy_unit(cell, GameState.GREEN)
	else:
		GameState.select(cell)

func _on_unit_deployed(id: int, cell: Vector2i, faction: String) -> void:
	var u: BeeUnit = BeeUnit.new()
	u.setup(id, faction, cell, GameState.DEF_ATK, GameState.DEF_HP)
	_unit_nodes[id] = u
	units_layer.add_child(u)

func _on_unit_moved(id: int, cell: Vector2i) -> void:
	if _unit_nodes.has(id):
		_unit_nodes[id].move_to(cell)


func _on_unit_damaged(id: int, hp: int) -> void:
	if _unit_nodes.has(id):
		_unit_nodes[id].set_hp(hp)
