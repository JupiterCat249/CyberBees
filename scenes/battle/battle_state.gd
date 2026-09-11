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
signal popup_requested(title: String, desc: String)  ## 请求弹出纯文本浮窗（投降确认等，复用 M3 浮窗）

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
## A5 UI：支援对象候选格（再次点击当前选中单位后进入支援对象选择）
var support_range: Array[Vector2i] = []
## A5 程序需求「点击确认攻击/部署/移动」：待确认目标（首次点=预览，再点同一目标=执行）
var pending_kind := ""
var pending_cell := Vector2i(-1, -1)
## 待确认预览数据（供视图显示：预计剩余血量 / 伤害等）
var preview := {}
## A5 UI：投降二次确认（确认 → 投降结算；取消 → 返回）
var surrender_pending := false

## a500 对战准备：本局先手方 / 抽取到的地图名（回合数以「先手方再次开始回合」为界）
var first_side := "green"
var map_name := ""
## a500 对战准备 5：准备阶段「调整初始手牌」——逐方剩余次数 + 当前操作的是哪一方的手牌
var exchange_left := {"green": 0, "red": 0}
var armed_side := ""

## 由协调器注入
var combat: Node = null
var skills = null             ## 结构化技能系统（迭代003，RefCounted）
var started := false
## 部署范围被动（机场）：逐方部署半径（a500 兵蜂限蜂王相邻格 → 被动可扩大）
var deploy_radius := {"green": 1, "red": 1}


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
	# a500 对战准备 5 + 9：进入「准备」阶段调整初始手牌（一次性），由主按钮开始第一回合
	current = first_side
	armed_side = ""
	exchange_left = {"green": D.EXCHANGE_MAX, "red": D.EXCHANGE_MAX}
	phase = D.Phase.PREPARE
	phase_changed.emit(phase)
	push_log("对战准备：可调整初始手牌（每方 %d 次），点主按钮「开始对局」进入第一回合" % D.EXCHANGE_MAX)
	refresh()


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
	# A5 UI：投降二次确认中，主按钮 = 确认投降
	if surrender_pending:
		surrender_pending = false
		surrender()
		return
	# a500 对战准备 5/9：准备阶段主按钮 = 换牌（可换牌时）/ 开始对局（含次数用尽的情况）
	if phase == D.Phase.PREPARE:
		if can_exchange():
			exchange_hand()
		else:
			start_battle()
		return	# a500 UI：选中手牌时主按钮执行「弃卡过牌」
	if armed_card >= 0:
		discard_armed()
		return
	# A5 程序需求：存在待确认目标时，主按钮 = 确认执行
	if pending_kind != "":
		confirm_pending()
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


# ============================================================
# 对战准备：调整初始手牌（a500 对战准备 5；决策一：一次性，不引入每回合换牌机会）
# ============================================================
## 换牌：指定手牌回墓地 → 从备卡补 1 张（手牌仍为 4 张）；每方上限 EXCHANGE_MAX
func exchange_hand() -> void:
	if phase != D.Phase.PREPARE or armed_card < 0:
		return
	var side := side_of_armed()
	if side == "" or exchange_left[side] <= 0:
		push_log("%s方 已无换牌次数（对战准备阶段每方 %d 次）" % [cn(side), D.EXCHANGE_MAX])
		clear_sel()
		refresh()
		return
	if armed_card >= hand[side].size():
		clear_sel()
		refresh()
		return
	var c: Dictionary = hand[side][armed_card]
	if deckl[side].is_empty():
		push_log("%s方 备卡已空，无法换牌" % cn(side))
		clear_sel()
		refresh()
		return
	exchange_left[side] -= 1
	grave[side].append(c)
	hand[side].remove_at(armed_card)
	draw_one(side)
	push_log("%s方 调整初始手牌：%s 回墓地 → 备卡补入（剩余 %d 次）" % [cn(side), c["name"], exchange_left[side]])
	clear_sel()
	refresh()


## 当前是否可以换牌（供 HUD 决定主按钮文案）
func can_exchange() -> bool:
	if phase != D.Phase.PREPARE:
		return false
	var side := side_of_armed()
	return side != "" and armed_card >= 0 and exchange_left[side] > 0


