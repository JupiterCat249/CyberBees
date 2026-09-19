class_name GameState
extends Node
## GameState —— 对局规则状态机（**规则真源 / Model**）
##
## 依据：`电子蜂a500规则.md`（T10 权威）
## 职责：持有全部对局状态 + 推进回合流程 + 结算规则；**不含任何渲染**
## 通信：只发信号；视图层/输入层通过公开方法下语义操作（本类不引用任何 UI 类）
##
## 回合流程（a500「回合流程」）：
##   先手：回费 → 场地 → 部署 → 行动
##   后手：回费 → 场地 → 部署 → 行动
## 每次进入「回费阶段」自动结算回费并重置行动机会，然后自动跳过「场地阶段」（无地形时空跑），
## **停在「部署阶段」等待玩家**（主按钮 = 确认部署 → 进入行动阶段）

const Action := preload("res://scripts/game/battle_action.gd")
const Effects := preload("res://scripts/game/battle_effects.gd")
const Command := preload("res://scripts/game/battle_command.gd")

signal state_changed()                        ## 粗粒度：任意状态变化
signal phase_changed(active: int, phase: int, round_no: int)
signal turn_started(active: int, round_no: int)
signal hand_changed(side: int)
signal cost_changed(side: int, cost: int)
signal unit_spawned(inst: UnitInstance)
signal unit_moved(inst: UnitInstance)
signal unit_damaged(inst: UnitInstance, amount: int)
signal unit_removed(inst: UnitInstance)
signal effect_changed(inst: UnitInstance)
signal selection_changed(kind: String, id: String)   ## kind: none|hand|unit|target
signal log_added(text: String)
signal battle_ended(result: int, reason: String)   ## result: RESULT_*
signal main_button_state(text: String, enabled: bool)

enum Phase { RECOVER, TERRAIN, DEPLOY, ACTION }
enum Result { NONE, ALLY_WIN, ENEMY_WIN, DRAW }
enum SelKind { NONE, HAND, UNIT }

const MAX_COST := 10                  ## a500：最多储存 10 点费用
const ROUND_EXTRA_COST := 2           ## a500：第 7 回合起回费 +2
const EXTRA_COST_FROM_ROUND := 7
const MAX_ROUNDS := 12                ## a500：第 12 回合结束后比蜂王血量
const SURRENDER_FROM_ROUND := 4       ## a500：第 4 回合起可投降
const HAND_MAX := 4                   ## a500：手牌补至 4 张
const ROTATE_COST := 1                ## 手牌轮换消耗（1 费）

var board := Board.new()
var round_no: int = 1
var active: int = Board.ALLY
var phase: int = Phase.RECOVER
var result: int = Result.NONE

## 双方资源
var cost := {Board.ALLY: 0, Board.ENEMY: 0}
var hand := {Board.ALLY: [], Board.ENEMY: []}        ## Array[CardData]
var deck := {Board.ALLY: [], Board.ENEMY: []}        ## Array[CardData]（牌库底）
var discard := {Board.ALLY: [], Board.ENEMY: []}     ## Array[CardData]
var queen := {Board.ALLY: null, Board.ENEMY: null}   ## UnitInstance
var player_names := {Board.ALLY: "玩家", Board.ENEMY: "对手"}

## 选中态（输入层维护语义，State 只做规则校验）
var sel_kind: int = SelKind.NONE
var sel_hand_index: int = -1
var sel_unit: UnitInstance = null
var sel_support: SkillData = null      ## 非空 = 正处于"选择支援目标"模式

var _uid_seq := 0


func _ready() -> void:
	board.changed.connect(func() -> void: state_changed.emit())


# ============================================================
#  开局
# ============================================================

