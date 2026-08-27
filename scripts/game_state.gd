extends Node
## 全局游戏状态单例（Autoload）：战斗状态 + 事件总线。
## 覆盖：节点化棋盘 / 网格部署移动攻击 / 费用回合阶段手牌 (检查点1-3)。
## 交互状态机（IMode）：IDLE→(点卡)DEPLOY→confirm_place；IDLE→(点己方单位)UNIT_ACTION→confirm_move/confirm_attack。
## 边界：T4 无物理(曼哈顿)、T5 鼠标、T8 费用上限10/第7回合+2、D6 4×4、D1 蜂。

signal unit_deployed(unit_id: int, cell: Vector2i, faction: String)
signal unit_moved(unit_id: int, cell: Vector2i)
signal unit_damaged(unit_id: int, hp: int)
signal selection_changed(selected_cell: Vector2i)
signal phase_changed(phase: int, turn: int)
signal cost_changed(cost: int)
signal state_changed

enum Phase { REFUND, DEPLOY, ACTION }
enum IMode { IDLE, DEPLOY, UNIT_ACTION }

const BOARD_ROWS := 4
const BOARD_COLS := 4
const GREEN := "green"
const RED := "red"
const DEF_ATK := 2
const DEF_HP := 4
const DEF_MOVE := 2
const DEF_ATK_RANGE := 1
const MAX_COST := 10
const HAND_SIZE := 4
const BASE_REFUND := 2
const EXTRA_REFUND_7 := 2

var current_player := GREEN
var next_id := 1
var turn_number := 1
var phase: Phase = Phase.REFUND
var cost := 0
var hand: Array = []

var mode: IMode = IMode.IDLE
var selected_card_index := -1
var selected_unit_id := -1
var selected_cell := Vector2i(-1, -1)
var move_range: Array[Vector2i] = []
var acted_unit_ids := {}   # 本回合已行动过的单位

var units := {}


func _ready() -> void:
	start_turn()


# ---------- 回合 / 费用 / 阶段 ----------

func start_turn() -> void:
	var refund: int = BASE_REFUND + (EXTRA_REFUND_7 if turn_number >= 7 else 0)
	cost = maxi(0, mini(cost + refund, MAX_COST))
	phase = Phase.REFUND
	acted_unit_ids = {}
	_clear_interaction()
	draw_to_hand(HAND_SIZE)
	phase_changed.emit(phase, turn_number)
	cost_changed.emit(cost)
	state_changed.emit()


func advance_phase() -> void:
	if phase == Phase.REFUND:
		phase = Phase.DEPLOY
	elif phase == Phase.DEPLOY:
		phase = Phase.ACTION
	elif phase == Phase.ACTION:
		end_turn()
		return
	phase_changed.emit(phase, turn_number)
	state_changed.emit()


func end_turn() -> void:
	turn_number += 1
	current_player = RED if current_player == GREEN else GREEN
	start_turn()


func can_afford(card_cost: int) -> bool:
	return cost >= card_cost


func spend(card_cost: int) -> bool:
	if not can_afford(card_cost):
		return false
	cost -= card_cost
	cost_changed.emit(cost)
	return true


func draw_to_hand(n: int) -> void:
	while hand.size() < n:
		hand.append(_random_card())


func _random_card() -> Dictionary:
	var r := randf()
	if r < 0.6:
		return {"type": "unit_bee", "name": "兵蜂", "cost": 1}
	else:
		return {"type": "command_burn", "name": "指令·灼烧", "cost": 1}


# ---------- 交互状态机（检查点：实机交互按设计） ----------

func select_card(index: int) -> bool:
	if index < 0 or index >= hand.size():
		return false
	var card: Dictionary = hand[index]
	if card["type"] != "unit_bee":
		return false
	if phase == Phase.REFUND:
		return false
	selected_card_index = index
	mode = IMode.DEPLOY
	state_changed.emit()
	return true


