extends Node2D
## ============================================================
## 电子蜂 · 战斗场景（用 card-system 的渲染代码组装，未新建任何渲染文件）
##   · 背景/棋盘/手牌面板/徽章/按钮  → 复用 card-system/card_system/battle_ui.tscn (shader)
##   · 卡牌(手牌 + 场上单位)          → 复用 card-system/card_system/card_auto.tscn (shader)
##   · 文字/数字                      → 标准 Label（battle_ui 明确"文字一律不画，由上层补"）
##   · 选中/范围高亮                  → 标准 ColorRect 半透明覆盖（非渲染脚本）
## 规则依据：电子蜂A5策划案/电子蜂a500规则.md
## ============================================================

const UI_SCENE := preload("res://card-system/card_system/battle_ui.tscn")
const CARD := preload("res://card-system/card_system/card_auto.tscn")
const ART_DIR := "res://card-system/card_system/art/"

# ---------------- 设计坐标（与 battle_ui.gdshader 常量一致） ----------------
const MAP_ORIGIN := Vector2(460.0, 40.0)   # 地图本体左上（1000x1000）
const CELL := 250.0
const PANEL_L := Vector2(32.0, 150.0)      # 绿方手牌面板 400x400
const PANEL_R := Vector2(1488.0, 150.0)    # 红方手牌面板 400x400
const PANEL_SZ := 400.0
const HEX_L := Vector2(82.0, 90.0)         # 绿方六边形徽章中心
const HEX_R := Vector2(1538.0, 90.0)       # 红方
const BTN_MAIN := Vector2(1488.0, 560.0)   # 主按钮 400x100
const DETAIL_POS := Vector2(32.0, 758.0)   # 左下卡牌详情 300x300

const ROWS := 4
const COLS := 4
const HAND_MAX := 4
const COST_MAX := 10

# ---------------- card_auto 图标索引 ----------------
const I_ATK := 0
const I_SPD := 1
const I_HP := 2
const I_RANGE := 3
const I_SOLDIER := 4
const I_BUILDING := 5
const I_COMMAND := 6
const I_QUEEN := 7

# ---------------- 阶段（A5 回合流程） ----------------
enum Phase { REFUND, FIELD, DEPLOY, ACTION }
const PHASE_NAME := ["回费", "场地", "部署", "行动"]

# ---------------- 卡池（替代 card_demo.gd 的 DATA；单位卡走同一套参数） ----------------
const POOL := [
	{"art": "卡牌a-金刚蜂王", "name": "金刚蜂王", "kind": "queen", "cost": 8, "atk": 7, "spd": 1, "hp": 8, "range": 2},
	{"art": "卡牌c1-叶蜂", "name": "叶蜂", "kind": "soldier", "cost": 2, "atk": 2, "spd": 1, "hp": 3, "range": 1},
	{"art": "卡牌c1-泥蜂", "name": "泥蜂", "kind": "soldier", "cost": 2, "atk": 3, "spd": 1, "hp": 4, "range": 2},
	{"art": "卡牌c2-熊蜂", "name": "熊蜂", "kind": "soldier", "cost": 5, "atk": 5, "spd": 1, "hp": 8, "range": 1},
	{"art": "卡牌b1-蜂巢", "name": "蜂巢", "kind": "building", "cost": 4, "atk": 0, "spd": 0, "hp": 5, "range": 0},
	{"art": "卡牌b1-蜂巢III", "name": "蜂巢III", "kind": "building", "cost": 9, "atk": 0, "spd": 0, "hp": 12, "range": 0},
	{"art": "卡牌d1-电击", "name": "电击", "kind": "command", "cost": 3, "dmg": 4, "range": 2},
	{"art": "卡牌d1-巡航导弹", "name": "巡航导弹", "kind": "command", "cost": 6, "dmg": 5, "range": 3},
]

var _holder: Node2D
var _ui: Node = null

# ---------------- 战斗状态 ----------------
var round_no := 1
var phase: Phase = Phase.REFUND
var current := "green"                      # green 先手
var cost := {"green": 2, "red": 4}          # 后手 +2（A5 对战准备 6）
var hand := {"green": [], "red": []}
var deck := {"green": [], "red": []}
var units := {}                             # id -> {cell, side, card, hp, acted}
var next_id := 1

# ---------------- 交互 ----------------
var armed_card := -1                        # 已选中的手牌索引（进入放置态）
var selected_unit := -1
var move_range: Array[Vector2i] = []
var atk_range: Array[Vector2i] = []

# ---------------- 渲染节点容器 ----------------
var _cards_node: Node2D
var _units_node: Node2D
var _text_node: Node2D
var _hl_node: Node2D
var _hand_nodes := {"green": [], "red": []}
var _unit_nodes := {}
var _labels := {}


