class_name Board
extends RefCounted
## 棋盘：4×4，上半（行 0-1）敌方领地，下半（行 2-3）我方领地
## 依据 a500「领地」：将地图一分为二得到的上下部分即为敌我双方的领地
##
## ⚠️ **坐标约定（沿用项目既有口径，勿改）**：
##   Vector2i(x = **行** 0..3 自上而下, y = **列** 0..3 自左而右)
##   屏幕位置 = MAP_ORIGIN + Vector2(cell.y * 250, cell.x * 250)
##   即 cell.x 决定纵向、cell.y 决定横向 —— 与 card_unit 的摆放口径一致

signal changed()

const COLS := 4
const ROWS := 4
const ALLY := 0        ## 绿方（我，固定下半）
const ENEMY := 1       ## 红方（敌，固定上半）

var _cells := {}       ## Vector2i → UnitInstance


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLS and c.y >= 0 and c.y < ROWS


func is_empty(c: Vector2i) -> bool:
	return in_bounds(c) and not _cells.has(c)


func unit_at(c: Vector2i) -> UnitInstance:
	return _cells.get(c, null)


func all_units() -> Array[UnitInstance]:
	var out: Array[UnitInstance] = []
	for k in _cells.keys():
		out.append(_cells[k])
	return out


func units_of(side: int) -> Array[UnitInstance]:
	var out: Array[UnitInstance] = []
	for u in all_units():
		if u.side == side:
			out.append(u)
	return out


## 领地判定（a500：上半=敌方，下半=我方）—— 按**行**（cell.x）划分
static func territory_of(c: Vector2i) -> int:
	return ALLY if c.x >= 2 else ENEMY


func is_own_territory(c: Vector2i, side: int) -> bool:
	return territory_of(c) == side


func place(inst: UnitInstance) -> bool:
	if inst == null or not is_empty(inst.cell):
		return false
	_cells[inst.cell] = inst
	changed.emit()
	return true


func move_unit(inst: UnitInstance, to: Vector2i) -> bool:
	if inst == null or not is_empty(to):
		return false
	_cells.erase(inst.cell)
	inst.cell = to
	_cells[to] = inst
	changed.emit()
	return true


func remove(inst: UnitInstance) -> void:
	if inst == null:
		return
	_cells.erase(inst.cell)
	changed.emit()


## 邻接（上下左右，不含斜角）—— 用于「蜂王巢口」与「力场相邻」
func neighbors_cardinal(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]
	for d in dirs:
		var n: Vector2i = c + d
		if in_bounds(n):
			out.append(n)
	return out


## 曼哈顿距离（a500：走格子范围按十字步数计算）
func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## 可移动范围：走格子、**会被单位阻挡**（a500「移动会被单位阻挡」）
## 返回 {cell: 步数}（不含起点）
func move_range(inst: UnitInstance) -> Dictionary:
	var out := {}
	if inst == null or inst.move_range() <= 0:
		return out
	var start := inst.cell
	var frontier := [start]
	var dist := {start: 0}
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		var d: int = int(dist[cur])
		if d >= inst.move_range():
			continue
		for n in neighbors_cardinal(cur):
			if dist.has(n):
				continue
			var blocker := unit_at(n)
			# 空格可走；起点自身不算阻挡；其它任何单位都阻挡
			if blocker != null:
				continue
			dist[n] = d + 1
			out[n] = d + 1
			frontier.append(n)
	return out


## 攻击范围内可指定的敌方单位（**攻击不会被阻挡** —— a500，故不做视线遮挡）
func attackable(inst: UnitInstance, board_units: Array[UnitInstance]) -> Array[UnitInstance]:
	var out: Array[UnitInstance] = []
	if inst == null or inst.atk() <= 0:
		return out
	var r := inst.attack_range()
	if r <= 0:
		return out
	for u in board_units:
		if u.side == inst.side or not u.is_alive():
			continue
		if manhattan(inst.cell, u.cell) <= r:
			out.append(u)
	return out