## 准备阶段结束，进入第一回合（a500 对战准备 9）
func start_battle() -> void:
	if phase != D.Phase.PREPARE:
		return
	# 被动技能结算（迭代003.1）：【机场】设定双方部署范围（deploy_radius）
	for side in ["green", "red"]:
		var q := queen_id_of(side)
		if q >= 0 and skills != null:
			var prev := current
			current = side
			run_passive("机场", q)
			current = prev
	push_log("对战准备结束，开始第一回合")
	clear_sel()
	begin_turn(first_side)


## 已选中的手牌属于哪一方（未选中/越界返回 ""）
func side_of_armed() -> String:
	if armed_card < 0:
		return ""
	var s := armed_side if armed_side != "" else current
	if s == "" or not hand.has(s) or armed_card >= hand[s].size():
		return ""
	return s


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
	# 准备阶段（a500 对战准备 5）：只做选中，供「换牌」使用，不进入部署/指令模式
	if phase == D.Phase.PREPARE:
		armed_side = current
		armed_card = index
		mode = D.Mode.IDLE
		selection_changed.emit()
		refresh()
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
			# 迭代003.1：部署范围由**被动技能**驱动（机场 → deploy_radius），不再硬编码"蜂王相邻"
			return within_deploy_radius(cell)
	return false


## 是否在己方部署范围内（半径 = deploy_radius[side]，由【机场】被动设定；
## a500 卡牌类型：兵蜂默认只能部署在蜂王相邻格 -> 默认半径 1）
func within_deploy_radius(cell: Vector2i) -> bool:
	var q := queen_id_of(current)
	if q < 0 or not units.has(q):
		return false
	var qc: Vector2i = units[q]["cell"]
	return abs(cell.x - qc.x) + abs(cell.y - qc.y) <= int(deploy_radius.get(current, 1))


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
	# a500 抽卡 1：使用卡牌需以「合法目标」为前提 —— 无目标时不得扣费、不得弃卡（审计 B1 修复）
	if tid < 0:
		push_log("指令「%s」需指定一个单位目标（该格无单位）" % c["name"])
		refresh()
		return
	var target: Dictionary = units[tid]["card"]
	# 辅助指令（治疗）只能对己方单位使用
	if c.has("heal") and units[tid]["side"] != current:
		push_log("「%s」只能对己方单位使用" % c["name"])
		refresh()
		return
	var pc: int = int(c["cost"])
	if c["kind"] == "command_x":
		pc = int(target["cost"])          # a500 费用 4：X 费卡费用 = 目标部署费（不可指定蜂王）
	if cost[current] < pc:
		push_log("费用不足（需 %d）" % pc)
		refresh()
		return
	# 蜂王免疫指令卡伤害与减益（a500 卡牌类型）
	if target["kind"] == "queen":
		push_log("蜂王免疫指令卡效果")
		refresh()
		return
	# ---- 迭代003.1：指令效果改走**结构化技能管线**（技能结构.md），删除原硬编码 伤害/治疗/减益 分支 ----
	var res: Dictionary = use_skill(str(c["name"]), cell)
	if not bool(res.get("ok", false)):
		refresh()
		return
	cost[current] -= pc
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
	if id < 0:
		return
	var u: Dictionary = units[id]
	# 任何单位都可选中用于**查看**（详情面板/技能区/属性栏跟随）；
	# 仅「己方 + 行动阶段 + 未行动」的单位才给出可行动范围
	var can_act: bool = u["side"] == current and phase == D.Phase.ACTION and not u["acted"]
	# 改选单位 -> 使旧的待确认失效（待确认只在明确改选/取消/执行时清除，不随 clear_sel 连带清除）
	clear_pending()
	selected_unit = id
	armed_card = -1
	mode = D.Mode.IDLE
	support_range = []
	move_range = []
	atk_range = []
	if can_act:
		var c: Vector2i = u["cell"]
		# a500 行动机会 4：本回合已移动则移动范围为 0
		if not u["moved"]:
			move_range = move_cells(c, final_spd(id))
		# a500 范围 3：攻击范围按曼哈顿距离；行动机会 5：无攻击力不给攻击范围
		if final_atk(id) > 0:
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
			# a500 行动机会 5：没有攻击力无法主动攻击（兜底校验，正常路径下攻击范围已为空）
			if final_atk(selected_unit) <= 0:
				push_log("%s 攻击力为 0，无法主动攻击" % unit_name(selected_unit))
				refresh()
				return
			# 先消耗行动机会再结算战斗：攻击方可能被反击打死，结算后会从 units 移除
			var aid := selected_unit
			units[aid]["acted"] = true
			if combat != null:
				combat.attack(aid, tid)
			remove_dead()
			clear_sel()
			check_victory()
			refresh()