## 按 a500「对战准备」建局
## deck_data：DeckData（含蜂王 + 11 张常规卡，其中前 4 张为初始手牌、后 4 张为备卡）
## first_player：先手方（0 我 / 1 敌）；后手初始费用 +2
func setup(decks: Dictionary, first_player: int = Board.ALLY,
		names: Dictionary = {}) -> void:
	board = Board.new()
	board.changed.connect(func() -> void: state_changed.emit())
	for side in [Board.ALLY, Board.ENEMY]:
		var dd: DeckData = decks.get(side, null)
		if dd == null:
			push_error("GameState.setup: 缺 %d 方的卡组" % side)
			continue
		if names.has(side):
			player_names[side] = names[side]
		cost[side] = 0
		hand[side] = []
		deck[side] = []
		discard[side] = []
		# 蜂王先就位
		var q := UnitInstance.create(dd.queen, side, _queen_cell(side))
		queen[side] = q
		board.place(q)
		# 卡组：蜂王之外的全部卡
		var rest: Array[CardData] = []
		for c in dd.cards:
			if c != null and c != dd.queen:
				rest.append(c)
		# 前 4 张初始手牌、后 4 张备卡入牌库底
		for i in rest.size():
			if i < HAND_MAX:
				hand[side].append(rest[i])
			else:
				deck[side].append(rest[i])
	# 后手初始费用 +2
	var second := 1 - first_player
	cost[second] = 2
	active = first_player
	round_no = 1
	result = Result.NONE
	_begin_turn()
	state_changed.emit()
	log_added.emit("对局开始：%s 先手；%s 初始费用 +2" % [player_names[first_player], player_names[second]])


func _queen_cell(side: int) -> Vector2i:
	## 半径约定：Vector2i(行, 列)；我方在下半（行 3）、敌方在上半（行 0），居中列
	return Vector2i(3, 1) if side == Board.ALLY else Vector2i(0, 1)


# ============================================================
#  回合流程
# ============================================================

func _begin_turn() -> void:
	phase = Phase.RECOVER
	turn_started.emit(active, round_no)
	_do_recover()
	phase_changed.emit(active, phase, round_no)
	_after_recover()


## 回费阶段：按 a500 — 蜂王回费量 + 第 7 回合起 +2
func _do_recover() -> void:
	## ⚠️ 迭代055：[回费] 是**单位自带技能**，凡标了回费的单位都应结算 ——
	##    金刚蜂王(4) / 蜂巢(1) / 蜂巢III(3)。此前只算蜂王，建筑的 [回费] 全部漏结算。
	var gain := 0
	for u in board.units_of(active):
		if u.data != null:
			gain += u.data.refund
	if round_no >= EXTRA_COST_FROM_ROUND:
		gain += ROUND_EXTRA_COST
	if gain > 0:
		cost[active] = mini(MAX_COST, cost[active] + gain)
		log_added.emit("%s 回费 +%d（现 %d）" % [player_names[active], gain, cost[active]])
	# 重置本方全部单位的行动机会（a500：己方回费阶段重置）
	for u in board.units_of(active):
		u.reset_turn_flags()
	cost_changed.emit(active, cost[active])
	state_changed.emit()


## 场地阶段：结算地形格上的单位效果（a500：地域效果作用于目标格子上的单位）
func _do_terrain() -> void:
	var terrain := _terrain_cells()
	if terrain.is_empty():
		return
	for c in terrain.keys():
		var u := board.unit_at(c)
		if u != null and u.is_alive():
			var eff: EffectData = terrain[c]
			if eff != null:
				u.apply_effect(eff)
				effect_changed.emit(u)
				log_added.emit("场地效果作用于 %s" % u.card_name())

var _terrain: Dictionary = {}      ## Vector2i → EffectData

func set_terrain(cells: Dictionary) -> void:
	_terrain = cells

func _terrain_cells() -> Dictionary:
	return _terrain


func _after_recover() -> void:
	phase = Phase.TERRAIN
	phase_changed.emit(active, phase, round_no)
	_do_terrain()
	phase = Phase.DEPLOY
	phase_changed.emit(active, phase, round_no)
	_update_main_button()


## 主按钮（a500：主按钮只做"确认推进"）
func advance_phase() -> void:
	if result != Result.NONE:
		return
	match phase:
		Phase.DEPLOY:
			cancel_selection()
			phase = Phase.ACTION
			phase_changed.emit(active, phase, round_no)
			_update_main_button()
		Phase.ACTION:
			_end_turn()


func _end_turn() -> void:
	cancel_selection()
	# a500：玩家回合结束后，抽取备卡补充手牌到 4 张
	_refill_hand()
	# 换手
	if active == Board.ENEMY:
		# 双方都行动完 → 进入下一回合；第 12 回合结束后判定胜负
		if round_no >= MAX_ROUNDS:
			_judge_by_hp()
			return
		round_no += 1
	active = 1 - active
	_begin_turn()


