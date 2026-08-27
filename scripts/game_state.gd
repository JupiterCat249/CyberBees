extends Node
## 全局游戏状态单例（Autoload，跨场景/节点共享）—— 用单例承载战斗状态与事件总线。
## Godot 通信不止信号：单例(Autoload) 承载全局状态，信号作为事件总线让 UI/棋盘监听。
## 边界：T4 无物理（纯网格/曼哈顿）、T6 2D、D6 4×4、D1 蜂主题。

signal unit_deployed(unit_id: int, cell: Vector2i, faction: String)
signal unit_moved(unit_id: int, cell: Vector2i)
signal unit_damaged(unit_id: int, hp: int)
signal selection_changed(selected_cell: Vector2i)
signal state_changed

const BOARD_ROWS := 4
const BOARD_COLS := 4
const GREEN := "green"
const RED := "red"
const DEF_ATK := 2
const DEF_HP := 4
const DEF_MOVE := 2
const DEF_ATK_RANGE := 1

var current_player := GREEN
var next_id := 1
var selected_unit_id := -1
var selected_cell := Vector2i(-1, -1)
var move_range: Array[Vector2i] = []

# units[id] = {cell: Vector2i, faction: String, atk:int, hp:int, move_range:int, atk_range:int}
var units := {}


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
	# 反击
	var counter: int = units[tid]["atk"]
	units[aid]["hp"] -= counter
	unit_damaged.emit(aid, units[aid]["hp"])
	state_changed.emit()
	return true


func _in_board(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < BOARD_ROWS and cell.y >= 0 and cell.y < BOARD_COLS


func _compute_move_range(from: Vector2i, range: int) -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	for r in BOARD_ROWS:
		for c in BOARD_COLS:
			var cell := Vector2i(r, c)
			if cell == from:
				continue
			var man: int = abs(cell.x - from.x) + abs(cell.y - from.y)
			if man <= range and is_cell_free(cell):
				res.append(cell)
	return res
