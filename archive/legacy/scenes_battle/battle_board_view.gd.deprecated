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
	if state == null:
		_unit_nodes = {}
		return
	# 迭代021 缺陷修复：**不再"全量重建"单位节点，改为复用 + 原地更新**。
	#   原实现每次刷新都 queue_free 全部单位卡并重新 make_card →
	#   ① 施加在单位上的动画（受击抖动/受伤闪红/增益脉冲等）**随即被丢弃**（实测：攻击后位移恒为 0，
	#      即"抖动从未生效"）；② 单位多时每帧重建开销大。
	#   现在：只在单位"新增/退场"时增删节点，其余原地改属性 → 动画得以保留。
	for id in _unit_nodes.keys():
		if not state.units.has(id):
			var old = _unit_nodes[id]
			if is_instance_valid(old):
				old.queue_free()
			_unit_nodes.erase(id)
	for id in state.units:
		var u: Dictionary = state.units[id]
		var node = _unit_nodes.get(id, null)
		var fresh := false
		if node == null or not is_instance_valid(node):
			node = D.make_card(u["card"], 1.0)
			fresh = true
		node.position = D.cell_pos(u["cell"])
		node.set("stat_r1", int(u["hp"]))
		# 攻击/速度/射程也必须用**实时值**（含 buff 与地形加成）——
		# 此前只覆盖了血量，导致支援「攻击+1」等效果在卡面上看不出来
		node.set("stat_l1", int(state.final_atk(id)))
		node.set("stat_l2", int(state.final_spd(id)))
		node.set("stat_r2", int(state.final_range(id)))
		if u["side"] == "red":
			node.set("col_base", Color(0.88, 0.74, 0.74))
			node.set("col_center", Color(0.94, 0.86, 0.86))
		else:
			node.set("col_base", Color(0.76, 0.88, 0.80))
			node.set("col_center", Color(0.88, 0.94, 0.89))
		if u["acted"]:
			node.modulate = Color(0.72, 0.72, 0.72)
		else:
			# 未行动单位必须恢复原色（复用节点时上一帧可能被置灰）
			node.modulate = Color(1, 1, 1, 1)
		if fresh:
			_units_node.add_child(node)
			_unit_nodes[id] = node
		# 迭代014：效果角标（灼烧/护甲等）—— 叠加在单位格上缘
		#   复用节点时需先清掉上一帧的角标，避免残留/叠加
		for ch in _units_node.get_children():
			if ch.has_meta("badge_of") and int(ch.get_meta("badge_of")) == id:
				ch.queue_free()
		var badge := _effect_badges(id)
		badge.set_meta("badge_of", id)
		_units_node.add_child(badge)


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
	# 支援对象候选：蓝色高亮（A5 UI：再次点击当前选中单位后进入）
	for cell in state.support_range:
		_hl_node.add_child(_hl(cell, Color(0.30, 0.60, 1.00, 0.38)))
	if state.armed_card >= 0 and state.mode == D.Mode.DEPLOY_TARGET:
		for r in D.ROWS:
			for c in D.COLS:
				var cell := Vector2i(r, c)
				if state.legal_place(cell):
					_hl_node.add_child(_hl(cell, Color(1.0, 0.80, 0.30, 0.35)))
	# 特殊地形：**不在游戏内额外绘制**（迭代005.1 人明确）——
	# 地形表现在地图素材上（制作地图时直接画好），数据侧只影响数值与部署合法性。
	# A5 程序需求：待确认目标 —— 叠加框架「地图格选中」素材 + 预计剩余血量（扩展 card-system 素材，不重做）
	if state.pending_kind != "" and D.in_map(state.pending_cell):
		var pcell: Vector2i = state.pending_cell
		# 迭代014（IDEA-012）：**伤害覆盖格描边**（青色细框）—— 普攻=目标格；溅射技能=半径内全部格
		if state.preview.has("coverage"):
			for cc in (state.preview["coverage"] as Array):
				_hl_node.add_child(_hl_outline(cc, Color(0.25, 0.95, 0.98, 0.85)))
		var tex := load(D.CELL_PENDING_PATH) as Texture2D
		if tex != null:
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.centered = false
			spr.position = D.cell_pos(pcell)
			spr.scale = Vector2(float(D.CELL) / float(tex.get_width()), float(D.CELL) / float(tex.get_width()))
			_hl_node.add_child(spr)
		if state.preview.has("dmg"):
			# 迭代004：数值文本按表现规范取色/字号（受伤 #FF2000；字号随数值）
			var _dmg: int = int(state.preview["dmg"])
			var _dcol: Color = state.anim.text_color("damage") if state.anim != null else Color(1.0, 0.62, 0.05)
			var _dsz: float = float(state.anim.text_size_for(_dmg)) if state.anim != null else 40.0
			_hl_node.add_child(D.digit_node(_dmg, _dsz, _dcol,
				D.cell_pos(pcell) + Vector2(D.CELL * 0.5, D.CELL * 0.18)))
		if state.preview.has("hp_after"):
			# 迭代004：预计剩余血量 —— 字号随数值
			var _hp: int = int(state.preview["hp_after"])
			var _hsz: float = float(state.anim.text_size_for(_hp)) if state.anim != null else 46.0
			_hl_node.add_child(D.digit_node(_hp, _hsz, Color(1.0, 0.32, 0.22),
				D.cell_pos(pcell) + Vector2(D.CELL * 0.5, D.CELL * 0.80)))
		# 行动方（攻方）预计剩余血量（蓝，反击后）—— 之前只画了被攻击方，攻方无数字
		if state.preview.has("attacker_hp_after"):
			var aid := int(state.preview.get("attacker_id", -1))
			if aid >= 0 and state.units.has(aid):
				var acell: Vector2i = state.units[aid]["cell"]
				_hl_node.add_child(D.digit_node(int(state.preview["attacker_hp_after"]), 46.0, Color(0.35, 0.75, 1.0),
					D.cell_pos(acell) + Vector2(D.CELL * 0.5, D.CELL * 0.80)))