func _refill_hand() -> void:
	while hand[active].size() < HAND_MAX:
		if deck[active].is_empty():
			# a500：牌库抽完 → 将墓地内前 4 张放入牌库并洗牌
			if discard[active].is_empty():
				break
			var n := mini(4, discard[active].size())
			for i in n:
				deck[active].append(discard[active].pop_front())
			deck[active].shuffle()
			log_added.emit("%s 牌库抽完，墓地前 %d 张洗回牌库" % [player_names[active], n])
		if deck[active].is_empty():
			break
		hand[active].append(deck[active].pop_front())
	hand_changed.emit(active)
	state_changed.emit()


func _update_main_button() -> void:
	match phase:
		Phase.DEPLOY:
			main_button_state.emit("完成部署", true)
		Phase.ACTION:
			main_button_state.emit("结束回合", true)
		_:
			main_button_state.emit("…", false)


# ============================================================
#  卡牌使用（部署 / 指令）
# ============================================================

func can_play_hand(side: int, idx: int) -> bool:
	if side != active or phase != Phase.DEPLOY and phase != Phase.ACTION:
		return false
	var cards: Array = hand[side]
	if idx < 0 or idx >= cards.size():
		return false
	var data: CardData = cards[idx]
	if data == null:
		return false
	if data is CommandData:
		# 指令：部署与行动阶段均可使用
		return true
	if data.kind == CardData.CardKind.BUILDING:
		return true          # 建筑：己方领地任意格（放置时校验）
	return false             # 兵蜂：只能由蜂王巢口/Specialist 部署（见 deploy 校验）


## 部署一张单位卡到格子上（返回是否成功）
func deploy_unit(side: int, idx: int, cell: Vector2i) -> bool:
	if side != active or not board.is_own_territory(cell, side):
		return false
	var data := take_hand_card(side, idx)
	if data == null:
		return false
	var ud := data as UnitData
	if ud == null:
		# 不是单位（指令卡走 use_command）
		hand[side].insert(idx, data)
		return false
	if not _deploy_cell_ok(side, ud, cell):
		hand[side].insert(idx, data)
		return false
	if ud.cost > cost[side]:
		hand[side].insert(idx, data)
		log_added.emit("费用不足")
		return false
	# 扣费（a500：使用单位卡时把卡复制一份部署到场上，原卡返回墓地）
	cost[side] = maxi(0, cost[side] - maxi(0, ud.cost))
	var inst := UnitInstance.create(ud, side, cell)
	inst.instance_id = _next_id()
	inst.has_moved = true
	inst.has_acted = true                 ## a500：单位部署时没有行动机会
	board.place(inst)
	_apply_deploy_skills(inst, ud)        ## 迭代055：[部署]获得[装甲] 等
	discard[side].append(data)
	cost_changed.emit(side, cost[side])
	hand_changed.emit(side)
	unit_spawned.emit(inst)
	log_added.emit("%s 部署 %s 到 (%d,%d)（费 -%d）" % [player_names[side], ud.display_name, cell.x, cell.y, maxi(0, ud.cost)])
	state_changed.emit()
	return true


## 落地「[部署]」类技能（迭代055：金刚蜂王 `[部署]获得[装甲]效果`）
## 判定依据：技能的 glossary 标为「部署」（卡数据里显式标注，不靠描述文本猜）
func _apply_deploy_skills(inst: UnitInstance, ud: UnitData) -> void:
	if inst == null or ud == null:
		return
	for sk in ud.skills:
		if sk == null or sk.glossary != "部署":
			continue
		for e in sk.effects:
			if e != null and Effects.grant(inst, e):
				log_added.emit("%s 触发【部署】%s" % [ud.display_name, e.display_name])
				effect_changed.emit(inst)


## 部署格合法性
func _deploy_cell_ok(side: int, ud: UnitData, cell: Vector2i) -> bool:
	if not board.is_empty(cell):
		return false
	match ud.kind:
		CardData.CardKind.BUILDING:
			return board.is_own_territory(cell, side)     # 建筑：己方领地任意格
		CardData.CardKind.SOLDIER:
			# 兵蜂：部署在蜂王相邻格（a500「兵蜂：使用后部署在蜂王相邻格子」）
			var q: UnitInstance = queen[side]
			if q == null:
				return false
			return board.manhattan(q.cell, cell) == 1
		CardData.CardKind.QUEEN:
			return false                                  # 蜂王部署由对战准备完成
		_:
			return false


## 从手牌取出一张（成功则返回该卡并从手牌移除）
## ⚠️ Godot 的 Array.remove_at() 返回 **void**（不是被移除的元素），
##    故必须**先取元素再移除** —— 曾误写成 `return cards.remove_at(idx)` 导致部署全部失效。
func take_hand_card(side: int, idx: int) -> CardData:
	var cards: Array = hand[side]
	if idx < 0 or idx >= cards.size():
		return null
	var data: CardData = cards[idx]
	cards.remove_at(idx)
	return data


