extends Node2D
## ============================================================
## 电子蜂 · 战斗场景（完整 A5 规则 + card-system 全套渲染）
##   规则依据: 电子蜂A5策划案/电子蜂a500规则.md
##   渲染复用: card-system/card_system/  (battle_ui shader 背景 + card_auto 卡牌 + 图集/类别图标)
##   本文件只做「规则逻辑 + 节点组装」——不含任何像素渲染代码
## ============================================================

const UI_SCENE := preload("res://card-system/card_system/battle_ui.tscn")
const CARD := preload("res://card-system/card_system/card_auto.tscn")
const ART_DIR := "res://card-system/card_system/art/"
const TAG_DIR := "res://card-system/card_system/tag_icons/"

# ---------------- 设计坐标（与 battle_ui.gdshader 常量一致） ----------------
const MAP_ORIGIN := Vector2(460.0, 40.0)
const CELL := 250.0
const ROWS := 4
const COLS := 4
const PANEL_L := Vector2(32.0, 150.0)
const PANEL_R := Vector2(1488.0, 150.0)
const PANEL_SZ := 400.0
const HEX_L := Vector2(82.0, 90.0)
const HEX_R := Vector2(1538.0, 90.0)
const BTN_MAIN := Vector2(1488.0, 560.0)
const BTN_MAIN_SZ := Vector2(400.0, 100.0)
const DETAIL_POS := Vector2(32.0, 758.0)
const DETAIL_SZ := 300.0
const STAT_X := 381.0
const STAT_Y0 := 800.0
const STAT_DY := 76.0
const SBTN0 := Vector2(1532.0, 1002.0)
const SBTN_DX := 104.0

# ---------------- 图标索引（card_auto 图集） ----------------
const I_ATK := 0
const I_SPD := 1
const I_HP := 2
const I_RANGE := 3
const I_SOLDIER := 4
const I_BUILDING := 5
const I_COMMAND := 6
const I_QUEEN := 7

const HAND_MAX := 4
const COST_MAX := 10
const ROUND_MAX := 12

enum Phase { REFUND, FIELD, DEPLOY, ACTION }
const PHASE_NAME := ["回费", "场地", "部署", "行动"]
enum Mode { IDLE, DEPLOY_TARGET, CMD_TARGET }

# ---------------- 卡池（含效果/支援/回费/治疗） ----------------
const POOL := [
	{"art": "卡牌a-金刚蜂王", "name": "金刚蜂王", "kind": "queen", "cost": 8, "atk": 7, "spd": 1, "hp": 8, "range": 2},
	{"art": "卡牌c1-叶蜂", "name": "叶蜂", "kind": "soldier", "cost": 2, "atk": 2, "spd": 1, "hp": 3, "range": 1, "support": {"id": "rally", "name": "鼓舞", "rng": 2, "buff": {"id": "atk_up", "atk_add": 1}}},
	{"art": "卡牌c1-泥蜂", "name": "泥蜂", "kind": "soldier", "cost": 2, "atk": 3, "spd": 1, "hp": 4, "range": 2},
	{"art": "卡牌c2-熊蜂", "name": "熊蜂", "kind": "soldier", "cost": 5, "atk": 5, "spd": 1, "hp": 8, "range": 1, "support": {"id": "guard", "name": "护卫", "rng": 1, "buff": {"id": "def_up", "reduce": 1}}},
	{"art": "卡牌b1-蜂巢", "name": "蜂巢", "kind": "building", "cost": 4, "atk": 0, "spd": 0, "hp": 5, "range": 0, "refund": 1},
	{"art": "卡牌b1-蜂巢III", "name": "蜂巢III", "kind": "building", "cost": 9, "atk": 0, "spd": 0, "hp": 12, "range": 0, "refund": 2},
	{"art": "卡牌d1-电击", "name": "电击", "kind": "command", "cost": 3, "dmg": 4, "range": 2},
	{"art": "卡牌d1-电击III", "name": "电击III", "kind": "command", "cost": 7, "dmg": 9, "range": 3},
	{"art": "卡牌d1-巡航导弹", "name": "巡航导弹", "kind": "command", "cost": 6, "dmg": 5, "range": 3, "debuff": {"id": "burn", "name": "灼烧", "dot": 1}},
	{"art": "卡牌d2-治疗", "name": "治疗", "kind": "command", "cost": 3, "heal": 4, "range": 2},
	{"art": "卡牌d1-电击", "name": "X费·毁灭", "kind": "command_x", "cost": -1, "dmg": 0, "range": 3},
]

