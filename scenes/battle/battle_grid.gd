extends RefCounted
## ============================================================
## BattleGrid —— 棋盘几何与范围计算（可维护性重构 第1块）
##
## 从 battle_state.gd 搬出的**纯函数**：不持有数据，只读共享 Model(state) 的单位分布与地图尺寸。
## 拆分原则（见 系统维护/战斗节点体系/专题-重构前代码复盘.md）：
##   各块只经共享 Model(state) + 信号交互；本块无信号、无副作用，最易验证。
##
## 术语基准：a500 范围 —— ① 移动按走格子（会被单位阻挡）② 攻击按曼哈顿距离（不被阻挡）
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

## 由协调器注入（共享 Model）
var state: Node = null


## 单位占位查询（转发；state 不可用时视为空）
func unit_at(cell: Vector2i) -> int:
	if state == null:
		return -1
	return state.unit_at(cell)


## 移动范围：走格子寻路（BFS 最短路；等权网格上与 A* 结果等价）
## a500 范围 1/3：通过走格子计算可移动范围；移动范围【会被单位阻挡】（不可穿过、不可停在有单位格）
func move_cells(from: Vector2i, steps: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if steps <= 0:
		return out
	var dist := {}
	dist[from] = 0
	var queue: Array[Vector2i] = [from]
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		var d: int = int(dist[cur])
		if d >= steps:
			continue
		for dir in dirs:
			var nxt: Vector2i = cur + dir
			if not D.in_map(nxt) or dist.has(nxt):
				continue
			if unit_at(nxt) >= 0:
				continue
			dist[nxt] = d + 1
			out.append(nxt)
			queue.append(nxt)
	return out


## 攻击范围：按曼哈顿距离（a500 范围 3：攻击范围不会被单位阻挡）
func range_cells(from: Vector2i, rng: int, need_free: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if rng <= 0:
		return out
	for r in D.ROWS:
		for c in D.COLS:
			var cell := Vector2i(r, c)
			if cell == from:
				continue
			var man: int = abs(cell.x - from.x) + abs(cell.y - from.y)
			if man > rng:
				continue
			if need_free and unit_at(cell) >= 0:
				continue
			out.append(cell)
	return out


## 全盘格子
func all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in D.ROWS:
		for c in D.COLS:
			out.append(Vector2i(r, c))
	return out


## 四邻（链式传播 / 相邻判定用）
func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nxt: Vector2i = cell + dir
		if D.in_map(nxt):
			out.append(nxt)
	return out


## 曼哈顿距离
func dist(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