## 是否可直接把该格作为支援目标（无需先进支援模式）—— a500 行动机会 5：技能没有支援条件无法使用支援技能
func can_support_at(cell: Vector2i) -> bool:
	if selected_unit < 0 or not units.has(selected_unit) or phase != D.Phase.ACTION:
		return false
	var u: Dictionary = units[selected_unit]
	if u["side"] != current or u["acted"]:
		return false
	var nm := str(u["card"].get("support", {}).get("name", ""))
	if nm == "" or D.skill(nm).is_empty() or str(D.skill(nm).get("source", "")) != "support":
		return false
	var tid := unit_at(cell)
	if tid < 0 or tid == selected_unit or units[tid]["side"] != current:
		return false
	return cell in support_targets()


func support_at(cell: Vector2i) -> void:
	if selected_unit < 0 or phase != D.Phase.ACTION:
		return
	if not units.has(selected_unit):
		clear_sel()
		refresh()
		return
	var u: Dictionary = units[selected_unit]
	# 只能由「己方 + 未行动」的单位提供支援（a500 行动机会 3/5）
	if u["side"] != current or u["acted"]:
		push_log("只能由己方未行动单位提供支援")
		refresh()
		return
	# 迭代003.1：支援技能走**结构化技能系统**（技能结构.md 四段管线），不再硬编码技能分支
	var skill_name := str(u["card"].get("support", {}).get("name", ""))
	if skill_name == "" or D.skill(skill_name).is_empty():
		push_log("%s 无支援技能（未在技能表中定义）" % u["card"]["name"])
		refresh()
		return
	if str(D.skill(skill_name).get("source", "")) != "support":
		push_log("%s 的技能非支援类" % u["card"]["name"])
		refresh()
		return
	var res: Dictionary = use_skill(skill_name, cell)
	if bool(res.get("ok", false)):
		units[selected_unit]["acted"] = true   # a500 行动机会 4：使用支援技能后结束行动
		push_log("%s 支援 %s" % [u["card"]["name"], unit_name(unit_at(cell))])
	clear_sel()
	refresh()


## a500 效果机制：①相同效果最多一个 ②效果 2：单位类型不匹配则无法赋予
## 效果字典可选带 `allow`（允许的单位类型列表，如 ["soldier"]）；不带则对任意单位类型生效。
func add_effect(id: int, eff: Dictionary) -> void:
	if not units.has(id):
		return
	var eid: String = eff["id"]
	var kind: String = str(units[id]["card"]["kind"])
	if eff.has("allow") and not (kind in eff["allow"]):
		push_log("%s 为 %s 类型，无法赋予效果「%s」（类型不匹配）" % [unit_name(id), kind, eff.get("name", eid)])
		return
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
	# a500 对战准备 5：准备阶段双方手牌均可点击（本地对战无 AI），用于「调整初始手牌」
	if phase == D.Phase.PREPARE:
		if index < 0 or index >= hand[side].size():
			return
		if armed_side == side and armed_card == index:
			armed_side = ""
			armed_card = -1          # 再次点击同一张 = 取消选中
		else:
			armed_side = side
			armed_card = index
		selection_changed.emit()
		refresh()
		return
	if side != current:
		return
	select_hand(index)


