extends Node
## ============================================================
## BattleState —— 战斗规则状态机（Model 层）
##   职责：持有并维护全部规则状态；对外只暴露"语义动作"；状态变化统一 emit 信号。
##   不做渲染、不读输入（输入由 BattleInput 转成语义信号后连到本节点的槽）。
##   规则依据: 电子蜂a500规则.md
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

# ---------------- 信号（视图/协调器订阅） ----------------
signal state_changed()                               ## 通用"状态已变，请重绘"
signal turn_started(side: String, round_no: int)     ## 新回合开始
signal phase_changed(phase: int)                     ## 阶段变化
signal log_added(text: String)                       ## 追加一条日志
signal battle_ended(winner: String)                  ## 胜负已定
signal selection_changed()                           ## 选中/待放置状态变化

# ---------------- 状态 ----------------
var round_no := 1
var phase: int = D.Phase.REFUND
var current := "green"
var mode: int = D.Mode.IDLE
var cost := {"green": 0, "red": 0}
var hand := {"green": [], "red": []}
var deckl := {"green": [], "red": []}
var grave := {"green": [], "red": []}
var units := {}
var terrain := {}
var next_id := 1
var winner := ""
var log_lines: Array = []
var help_on := false

var armed_card := -1
var selected_unit := -1
var move_range: Array[Vector2i] = []
var atk_range: Array[Vector2i] = []

## a500 对战准备：本局先手方 / 抽取到的地图名（回合数以「先手方再次开始回合」为界）
var first_side := "green"
var map_name := ""

## 由协调器注入
var combat: Node = null
var started := false


# ============================================================
# 生命周期 / 对战准备（a500 对战准备）
# ============================================================
func start() -> void:
	if started:
		return
	started = true
	_prepare()


func _prepare() -> void:
	# a500 构筑 2：前 4 张常规卡为初始手牌、后 4 张为备卡
	for side in ["green", "red"]:
		var cards: Array = []
		for nm in D.DECK_LIST:
			cards.append(D.card(nm))
		hand[side] = []
		deckl[side] = []
		for i in cards.size():
			if i < D.HAND_MAX:
				hand[side].append(cards[i])
			else:
				deckl[side].append(cards[i])
	# a500 对战准备 6：随机决定先后手（后手初始费用 +2）
	var order := ["green", "red"]
	order.shuffle()
	first_side = order[0]
	cost["green"] = 0
	cost["red"] = 0
	cost[order[1]] = D.SECOND_PLAYER_BONUS
	# a500 对战准备 5：抽取对战地图；提前部署蜂王并载入手牌
	draw_map()
	spawn(Vector2i(3, 1), "green", D.card("金刚蜂王"))
	spawn(Vector2i(0, 2), "red", D.card("金刚蜂王"))
	push_log("对战开始：%s方先手 · %s方后手（初始费用 +2）" % [cn(order[0]), cn(order[1])])
	push_log("牌组：初始手牌 %d 张 + 备卡 %d 张（a500 构筑 2）" % [hand[first_side].size(), deckl[first_side].size()])
	begin_turn(first_side)


## a500 对战准备 5：抽取对战地图（从地图池随机，播报地图名与特殊地形）
func draw_map() -> void:
	var maps: Array = D.MAP_POOL
	var m: Dictionary = maps[randi() % maps.size()]
	map_name = str(m["name"])
	terrain.clear()
	for c in m["terrain_cells"]:
		terrain[c] = {"id": m["terrain_id"], "name": m["terrain_name"],
			"atk_add": int(m["terrain_atk_add"]), "spd_add": int(m["terrain_spd_add"])}
	push_log("地图「%s」：特殊地形 %d 格「%s」（%s）" % [map_name, terrain.size(), m["terrain_name"], m["terrain_desc"]])


func draw_one(side: String) -> void:
	if hand[side].size() >= D.HAND_MAX:
		return
	if deckl[side].is_empty():
		# a500：牌库抽完 -> 立刻把墓地前 4 张按随机顺序放回牌库
		if grave[side].is_empty():
			return
		var back: Array = []
		for i in mini(4, grave[side].size()):
			back.append(grave[side].pop_front())
		back.shuffle()
		deckl[side].append_array(back)
		push_log("%s方 牌库抽完 → 墓地 4 张洗回" % cn(side))
	if deckl[side].is_empty():
		return
	hand[side].append(deckl[side].pop_front())