## 弃牌（a500：丢弃消耗等同于部署的费用，X 费卡消耗 10）
func can_discard(side: int, idx: int) -> bool:
	var cards: Array = hand[side]
	if idx < 0 or idx >= cards.size():
		return false
	var d: CardData = cards[idx]
	return true if d == null else cost[side] >= _discard_cost(d)


func _discard_cost(d: CardData) -> int:
	if d.kind == CardData.CardKind.COMMAND_X:
		return MAX_COST
	return maxi(0, d.cost)


func discard_card(side: int, idx: int) -> bool:
	var d := take_hand_card(side, idx)
	if d == null:
		return false
	var c := _discard_cost(d)
	cost[side] = maxi(0, cost[side] - c)
	discard[side].append(d)
	cost_changed.emit(side, cost[side])
	hand_changed.emit(side)
	log_added.emit("%s 弃牌 %s（费 -%d）" % [player_names[side], d.display_name, c])
	state_changed.emit()
	return true


# ============================================================
#  抽卡 / 轮换（a500「抽卡」）
# ============================================================

## 抽 n 张（牌库空时把墓地前 4 张洗回 —— a500）
## 返回实际抽到的张数
func draw_card(side: int, n: int = 1) -> int:
	var got := 0
	for _i in n:
		if hand[side].size() >= HAND_MAX + 4:      # 防止无限膨胀（手牌上限之外不再抽）
			break
		if deck[side].is_empty():
			if discard[side].is_empty():
				break
			var take := mini(4, discard[side].size())
			for k in take:
				deck[side].append(discard[side].pop_front())
			deck[side].shuffle()
			log_added.emit("%s 牌库抽完，墓地前 %d 张洗回牌库" % [player_names[side], take])
		if deck[side].is_empty():
			break
		hand[side].append(deck[side].pop_front())
		got += 1
	if got > 0:
		hand_changed.emit(side)
		state_changed.emit()
	return got


## 轮换（手牌轮换）：弃掉全部手牌并抽等量的新牌，消耗 1 费
## 依据 a500「抽卡」：丢弃卡牌消耗费用；轮换 = 把手牌整体换掉
func can_rotate(side: int) -> bool:
	if side != active or result != Result.NONE:
		return false
	return cost[side] >= ROTATE_COST and not hand[side].is_empty()


func rotate_hand(side: int) -> bool:
	if not can_rotate(side):
		return false
	var n: int = hand[side].size()
	cost[side] = maxi(0, cost[side] - ROTATE_COST)
	for c in hand[side]:
		discard[side].append(c)
	hand[side] = []
	var got := draw_card(side, n)
	cost_changed.emit(side, cost[side])
	hand_changed.emit(side)
	log_added.emit("%s 轮换手牌：弃 %d 张、抽 %d 张（费 -%d）" % [player_names[side], n, got, ROTATE_COST])
	# ⚠️ 不做"从墓地兜底补到手牌"——那会让刚弃掉的卡**同时**存在于墓地与手牌（同一张被引用两处，
	#    总数守恒被破坏）。a500 的口径是"抽卡抽不出来就是抽不出来"，故本轮只按牌库抽。
	state_changed.emit()
	return true


# ============================================================
#  指令卡
# ============================================================

## 指令卡能否使用（阶段 / 费用 / 目标）
func can_use_command(side: int, idx: int, target: UnitInstance) -> bool:
	if side != active:
		return false
	if phase != Phase.DEPLOY and phase != Phase.ACTION:
		return false
	var cards: Array = hand[side]
	if idx < 0 or idx >= cards.size():
		return false
	var cmd := cards[idx] as CommandData
	if cmd == null:
		return false
	if not Command.target_legal(cmd, side, target):
		return false
	return cost[side] >= command_cost(cmd, target)


## 指令卡的实际费用（X 费卡 = 目标单位的部署费用）
func command_cost(cmd: CommandData, target: UnitInstance) -> int:
	if cmd == null:
		return 0
	if cmd.kind == CardData.CardKind.COMMAND_X:
		return Command.x_cost_of(target)
	return maxi(0, cmd.cost)


