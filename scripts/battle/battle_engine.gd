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
## 支援：**待确认目标**（迭代059 步3：人要求「做回原有设计 —— 双击确认」）
##   第一次点击友方 → 进入待确认；**再次点击同一目标**或按主按钮「确认」→ 执行
##   改选其它单位 / 取消选中 → 待确认失效
var support_pending: UnitInstance = null
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
## ⭐ 迭代059 G-4：特殊地形「禁区」不可部署（a500：障碍地形无法部署，**但不阻挡移动与攻击**）
func _deploy_cell_ok(side: int, ud: UnitData, cell: Vector2i) -> bool:
	if state.board == null or not state.board.in_bounds(cell):
		return false
	if not state.board.is_empty(cell):
		return false
	if _terrain_blocks_deploy(cell):
		return false
	if ud.kind == CardData.CardKind.BUILDING:
		return state.board.is_own_territory(cell, side)
	var q: UnitInstance = state.queen(side)
	if q == null:
		return false
	return state.board.manhattan(q.cell, cell) == 1


## 该格是否因地形禁止部署（禁区）
func _terrain_blocks_deploy(cell: Vector2i) -> bool:
	if state == null or state.map_data == null:
		return false
	var te: TerrainEffect = state.map_data.effect_at(cell)
	if te == null:
		return false
	return te.blocks_deploy


## 供预览/UI 查询：某格是否因地形不可部署（视图只读，不自行判定）
func terrain_blocks_deploy(cell: Vector2i) -> bool:
	return _terrain_blocks_deploy(cell)


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
	## ⚠️ 结算必须先做（迭代059 曾因 patch 误删这两行 → 攻击"命中"却不掉血）
	Combat.resolve_attack(attacker, defender, state.board)
	attacker.mark_acted()                      ## 行动机会 4：攻击后自动结束行动
	var killed_queen: int = -1
	var _is_q: bool = defender.data != null and defender.data.kind == CardData.CardKind.QUEEN
	## ⭐ 迭代059 修缺陷：**必须在 _cleanup_dead 之前判定胜负** ——
	##   死掉的蜂王会被移出棋盘，之后 state.queen() 查不到 → 胜负永远判不出来
	if defender.data != null and defender.data.kind == CardData.CardKind.QUEEN \
			and not defender.is_alive():
		killed_queen = defender.side
	_cleanup_dead()
	_log("%s 攻击 %s" % [attacker.card_name(), defender.card_name()])
	_cancel_selection()
	_emit_selection()
	_emit_action_availability()
	if killed_queen >= 0:
		_declare_queen_killed(killed_queen)
	else:
		_check_win()
	return true


## ⭐ 迭代059 修缺陷：**side 与 Result 是两套语义，不能混用**
##   `enum Result { NONE=0, ALLY_WIN=1, ENEMY_WIN=2, DRAW=3 }` 而 `SIDE_ALLY=0 / SIDE_ENEMY=1`
##   直接把 side 赋给 result → 胜者是绿方时恰好等于 `Result.NONE` → 对局看起来"没结束"。
##   （与本日早前修的 `PreviewKind vs BattleState.Phase` 是同一类枚举撞车问题）
static func result_of_winner(winner_side: int) -> int:
	return StateLib.Result.ALLY_WIN if winner_side == StateLib.SIDE_ALLY else StateLib.Result.ENEMY_WIN


## 蜂王被击杀 → 对局结束（a500 胜利条件 1）
func _declare_queen_killed(side_of_killed: int) -> void:
	var winner_side: int = state.SIDE_ENEMY if side_of_killed == state.SIDE_ALLY else state.SIDE_ALLY
	state.result = result_of_winner(winner_side)
	state.result_reason = "%s 蜂王被击败" % config.name_of(side_of_killed)
	_log("%s 蜂王被击败 —— %s 获胜" % [config.name_of(side_of_killed), config.name_of(winner_side)])
	bus().emit_signal(Bus.SIG_BATTLE_ENDED, state.result, state.result_reason)


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