func on_cell_clicked(cell: Vector2i) -> void:
	if winner != "":
		return
	# ①【待确认优先】点击与待确认相同的目标 = 执行 —— 不依赖 mode/选中是否仍在，
	#    从根本上避免"多个状态互相冲突"导致待确认永远匹配不上（人实测：日志反复输出待确认）
	if pending_kind != "" and pending_cell == cell:
		confirm_pending_at(cell)
		return
	# ①b 支援待确认：点在蓝色候选范围之外 -> 退出该状态（人要求）
	if pending_kind == "支援" and not (cell in support_range):
		clear_pending()
		_leave_support_mode()
		clear_sel()
		push_log("已退出支援对象选择")
		refresh()
		return
	if armed_card >= 0 and mode == D.Mode.DEPLOY_TARGET:
		if legal_place(cell) and confirm("部署", cell):
			place_at(cell)
		return
	if armed_card >= 0 and mode == D.Mode.CMD_TARGET:
		if confirm("指令", cell):
			cmd_at(cell)
		return
	if mode == D.Mode.SUPPORT_TARGET:
		# A5 UI：支援对象选择中 —— 点候选格走二次确认；**点蓝色高亮范围之外即退出该状态**（人要求）
		if cell in support_range:
			if confirm("支援", cell):
				support_at(cell)
		else:
			clear_pending()
			_leave_support_mode()
			clear_sel()
			push_log("已退出支援对象选择")
			refresh()
		return
	if selected_unit >= 0 and units.has(selected_unit):
		# A5 UI：再次点击当前选中单位 = 进入支援对象选择
		if cell == units[selected_unit]["cell"]:
			enter_support_mode()
			return
		if cell in move_range and unit_at(cell) < 0:
			if confirm("移动", cell):
				act_at(cell)
			return
		if cell in atk_range and unit_at(cell) >= 0 and units[unit_at(cell)]["side"] != current:
			if confirm("攻击", cell):
				act_at(cell)
			return
		# 支援目标：所选单位有支援技能且未行动、目标为己方且在射程内 —— 直接点友方即可进入确认
		if can_support_at(cell):
			if confirm("支援", cell):
				support_at(cell)
			return
		# 点其他己方单位 = 改选
		clear_pending()
		select_unit_at(cell)
		return
	clear_pending()
	select_unit_at(cell)


# ============================================================
# A5 程序需求：点击确认（首次点目标=预览，再次点同一目标=执行）
# ============================================================
## 返回 true 表示"这是对同一目标的第二次点击，可以执行"
func confirm(kind: String, cell: Vector2i) -> bool:
	if pending_kind == kind and pending_cell == cell:
		clear_pending()
		return true
	pending_kind = kind
	pending_cell = cell
	preview = _build_preview(kind, cell)
	preview["source_id"] = selected_unit   # 记录施放者，供"待确认优先执行"在选中被清掉时补回
	push_log("待确认：%s @(%d,%d) —— 再次点击同一目标或按主按钮确认" % [kind, cell.x, cell.y])
	selection_changed.emit()
	refresh()
	return false


## 待确认优先执行：按记录的 kind 直接结算（供 on_cell_clicked 的最高优先分支调用）
func confirm_pending_at(cell: Vector2i) -> void:
	var kind := pending_kind
	var src := int(preview.get("source_id", -1))
	clear_pending()
	match kind:
		"部署":
			place_at(cell)
		"指令":
			cmd_at(cell)
		"支援":
			# 支援需要施放者：若选中已被清掉，用待确认时记录的来源单位补回
			if selected_unit < 0 and src >= 0 and units.has(src):
				selected_unit = src
			support_at(cell)
		_:
			act_at(cell)


func clear_pending() -> void:
	pending_kind = ""
	pending_cell = Vector2i(-1, -1)
	preview = {}


## 预览数据：攻击给出预计伤害与预计剩余血量；移动/部署/支援给出目标格
func _build_preview(kind: String, cell: Vector2i) -> Dictionary:
	var p := {"kind": kind, "cell": cell}
	if kind == "攻击":
		var aid := selected_unit
		var tid := unit_at(cell)
		if aid >= 0 and tid >= 0 and combat != null:
			var dmg := maxi(0, int(combat.final_atk(aid)) - int(combat.final_reduce(tid)))
			p["attacker_id"] = aid
			p["attacker_hp_now"] = int(units[aid]["hp"])
			p["target_id"] = tid
			p["dmg"] = dmg
			p["hp_now"] = int(units[tid]["hp"])
			p["hp_after"] = maxi(0, int(units[tid]["hp"]) - dmg)
			# 反击预估（对方存活且射程覆盖）：同时给出「攻方」预计剩余血量
			var back := 0
			if p["hp_after"] > 0:
				var ac: Vector2i = units[aid]["cell"]
				if abs(cell.x - ac.x) + abs(cell.y - ac.y) <= int(combat.final_range(tid)):
					back = maxi(0, int(combat.final_atk(tid)) - int(combat.final_reduce(aid)))
			p["counter"] = back
			p["attacker_hp_after"] = maxi(0, int(units[aid]["hp"]) - back)
	return p


