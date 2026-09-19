class_name BattleEngine
extends RefCounted
## BattleEngine —— 战斗**规则引擎**（a500 阶段状态机 + 请求 API + 信号广播）
##
## ⚠️ **零 UI 依赖（迭代056 解耦目标 G1）**：
##   · 本文件与 `scripts/battle/` 下全部文件**不 preload 任何 `scenes/`**、**不 get_node**、
##     **不引用 Control / Node 类型**（本类自身 extends RefCounted，不挂场景树）
##   · 对外只有两类交互：
##       ① **请求**（视图/测试调用）：request_deploy / request_move / request_attack /
##          request_use_command / request_end_phase / request_surrender
##       ② **广播**（经 BattleSignalBus）：一切结果与状态变化
##   · 视图**不读**本引擎内部状态；需要数据只从信号参数取（G2/G4）
##
## a500 阶段流程（回合流程 1~8）
##   回费 → 场地 → 部署 → 行动
##   已有回合方走完四阶段后换手；双方都走完 → 回合数 +1
##   ⚠️ 与旧实现差异 P-1：回费/场地由引擎**自动**推进（不由玩家连点），部署/行动等玩家按钮

const Bus := preload("res://scripts/battle/battle_signal_bus.gd")
const StateLib := preload("res://scripts/battle/battle_state.gd")
const ConfigLib := preload("res://scripts/battle/battle_config.gd")
const Effects := preload("res://scripts/battle/rules_effects.gd")
const Combat := preload("res://scripts/battle/rules_combat.gd")
const Command := preload("res://scripts/battle/rules_command.gd")
const Preview := preload("res://scripts/battle/rules_preview.gd")
const Assets := preload("res://scripts/battle/arena_assets.gd")
const Pool := preload("res://scripts/data/card_pool.gd")

var state: BattleState = null
var config: BattleConfig = null

## 当前选中（**只保存索引/id，不保存 UI 引用**）
var sel_kind: int = 0            ## 0=无 1=手牌 2=单位 3=支援
var sel_support: SkillData = null   ## 支援技能（sel_kind==3 时有效）
var sel_hand_index: int = -1
var sel_unit: UnitInstance = null


func bus() -> Node:
	return Bus.shared()


# ============================================================
#  开局（a500 对战准备 1~9）
# ============================================================

func start(p_config: BattleConfig) -> bool:
	if p_config == null:
		return false
	var errs := p_config.validate()
	if not errs.is_empty():
		for e in errs:
			bus().emit_signal(Bus.SIG_LOG, "配置错误：" + e, 2)
		return false
	config = p_config
	state = StateLib.new()
	state.setup(config)

	# 对战准备 7~8：前 4 张为初始手牌、后 4 张为备卡入牌库底
	for side in [state.SIDE_ALLY, state.SIDE_ENEMY]:
		var dd: DeckData = config.deck_of(side)
		# 玩家信息
		state.sides[side]["queen"] = null
		# 分配：常规卡前 N 张进手牌，其余进牌库
		var i := 0
		for c in dd.cards:
			if c == null:
				continue
			if i < config.initial_hand_size:
				state.sides[side]["hand"].append(c)
			else:
				state.sides[side]["deck"].append(c)
			i += 1
		# 对战准备 9：部署蜂王（a500 建筑/兵蜂另论；蜂王开局即在位）
		var q := UnitInstance.create(dd.queen, side, queen_cell(side))
		state.sides[side]["queen"] = q
		state.board.place(q)
		# 蜂王开局即结算它的 [部署] 技能（如金刚蜂王「获得装甲」）
		_apply_deploy_skills(q, dd.queen)

	# 对战准备 6：后手初始费用 +2
	state.sides[config.second_side()]["cost"] = config.second_side_bonus

	bus().emit_signal(Bus.SIG_BATTLE_STARTED, state.active, state.round_no,
		config.ally_name, config.enemy_name)
	_log("对局开始：%s 先手；%s 初始费用 +%d" % [
		config.name_of(state.active), config.name_of(config.second_side()),
		config.second_side_bonus])
	# 地图/背景下发（**解耦**：视图两个 TextureRect 各自订阅同一条信号的参数）
	emit_map_assets()
	_enter_phase(state.Phase.RECOVER)
	return true