## 卡组：1 蜂王 + 8 常规卡（同名 ≤4）
const DECK_LIST := ["叶蜂", "叶蜂", "泥蜂", "泥蜂", "熊蜂", "蜂巢", "电击", "治疗"]

# ---------------- 状态 ----------------
var round_no := 1
var phase: Phase = Phase.REFUND
var current := "green"
var mode: Mode = Mode.IDLE
var cost := {"green": 0, "red": 0}
var hand := {"green": [], "red": []}
var deckl := {"green": [], "red": []}
var grave := {"green": [], "red": []}
var units := {}
var terrain := {}                    # cell -> {id,name,atk_add,spd_add}
var next_id := 1
var winner := ""
var log_lines: Array = []

var armed_card := -1
var selected_unit := -1
var move_range: Array[Vector2i] = []
var atk_range: Array[Vector2i] = []
var help_on := false

# ---------------- 节点 ----------------
var _holder: Node2D
var _cards_node: Node2D
var _units_node: Node2D
var _text_node: Node2D
var _hl_node: Node2D
var _detail_node: Node2D
var _hand_nodes := {"green": [], "red": []}
var _unit_nodes := {}
var _labels := {}


# ============================================================
func _ready() -> void:
	_holder = UI_SCENE.instantiate()
	add_child(_holder)
	_holder = _holder.get_node("Holder")
	_cards_node = _mk("HandCards")
	_units_node = _mk("Units")
	_text_node = _mk("Texts")
	_hl_node = _mk("Highlights")
	_detail_node = _mk("Detail")
	_prepare()
	_build_texts()
	_refresh()


func _mk(n: String) -> Node2D:
	var x := Node2D.new()
	x.name = n
	_holder.add_child(x)
	return x


# ============================================================
# 对战准备（A5 对战准备 1-9）
# ============================================================
func _prepare() -> void:
	for side in ["green", "red"]:
		var cards: Array = []
		for nm in DECK_LIST:
			cards.append(_find_card(nm))
		deckl[side] = cards
		for i in HAND_MAX:
			_draw_one(side)
	cost["green"] = 2
	cost["red"] = 4                                   # 后手初始 +2
	# 抽取对战地图：随机 2 格特殊地形
	var spots := [Vector2i(1, 1), Vector2i(2, 2), Vector2i(1, 2), Vector2i(2, 1)]
	spots.shuffle()
	for i in 2:
		terrain[spots[i]] = {"id": "hive_ground", "name": "蜂巢地面", "atk_add": 1, "spd_add": 0}
	# 部署蜂王
	_spawn(Vector2i(3, 1), "green", _find_card("金刚蜂王"))
	_spawn(Vector2i(0, 2), "red", _find_card("金刚蜂王"))
	_push("对战开始：绿方先手（费用2）· 红方后手（费用4）")


func _find_card(nm: String) -> Dictionary:
	for c in POOL:
		if c["name"] == nm:
			return c
	return POOL[1]


func _draw_one(side: String) -> void:
	if hand[side].size() >= HAND_MAX:
		return
	if deckl[side].is_empty():
		# 牌库抽完：墓地前 4 张洗回牌库（A5 抽卡 5）
		if grave[side].is_empty():
			return
		var back: Array = []
		for i in mini(4, grave[side].size()):
			back.append(grave[side].pop_front())
		back.shuffle()
		deckl[side].append_array(back)
		_push("%s方 牌库抽完 → 墓地 4 张洗回" % _cn(side))
	if deckl[side].is_empty():
		return
	hand[side].append(deckl[side].pop_front())