## 支援：**双击确认 · 不针对特定单位**（迭代059 人澄清 Y-5）
##   人：「熊蜂的支援技能是为己方回费3，这种技能自然不需要射程 —— 根本不是针对特定单位的技能」
##   → 第一次调用 = 进入待确认（按钮变「确认」）；**第二次调用同一单位** = 执行
##   → 执行效果作用于**己方整体**（回费/回血），不需要选目标
func request_support(side: int, unit: UnitInstance, skill: SkillData,
		_target: UnitInstance = null) -> bool:
	if not _can_act_with(side, unit) or skill == null:
		return false
	if skill.kind != SkillData.Kind.SUPPORT:
		return false
	# ── 双击确认：第一次只进入待确认，不执行 ──
	if support_pending != unit:
		support_pending = unit
		_log("待确认：再次使用 %s 的【支援】%s" % [unit.card_name(), skill.display_name])
		_emit_button()
		_emit_selection()
		return false
	# ── 第二次 → 执行 ──
	support_pending = null
	return _resolve_support(side, unit, skill)


## 实际结算支援（作用于己方整体：回费 / 回血；也支持效果赋予给自身）
func _resolve_support(side: int, unit: UnitInstance, skill: SkillData) -> bool:
	var applied := 0
	for e in skill.effects:
		if Effects.grant(unit, e):
			applied += 1
	var refunded := 0
	if skill.refund > 0:
		var before: int = state.cost(side)
		state.sides[side]["cost"] = mini(state.MAX_COST, before + skill.refund)
		refunded = state.cost(side) - before
		bus().emit_signal(Bus.SIG_COST_CHANGED, side, state.cost(side), refunded)
	var extra := ""
	if refunded > 0:
		extra = "回费 +%d" % refunded
	unit.mark_acted()                           ## 行动机会 4：使用支援后自动结束行动
	_log("%s 使用【支援】%s（%s%s）" % [
		unit.card_name(), skill.display_name, extra,
		"，生效 %d 个效果" % applied if applied > 0 else ""])
	_cancel_selection()
	_emit_selection()
	_emit_action_availability()
	_emit_button()
	return true


## 主按钮「确认」：对待确认的支援单位执行支援
func confirm_pending() -> bool:
	if support_pending == null:
		return false
	var u: UnitInstance = support_pending
	var sk := sel_support
	if sk == null:
		sk = find_support_skill(u)
	if sk == null:
		support_pending = null
		_emit_button()
		return false
	return request_support(u.side, u, sk)


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
	_emit_button()          ## 选卡后按钮变「弃牌」（G-6 Q-3）


## 选中单位（迭代059 步3：自动带上该单位的支援技能 —— 不需要额外 UI 入口）
func select_unit(side: int, unit: UnitInstance) -> void:
	if state == null or unit == null or unit.side != state.active:
		return
	support_pending = null        ## 改选单位 → 旧的待确认失效（原设计口径）
	sel_kind = 2
	sel_unit = unit
	sel_hand_index = -1
	sel_support = find_support_skill(unit)   ## 自动带上支援技能（有则可直接点友方）
	if sel_support != null:
		sel_kind = 3
	_emit_selection()
	_emit_button()          ## 选中单位 → 按钮退出「弃牌」态，恢复阶段文案（G-6）


## 取该单位的支援技能（无则 null）—— 视图/引擎共用，避免UI为支援单独做入口
func find_support_skill(unit: UnitInstance) -> SkillData:
	if unit == null or unit.data == null:
		return null
	for sk in unit.data.skills:
		if sk != null and sk.kind == SkillData.Kind.SUPPORT:
			return sk
	return null


## 该单位是否有支援技能（视图可据此提示，但不需要额外入口）
func has_support_skill(unit: UnitInstance) -> bool:
	return find_support_skill(unit) != null


## 选中支援技能（视图点"支援"按钮时调用）→ 会下发支援目标预览
func select_support(side: int, unit: UnitInstance, skill: SkillData) -> void:
	if state == null or unit == null or skill == null or unit.side != state.active:
		return
	sel_kind = 3
	sel_unit = unit
	sel_support = skill
	sel_hand_index = -1
	_emit_selection()


## 公开入口：取消当前选中（视图在"点击非手牌位置"时调用，退出弃牌/确认等态）
func cancel_selection() -> void:
	_cancel_selection()
	_emit_selection()
	_emit_action_availability()


func _cancel_selection() -> void:
	support_pending = null
	sel_kind = 0
	sel_hand_index = -1
	sel_unit = null
	sel_support = null
	## 取消选中 → 按钮恢复原文案（G-6 Q-3：弃牌态只在选中手牌时存在）
	_emit_button()


# ============================================================
#  胜负（a500 胜利条件 1~4）
# ============================================================