## 蜂王开局位置（a500 对战准备 9）
## ⚠️ 坐标约定：`Vector2i(行, 列)`；行 0 在上（红方领地）、行 3 在下（我方领地）
##
## 人 2026-09-19 最终指定（**位于顶部/底部行**，不是左右两侧）：
##   · 我方蜂王 **(行3, 列2)** —— 底部行·中右列
##   · 红方蜂王 **(行0, 列1)** —— 顶部行·中左列
##
## ✅ 中心对称校验（棋盘 4×4，几何中心在 (1.5, 1.5)）：
##   我方偏移 = (3−1.5, 2−1.5) = (+1.5, +0.5)
##   红方偏移 = (0−1.5, 1−1.5) = (−1.5, −0.5)  → 互为相反数，**严格中心对称**
##   （人原口径 (4,2)/(1,3) 指旧朝向；整体顺时针旋转 90° 后即本值）
static func queen_cell(side: int) -> Vector2i:
	return Vector2i(3, 2) if side == 0 else Vector2i(0, 1)


func _apply_deploy_skills(inst: UnitInstance, ud: UnitData) -> void:
	## a500：`[部署]` 类技能（如金刚蜂王「[部署]获得[装甲]效果」）
	if inst == null or ud == null:
		return
	for sk in ud.skills:
		if sk == null or sk.glossary != "部署":
			continue
		for e in sk.effects:
			if e != null and Effects.grant(inst, e):
				_log("%s 触发【部署】%s" % [ud.display_name, e.display_name])


# ============================================================
#  地图 / 背景（**解耦下发**）
# ============================================================

## 主动广播地图/背景资源。
## 视图侧 `Battle/MapView/MapPlate/TextureRect` 与 `Background/TextureRect`
## **各自独立订阅** `SIG_MAP_ASSETS`（同一条信号两个参数，互不直接引用）。
func emit_map_assets() -> void:
	var a: Resource = Assets.make(state.map_data)
	bus().emit_signal(Bus.SIG_MAP_ASSETS, a)


## 换图（外部可调；走同一信号，视图无需知道变化来源）
func load_map(md: MapData) -> void:
	if state == null:
		return
	state.map_data = md
	emit_map_assets()
	_log("更换地图：%s" % (md.display_name if md != null else "（无）"))


# ============================================================
#  阶段状态机（a500 回合流程 1~8）
# ============================================================

func _enter_phase(phase: int) -> void:
	state.phase = phase
	bus().emit_signal(Bus.SIG_PHASE_STARTED, state.active, phase, state.round_no)
	_emit_button()
	match phase:
		state.Phase.RECOVER:
			_do_recover(state.active)
			_end_phase()                       ## 自动推进（P-1）
		state.Phase.TERRAIN:
			Effects.resolve_terrain_phase(state, state.active)
			_end_phase()                       ## 自动推进（P-1）
		state.Phase.DEPLOY:
			_emit_selection()
			_emit_action_availability()
		state.Phase.ACTION:
			_emit_selection()
			_emit_action_availability()


func _end_phase() -> void:
	bus().emit_signal(Bus.SIG_PHASE_ENDED, state.active, state.phase)
	match state.phase:
		state.Phase.RECOVER:
			_enter_phase(state.Phase.TERRAIN)
		state.Phase.TERRAIN:
			_enter_phase(state.Phase.DEPLOY)
		state.Phase.DEPLOY:
			_enter_phase(state.Phase.ACTION)
		state.Phase.ACTION:
			_end_turn()


## 玩家请求：推进阶段（部署 → 行动 / 行动 → 换手）
func request_end_phase() -> bool:
	if state == null or state.is_over():
		return false
	if state.phase != state.Phase.DEPLOY and state.phase != state.Phase.ACTION:
		return false                          ## 回费/场地由引擎自动推进
	_cancel_selection()
	_end_phase()
	return true


# ============================================================
#  回费阶段（a500 费用 1~3 + 行动机会 2）
# ============================================================