func _spawn(cell: Vector2i, side: String, card: Dictionary) -> int:
	var id := next_id
	next_id += 1
	units[id] = {"cell": cell, "side": side, "card": card, "hp": int(card["hp"]),
		"acted": true, "effects": {}, "blank": false}
	return id


func unit_at(cell: Vector2i) -> int:
	for id in units:
		if units[id]["cell"] == cell:
			return id
	return -1


# ============================================================
# 回合流程（A5 回合流程 1-8）
# ============================================================
func advance_phase() -> void:
	match phase:
		Phase.REFUND:
			phase = Phase.FIELD
			_apply_terrain()
		Phase.FIELD:
			phase = Phase.DEPLOY
		Phase.DEPLOY:
			phase = Phase.ACTION
		Phase.ACTION:
			_end_turn()
			return
	_clear_sel()
	_refresh()


func _apply_terrain() -> void:
	for id in units:
		var c: Vector2i = units[id]["cell"]
		if terrain.has(c):
			_push("%s 受地形 %s 影响（攻+%d）" % [_unit_name(id), terrain[c]["name"], int(terrain[c]["atk_add"])])


func _end_turn() -> void:
	# 灼烧等持续效果结算
	for id in units.keys():
		var eff: Dictionary = units[id]["effects"]
		if eff.has("burn"):
			units[id]["hp"] = int(units[id]["hp"]) - int(eff["burn"]["dot"])
			_push("%s 受灼烧 -%d" % [_unit_name(id), int(eff["burn"]["dot"])])
	_cleanup_dead()
	if winner != "":
		_refresh()
		return
	if current == "green":
		current = "red"
	else:
		current = "green"
		round_no += 1
	var gain := 2 + (2 if round_no >= 7 else 0)           # A5 费用 3
	cost[current] = mini(cost[current] + gain, COST_MAX)
	for side in ["green", "red"]:
		while hand[side].size() < HAND_MAX:
			_draw_one(side)
	for id in units:
		units[id]["acted"] = false                        # A5 行动机会 2
	phase = Phase.REFUND
	_clear_sel()
	_check_victory()
	if round_no > ROUND_MAX:
		_round12_result()
	_push("—— 第 %d 回合 · %s方 ——" % [round_no, _cn(current)])
	_refresh()


func surrender() -> void:
	if round_no < 4:                                      # A5 胜利条件 4
		_push("第 4 回合起才可投降")
		_refresh()
		return
	winner = "red" if current == "green" else "green"
	_push("%s方 投降，%s方 获胜" % [_cn(current), _cn(winner)])
	_refresh()


# ============================================================
# 出牌
# ============================================================
func select_hand(index: int) -> void:
	if index < 0 or index >= hand[current].size():
		return
	var c: Dictionary = hand[current][index]
	if c["kind"] == "command" or c["kind"] == "command_x":
		if phase == Phase.REFUND:
			return
		armed_card = index
		mode = Mode.CMD_TARGET
		selected_unit = -1
		move_range = []
		atk_range = _all_cells()
	else:
		if phase != Phase.DEPLOY:
			return
		armed_card = index
		mode = Mode.DEPLOY_TARGET
		selected_unit = -1
		move_range = []
		atk_range = []
	_refresh()