func spawn(cell: Vector2i, side: String, card: Dictionary) -> int:
	var id := next_id
	next_id += 1
	# acted=true：部署当回合没有行动机会（a500 行动机会 3）；moved 一并用尽
	units[id] = {"cell": cell, "side": side, "card": card, "hp": int(card["hp"]),
		"acted": true, "moved": true, "effects": {}}
	return id


func unit_at(cell: Vector2i) -> int:
	for id in units:
		if units[id]["cell"] == cell:
			return id
	return -1


# ============================================================
# 回合流程（a500：回费/场地自动 → 部署 → 行动）
# ============================================================
## 主按钮：只服务"需要玩家确认"的 部署 / 行动 两个阶段；选中手牌时执行「弃卡过牌」
func advance_phase() -> void:
	if winner != "":
		return
	# a500 UI：选中手牌时主按钮执行「弃卡过牌」
	if armed_card >= 0:
		discard_armed()
		return
	match phase:
		D.Phase.DEPLOY:
			phase = D.Phase.ACTION
			phase_changed.emit(phase)
			clear_sel()
			refresh()
		D.Phase.ACTION:
			end_turn()


## a500 抽卡 6：丢弃手牌消耗 = 该卡部署费用；X 费卡丢弃消耗 10 点
## 弃卡后该卡入墓地，并补充 1 张手牌（保持 a500 抽卡 4「补至 4 张」的节奏）
func discard_armed() -> void:
	if armed_card < 0 or armed_card >= hand[current].size():
		return
	var c: Dictionary = hand[current][armed_card]
	var pc: int = int(c["cost"])
	if pc < 0:
		pc = D.COST_MAX
	if cost[current] < pc:
		push_log("费用不足（弃卡需 %d，现有 %d）" % [pc, cost[current]])
		refresh()
		return
	cost[current] -= pc
	grave[current].append(c)
	hand[current].remove_at(armed_card)
	draw_one(current)
	push_log("%s方 弃置「%s」（-%d 费）→ 补充 1 张手牌" % [cn(current), c["name"], pc])
	clear_sel()
	refresh()


## 当前是否可以弃卡（供 HUD 决定主按钮文案）
func can_discard() -> bool:
	return winner == "" and armed_card >= 0 and armed_card < hand[current].size()


func begin_turn(side: String) -> void:
	current = side
	turn_started.emit(side, round_no)
	push_log("—— 第 %d 回合 · %s方 ——" % [round_no, cn(side)])
	# 回费阶段（自动）：基础回费 + 资源建筑回费
	phase = D.Phase.REFUND
	phase_changed.emit(phase)
	var gain := D.BASE_REFUND + (D.ROUND7_EXTRA if round_no >= 7 else 0)
	var rf := refund_of(side)
	cost[side] = mini(cost[side] + gain + rf, D.COST_MAX)
	if rf > 0:
		push_log("【回费】%s方 +%d（基础%d + 资源建筑%d）→ 费用 %d（上限 %d）" % [cn(side), gain + rf, gain, rf, cost[side], D.COST_MAX])
	else:
		push_log("【回费】%s方 +%d → 费用 %d（上限 %d）" % [cn(side), gain, cost[side], D.COST_MAX])
	# 场地阶段（自动）
	phase = D.Phase.FIELD
	phase_changed.emit(phase)
	_apply_terrain()
	# 停在部署阶段等玩家操作
	phase = D.Phase.DEPLOY
	phase_changed.emit(phase)
	for id in units:
		units[id]["acted"] = false
		units[id]["moved"] = false
	clear_sel()
	refresh()


func end_turn() -> void:
	# 结算持续效果（灼烧等）
	for id in units.keys():
		var eff: Dictionary = units[id]["effects"]
		if eff.has("burn"):
			units[id]["hp"] = int(units[id]["hp"]) - int(eff["burn"]["dot"])
			push_log("%s 受灼烧 -%d" % [unit_name(id), int(eff["burn"]["dot"])])
	remove_dead()
	if winner != "":
		refresh()
		return
	var next := "red" if current == "green" else "green"
	# 回合数以「先手方再次开始回合」为界（先手方随机，不能写死绿方）
	if next == first_side:
		round_no += 1
	for side in ["green", "red"]:
		while hand[side].size() < D.HAND_MAX:
			draw_one(side)
	check_victory()
	if round_no > D.ROUND_MAX:
		round12_result()
	if winner != "":
		refresh()
		return
	begin_turn(next)