func _do_recover(side: int) -> void:
	var before: int = state.cost(side)
	var gain := state.recover_gain(side)
	if gain > 0:
		state.sides[side]["cost"] = mini(state.MAX_COST, before + gain)
	# 行动机会 2：己方回费阶段重置每个单位的行动机会
	for u in state.units(side):
		u.reset_turn_flags()
	var delta: int = state.cost(side) - before
	if delta > 0:
		_log("%s 回费 +%d（现 %d）" % [config.name_of(side), delta, state.cost(side)])
	bus().emit_signal(Bus.SIG_COST_CHANGED, side, state.cost(side), delta)


# ============================================================
#  回合切换 + 抽卡（a500 抽卡 4~5）
# ============================================================

func _end_turn() -> void:
	var side := state.active
	bus().emit_signal(Bus.SIG_TURN_ENDED, side, state.round_no)
	_draw_to_full(side)                        ## 抽卡 4：回合结束后补至 4 张
	_emit_hand(side)
	if state.is_over():
		return
	var other := state.opponent(side)
	if other == config.first_side:
		## 先手方走完 → 新一轮
		state.round_no += 1
		bus().emit_signal(Bus.SIG_ROUND_STARTED, state.round_no)
		_check_round_limit()
		if state.is_over():
			return
	state.active = other
	bus().emit_signal(Bus.SIG_TURN_STARTED, state.active, state.round_no)
	_log("%s 回合开始（第 %d 回合）" % [config.name_of(state.active), state.round_no])
	_enter_phase(state.Phase.RECOVER)


## 抽卡 4：抽备卡补手牌到 hand_max
func _draw_to_full(side: int) -> void:
	var hand: Array = state.sides[side]["hand"]
	while hand.size() < config.hand_max:
		var d := draw_card(side, 1)
		if d == 0:
			break


## 抽 n 张；牌库空则按抽卡 5 把墓地前 4 张洗回
func draw_card(side: int, n: int) -> int:
	var got := 0
	for _i in n:
		var dk: Array = state.sides[side]["deck"]
		if dk.is_empty():
			# 抽卡 5：牌库抽完 → 墓地内前 4 张放入牌库并洗牌
			var dis: Array = state.sides[side]["discard"]
			if dis.is_empty():
				break
			var take := mini(4, dis.size())
			var moved: Array = []
			for _k in take:
				moved.append(dis.pop_front())
			dk.append_array(moved)
			dk.shuffle()
			bus().emit_signal(Bus.SIG_DECK_RESHUFFLED, side, moved.size())
			_log("%s 牌库抽完 → 墓地前 %d 张洗回" % [config.name_of(side), moved.size()])
		var card: CardData = dk.pop_front()
		if card == null:
			continue
		state.sides[side]["hand"].append(card)
		got += 1
		bus().emit_signal(Bus.SIG_CARD_DRAWN, side, card, state.sides[side]["hand"].size())
	return got


# ============================================================
#  请求：部署（a500 卡牌类型 + 部署格规则）
# ============================================================

func request_deploy(side: int, hand_index: int, cell: Vector2i) -> bool:
	if state == null or state.is_over():
		return false
	if side != state.active:
		return false
	if state.phase != state.Phase.DEPLOY:
		return false
	var hand: Array = state.sides[side]["hand"]
	if hand_index < 0 or hand_index >= hand.size():
		return false
	var data: CardData = hand[hand_index]
	if data == null or not (data is UnitData):
		return false
	var ud := data as UnitData
	if not _deploy_cell_ok(side, ud, cell):
		_log("该格不可部署", 1)
		return false
	if ud.cost > state.cost(side):
		_log("费用不足", 1)
		return false
	# 付费（a500 抽卡 2：使用单位卡把卡复制一份部署，原卡进墓地）
	state.sides[side]["cost"] -= maxi(0, ud.cost)
	bus().emit_signal(Bus.SIG_COST_CHANGED, side, state.cost(side), -maxi(0, ud.cost))
	hand.remove_at(hand_index)
	state.sides[side]["discard"].append(data)
	# 入场：行动机会 3 —— 部署当回合**没有**行动机会
	var inst := UnitInstance.create(ud, side, cell)
	inst.instance_id = _next_instance_id()
	inst.has_moved = true
	inst.has_acted = true
	state.board.place(inst)
	_apply_deploy_skills(inst, ud)
	bus().emit_signal(Bus.SIG_UNIT_SPAWNED, inst, cell)
	_log("%s 部署 %s 到 (%d,%d)（费 -%d）" % [
		config.name_of(side), ud.display_name, cell.x, cell.y, maxi(0, ud.cost)])
	_cancel_selection()
	_emit_hand(side)
	_emit_selection()
	_emit_action_availability()
	return true


