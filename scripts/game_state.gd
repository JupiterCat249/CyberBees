extends Node
## 全局游戏状态单例（Autoload）：战斗状态 + 事件总线。
## 覆盖：网格部署/移动/攻击(检查点2) + 费用/回合/阶段/手牌(检查点3)。
## 边界：T4 无物理(曼哈顿)、T6 2D、D6 4×4、D1 蜂主题、T8 费用上限10/第7回合回费+2。

signal unit_deployed(unit_id: int, cell: Vector2i, faction: String)
signal unit_moved(unit_id: int, cell: Vector2i)
signal unit_damaged(unit_id: int, hp: int)
signal selection_changed(selected_cell: Vector2i)
signal phase_changed(phase: int, turn: int)
signal cost_changed(cost: int)
signal state_changed

enum Phase { REFUND, DEPLOY, ACTION }

const BOARD_ROWS := 4
const BOARD_COLS := 4
const GREEN := "green"
const RED := "red"
const DEF_ATK := 2
const DEF_HP := 4
const DEF_MOVE := 2
const DEF_ATK_RANGE := 1
const MAX_COST := 10        # T8 费用上限
const HAND_SIZE := 4        # 手牌补至4
const BASE_REFUND := 2      # 每回合基础回费
const EXTRA_REFUND_7 := 2   # T8 第7回合起回费阶段额外+2

var current_player := GREEN
var next_id := 1
var selected_unit_id := -1
var selected_cell := Vector2i(-1, -1)
var move_range: Array[Vector2i] = []

var turn_number := 1
var phase: Phase = Phase.REFUND
var cost := 0               # 当前回合可用费用
var hand: Array = []        # 手牌（Dictionary: {type, name, cost}）

# units[id] = {cell, faction, atk, hp, move_range, atk_range}
var units := {}


func _ready() -> void:
	start_turn()


# ---------- 回合 / 费用 / 阶段 ----------

func start_turn() -> void:
	var refund: int = BASE_REFUND + (EXTRA_REFUND_7 if turn_number >= 7 else 0)  # T8
	cost = maxi(0, mini(cost + refund, MAX_COST))
	phase = Phase.REFUND
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
	state_changed.emit()
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


# ---------- 网格战斗（检查点2） ----------

func deploy_unit(cell: Vector2i, faction: String) -> int:
	if not _in_board(cell) or not is_cell_free(cell):
		return -1
	var id := next_id
	next_id += 1
	units[id] = {
		"cell": cell, "faction": faction, "atk": DEF_ATK, "hp": DEF_HP,
		"move_range": DEF_MOVE, "atk_range": DEF_ATK_RANGE,
	}
	unit_deployed.emit(id, cell, faction)
	state_changed.emit()
	return id


func unit_at(cell: Vector2i) -> int:
	for id in units:
		if units[id]["cell"] == cell:
			return id
	return -1


func is_cell_free(cell: Vector2i) -> bool:
	return _in_board(cell) and unit_at(cell) < 0


func select(cell: Vector2i) -> void:
	var id: int = unit_at(cell)
	if id >= 0:
		selected_unit_id = id
		selected_cell = cell
		move_range = _compute_move_range(cell, units[id]["move_range"])
	else:
		selected_unit_id = -1
		selected_cell = cell
		move_range = []
	selection_changed.emit(cell)
	state_changed.emit()


func try_move(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var id: int = unit_at(from_cell)
	if id < 0:
		return false
	if to_cell not in move_range or not is_cell_free(to_cell):
		return false
	units[id]["cell"] = to_cell
	unit_moved.emit(id, to_cell)
	selected_unit_id = -1
	selected_cell = Vector2i(-1, -1)
	move_range = []
	state_changed.emit()
	return true


func attack(attacker_cell: Vector2i, target_cell: Vector2i) -> bool:
	var aid: int = unit_at(attacker_cell)
	var tid: int = unit_at(target_cell)
	if aid < 0 or tid < 0 or aid == tid:
		return false
	if abs(target_cell.x - attacker_cell.x) + abs(target_cell.y - attacker_cell.y) > units[aid]["atk_range"]:
		return false
	var dmg: int = units[aid]["atk"]
	units[tid]["hp"] -= dmg
	unit_damaged.emit(tid, units[tid]["hp"])
	var counter: int = units[tid]["atk"]
	units[aid]["hp"] -= counter
	unit_damaged.emit(aid, units[aid]["hp"])
	state_changed.emit()
	return true


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