## 主按钮在待确认态 = 确认执行（与「再次点击同一目标」等价）
func confirm_pending() -> bool:
	if pending_kind == "":
		return false
	var kind := pending_kind
	var cell := pending_cell
	clear_pending()
	match kind:
		"部署":
			place_at(cell)
		"指令":
			cmd_at(cell)
		"支援":
			support_at(cell)
		_:
			act_at(cell)
	return true


## A5 UI：再次点击当前选中单位 → 进入「支援对象选择」
func enter_support_mode() -> void:
	if selected_unit < 0 or not units.has(selected_unit):
		return
	var u: Dictionary = units[selected_unit]
	if not u["card"].has("support"):
		push_log("%s 没有支援技能" % u["card"]["name"])
		refresh()
		return
	mode = D.Mode.SUPPORT_TARGET
	move_range = []
	atk_range = []
	support_range = support_targets()
	push_log("选择支援对象：「%s」射程 %d（点其他单位可改选）" % [u["card"]["support"]["name"], int(u["card"]["support"]["rng"])])
	selection_changed.emit()
	refresh()


func _leave_support_mode() -> void:
	mode = D.Mode.IDLE
	support_range = []


## 支援候选格：射程内的己方单位（不含自身）
func support_targets() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if selected_unit < 0 or not units.has(selected_unit):
		return out
	var u: Dictionary = units[selected_unit]
	if not u["card"].has("support"):
		return out
	var rng := int(u["card"]["support"]["rng"])
	for id in units:
		if id == selected_unit or units[id]["side"] != current:
			continue
		var c: Vector2i = units[id]["cell"]
		if abs(c.x - u["cell"].x) + abs(c.y - u["cell"].y) <= rng:
			out.append(c)
	return out


func on_support_clicked(cell: Vector2i) -> void:
	support_at(cell)


## A5 程序需求：点击非交互区域取消当前选中（三种选中态通吃：待放置卡 / 选中单位 / 指令目标）
## 同时清除待确认（明确取消语义）
func on_click_empty() -> void:
	if armed_card >= 0 or selected_unit >= 0 or pending_kind != "":
		clear_pending()
		clear_sel()
		refresh()


func on_small_pressed(index: int) -> void:
	match index:
		0:
			help_on = not help_on
		2:
			push_log("回合%d/%d · %s方 · 费%d" % [round_no, D.ROUND_MAX, cn(current), cost[current]])
		3:
			request_surrender()
	refresh()


## A5 UI：投降需二次确认（确认 → 投降结算；取消 → 返回）
func request_surrender() -> void:
	if winner != "":
		return
	if round_no < 4:
		push_log("第 4 回合起才可投降（当前第 %d 回合）" % round_no)
		refresh()
		return
	if surrender_pending:
		surrender_pending = false
		surrender()
		return
	surrender_pending = true
	push_log("投降确认：再次点击投降按钮，或按主按钮「确认投降」")
	popup_requested.emit("确认投降",
		"点击任意处取消；点主按钮「确认投降」执行投降。\n\n（a500 胜利条件 4：从第 4 回合开始，允许主动投降）")
	refresh()


## 取消投降（点击任意处关闭浮窗时）
func cancel_surrender() -> void:
	if surrender_pending:
		surrender_pending = false
		push_log("已取消投降")
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
	support_range = []
	# 注意：**不清除待确认**（pending 是独立状态）——
	# 此前此处连带 clear_pending()，而 clear_sel() 有 16 处调用，
	# 任何一次顺手的清选中都会杀掉待确认，导致"反复点击只输出待确认、永远匹配不上"（人实测现象）
	selection_changed.emit()


func push_log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 60:
		log_lines.pop_front()
	log_added.emit(s)


func cn(side: String) -> String:
	return "绿" if side == "green" else ("红" if side == "red" else "—")