## 部署格合法性（a500 卡牌类型：兵蜂→蜂王相邻格；建筑→己方领地任意格）
func _deploy_cell_ok(side: int, ud: UnitData, cell: Vector2i) -> bool:
	if state.board == null or not state.board.in_bounds(cell):
		return false
	if not state.board.is_empty(cell):
		return false
	if ud.kind == CardData.CardKind.BUILDING:
		return state.board.is_own_territory(cell, side)
	var q: UnitInstance = state.queen(side)
	if q == null:
		return false
	return state.board.manhattan(q.cell, cell) == 1


# ============================================================
#  请求：移动 / 攻击 / 支援（a500 行动机会 4~6）
# ============================================================

func request_move(side: int, unit: UnitInstance, cell: Vector2i) -> bool:
	if not _can_act_with(side, unit):
		return false
	var allow: Dictionary = state.board.move_range(unit)
	if not allow.has(cell):
		return false
	var from := unit.cell
	state.board.move_unit(unit, cell)
	unit.mark_moved()
	bus().emit_signal(Bus.SIG_UNIT_MOVED, unit, from, cell)
	_log("%s 移动到 (%d,%d)" % [unit.card_name(), cell.x, cell.y])
	_cancel_selection()
	_emit_selection()
	_emit_action_availability()
	return true


func request_attack(side: int, attacker: UnitInstance, defender: UnitInstance) -> bool:
	if not _can_act_with(side, attacker):
		return false
	if defender == null or defender.side == side or not defender.is_alive():
		return false
	if state.board.manhattan(attacker.cell, defender.cell) > attacker.attack_range():
		return false
	Combat.resolve_attack(attacker, defender, state.board)
	attacker.mark_acted()                      ## 行动机会 4：攻击后自动结束行动
	_cleanup_dead()
	_log("%s 攻击 %s" % [attacker.card_name(), defender.card_name()])
	_cancel_selection()
	_emit_selection()
	_emit_action_availability()
	_check_win()
	return true


func request_use_command(side: int, hand_index: int, target: UnitInstance) -> bool:
	if state == null or state.is_over():
		return false
	if side != state.active:
		return false
	if state.phase != state.Phase.DEPLOY and state.phase != state.Phase.ACTION:
		return false                            ## a500：指令卡在部署与行动阶段均可使用
	var hand: Array = state.sides[side]["hand"]
	if hand_index < 0 or hand_index >= hand.size():
		return false
	var card: CardData = hand[hand_index]
	if card == null or not (card is CommandData):
		return false
	var cd := card as CommandData
	if cd.cost > state.cost(side):
		_log("费用不足", 1)
		return false
	var res := Command.execute(state, cd, side, target)
	if not res["ok"]:
		_log("指令目标不合法", 1)
		return false
	state.sides[side]["cost"] -= maxi(0, cd.cost)
	bus().emit_signal(Bus.SIG_COST_CHANGED, side, state.cost(side), -maxi(0, cd.cost))
	hand.remove_at(hand_index)
	state.sides[side]["discard"].append(card)   ## 抽卡 1：用完进墓地
	_log("%s 使用指令 %s" % [config.name_of(side), cd.display_name])
	_cleanup_dead()
	_cancel_selection()
	_emit_hand(side)
	_emit_selection()
	_check_win()
	return true