func request_surrender(side: int) -> bool:
	if state == null or state.is_over():
		return false
	if state.round_no < state.SURRENDER_FROM_ROUND:
		_log("第 %d 回合起才可投降" % state.SURRENDER_FROM_ROUND, 1)
		return false
	state.result = result_of_winner(state.SIDE_ENEMY if side == state.SIDE_ALLY else state.SIDE_ALLY)
	state.result_reason = "%s 投降" % config.name_of(side)
	bus().emit_signal(Bus.SIG_BATTLE_ENDED, state.result, state.result_reason)
	return true


func _check_win() -> void:
	## 胜利条件 1：击败敌方蜂王
	for side in [state.SIDE_ALLY, state.SIDE_ENEMY]:
		var q: UnitInstance = state.queen(side)
		if q != null and not q.is_alive():
			state.result = result_of_winner(state.SIDE_ENEMY if side == state.SIDE_ALLY else state.SIDE_ALLY)
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


## 主按钮文案与可用态
## ⭐ 迭代059 G-6（人裁决 Q-3）：**选中手牌时，按钮兼顾「弃牌」**（文案同步改变）
##    未选中手牌 → 保持原设计文案（完成部署 / 结束回合）
func _emit_button() -> void:
	var text := ""
	var hint := ""
	var enabled := true
	## 待确认支援 → 按钮变「确认」（迭代059 步3：恢复原设计的待确认态）
	if support_pending != null:
		text = "确认"
		enabled = true
		hint = "再次点击该单位或点本按钮执行【支援】%s" % [
			sel_support.display_name if sel_support != null else ""]
		bus().emit_signal(Bus.SIG_MAIN_BUTTON, text, enabled, hint)
		return
	## 选中手牌 → 按钮变弃牌（a500 抽卡 6：丢弃消耗 = 部署费用；X 费卡 = 10）
	var sel_card: CardData = _selected_hand_card()
	if sel_card != null:
		var dc := discard_cost_of(sel_card)
		text = "弃牌（消耗 %d 费）" % dc
		enabled = state.cost(state.active) >= dc
		hint = "%s：点右侧按钮丢弃此牌（消耗 %d 费）；或点高亮格使用它" % [sel_card.display_name, dc]
		bus().emit_signal(Bus.SIG_MAIN_BUTTON, text, enabled, hint)
		return
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


## 当前选中的手牌（无则 null）
func _selected_hand_card() -> CardData:
	if state == null or sel_kind != 1 or sel_hand_index < 0:
		return null
	var hand: Array = state.sides[state.active]["hand"]
	if sel_hand_index >= hand.size():
		return null
	return hand[sel_hand_index]


## 弃牌消耗（a500 抽卡 6：消耗等同于部署的费用；**X 费卡牌消耗 10 点费用**）
func discard_cost_of(card: CardData) -> int:
	if card == null:
		return 0
	if card.cost < 0:
		return 10
	return card.cost


## 请求：丢弃手牌（a500 抽卡 6）
##   · 消耗 = 卡费；X 费卡 = 10
##   · 弃牌后进墓地（与使用后一样）
##   · 仅可在部署/行动阶段
func request_discard(side: int, hand_index: int) -> bool:
	if state == null or state.is_over() or side != state.active:
		return false
	if state.phase != state.Phase.DEPLOY and state.phase != state.Phase.ACTION:
		_log("仅部署/行动阶段可弃牌", 1)
		return false
	var hand: Array = state.sides[side]["hand"]
	if hand_index < 0 or hand_index >= hand.size():
		return false
	var card: CardData = hand[hand_index]
	if card == null:
		return false
	var dc := discard_cost_of(card)
	if dc > state.cost(side):
		_log("费用不足：弃牌需 %d，当前 %d" % [dc, state.cost(side)], 1)
		return false
	state.sides[side]["cost"] -= dc
	bus().emit_signal(Bus.SIG_COST_CHANGED, side, state.cost(side), -dc)
	hand.remove_at(hand_index)
	state.sides[side]["discard"].append(card)
	bus().emit_signal(Bus.SIG_CARD_DISCARDED, side, card, dc)
	_log("%s 弃置 %s（费 -%d）" % [config.name_of(side), card.display_name, dc])
	_cancel_selection()
	_emit_hand(side)
	_emit_selection()
	_emit_button()
	_emit_action_availability()
	return true


func _log(text: String, level: int = 0) -> void:
	bus().emit_signal(Bus.SIG_LOG, text, level)


func _next_instance_id() -> String:
	return "u%d_%s" % [state.board.all_units().size(), Uuid.generate().substr(0, 8)]
