extends Node
## 全局游戏状态单例（Autoload）：战斗循环唯一事实源 + 事件总线。
## 设计依据：Godot 引擎运行模型 + 战斗循环设计.md。回合制 = 事件驱动状态机（非每帧 loop）。
## 交互：IMode{IDLE,DEPLOY,UNIT_ACTION}；通信：信号 + 单例。边界 T4/T5/T6/T8/D6/D1。

signal unit_deployed(unit_id: int, cell: Vector2i, faction: String)
signal unit_moved(unit_id: int, cell: Vector2i)
signal unit_damaged(unit_id: int, hp: int)
signal unit_died(unit_id: int)
signal phase_changed(phase: int, turn: int)
signal cost_changed(cost: int)
signal ranges_changed                   # 选中单位的移动/攻击范围高亮变化
signal state_changed
signal game_over(winner: String)

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
var winner := ""

var mode: IMode = IMode.IDLE
var selected_card_index := -1
var selected_unit_id := -1
var selected_cell := Vector2i(-1, -1)
var move_range: Array[Vector2i] = []
var attack_range: Array[Vector2i] = []
var acted_unit_ids := {}

var units := {}   # id -> {cell, faction, atk, hp, move_range, atk_range, is_queen:bool}


func _ready() -> void:
	start_turn()


# ---------- 回合 / 费用 / 阶段 ----------

func start_turn() -> void:
	var refund := BASE_REFUND + (EXTRA_REFUND_7 if turn_number >= 7 else 0)
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


# ---------- 交互状态机 ----------

func select_card(index: int) -> bool:
	if index < 0 or index >= hand.size():
		return false
	if hand[index]["type"] != "unit_bee" or phase == Phase.REFUND:
		return false
	selected_card_index = index
	mode = IMode.DEPLOY
	state_changed.emit()
	return true


func select_unit(cell: Vector2i) -> bool:
	var id: int = unit_at(cell)
	if id < 0 or units[id]["faction"] != current_player or acted_unit_ids.has(id):
		return false
	selected_unit_id = id
	selected_cell = cell
	move_range = _compute_range(cell, units[id]["move_range"], true)
	attack_range = _compute_range(cell, units[id]["atk_range"], false)
	mode = IMode.UNIT_ACTION
	ranges_changed.emit()
	state_changed.emit()
	return true


func confirm_place(cell: Vector2i) -> bool:
	if mode != IMode.DEPLOY or selected_card_index < 0:
		return false
	var card: Dictionary = hand[selected_card_index]
	if not is_cell_free(cell) or cell.y < 2:
		_clear_interaction()
		state_changed.emit()
		return false
	if not spend(card["cost"]):
		return false
	var id := deploy_unit(cell, GREEN, false)
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
	var dist: int = abs(cell.x - selected_cell.x) + abs(cell.y - selected_cell.y)
	if tid < 0 or units[tid]["faction"] == current_player or dist > units[selected_unit_id]["atk_range"]:
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
	attack_range = []
	ranges_changed.emit()


# ---------- 网格战斗 ----------

func deploy_unit(cell: Vector2i, faction: String, is_queen: bool) -> int:
	if not _in_board(cell) or not is_cell_free(cell):
		return -1
	var id := next_id
	next_id += 1
	units[id] = {
		"cell": cell, "faction": faction, "atk": DEF_ATK, "hp": DEF_HP,
		"move_range": DEF_MOVE, "atk_range": DEF_ATK_RANGE, "is_queen": is_queen,
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
	a_attack(attacker_id, defender_id)
	if units.has(defender_id):
		a_attack(defender_id, attacker_id)


func a_attack(attacker_id: int, defender_id: int) -> void:
	var dmg: int = units[attacker_id]["atk"]
	units[defender_id]["hp"] -= dmg
	unit_damaged.emit(defender_id, units[defender_id]["hp"])
	if units[defender_id]["hp"] <= 0:
		units.erase(defender_id)
		unit_died.emit(defender_id)
		_check_win()


func _check_win() -> void:
	if winner != "":
		return
	var has_green := false
	var has_red := false
	for id in units:
		if units[id]["faction"] == GREEN:
			has_green = true
		else:
			has_red = true
	if not has_green:
		winner = RED
	elif not has_red:
		winner = GREEN
	if winner != "":
		game_over.emit(winner)
		state_changed.emit()


func _in_board(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < BOARD_ROWS and cell.y >= 0 and cell.y < BOARD_COLS


func _compute_range(from: Vector2i, rng: int, only_free: bool) -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	for r in BOARD_ROWS:
		for c in BOARD_COLS:
			var cell := Vector2i(r, c)
			if cell == from:
				continue
			var man: int = abs(cell.x - from.x) + abs(cell.y - from.y)
			if man <= rng:
				if only_free and not is_cell_free(cell):
					continue
				res.append(cell)
	return res