## 支援技能（a500 行动机会 5：技能没有支援条件无法使用支援技能）
func request_support(side: int, unit: UnitInstance, skill: SkillData,
		target: UnitInstance) -> bool:
	if not _can_act_with(side, unit) or skill == null or target == null:
		return false
	if skill.kind != SkillData.Kind.SUPPORT:
		return false
	if target.side != side or not target.is_alive():
		return false
	if state.board.manhattan(unit.cell, target.cell) > skill.target_range:
		return false
	var applied := 0
	for e in skill.effects:
		if Effects.grant(target, e):
			applied += 1
	# 支援回费（如熊蜂「[支援]回复 3 点费用」）
	var refunded := 0
	if skill.refund > 0:
		var before: int = state.cost(side)
		state.sides[side]["cost"] = mini(state.MAX_COST, before + skill.refund)
		refunded = state.cost(side) - before
		bus().emit_signal(Bus.SIG_COST_CHANGED, side, state.cost(side), refunded)
	var healed := 0
	if skill.heal > 0:
		var hp0: int = target.current_hp
		target.heal(skill.heal)
		healed = target.current_hp - hp0
	unit.mark_acted()                           ## 行动机会 4：支援后自动结束行动
	var extra := ""
	if refunded > 0:
		extra += "，回费 +%d" % refunded
	if healed > 0:
		extra += "，回血 +%d" % healed
	_log("%s 对 %s 使用【支援】%s（生效 %d 个效果%s）" % [
		unit.card_name(), target.card_name(), skill.display_name, applied, extra])
	_cancel_selection()
	_emit_selection()
	_emit_action_availability()
	return true


func _can_act_with(side: int, unit: UnitInstance) -> bool:
	if state == null or state.is_over() or unit == null:
		return false
	if unit.side != side or side != state.active:
		return false
	if state.phase != state.Phase.ACTION:       ## 行动机会 1：只有行动阶段能行动
		return false
	if unit.has_acted or not unit.is_alive():
		return false
	return true


# ============================================================
#  选择（视图调用；只产生信号，不改规则）
# ============================================================

func select_hand(side: int, index: int) -> void:
	if state == null or side != state.active:
		return
	sel_kind = 1
	sel_hand_index = index
	sel_unit = null
	_emit_selection()


func select_unit(side: int, unit: UnitInstance) -> void:
	if state == null or unit == null or unit.side != state.active:
		return
	sel_kind = 2
	sel_unit = unit
	sel_hand_index = -1
	_emit_selection()


## 选中支援技能（视图点"支援"按钮时调用）→ 会下发支援目标预览
func select_support(side: int, unit: UnitInstance, skill: SkillData) -> void:
	if state == null or unit == null or skill == null or unit.side != state.active:
		return
	sel_kind = 3
	sel_unit = unit
	sel_support = skill
	sel_hand_index = -1
	_emit_selection()


func _cancel_selection() -> void:
	sel_kind = 0
	sel_hand_index = -1
	sel_unit = null
	sel_support = null


# ============================================================
#  胜负（a500 胜利条件 1~4）
# ============================================================

func request_surrender(side: int) -> bool:
	if state == null or state.is_over():
		return false
	if state.round_no < state.SURRENDER_FROM_ROUND:
		_log("第 %d 回合起才可投降" % state.SURRENDER_FROM_ROUND, 1)
		return false
	state.result = state.SIDE_ENEMY if side == state.SIDE_ALLY else state.SIDE_ALLY
	state.result_reason = "%s 投降" % config.name_of(side)
	bus().emit_signal(Bus.SIG_BATTLE_ENDED, state.result, state.result_reason)
	return true


func _check_win() -> void:
	## 胜利条件 1：击败敌方蜂王
	for side in [state.SIDE_ALLY, state.SIDE_ENEMY]:
		var q: UnitInstance = state.queen(side)
		if q != null and not q.is_alive():
			state.result = state.SIDE_ENEMY if side == state.SIDE_ALLY else state.SIDE_ALLY
			state.result_reason = "%s 蜂王被击败" % config.name_of(side)
			bus().emit_signal(Bus.SIG_BATTLE_ENDED, state.result, state.result_reason)
			return


func _check_round_limit() -> void:
	## 胜利条件 2~3：第 12 回合结束后比蜂王生命，相同则平局
	if state.round_no <= state.MAX_ROUNDS:
		return
	var a: int = state.queen(state.SIDE_ALLY).current_hp if state.queen(state.SIDE_ALLY) != null else 0
	var e: int = state.queen(state.SIDE_ENEMY).current_hp if state.queen(state.SIDE_ENEMY) != null else 0
	if a == e:
		state.result = state.Result.DRAW
	elif a > e:
		state.result = state.Result.ALLY_WIN
	else:
		state.result = state.Result.ENEMY_WIN
	state.result_reason = "第 %d 回合结束，蜂王生命 %d : %d" % [state.MAX_ROUNDS, a, e]
	bus().emit_signal(Bus.SIG_BATTLE_ENDED, state.result, state.result_reason)