func _legal_place(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= ROWS or cell.y < 0 or cell.y >= COLS:
		return false
	if unit_at(cell) >= 0:
		return false
	var c: Dictionary = hand[current][armed_card]
	match c["kind"]:
		"building":
			return (cell.x >= 2) if current == "green" else (cell.x < 2)
		"soldier":
			return _adjacent_own_queen(cell)
	return false


func _adjacent_own_queen(cell: Vector2i) -> bool:
	for id in units:
		var u: Dictionary = units[id]
		if u["side"] == current and u["card"]["kind"] == "queen":
			var q: Vector2i = u["cell"]
			if abs(q.x - cell.x) + abs(q.y - cell.y) == 1:
				return true
	return false


func _pay(c: Dictionary) -> int:
	var pc: int = int(c["cost"])
	if pc < 0:                                            # X费卡：目标部署费用（A5 费用 4）
		return pc
	return pc


func place_at(cell: Vector2i) -> void:
	if armed_card < 0 or not _legal_place(cell):
		return
	var c: Dictionary = hand[current][armed_card]
	if cost[current] < int(c["cost"]):
		_push("费用不足")
		return
	cost[current] -= int(c["cost"])
	_spawn(cell, current, c)
	grave[current].append(c)                              # 原卡入墓地（A5 抽卡 2）
	hand[current].remove_at(armed_card)
	_push("%s方 部署 %s @(%d,%d)" % [_cn(current), c["name"], cell.x, cell.y])
	_clear_sel()
	_refresh()


func cmd_at(cell: Vector2i) -> void:
	if armed_card < 0:
		return
	var c: Dictionary = hand[current][armed_card]
	var tid := unit_at(cell)
	var target: Dictionary = {}
	if tid >= 0:
		target = units[tid]["card"]
	var pc: int = int(c["cost"])
	if c["kind"] == "command_x":
		if tid < 0 or target["kind"] == "queen":
			_push("X费卡：需指定一个非蜂王单位（费用=其部署费用）")
			_refresh()
			return
		pc = int(target["cost"])
	if cost[current] < pc:
		_push("费用不足（需 %d）" % pc)
		_refresh()
		return
	# 蜂王免疫指令伤害/减益（A5 卡牌类型 1）
	if tid >= 0 and target["kind"] == "queen":
		_push("蜂王免疫指令卡效果")
		_refresh()
		return
	cost[current] -= pc
	if tid >= 0:
		if c.has("heal"):
			units[tid]["hp"] = mini(int(units[tid]["hp"]) + int(c["heal"]), int(target["hp"]))
			_push("%s 治疗 +%d" % [_unit_name(tid), int(c["heal"])])
		else:
			var dmg := int(c.get("dmg", 0))
			if c["kind"] == "command_x":
				dmg = int(target["cost"]) * 2
			units[tid]["hp"] = int(units[tid]["hp"]) - dmg
			_push("%s 受指令伤害 -%d" % [_unit_name(tid), dmg])
			if c.has("debuff"):
				_add_effect(tid, c["debuff"])
	grave[current].append(c)
	hand[current].remove_at(armed_card)
	_cleanup_dead()
	_clear_sel()
	_check_victory()
	_refresh()


# ============================================================
# 行动（移动 / 攻击 / 支援技能）
# ============================================================
func select_unit_at(cell: Vector2i) -> void:
	var id := unit_at(cell)
	if id < 0 or units[id]["side"] != current:
		return
	if phase != Phase.ACTION or units[id]["acted"]:
		return
	selected_unit = id
	armed_card = -1
	mode = Mode.IDLE
	var u: Dictionary = units[id]
	var c: Vector2i = u["cell"]
	move_range = _range(c, _final_spd(id), true)
	atk_range = _range(c, _final_range(id), false)
	_refresh()


func act_at(cell: Vector2i) -> void:
	if selected_unit < 0:
		return
	if cell in move_range and unit_at(cell) < 0:
		units[selected_unit]["cell"] = cell
		units[selected_unit]["acted"] = true
		_push("%s 移动到 (%d,%d)" % [_unit_name(selected_unit), cell.x, cell.y])
		_clear_sel()
		_refresh()
		return
	if cell in atk_range:
		var tid := unit_at(cell)
		if tid >= 0 and units[tid]["side"] != current:
			_attack(selected_unit, tid)
			units[selected_unit]["acted"] = true
			_clear_sel()
			_refresh()


## 支援技能（A5 行动机会 4/5）
func support_at(cell: Vector2i) -> void:
	if selected_unit < 0:
		return
	var u: Dictionary = units[selected_unit]
	if not u["card"].has("support"):
		_push("%s 无支援技能" % u["card"]["name"])
		_refresh()
		return
	var tid := unit_at(cell)
	if tid < 0 or units[tid]["side"] != current:
		return
	var dist: int = abs(cell.x - u["cell"].x) + abs(cell.y - u["cell"].y)
	if dist > int(u["card"]["support"]["rng"]):
		return
	_add_effect(tid, u["card"]["support"]["buff"])
	u["acted"] = true
	_push("%s 支援 %s" % [u["card"]["name"], _unit_name(tid)])
	_clear_sel()
	_refresh()


# ============================================================
# 战斗（A5 战斗系统）
# ============================================================
func _attack(aid: int, tid: int) -> void:
	# 攻击力变化优先 → 乘法优先于加法 → 攻击计算优先于伤害减免
	var raw := _final_atk(aid)
	var reduce := _final_reduce(tid)
	units[tid]["hp"] = int(units[tid]["hp"]) - maxi(0, raw - reduce)
	_push("%s 攻击 %s：%d" % [_unit_name(aid), _unit_name(tid), maxi(0, raw - reduce)])
	# 反击（射程外无效）
	var ac: Vector2i = units[aid]["cell"]
	var tc: Vector2i = units[tid]["cell"]
	var counter_on := int(units[tid]["hp"]) > 0
	if counter_on and abs(tc.x - ac.x) + abs(tc.y - ac.y) <= _final_range(tid):
		var craw := _final_atk(tid)
		units[aid]["hp"] = int(units[aid]["hp"]) - maxi(0, craw - _final_reduce(aid))
		_push("%s 反击：%d" % [_unit_name(tid), maxi(0, craw - _final_reduce(aid))])
	_cleanup_dead()


func _final_atk(id: int) -> int:
	var base := int(units[id]["card"].get("atk", 0))
	var add := 0
	var mult := 1.0
	for k in units[id]["effects"]:
		add += int(units[id]["effects"][k].get("atk_add", 0))
		mult *= float(units[id]["effects"][k].get("atk_mult", 1.0))
	var c: Vector2i = units[id]["cell"]
	if terrain.has(c):
		add += int(terrain[c]["atk_add"])
	return int(round(float(base + add) * mult))


func _final_spd(id: int) -> int:
	var s := int(units[id]["card"].get("spd", 0))
	var c: Vector2i = units[id]["cell"]
	if terrain.has(c):
		s += int(terrain[c]["spd_add"])
	return maxi(0, s)


func _final_range(id: int) -> int:
	return int(units[id]["card"].get("range", 0))


func _final_reduce(id: int) -> int:
	var r := 0
	for k in units[id]["effects"]:
		r += int(units[id]["effects"][k].get("reduce", 0))
	return r


## 效果：相同效果最多一个；单位类型不匹配不赋予（A5 效果 1/2）
func _add_effect(id: int, eff: Dictionary) -> void:
	var eid: String = eff["id"]
	var existing: Dictionary = units[id]["effects"]
	if existing.has(eid):
		_push("%s 已有相同效果「%s」，不再叠加" % [_unit_name(id), eff.get("name", eid)])
		return
	existing[eid] = eff
	_push("%s 获得效果「%s」" % [_unit_name(id), eff.get("name", eid)])


func _cleanup_dead() -> void:
	var dead: Array = []
	for id in units:
		if int(units[id]["hp"]) <= 0:
			dead.append(id)
	for id in dead:
		var nm := _unit_name(id)
		units.erase(id)
		_push("%s 退场" % nm)


func _range(from: Vector2i, rng: int, need_free: bool) -> Array[Vector2i]:
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


func _all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in ROWS:
		for c in COLS:
			out.append(Vector2i(r, c))
	return out


# ============================================================
# 胜负（A5 胜利条件）
# ============================================================
func _check_victory() -> void:
	if winner != "":
		return
	var gq := _queen_alive("green")
	var rq := _queen_alive("red")
	if not gq and not rq:
		winner = "draw"
	elif not gq:
		winner = "red"
	elif not rq:
		winner = "green"
	if winner != "":
		_push("游戏结束：%s" % ("平局" if winner == "draw" else _cn(winner) + "方 获胜"))


func _queen_alive(side: String) -> bool:
	for id in units:
		if units[id]["side"] == side and units[id]["card"]["kind"] == "queen":
			return true
	return false


func _queen_hp(side: String) -> int:
	for id in units:
		if units[id]["side"] == side and units[id]["card"]["kind"] == "queen":
			return int(units[id]["hp"])
	return 0


func _round12_result() -> void:
	if winner != "":
		return
	var gh := _queen_hp("green")
	var rh := _queen_hp("red")
	if gh == rh:
		winner = "draw"
	else:
		winner = "green" if gh > rh else "red"
	_push("第12回合结束：蜂王血量 绿%d / 红%d → %s" % [gh, rh, "平局" if winner == "draw" else _cn(winner) + "方 获胜"])


func _clear_sel() -> void:
	armed_card = -1
	selected_unit = -1
	mode = Mode.IDLE
	move_range = []
	atk_range = []


func _push(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 60:
		log_lines.pop_front()


func _cn(side: String) -> String:
	return "绿" if side == "green" else ("红" if side == "red" else "—")


func _unit_name(id: int) -> String:
	return units[id]["card"]["name"] if units.has(id) else "?"


# ============================================================
# 渲染（全部复用 card-system 组件）
# ============================================================
func _refresh() -> void:
	_render_hand("green")
	_render_hand("red")
	_render_units()
	_render_highlights()
	_render_detail()
	_update_texts()


func _render_hand(side: String) -> void:
	for n in _hand_nodes[side]:
		n.queue_free()
	_hand_nodes[side] = []
	var base: Vector2 = PANEL_L if side == "green" else PANEL_R
	var cards: Array = hand[side]
	for i in cards.size():
		var node := _make_card(cards[i], 0.5)
		var col := i % 2
		@warning_ignore("integer_division")
		var rowi := i / 2
		node.position = base + Vector2(18.0 + col * 195.0, 18.0 + rowi * 195.0)
		_cards_node.add_child(node)
		_hand_nodes[side].append(node)


func _render_units() -> void:
	for n in _unit_nodes.values():
		n.queue_free()
	_unit_nodes = {}
	for id in units:
		var u: Dictionary = units[id]
		var node := _make_card(u["card"], 1.0)
		var cell: Vector2i = u["cell"]
		node.position = MAP_ORIGIN + Vector2(cell.y * CELL, cell.x * CELL)
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


func _render_highlights() -> void:
	for n in _hl_node.get_children():
		n.queue_free()
	for cell in move_range:
		_hl_node.add_child(_hl(cell, Color(0.25, 0.85, 0.45, 0.35)))
	for cell in atk_range:
		_hl_node.add_child(_hl(cell, Color(0.90, 0.25, 0.20, 0.32)))
	if armed_card >= 0 and mode == Mode.DEPLOY_TARGET:
		for r in ROWS:
			for c in COLS:
				var cell := Vector2i(r, c)
				if _legal_place(cell):
					_hl_node.add_child(_hl(cell, Color(1.0, 0.80, 0.30, 0.35)))
	for c in terrain:
		_hl_node.add_child(_hl(c, Color(0.95, 0.80, 0.10, 0.18)))


func _hl(cell: Vector2i, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = MAP_ORIGIN + Vector2(cell.y * CELL, cell.x * CELL)
	r.size = Vector2(CELL, CELL)
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _make_card(d: Dictionary, sc: float) -> Node2D:
	var node := CARD.instantiate()
	node.scale = Vector2(sc, sc)
	node.set("art", load(ART_DIR + d["art"] + ".png"))
	node.set("cost", int(d["cost"]))
	node.set("art_fit", 1)
	node.set("art_zoom", 1.05)
	match d["kind"]:
		"queen":
			node.set("icon_tag", I_QUEEN)
		"soldier":
			node.set("icon_tag", I_SOLDIER)
		"building":
			node.set("icon_tag", I_BUILDING)
		_:
			node.set("icon_tag", I_COMMAND)
	if d["kind"] == "command" or d["kind"] == "command_x":
		node.set("stat_l1", int(d.get("dmg", 0)) if not d.has("heal") else int(d["heal"]))
		node.set("icon_l1", I_ATK if not d.has("heal") else I_HP)
		node.set("stat_l2", -1)
		node.set("icon_l2", -1)
		node.set("stat_r1", -1)
		node.set("icon_r1", -1)
		node.set("stat_r2", int(d.get("range", 0)))
		node.set("icon_r2", I_RANGE)
	else:
		node.set("stat_l1", int(d.get("atk", -1)))
		node.set("icon_l1", I_ATK if int(d.get("atk", 0)) > 0 else -1)
		node.set("stat_l2", int(d.get("spd", -1)))
		node.set("icon_l2", I_SPD if int(d.get("spd", 0)) > 0 else -1)
		node.set("stat_r1", int(d.get("hp", -1)))
		node.set("icon_r1", I_HP)
		node.set("stat_r2", int(d.get("range", -1)))
		node.set("icon_r2", I_RANGE if int(d.get("range", 0)) > 0 else -1)
	return node


## 左下 300x300 卡牌详情块：显示当前选中卡/单位的大卡（缩放 300/250=1.2）
func _render_detail() -> void:
	for n in _detail_node.get_children():
		n.queue_free()
	var d: Dictionary = {}
	if armed_card >= 0 and armed_card < hand[current].size():
		d = hand[current][armed_card]
	elif selected_unit >= 0 and units.has(selected_unit):
		d = units[selected_unit]["card"]
	elif current == "red" and not hand["red"].is_empty():
		d = hand["red"][0]
	elif not hand["green"].is_empty():
		d = hand["green"][0]
	if d.is_empty():
		return
	var node := _make_card(d, 1.2)
	node.position = DETAIL_POS
	_detail_node.add_child(node)


# ============================================================
# 文字层（battle_ui 明确"文字一律不画"，此处补）
# ============================================================
func _build_texts() -> void:
	_labels["gcost"] = _mk_label(HEX_L, 40, Color(0.14, 0.14, 0.14), 1)
	_labels["rcost"] = _mk_label(HEX_R, 40, Color(0.14, 0.14, 0.14), 1)
	_labels["info"] = _mk_label(Vector2(452.0, 4.0), 26, Color(1, 1, 1), 0)
	_labels["btn"] = _mk_label(BTN_MAIN + Vector2(250.0, 26.0), 34, Color(0.14, 0.14, 0.14), 1)
	_labels["gs"] = _mk_label(Vector2(120.0, 146.0), 22, Color(0.78, 1.0, 0.80), 0)
	_labels["rs"] = _mk_label(Vector2(1576.0, 146.0), 22, Color(1.0, 0.80, 0.80), 0)
	_labels["gname"] = _mk_label(Vector2(60.0, 58.0), 20, Color(0.10, 0.10, 0.10), 1)
	_labels["rname"] = _mk_label(Vector2(1516.0, 58.0), 20, Color(0.10, 0.10, 0.10), 1)
	# 左下状态图标列旁的数值（复用 shader 已画的 4 个图标：剑/盾/速度/准星）
	_labels["st0"] = _mk_label(Vector2(STAT_X + 26.0, STAT_Y0 - 16.0), 30, Color(1, 1, 1), 0)
	_labels["st1"] = _mk_label(Vector2(STAT_X + 26.0, STAT_Y0 + STAT_DY - 16.0), 30, Color(1, 1, 1), 0)
	_labels["st2"] = _mk_label(Vector2(STAT_X + 26.0, STAT_Y0 + STAT_DY * 2 - 16.0), 30, Color(1, 1, 1), 0)
	_labels["st3"] = _mk_label(Vector2(STAT_X + 26.0, STAT_Y0 + STAT_DY * 3 - 16.0), 30, Color(1, 1, 1), 0)
	_labels["log"] = _mk_label(Vector2(1494.0, 674.0), 17, Color(0.86, 0.86, 0.86), 0)
	_labels["help"] = _mk_label(Vector2(452.0, 120.0), 20, Color(1.0, 0.95, 0.75), 0)


func _mk_label(pos: Vector2, size: int, col: Color, center: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if center == 1:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(96.0, 0.0)
		l.position = pos - Vector2(48.0, 0.0)
	_text_node.add_child(l)
	return l


func _update_texts() -> void:
	_labels["gcost"].text = str(cost["green"])
	_labels["rcost"].text = str(cost["red"])
	_labels["gname"].text = "绿方"
	_labels["rname"].text = "红方"
	_labels["gs"].text = "绿方领地"
	_labels["rs"].text = "红方领地"
	var hint := ""
	match mode:
		Mode.DEPLOY_TARGET:
			hint = "点高亮格放置"
		Mode.CMD_TARGET:
			hint = "点目标格使用指令"
		_:
			hint = "点牌选中 / 点己方单位行动"
	_labels["info"].text = "第%d回合 · 阶段:%s · %s方 · %s" % [round_no, PHASE_NAME[phase], _cn(current), hint]
	for k in ["gcost", "rcost"]:
		_labels[k].position = (HEX_L if k == "gcost" else HEX_R) - Vector2(48.0, 22.0)
	_labels["btn"].text = "结束阶段" if phase != Phase.ACTION else "结束回合"
	if winner != "":
		_labels["btn"].text = "游戏结束"
	var sid := selected_unit if selected_unit >= 0 else _queen_id_of(current)
	_labels["st0"].text = str(_final_atk(sid)) if sid >= 0 else "-"
	_labels["st1"].text = str(_final_reduce(sid)) if sid >= 0 else "-"
	_labels["st2"].text = str(_final_spd(sid)) if sid >= 0 else "-"
	_labels["st3"].text = str(_final_range(sid)) if sid >= 0 else "-"
	_labels["log"].text = "\n".join(log_lines.slice(maxi(0, log_lines.size() - 6), log_lines.size()))
	_labels["help"].text = "A5 规则速览：蜂王被击败即负 | 第12回合比蜂王血量 | 第4回合起可投降\n兵蜂→蜂王相邻格 · 建筑→己方领地 · 指令→任意目标(蜂王免疫)\n每单位每回合1次行动(移动/攻击/支援) · 反击射程外无效" if help_on else ""


func _queen_id_of(side: String) -> int:
	for id in units:
		if units[id]["side"] == side and units[id]["card"]["kind"] == "queen":
			return id
	return -1


# ============================================================
# 输入
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if winner != "":
		return
	var p := _to_design(mb.position)

	if Rect2(BTN_MAIN, BTN_MAIN_SZ).has_point(p):
		advance_phase()
		return
	# 右下 4 个小按钮：螺母=规则帮助 / 笑脸=投降确认 / 信息=日志 / 退出=投降
	for k in 4:
		if Rect2(SBTN0 + Vector2(k * SBTN_DX, 0.0) - Vector2(44.0, 44.0), Vector2(88.0, 88.0)).has_point(p):
			match k:
				0:
					help_on = not help_on
				2:
					_push("回合%d/%d · %s方 · 费%d" % [round_no, ROUND_MAX, _cn(current), cost[current]])
				3:
					surrender()
			_refresh()
			return
	# 手牌
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
	if armed_card >= 0 and mode == Mode.DEPLOY_TARGET:
		place_at(cell)
	elif armed_card >= 0 and mode == Mode.CMD_TARGET:
		cmd_at(cell)
	elif selected_unit >= 0:
		# 右键语义此处简化：支援技能用 Shift 点击由 support_at 承担（见下）
		if Input.is_key_pressed(KEY_SHIFT):
			support_at(cell)
		else:
			act_at(cell)
	else:
		select_unit_at(cell)


func _to_design(screen_pos: Vector2) -> Vector2:
	var xf := (_holder.get_global_transform() as Transform2D).affine_inverse()
	return xf * screen_pos