func _ready() -> void:
	_ui = UI_SCENE.instantiate()
	add_child(_ui)
	_holder = _ui.get_node("Holder")

	_cards_node = _make_node("HandCards")
	_units_node = _make_node("Units")
	_text_node = _make_node("Texts")
	_hl_node = _make_node("Highlights")

	_setup_pool()
	_deploy_start()
	_build_texts()
	_refresh()


func _make_node(n: String) -> Node2D:
	var node := Node2D.new()
	node.name = n
	_holder.add_child(node)
	return node


# ============================================================
# 战斗初始化
# ============================================================
func _setup_pool() -> void:
	var pool: Array = []
	for c in POOL:
		if c["kind"] != "queen":
			pool.append(c)
	for side in ["green", "red"]:
		deck[side] = pool.duplicate()
		for i in HAND_MAX:
			_draw_one(side)


func _draw_one(side: String) -> void:  ## 抽一张手牌（避开父类 _draw 回调名）
	if deck[side].is_empty():
		return
	if hand[side].size() >= HAND_MAX:
		return
	var d: Dictionary = deck[side].pop_front()
	hand[side].append(d)


## 起手：双方蜂王各自部署（A5 对战准备 9）
func _deploy_start() -> void:
	var qcard := POOL[0]
	_spawn_unit(Vector2i(3, 1), "green", qcard)
	_spawn_unit(Vector2i(0, 2), "red", qcard)


func _spawn_unit(cell: Vector2i, side: String, card: Dictionary) -> int:
	var id := next_id
	next_id += 1
	units[id] = {"cell": cell, "side": side, "card": card, "hp": card["hp"], "acted": true, "deployed_round": round_no}
	return id


func unit_at(cell: Vector2i) -> int:
	for id in units:
		if units[id]["cell"] == cell:
			return id
	return -1


func side_of(cell: Vector2i) -> String:
	return "green" if cell.x >= 2 else "red"


# ============================================================
# 回合流程（A5：回费 → 场地 → 部署 → 行动）
# ============================================================
func advance_phase() -> void:
	match phase:
		Phase.REFUND:
			phase = Phase.FIELD
		Phase.FIELD:
			phase = Phase.DEPLOY
		Phase.DEPLOY:
			phase = Phase.ACTION
		Phase.ACTION:
			_end_turn()
			return
	_clear_sel()
	_refresh()


func _end_turn() -> void:
	if current == "green":
		current = "red"
	else:
		current = "green"
		round_no += 1
	# 换手：回费（上限10；第7回合起 +2）
	var gain := 2 + (2 if round_no >= 7 else 0)
	cost[current] = mini(cost[current] + gain, COST_MAX)
	# 抽到4（A5 抽卡 4）
	for side in ["green", "red"]:
		while hand[side].size() < HAND_MAX:
			_draw_one(side)
	# 重置行动机会（A5 行动机会 2）
	for id in units:
		units[id]["acted"] = false
	phase = Phase.REFUND
	_clear_sel()
	_refresh()


# ============================================================
# 放置 / 行动
# ============================================================
func select_hand(index: int) -> void:
	if phase != Phase.DEPLOY:
		return
	if index < 0 or index >= hand[current].size():
		return
	armed_card = index
	selected_unit = -1
	move_range = []
	atk_range = []
	_refresh()