## 某张手牌（指令卡）的合法目标集合（供视图高亮）
func command_targets(idx: int) -> Array[UnitInstance]:
	var out: Array[UnitInstance] = []
	var cards: Array = hand[active]
	if idx < 0 or idx >= cards.size():
		return out
	var cmd := cards[idx] as CommandData
	if cmd == null:
		return out
	for u in board.all_units():
		if Command.target_legal(cmd, active, u) and cost[active] >= command_cost(cmd, u):
			out.append(u)
	return out


## 使用指令卡（成功返回 true；卡进墓地）
func use_command(side: int, idx: int, target: UnitInstance) -> bool:
	if not can_use_command(side, idx, target):
		return false
	var cmd: CommandData = hand[side][idx]
	var c := command_cost(cmd, target)
	hand[side].remove_at(idx)
	cost[side] = maxi(0, cost[side] - c)
	# 先扣费再结算（结算里可能读费用，如补给）
	var res := Command.execute(self, cmd, target)
	discard[side].append(cmd)          # a500：指令用完后退场（进墓地）
	cost_changed.emit(side, cost[side])
	hand_changed.emit(side)
	var detail := ""
	if not res["damage"].is_empty():
		var parts: Array[String] = []
		for d in res["damage"]:
			parts.append("%s -%d%s" % [d["unit"].card_name(), d["amount"], "（护盾抵挡）" if d["blocked"] else ""])
		detail = "，".join(parts)
	elif res["healed"] > 0:
		detail = "治疗 %d" % res["healed"]
	elif res["extra"] != "":
		detail = res["extra"]
	log_added.emit("%s 使用【指令】%s（费 -%d）%s" % [player_names[side], cmd.display_name, c,
		"" if detail == "" else "：" + detail])
	check_victory()
	state_changed.emit()
	return true


# ============================================================
#  选中 / 交互（输入层下语义，State 校验规则）

func select_hand(idx: int) -> void:
	if sel_kind == SelKind.HAND and sel_hand_index == idx:
		cancel_selection()
		return
	sel_kind = SelKind.HAND
	sel_hand_index = idx
	sel_unit = null
	selection_changed.emit("hand", _hand_card_id(idx))


func select_unit(inst: UnitInstance) -> void:
	if inst == null or inst.side != active:
		cancel_selection()
		return
	if sel_kind == SelKind.UNIT and sel_unit == inst:
		cancel_selection()
		return
	sel_kind = SelKind.UNIT
	sel_unit = inst
	sel_hand_index = -1
	selection_changed.emit("unit", inst.instance_id)


func cancel_selection() -> void:
	sel_kind = SelKind.NONE
	sel_hand_index = -1
	sel_unit = null
	selection_changed.emit("none", "")


func _hand_card_id(idx: int) -> String:
	var cards: Array = hand[active]
	if idx < 0 or idx >= cards.size():
		return ""
	var d: CardData = cards[idx]
	return d.id if d != null else ""


## 当前选中的手牌对应的可用格（供视图高亮）；无则空
func selected_deploy_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if sel_kind != SelKind.HAND:
		return out
	var cards: Array = hand[active]
	if sel_hand_index < 0 or sel_hand_index >= cards.size():
		return out
	var ud: UnitData = cards[sel_hand_index] as UnitData
	if ud == null:
		return out
	for y in Board.ROWS:
		for x in Board.COLS:
			var c := Vector2i(x, y)
			if _deploy_cell_ok(active, ud, c):
				out.append(c)
	return out


## 当前选中单位的可移动格
func selected_move_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if sel_unit == null or sel_unit.has_moved or sel_unit.has_acted:
		return out
	for c in board.move_range(sel_unit).keys():
		out.append(c)
	return out


# ============================================================
#  行动接口（a500「行动机会」）—— 由输入层下语义操作
# ============================================================

## 单位有无行动机会（供 UI 判断能否操作）
func can_unit_move(inst: UnitInstance) -> bool:
	return Action.can_move(self, inst)

func can_unit_attack(inst: UnitInstance) -> bool:
	return Action.can_attack(self, inst)

func can_unit_support(inst: UnitInstance) -> bool:
	return Action.can_support(self, inst)


## 移动一次（成功返回 true）
func move_unit(inst: UnitInstance, to: Vector2i) -> bool:
	return Action.move(self, inst, to)


## 主动攻击（含同时反击；使用后自动结束该单位行动）
func attack(attacker: UnitInstance, target: UnitInstance) -> bool:
	return Action.attack(self, attacker, target)


## 使用支援技能
func use_support(inst: UnitInstance, skill: SkillData, target: UnitInstance) -> bool:
	return Action.support(self, inst, skill, target)