# ============================================================
# 结构化技能系统入口（迭代003 · 依据技能结构.md 四段管线）
# ============================================================
## 以结构化技能定义施放：管线由 BattleSkills.run_skill 执行
func use_skill(skill_name: String, target: Vector2i) -> Dictionary:
	if skills == null:
		# 绝不静默：接线丢失时大声报错（G-01 教训）
		push_error("[BattleState] 技能系统未接入（skills == null）—— 技能调用被忽略")
		push_log("技能系统未接入，无法使用「%s」" % skill_name)
		refresh()
		return {"ok": false, "reason": "技能系统未接入"}
	var def: Dictionary = D.skill(skill_name)
	if def.is_empty():
		push_log("未找到技能定义：%s" % skill_name)
		return {"ok": false, "reason": "无技能定义"}
	var sid: int = selected_unit if selected_unit >= 0 else -1
	var ctx := {"source_id": sid, "side": current, "target": target}
	var res: Dictionary = skills.run_skill(def, ctx)
	if bool(res.get("ok", false)):
		push_log("技能「%s」生效（命中 %d 处）" % [str(def.get("name", skill_name)), res["hits"].size()])
		remove_dead()
		check_victory()
	else:
		push_log("技能「%s」未生效：%s" % [str(def.get("name", skill_name)), str(res.get("reason", ""))])
	refresh()
	return res


## 被动技能：进入场地时结算（部署 / 回合开始）
func run_passive(skill_name: String, owner_id: int) -> Dictionary:
	if skills == null:
		return {"ok": false, "reason": "技能系统未接入"}
	var def: Dictionary = D.skill(skill_name)
	if def.is_empty() or str(def.get("source", "")) != "passive":
		return {"ok": false, "reason": "非被动技能"}
	return skills.run_skill(def, {"source_id": owner_id, "side": current,
		"target": units[owner_id]["cell"] if units.has(owner_id) else Vector2i(-1, -1)})


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


## 长按查看详情是否允许
## 仅当「有待确认目标 / 已持牌 / 处于部署·指令·支援目标选择模式」时禁止 ——
## 目的：避免长按浮窗抢走确认点击（本轮支援卡死根因）；
## **选中单位本身不禁止**（长按查看详情正是要点单位；之前误加 selected_unit<0 导致浮窗永不弹出）
func can_long_press() -> bool:
	return winner == "" and pending_kind == "" and armed_card < 0 and mode == D.Mode.IDLE


## 当前查看对象的单位 id（无则退回当前方蜂王）
func focus_unit_id() -> int:
	if selected_unit >= 0 and units.has(selected_unit):
		return selected_unit
	return queen_id_of(current)


## 指定单位的**实时**卡面数据（含 buff 与地形加成）—— 显示层统一入口
func unit_card_live(id: int) -> Dictionary:
	if not units.has(id):
		return {}
	var out: Dictionary = units[id]["card"].duplicate()
	out["hp"] = int(units[id]["hp"])
	out["atk"] = final_atk(id)
	out["spd"] = final_spd(id)
	out["range"] = final_range(id)
	return out


## 当前查看对象的卡面数据：若焦点是场上单位，用**实时数值**覆盖基础值（保证卡面与状态一致）
func detail_card_live() -> Dictionary:
	var d: Dictionary = current_detail_card()
	if d.is_empty():
		return d
	var id := focus_unit_id()
	if id < 0 or not units.has(id):
		return d
	if str(units[id]["card"]["name"]) != str(d.get("name", "")):
		return d
	var out := d.duplicate()
	out["hp"] = int(units[id]["hp"])
	out["atk"] = final_atk(id)
	out["spd"] = final_spd(id)
	out["range"] = final_range(id)
	return out


## 详情栏「属性值」：与当前查看对象一致（场上单位=实时值；手牌=卡牌基础值）
func focus_values() -> Array:
	var d: Dictionary = current_detail_card()
	if d.is_empty():
		return ["-", "-", "-", "-"]
	var id := focus_unit_id()
	if id >= 0 and units.has(id) and str(units[id]["card"]["name"]) == str(d.get("name", "")):
		return [str(final_atk(id)), str(final_reduce(id)), str(final_spd(id)), str(final_range(id))]
	if d["kind"] == "command" or d["kind"] == "command_x":
		return ["—", "—", "—", str(int(d.get("range", 0)))]
	return [str(int(d.get("atk", 0))), "0", str(int(d.get("spd", 0))), str(int(d.get("range", 0)))]


func queen_id_of(side: String) -> int:
	for id in units:
		if units[id]["side"] == side and units[id]["card"]["kind"] == "queen":
			return id
	return -1


## 通用刷新（视图订阅 state_changed 后各自重绘）
func refresh() -> void:
	state_changed.emit()