func _legal_place(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= ROWS or cell.y < 0 or cell.y >= COLS:
		return false
	if unit_at(cell) >= 0:
		return false
	var card: Dictionary = hand[current][armed_card]
	var kind: String = card["kind"]
	if kind == "building":
		return cell.x >= 2 if current == "green" else cell.x < 2
	if kind == "soldier":
		return _adjacent_to_own_queen(cell)
	return false


func _adjacent_to_own_queen(cell: Vector2i) -> bool:
	for id in units:
		var u: Dictionary = units[id]
		if u["side"] == current and u["card"]["kind"] == "queen":
			var q: Vector2i = u["cell"]
			if abs(q.x - cell.x) + abs(q.y - cell.y) == 1:
				return true
	return false


func place_at(cell: Vector2i) -> void:
	if armed_card < 0 or not _legal_place(cell):
		return
	var card: Dictionary = hand[current][armed_card]
	if cost[current] < card["cost"]:
		return
	cost[current] -= card["cost"]
	_spawn_unit(cell, current, card)
	hand[current].remove_at(armed_card)
	armed_card = -1
	_refresh()


func select_unit_at(cell: Vector2i) -> void:
	var id := unit_at(cell)
	if id < 0:
		return
	if units[id]["side"] != current or units[id]["acted"]:
		return
	if phase != Phase.ACTION:
		return
	selected_unit = id
	armed_card = -1
	var u: Dictionary = units[id]
	var c: Vector2i = u["cell"]
	move_range = _range_cells(c, int(u["card"].get("spd", 0)), true)
	atk_range = _range_cells(c, int(u["card"].get("range", 0)), false)
	_refresh()


func act_at(cell: Vector2i) -> void:
	if selected_unit < 0:
		return
	var u: Dictionary = units[selected_unit]
	if cell in move_range and unit_at(cell) < 0:
		u["cell"] = cell
		u["acted"] = true
		_clear_sel()
		_refresh()
		return
	if cell in atk_range:
		var tid := unit_at(cell)
		if tid >= 0 and units[tid]["side"] != current:
			_combat(selected_unit, tid)
			u["acted"] = true
			_clear_sel()
			_refresh()


## 菱形范围（A5：十字=1，斜角=2）：按曼哈顿距离
func _range_cells(from: Vector2i, rng: int, need_free: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if rng <= 0:
		return out
	for r in ROWS:
		for c in COLS:
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


func _combat(aid: int, tid: int) -> void:
	var a: Dictionary = units[aid]
	var t: Dictionary = units[tid]
	t["hp"] = int(t["hp"]) - int(a["card"].get("atk", 0))
	# 反击（A5：射程外无效）
	var tc: Vector2i = t["cell"]
	var ac: Vector2i = a["cell"]
	if abs(tc.x - ac.x) + abs(tc.y - ac.y) <= int(t["card"].get("range", 0)):
		a["hp"] = int(a["hp"]) - int(t["card"].get("atk", 0))
	_cleanup_dead()


func _cleanup_dead() -> void:
	var dead := []
	for id in units:
		if int(units[id]["hp"]) <= 0:
			dead.append(id)
	for id in dead:
		units.erase(id)


func _clear_sel() -> void:
	armed_card = -1
	selected_unit = -1
	move_range = []
	atk_range = []


# ============================================================
# 渲染（全部复用 card-system 组件）
# ============================================================
func _refresh() -> void:
	_render_hand("green")
	_render_hand("red")
	_render_units()
	_render_highlights()
	_update_texts()


func _render_hand(side: String) -> void:
	for n in _hand_nodes[side]:
		n.queue_free()
	_hand_nodes[side] = []
	var base: Vector2 = PANEL_L if side == "green" else PANEL_R
	var cards: Array = hand[side]
	for i in cards.size():
		var c := _make_card(cards[i], 0.5)
		var col := i % 2
		@warning_ignore("integer_division")
		var rowi := i / 2
		c.position = base + Vector2(18.0 + col * 195.0, 18.0 + rowi * 195.0)
		_cards_node.add_child(c)
		_hand_nodes[side].append(c)


func _render_units() -> void:
	for n in _unit_nodes.values():
		n.queue_free()
	_unit_nodes = {}
	for id in units:
		var u: Dictionary = units[id]
		var c := _make_card(u["card"], 1.0)
		var cell: Vector2i = u["cell"]
		c.position = MAP_ORIGIN + Vector2(cell.y * CELL, cell.x * CELL)
		# 数值随战况更新：右栏上=剩余生命
		c.set("stat_r1", int(u["hp"]))
		if u["side"] == "red":
			c.set("col_base", Color(0.86, 0.72, 0.72))
		else:
			c.set("col_base", Color(0.74, 0.86, 0.78))
		if int(u["hp"]) < int(u["card"]["hp"]):
			c.modulate = Color(1.0, 1.0, 1.0)
		_units_node.add_child(c)
		_unit_nodes[id] = c


func _render_highlights() -> void:
	for n in _hl_node.get_children():
		n.queue_free()
	for cell in move_range:
		_hl_node.add_child(_hl_rect(cell, Color(0.25, 0.85, 0.45, 0.35)))
	for cell in atk_range:
		_hl_node.add_child(_hl_rect(cell, Color(0.90, 0.25, 0.20, 0.32)))
	if armed_card >= 0:
		for r in ROWS:
			for c in COLS:
				var cell := Vector2i(r, c)
				if _legal_place(cell):
					_hl_node.add_child(_hl_rect(cell, Color(1.0, 0.80, 0.30, 0.35)))


func _hl_rect(cell: Vector2i, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = MAP_ORIGIN + Vector2(cell.y * CELL, cell.x * CELL)
	r.size = Vector2(CELL, CELL)
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _make_card(d: Dictionary, sc: float) -> Node2D:
	var c := CARD.instantiate()
	c.scale = Vector2(sc, sc)
	c.set("art", load(ART_DIR + d["art"] + ".png"))
	c.set("cost", int(d["cost"]))
	match d["kind"]:
		"queen":
			c.set("icon_tag", I_QUEEN)
		"soldier":
			c.set("icon_tag", I_SOLDIER)
		"building":
			c.set("icon_tag", I_BUILDING)
		_:
			c.set("icon_tag", I_COMMAND)
	if d["kind"] == "command":
		c.set("stat_l1", int(d.get("dmg", 0)))
		c.set("icon_l1", I_ATK)
		c.set("stat_l2", -1)
		c.set("icon_l2", -1)
		c.set("stat_r1", -1)
		c.set("icon_r1", I_RANGE)
		c.set("stat_r2", int(d.get("range", 0)))
		c.set("icon_r2", I_RANGE)
	else:
		c.set("stat_l1", int(d.get("atk", -1)))
		c.set("icon_l1", I_ATK if int(d.get("atk", 0)) > 0 else -1)
		c.set("stat_l2", int(d.get("spd", -1)))
		c.set("icon_l2", I_SPD if int(d.get("spd", 0)) > 0 else -1)
		c.set("stat_r1", int(d.get("hp", -1)))
		c.set("icon_r1", I_HP)
		c.set("stat_r2", int(d.get("range", -1)))
		c.set("icon_r2", I_RANGE if int(d.get("range", 0)) > 0 else -1)
	return c


# ============================================================
# 文字层（battle_ui 明确"文字一律不画"，此处补）
# ============================================================
func _build_texts() -> void:
	_labels["green_cost"] = _mk_label(HEX_L, 40, Color(0.16, 0.16, 0.16))
	_labels["red_cost"] = _mk_label(HEX_R, 40, Color(0.16, 0.16, 0.16))
	_labels["info"] = _mk_label(Vector2(460.0, 6.0), 28, Color(1, 1, 1))
	_labels["btn"] = _mk_label(BTN_MAIN + Vector2(20.0, 24.0), 34, Color(0.15, 0.15, 0.15))
	_labels["detail"] = _mk_label(DETAIL_POS + Vector2(16.0, 16.0), 22, Color(0.9, 0.9, 0.9))
	_labels["green_side"] = _mk_label(Vector2(150.0, 148.0), 22, Color(0.85, 1.0, 0.85))
	_labels["red_side"] = _mk_label(Vector2(1606.0, 148.0), 22, Color(1.0, 0.85, 0.85))


func _mk_label(pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	_text_node.add_child(l)
	return l


func _update_texts() -> void:
	_labels["green_cost"].text = str(cost["green"])
	_labels["red_cost"].text = str(cost["red"])
	_labels["info"].text = "第%d回合 · 阶段:%s · %s方" % [round_no, PHASE_NAME[phase], "绿" if current == "green" else "红"]
	_labels["btn"].text = "结束阶段" if phase != Phase.ACTION else "结束回合"
	_labels["green_side"].text = "绿方领地"
	_labels["red_side"].text = "红方领地"
	if armed_card >= 0:
		_labels["detail"].text = "已选牌: %s  点高亮格放置" % hand[current][armed_card]["name"]
	elif selected_unit >= 0:
		var u: Dictionary = units[selected_unit]
		_labels["detail"].text = "%s\nHP %d/%d  攻 %d  速 %d  射程 %d" % [
			u["card"]["name"], int(u["hp"]), int(u["card"]["hp"]),
			int(u["card"].get("atk", 0)), int(u["card"].get("spd", 0)), int(u["card"].get("range", 0))]
	else:
		_labels["detail"].text = "点手牌 → 选格放置\n点己方单位 → 移动/攻击"


# ============================================================
# 输入（点击 → 设计坐标 → 判定）
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var p := _to_design(mb.position)

	# 主按钮
	if Rect2(BTN_MAIN, Vector2(400.0, 100.0)).has_point(p):
		advance_phase()
		return

	# 手牌（左=绿 / 右=红，2x2）
	for side in ["green", "red"]:
		var base: Vector2 = PANEL_L if side == "green" else PANEL_R
		if not Rect2(base, Vector2(PANEL_SZ, PANEL_SZ)).has_point(p):
			continue
		if side != current:
			return
		var lp := p - base
		@warning_ignore("integer_division")
		var col := int(lp.x / 195.0)
		@warning_ignore("integer_division")
		var rowi := int(lp.y / 195.0)
		select_hand(rowi * 2 + col)
		return

	# 棋盘
	var b := p - MAP_ORIGIN
	if b.x < 0.0 or b.y < 0.0 or b.x >= COLS * CELL or b.y >= ROWS * CELL:
		return
	@warning_ignore("integer_division")
	var row := int(b.y / CELL)
	@warning_ignore("integer_division")
	var col2 := int(b.x / CELL)
	var cell := Vector2i(row, col2)
	if armed_card >= 0:
		place_at(cell)
	elif selected_unit >= 0:
		act_at(cell)
	else:
		select_unit_at(cell)


func _to_design(screen_pos: Vector2) -> Vector2:
	var xf := (_holder.get_global_transform() as Transform2D).affine_inverse()
	return xf * screen_pos