## 结算某单位的持续效果（回合切换时调用）
func tick_effects(inst: UnitInstance) -> void:
	var removed := Effects.tick_effects(inst)
	if not removed.is_empty():
		effect_changed.emit(inst)
	if not inst.is_alive():
		board.remove(inst)
		unit_removed.emit(inst)
	check_victory()


# ---------------- 支援技能（a500：1 移动 + 1 攻击/支援） ----------------

## 选中单位可用支援技能列表
func unit_support_skills(inst: UnitInstance) -> Array[SkillData]:
	var out: Array[SkillData] = []
	if inst == null or inst.data == null:
		return out
	for s in inst.data.skills:
		if s != null and s.kind == SkillData.Kind.SUPPORT:
			out.append(s)
	return out


## 进入"选择支援目标"模式（需已选中己方单位且该单位可支援）
func begin_support(inst: UnitInstance, skill: SkillData) -> bool:
	if not Action.can_support(self, inst) or skill == null:
		return false
	sel_unit = inst
	sel_support = skill
	selection_changed.emit("support", inst.instance_id)
	return true


func cancel_support() -> void:
	if sel_support != null:
		sel_support = null
		selection_changed.emit("none", "")


## 支援模式下的合法目标（己方、范围内、存活）
func support_targets() -> Array[UnitInstance]:
	var out: Array[UnitInstance] = []
	if sel_unit == null or sel_support == null:
		return out
	for u in board.units_of(active):
		if not u.is_alive():
			continue
		if board.manhattan(sel_unit.cell, u.cell) <= sel_support.target_range:
			out.append(u)
	return out


## 执行支援（成功返回 true）
func confirm_support(target: UnitInstance) -> bool:
	if sel_unit == null or sel_support == null:
		return false
	var ok := Action.support(self, sel_unit, sel_support, target)
	if ok:
		sel_support = null
		selection_changed.emit("none", "")
	return ok


## 当前选中单位可攻击的目标（供视图高亮）
func selected_attack_targets() -> Array[UnitInstance]:
	if sel_unit == null or not Action.can_attack(self, sel_unit):
		return []
	return board.attackable(sel_unit, board.all_units())


## 当前费用（当前行动方）
func current_cost() -> int:
	return cost[active]


## 手牌（当前行动方）
func current_hand() -> Array:
	return hand[active]


## 我方/敌方蜂王血量（HUD）
func queen_hp(side: int) -> int:
	var q: UnitInstance = queen[side]
	return q.current_hp if q != null else 0


## 回费阶段结束后，随机格是否可视为"场地阶段"处理（本框架：地形由 set_terrain 注入）
func has_terrain() -> bool:
	return not _terrain.is_empty()


# ============================================================
#  胜负
# ============================================================

func _next_id() -> String:
	_uid_seq += 1
	return "%s#%d" % [Uuid.generate(), _uid_seq]


func check_victory() -> void:
	var a: UnitInstance = queen[Board.ALLY]
	var e: UnitInstance = queen[Board.ENEMY]
	if a != null and not a.is_alive():
		_finish(Result.ENEMY_WIN, "我方蜂王被击败")
		return
	if e != null and not e.is_alive():
		_finish(Result.ALLY_WIN, "敌方蜂王被击败")


func _judge_by_hp() -> void:
	var a: UnitInstance = queen[Board.ALLY]
	var e: UnitInstance = queen[Board.ENEMY]
	var ah := a.current_hp if a != null else 0
	var eh := e.current_hp if e != null else 0
	if ah > eh:
		_finish(Result.ALLY_WIN, "第 12 回合结束：蜂王血量 %d : %d" % [ah, eh])
	elif eh > ah:
		_finish(Result.ENEMY_WIN, "第 12 回合结束：蜂王血量 %d : %d" % [ah, eh])
	else:
		_finish(Result.DRAW, "第 12 回合结束：蜂王血量持平 %d : %d" % [ah, eh])


func can_surrender(side: int) -> bool:
	return round_no >= SURRENDER_FROM_ROUND and result == Result.NONE


func surrender(side: int) -> void:
	if not can_surrender(side):
		return
	_finish(Result.ENEMY_WIN if side == Board.ALLY else Result.ALLY_WIN,
		"%s 投降" % player_names[side])


func _finish(res: int, reason: String) -> void:
	result = res
	log_added.emit("对局结束：" + reason)
	battle_ended.emit(res, reason)
	state_changed.emit()