func _apply_terrain() -> void:
	for id in units:
		var c: Vector2i = units[id]["cell"]
		if terrain.has(c):
			push_log("%s 受地形 %s 影响（攻+%d）" % [unit_name(id), terrain[c]["name"], int(terrain[c]["atk_add"])])


func surrender() -> void:
	if round_no < 4:
		push_log("第 4 回合起才可投降")
		refresh()
		return
	winner = "red" if current == "green" else "green"
	push_log("%s方 投降，%s方 获胜" % [cn(current), cn(winner)])
	battle_ended.emit(winner)
	refresh()


## 资源建筑回费合计（a500 基础术语·资源建筑）
func refund_of(side: String) -> int:
	var sum := 0
	for id in units:
		var u: Dictionary = units[id]
		if u["side"] == side:
			sum += int(u["card"].get("refund", 0))
	return sum


# ============================================================
# 出牌
# ============================================================
func select_hand(index: int) -> void:
	if winner != "":
		return
	if index < 0 or index >= hand[current].size():
		return
	var c: Dictionary = hand[current][index]
	if c["kind"] == "command" or c["kind"] == "command_x":
		if phase == D.Phase.REFUND or phase == D.Phase.FIELD:
			return
		armed_card = index
		mode = D.Mode.CMD_TARGET
		selected_unit = -1
		move_range = []
		atk_range = all_cells()
	else:
		if phase != D.Phase.DEPLOY:
			return
		armed_card = index
		mode = D.Mode.DEPLOY_TARGET
		selected_unit = -1
		move_range = []
		atk_range = []
	selection_changed.emit()
	refresh()


func legal_place(cell: Vector2i) -> bool:
	if not D.in_map(cell):
		return false
	if unit_at(cell) >= 0:
		return false
	if armed_card < 0 or armed_card >= hand[current].size():
		return false
	var c: Dictionary = hand[current][armed_card]
	match c["kind"]:
		"building":
			return (cell.x >= 2) if current == "green" else (cell.x < 2)
		"soldier":
			return adjacent_own_queen(cell)
	return false


func adjacent_own_queen(cell: Vector2i) -> bool:
	for id in units:
		var u: Dictionary = units[id]
		if u["side"] == current and u["card"]["kind"] == "queen":
			var q: Vector2i = u["cell"]
			if abs(q.x - cell.x) + abs(q.y - cell.y) == 1:
				return true
	return false


func place_at(cell: Vector2i) -> void:
	if winner != "" or armed_card < 0 or not legal_place(cell):
		return
	var c: Dictionary = hand[current][armed_card]
	if cost[current] < int(c["cost"]):
		push_log("费用不足")
		return
	cost[current] -= int(c["cost"])
	spawn(cell, current, c)
	grave[current].append(c)
	hand[current].remove_at(armed_card)
	push_log("%s方 部署 %s @(%d,%d)" % [cn(current), c["name"], cell.x, cell.y])
	clear_sel()
	refresh()


func cmd_at(cell: Vector2i) -> void:
	if winner != "" or armed_card < 0:
		return
	var c: Dictionary = hand[current][armed_card]
	var tid := unit_at(cell)
	var target: Dictionary = units[tid]["card"] if tid >= 0 else {}
	var pc: int = int(c["cost"])
	if c["kind"] == "command_x":
		if tid < 0 or target["kind"] == "queen":
			push_log("X费卡：需指定一个非蜂王单位（费用=其部署费用）")
			refresh()
			return
		pc = int(target["cost"])
	if cost[current] < pc:
		push_log("费用不足（需 %d）" % pc)
		refresh()
		return
	# 蜂王免疫指令卡伤害与减益（a500 卡牌类型）
	if tid >= 0 and target["kind"] == "queen":
		push_log("蜂王免疫指令卡效果")
		refresh()
		return
	cost[current] -= pc
	if tid >= 0:
		if c.has("heal"):
			units[tid]["hp"] = mini(int(units[tid]["hp"]) + int(c["heal"]), int(target["hp"]))
			push_log("%s 治疗 +%d" % [unit_name(tid), int(c["heal"])])
		else:
			var dmg := int(c.get("dmg", 0))
			if c["kind"] == "command_x":
				dmg = int(target["cost"]) * 2
			units[tid]["hp"] = int(units[tid]["hp"]) - dmg
			push_log("%s 受指令伤害 -%d" % [unit_name(tid), dmg])
			if c.has("debuff"):
				add_effect(tid, c["debuff"])
	grave[current].append(c)
	hand[current].remove_at(armed_card)
	remove_dead()
	clear_sel()
	check_victory()
	refresh()