func select_unit(cell: Vector2i) -> bool:
	var id: int = unit_at(cell)
	if id < 0:
		return false
	if units[id]["faction"] != current_player:
		return false
	if acted_unit_ids.has(id):
		return false
	selected_unit_id = id
	selected_cell = cell
	move_range = _compute_move_range(cell, units[id]["move_range"])
	mode = IMode.UNIT_ACTION
	state_changed.emit()
	return true


func confirm_place(cell: Vector2i) -> bool:
	if mode != IMode.DEPLOY or selected_card_index < 0:
		return false
	var card: Dictionary = hand[selected_card_index]
	if not is_cell_free(cell) or cell.y < 2:            # 兵蜂必须部署在绿方领地(下半)
		_clear_interaction()
		return false
	if not spend(card["cost"]):
		return false
	var id := deploy_unit(cell, GREEN)
	hand.remove_at(selected_card_index)
	_clear_interaction()
	unit_deployed.emit(id, cell, GREEN)
	state_changed.emit()
	return true


func confirm_move(cell: Vector2i) -> bool:
	if mode != IMode.UNIT_ACTION or selected_unit_id < 0:
		return false
	if cell not in move_range or not is_cell_free(cell):
		return false
	units[selected_unit_id]["cell"] = cell
	acted_unit_ids[selected_unit_id] = true
	unit_moved.emit(selected_unit_id, cell)
	_clear_interaction()
	state_changed.emit()
	return true


func confirm_attack(cell: Vector2i) -> bool:
	if mode != IMode.UNIT_ACTION or selected_unit_id < 0:
		return false
	var tid: int = unit_at(cell)
	if tid < 0 or units[tid]["faction"] == current_player:
		return false
	var dist: int = abs(cell.x - selected_cell.x) + abs(cell.y - selected_cell.y)
	if dist > units[selected_unit_id]["atk_range"]:
		return false
	_combat(selected_unit_id, tid)
	acted_unit_ids[selected_unit_id] = true
	_clear_interaction()
	state_changed.emit()
	return true


func cancel() -> void:
	_clear_interaction()
	state_changed.emit()


func _clear_interaction() -> void:
	mode = IMode.IDLE
	selected_card_index = -1
	selected_unit_id = -1
	selected_cell = Vector2i(-1, -1)
	move_range = []


# ---------- 网格战斗 ----------

func deploy_unit(cell: Vector2i, faction: String) -> int:
	if not _in_board(cell) or not is_cell_free(cell):
		return -1
	var id := next_id
	next_id += 1
	units[id] = {
		"cell": cell, "faction": faction, "atk": DEF_ATK, "hp": DEF_HP,
		"move_range": DEF_MOVE, "atk_range": DEF_ATK_RANGE,
	}
	return id


func unit_at(cell: Vector2i) -> int:
	for id in units:
		if units[id]["cell"] == cell:
			return id
	return -1


func is_cell_free(cell: Vector2i) -> bool:
	return _in_board(cell) and unit_at(cell) < 0


func _combat(attacker_id: int, defender_id: int) -> void:
	var dmg: int = units[attacker_id]["atk"]
	units[defender_id]["hp"] -= dmg
	unit_damaged.emit(defender_id, units[defender_id]["hp"])
	var counter: int = units[defender_id]["atk"]
	units[attacker_id]["hp"] -= counter
	unit_damaged.emit(attacker_id, units[attacker_id]["hp"])


func _in_board(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < BOARD_ROWS and cell.y >= 0 and cell.y < BOARD_COLS


func _compute_move_range(from: Vector2i, rng: int) -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	for r in BOARD_ROWS:
		for c in BOARD_COLS:
			var cell := Vector2i(r, c)
			if cell == from:
				continue
			var man: int = abs(cell.x - from.x) + abs(cell.y - from.y)
			if man <= rng and is_cell_free(cell):
				res.append(cell)
	return res