## 单位退场清理（a500 抽卡 3：被击败直接删除卡牌）
func _cleanup_dead() -> void:
	for u in state.board.all_units():
		if u.is_alive():
			continue
		Effects.clear_all(u)
		state.board.remove(u)
		bus().emit_signal(Bus.SIG_UNIT_REMOVED, u, "defeated")
		_log("%s 退场" % u.card_name())


# ============================================================
#  信号广播（把内部状态翻译成视图可用的参数）
# ============================================================

func _emit_hand(side: int) -> void:
	var hand: Array = state.sides[side]["hand"]
	var mask: Array = []
	for i in hand.size():
		mask.append(can_play_hand(side, i))
	bus().emit_signal(Bus.SIG_HAND_CHANGED, side, hand.duplicate(), mask)
	var playable := hand.size() > 0
	bus().emit_signal(Bus.SIG_ACTION_AVAIL, side, true, false, playable, true)


## 手牌 i 当前是否可打出（费用 + 阶段）
func can_play_hand(side: int, index: int) -> bool:
	if state == null or side != state.active:
		return false
	var hand: Array = state.sides[side]["hand"]
	if index < 0 or index >= hand.size():
		return false
	var c: CardData = hand[index]
	if c == null:
		return false
	if c.cost < 0:                              ## X 费卡：费用不固定，按可负担判断
		return state.phase == state.Phase.DEPLOY or state.phase == state.Phase.ACTION
	if c.cost > state.cost(side):
		return false
	return state.phase == state.Phase.DEPLOY or state.phase == state.Phase.ACTION


## 选中态 + **操作预览资源**一起下发
## ⚠️ 人指示（迭代056）：范围预览是**资源类**（PreviewData），视图直接读它渲染，不自己算规则。
## 这也保证「预览与试算同源」—— 视图看到的范围与实际可执行集合来自同一处计算。
func _emit_selection() -> void:
	var pv: Resource = Preview.build(state, sel_kind, sel_hand_index, sel_unit, sel_support)
	var units: Array = []
	if pv != null:
		units = pv.units
	bus().emit_signal(Bus.SIG_SELECTION, sel_kind,
		sel_unit.instance_id if sel_unit != null else "", pv, units)


## 供视图/测试直接索取预览资源（不必等信号）
func current_preview():
	return Preview.build(state, sel_kind, sel_hand_index, sel_unit, sel_support)


## 某单位可操作范围预览（无选中时的"我的单位能做什么"提示）
func availability_preview():
	return Preview.availability(state)


func _emit_action_availability() -> void:
	var can_deploy: bool = state.phase == state.Phase.DEPLOY
	var can_act: bool = state.phase == state.Phase.ACTION
	bus().emit_signal(Bus.SIG_ACTION_AVAIL, state.active, can_deploy, can_act, can_act, true)


func _emit_button() -> void:
	var text := ""
	var hint := ""
	var enabled := true
	match state.phase:
		state.Phase.RECOVER, state.Phase.TERRAIN:
			text = "自动结算中…"
			hint = "回费/场地阶段自动结算，无需操作"
			enabled = false
		state.Phase.DEPLOY:
			## 文案保持原设计（人 2026-09-19 明确：不要改动按钮文案）
			text = "完成部署"
			hint = "点手牌部署单位/使用指令；准备好后点右侧按钮进入行动阶段"
		state.Phase.ACTION:
			text = "结束回合"
			hint = "点自己的单位可移动/攻击/支援；每个单位每回合 1 次行动"
	bus().emit_signal(Bus.SIG_MAIN_BUTTON, text, enabled, hint)


func _log(text: String, level: int = 0) -> void:
	bus().emit_signal(Bus.SIG_LOG, text, level)


func _next_instance_id() -> String:
	return "u%d_%s" % [state.board.all_units().size(), Uuid.generate().substr(0, 8)]