## 迭代014（方案 A）：**效果角标** —— 在单位格上缘标出"身上有灼烧/护甲"
##   ⚠️ 框架卡面四角已被四维数值占满且 card-system 只读（T11）→ 效果只能做在项目侧叠加层
##   颜色：减益 = 红橙；增益 = 青蓝（与 anim 的减益/增益脉冲取色同族，便于玩家建立联系）
## 迭代014/015（方案 A）：**效果角标** —— 在单位格上缘标出"身上有灼烧/装甲"等状态
##   ⚠️ 框架卡面四角已被四维数值占满且 card-system 只读（T11）→ 效果只能做在项目侧叠加层
##   迭代015：改用 **A5 状态图标素材**（assets/status_icons/，80×80）；无对应素材时回退到纯色角标
func _effect_badges(id: int) -> Node2D:
	var root := Node2D.new()
	if state == null or not state.units.has(id):
		return root
	var eff: Dictionary = state.units[id]["effects"]
	if eff.is_empty():
		return root
	var u: Dictionary = state.units[id]
	var base := D.cell_pos(u["cell"])
	var n: int = eff.size()
	var bw := 38.0        # 迭代015：图标略放大（源素材 80×80，缩到 38 仍清晰）
	var gap := 6.0
	var total: float = float(n) * bw + float(maxi(n - 1, 0)) * gap
	var x := base.x + (D.CELL - total) * 0.5
	var y := base.y + 6.0
	for key in eff.keys():
		var e: Dictionary = eff[key]
		var tex_path: String = D.status_icon_path(str(key))
		if tex_path != "":
			# 暗底衬：让图标在杂色卡面上也能看清（素材本身是彩色描线，无底板）
			var plate := ColorRect.new()
			plate.color = Color(0.10, 0.11, 0.10, 0.62)
			plate.size = Vector2(bw, bw)
			plate.position = Vector2(x - 2.0, y - 2.0)
			plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(plate)
			var sp := Sprite2D.new()
			sp.texture = load(tex_path) as Texture2D
			sp.centered = false
			var tex := sp.texture
			var sc: float = bw / float(tex.get_width()) if tex != null else 1.0
			sp.scale = Vector2(sc, sc)
			sp.position = Vector2(x, y)
			root.add_child(sp)
		else:
			# 回退：纯色角标（减益红橙 / 增益青蓝）—— 该效果尚无对应素材
			var is_debuff: bool = e.has("dot") or e.has("reduce") or e.has("atk_mult")
			var col: Color = Color(0.95, 0.34, 0.20, 1.0) if is_debuff else Color(0.30, 0.72, 1.0, 1.0)
			var bg := ColorRect.new()
			bg.color = col
			bg.size = Vector2(bw, 34.0)
			bg.position = Vector2(x, y)
			bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(bg)
		x += bw + gap
	return root
func _hl(cell: Vector2i, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = D.cell_pos(cell)
	r.size = Vector2(D.CELL, D.CELL)
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 迭代014（IDEA-012）：**伤害覆盖格**描边 —— 只画细边框（不铺色），
## 避免与"可移动(绿铺色)/可攻击(红铺色)/支援(蓝铺色)"三种既有高亮混淆
func _hl_outline(cell: Vector2i, col: Color, w := 8.0) -> Node2D:
	var root := Node2D.new()
	var base := D.cell_pos(cell)
	var ins := w * 0.5
	for r in [
		Rect2(base.x + ins, base.y + ins, D.CELL - w, w),
		Rect2(base.x + ins, base.y + D.CELL - ins - w, D.CELL - w, w),
		Rect2(base.x + ins, base.y + ins, w, D.CELL - w),
		Rect2(base.x + D.CELL - ins - w, base.y + ins, w, D.CELL - w)]:
		var bar := ColorRect.new()
		bar.position = r.position
		bar.size = r.size
		bar.color = col
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
	return root
