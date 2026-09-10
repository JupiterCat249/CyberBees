extends Node2D
## ============================================================
## BattleBoardView —— 棋盘视图
##   ① 棋盘背景：地图底图 + 格子（框架未提供，属补充）——插在框架 Holder 的 index 1，
##      位于骨架棋盘之上、卡牌/单位之下。
##   ② 场上单位：复用框架 card_auto（红/绿底色区分敌我；已行动者变暗）。
##   ③ 高亮：移动(绿) / 攻击(红) / 可放置(琥珀) / 特殊地形(淡黄 + 图集图标)。
##   只读 BattleState，不做任何规则判断；卡牌/图集工厂统一取自 BattleDefs。
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

var holder: Node2D = null
var state: Node = null

var _map_bg: Node2D = null
var _units_node: Node2D = null
var _hl_node: Node2D = null
var _unit_nodes := {}


## 由协调器注入依赖并接线
func setup(h: Node2D, st: Node) -> void:
	holder = h
	state = st
	_units_node = _mk("Units")
	_hl_node = _mk("Highlights")
	_build_map_bg()
	state.state_changed.connect(_on_state_changed)


func _mk(n: String) -> Node2D:
	var x := Node2D.new()
	x.name = n
	holder.add_child(x)
	return x


## 棋盘底图 + 格子（属"框架未提供的背景"）
func _build_map_bg() -> void:
	if _map_bg != null:
		return
	_map_bg = Node2D.new()
	_map_bg.name = "MapBg"
	holder.add_child(_map_bg)
	# 骨架 Rect 在 index 0；移到 1 = 盖住骨架棋盘，同时被其后的卡牌/单位盖住
	if holder.get_child_count() > 1:
		holder.move_child(_map_bg, 1)
	var terrain_spr := Sprite2D.new()
	terrain_spr.name = "Terrain"
	terrain_spr.texture = load(D.MAP_TERRAIN_PATH)
	terrain_spr.centered = false
	terrain_spr.position = D.MAP_ORIGIN
	_map_bg.add_child(terrain_spr)
	var grid_spr := Sprite2D.new()
	grid_spr.name = "Grid"
	grid_spr.texture = load(D.MAP_GRID_PATH)
	grid_spr.centered = false
	grid_spr.position = D.MAP_ORIGIN
	_map_bg.add_child(grid_spr)


func _on_state_changed() -> void:
	render_units()
	render_highlights()


# ---------------- 场上单位 ----------------
func render_units() -> void:
	for n in _unit_nodes.values():
		if is_instance_valid(n):
			n.queue_free()
	_unit_nodes = {}
	if state == null:
		return
	for id in state.units:
		var u: Dictionary = state.units[id]
		var node := D.make_card(u["card"], 1.0)
		node.position = D.cell_pos(u["cell"])
		node.set("stat_r1", int(u["hp"]))
		if u["side"] == "red":
			node.set("col_base", Color(0.88, 0.74, 0.74))
			node.set("col_center", Color(0.94, 0.86, 0.86))
		else:
			node.set("col_base", Color(0.76, 0.88, 0.80))
			node.set("col_center", Color(0.88, 0.94, 0.89))
		if u["acted"]:
			node.modulate = Color(0.72, 0.72, 0.72)
		_units_node.add_child(node)
		_unit_nodes[id] = node


# ---------------- 高亮 ----------------
func render_highlights() -> void:
	for n in _hl_node.get_children():
		n.queue_free()
	if state == null:
		return
	for cell in state.move_range:
		_hl_node.add_child(_hl(cell, Color(0.25, 0.85, 0.45, 0.35)))
	for cell in state.atk_range:
		_hl_node.add_child(_hl(cell, Color(0.90, 0.25, 0.20, 0.32)))
	if state.armed_card >= 0 and state.mode == D.Mode.DEPLOY_TARGET:
		for r in D.ROWS:
			for c in D.COLS:
				var cell := Vector2i(r, c)
				if state.legal_place(cell):
					_hl_node.add_child(_hl(cell, Color(1.0, 0.80, 0.30, 0.35)))
	# 特殊地形：淡色底 + 图集图标（复用框架图集，不新建渲染文件）
	for c in state.terrain:
		_hl_node.add_child(_hl(c, Color(0.95, 0.80, 0.10, 0.14)))
		_hl_node.add_child(D.atlas_icon(D.I_TERRAIN, 76.0,
			D.cell_pos(c) + Vector2(D.CELL * 0.5, D.CELL * 0.5),
			Color(0.38, 0.28, 0.04, 0.80)))


func _hl(cell: Vector2i, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = D.cell_pos(cell)
	r.size = Vector2(D.CELL, D.CELL)
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