# ============================================================
# 行动（移动 / 攻击 / 支援）—— a500：1 次移动 + 1 次攻击或支援
# ============================================================
func select_unit_at(cell: Vector2i) -> void:
	var id := unit_at(cell)
	if id < 0 or units[id]["side"] != current:
		return
	if phase != D.Phase.ACTION or units[id]["acted"]:
		return
	selected_unit = id
	armed_card = -1
	mode = D.Mode.IDLE
	var c: Vector2i = units[id]["cell"]
	# a500 行动机会 4：行动 = 1 次移动 + 1 次（主动攻击或支援技能）；本回合已移动则移动范围为 0
	move_range = []
	if not units[id]["moved"]:
		move_range = move_cells(c, final_spd(id))
	# a500 范围 3：攻击范围不会被单位阻挡（按曼哈顿距离）
	atk_range = range_cells(c, final_range(id), false)
	selection_changed.emit()
	refresh()


func act_at(cell: Vector2i) -> void:
	if selected_unit < 0:
		return
	if not units.has(selected_unit):
		clear_sel()
		refresh()
		return
	if cell in move_range and unit_at(cell) < 0:
		# a500 行动机会 4：移动不结束行动 —— 移动后仍可攻击/支援；仅消耗"本回合移动"
		var uid := selected_unit
		units[uid]["cell"] = cell
		units[uid]["moved"] = true
		push_log("%s 移动到 (%d,%d)" % [unit_name(uid), cell.x, cell.y])
		# 就地重新选中：刷新为「不可再移动 + 仍可攻击/支援」的范围
		select_unit_at(cell)
		return
	if cell in atk_range:
		var tid := unit_at(cell)
		if tid >= 0 and units[tid]["side"] != current:
			# 先消耗行动机会再结算战斗：攻击方可能被反击打死，结算后会从 units 移除
			var aid := selected_unit
			units[aid]["acted"] = true
			if combat != null:
				combat.attack(aid, tid)
			remove_dead()
			clear_sel()
			check_victory()
			refresh()


func support_at(cell: Vector2i) -> void:
	if selected_unit < 0 or phase != D.Phase.ACTION:
		return
	if not units.has(selected_unit):
		clear_sel()
		refresh()
		return
	var u: Dictionary = units[selected_unit]
	if not u["card"].has("support"):
		push_log("%s 无支援技能" % u["card"]["name"])
		refresh()
		return
	var tid := unit_at(cell)
	if tid < 0 or units[tid]["side"] != current:
		return
	var dist: int = abs(cell.x - u["cell"].x) + abs(cell.y - u["cell"].y)
	if dist > int(u["card"]["support"]["rng"]):
		return
	add_effect(tid, u["card"]["support"]["buff"])
	u["acted"] = true
	push_log("%s 支援 %s" % [u["card"]["name"], unit_name(tid)])
	clear_sel()
	refresh()


## a500 效果机制：相同效果最多一个；类型不匹配不赋予（当前仅做"同名不叠加"）
func add_effect(id: int, eff: Dictionary) -> void:
	var eid: String = eff["id"]
	var existing: Dictionary = units[id]["effects"]
	if existing.has(eid):
		push_log("%s 已有相同效果「%s」，不再叠加" % [unit_name(id), eff.get("name", eid)])
		return
	existing[eid] = eff
	push_log("%s 获得效果「%s」" % [unit_name(id), eff.get("name", eid)])


func remove_dead() -> void:
	var dead: Array = []
	for id in units:
		if int(units[id]["hp"]) <= 0:
			dead.append(id)
	for id in dead:
		push_log("%s 退场" % unit_name(id))
		units.erase(id)


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


func all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in D.ROWS:
		for c in D.COLS:
			out.append(Vector2i(r, c))
	return out


# ============================================================
# 数值查询（转发给 BattleCombat，供视图显示）
# ============================================================
func final_atk(id: int) -> int:
	return int(combat.final_atk(id)) if combat != null else 0


func final_spd(id: int) -> int:
	return int(combat.final_spd(id)) if combat != null else 0


func final_range(id: int) -> int:
	return int(combat.final_range(id)) if combat != null else 0


func final_reduce(id: int) -> int:
	return int(combat.final_reduce(id)) if combat != null else 0


# ============================================================
# 胜负（a500 胜利条件）
# ============================================================
func check_victory() -> void:
	if winner != "":
		return
	var gq := queen_alive("green")
	var rq := queen_alive("red")
	if not gq and not rq:
		winner = "draw"
	elif not gq:
		winner = "red"
	elif not rq:
		winner = "green"
	if winner != "":
		push_log("游戏结束：%s" % ("平局" if winner == "draw" else cn(winner) + "方 获胜"))
		battle_ended.emit(winner)


func queen_alive(side: String) -> bool:
	for id in units:
		if units[id]["side"] == side and units[id]["card"]["kind"] == "queen":
			return true
	return false


func queen_hp(side: String) -> int:
	for id in units:
		if units[id]["side"] == side and units[id]["card"]["kind"] == "queen":
			return int(units[id]["hp"])
	return 0


func round12_result() -> void:
	if winner != "":
		return
	var gh := queen_hp("green")
	var rh := queen_hp("red")
	if gh == rh:
		winner = "draw"
	else:
		winner = "green" if gh > rh else "red"
	push_log("第12回合结束：蜂王血量 绿%d / 红%d → %s" % [gh, rh, "平局" if winner == "draw" else cn(winner) + "方 获胜"])
	battle_ended.emit(winner)


# ============================================================
# 输入语义槽（由 BattleInput 的信号连接）
# ============================================================
func on_hand_clicked(side: String, index: int) -> void:
	if side != current:
		return
	select_hand(index)


func on_cell_clicked(cell: Vector2i) -> void:
	if winner != "":
		return
	if armed_card >= 0 and mode == D.Mode.DEPLOY_TARGET:
		place_at(cell)
	elif armed_card >= 0 and mode == D.Mode.CMD_TARGET:
		cmd_at(cell)
	elif selected_unit >= 0:
		act_at(cell)
	else:
		select_unit_at(cell)


func on_support_clicked(cell: Vector2i) -> void:
	support_at(cell)


func on_small_pressed(index: int) -> void:
	match index:
		0:
			help_on = not help_on
		2:
			push_log("回合%d/%d · %s方 · 费%d" % [round_no, D.ROUND_MAX, cn(current), cost[current]])
		3:
			surrender()
	refresh()


# ============================================================
# 工具
# ============================================================
func clear_sel() -> void:
	armed_card = -1
	selected_unit = -1
	mode = D.Mode.IDLE
	move_range = []
	atk_range = []
	selection_changed.emit()


func push_log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 60:
		log_lines.pop_front()
	log_added.emit(s)


func cn(side: String) -> String:
	return "绿" if side == "green" else ("红" if side == "red" else "—")


func unit_name(id: int) -> String:
	return str(units[id]["card"]["name"]) if units.has(id) else "?"


## 当前"被查看"的卡（详情块与技能区共用）：选中卡 → 选中单位 → 当前方手牌首张
func current_detail_card() -> Dictionary:
	if armed_card >= 0 and armed_card < hand[current].size():
		return hand[current][armed_card]
	if selected_unit >= 0 and units.has(selected_unit):
		return units[selected_unit]["card"]
	if not hand[current].is_empty():
		return hand[current][0]
	return {}


## 当前查看对象的单位 id（无则退回当前方蜂王）
func focus_unit_id() -> int:
	if selected_unit >= 0 and units.has(selected_unit):
		return selected_unit
	return queen_id_of(current)


func queen_id_of(side: String) -> int:
	for id in units:
		if units[id]["side"] == side and units[id]["card"]["kind"] == "queen":
			return id
	return -1


## 通用刷新（视图订阅 state_changed 后各自重绘）
func refresh() -> void:
	state_changed.emit()
