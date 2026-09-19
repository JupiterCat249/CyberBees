class_name RulesPreview
extends RefCounted
## **操作预览计算**（移动 / 攻击 / 支援 / 部署 / 指令 范围）
##
## 人指示（迭代056）：「完成操作预览（如移动或攻击范围显示），这些东西也做成**资源-供UI调用的资源类**」
##
## 设计
##   · 输入：BattleState + 当前选中（手牌索引 / 单位 / 支援技能）
##   · 输出：**PreviewData 资源**（纯数据）→ 经 BattleSignalBus.preview_ready 广播
##   · 视图**不自己算范围**：规则层算完给结果，保证"预览与试算同源"（口径不会漂移）
##
## ⚠️ **零 UI 依赖**：不 preload 任何 scenes/、不 get_node、不引用 Control/Node。
##
## a500 依据
##   · 范围 1：通过**走格子**的方式能够计算出可移动/攻击的范围
##   · 范围 2：**攻击不会被单位阻挡**
##   · 范围 3：**移动会被单位阻挡**
##   · 卡牌类型：兵蜂→蜂王相邻格部署；建筑→己方领地任意格

const Bus := preload("res://scripts/battle/battle_signal_bus.gd")
const StateLib := preload("res://scripts/battle/battle_state.gd")
const PV := preload("res://scripts/battle/preview_data.gd")
const K := preload("res://scripts/battle/preview_kind.gd")


## 主入口：按当前选中算出预览资源
## sel_kind: 0=无 1=手牌 2=单位 3=支援
static func build(state, sel_kind: int, hand_index: int, sel_unit: UnitInstance,
		sel_support: SkillData = null) -> PreviewData:
	if state == null or state.board == null:
		return PV.make(K.Kind.NONE)
	match sel_kind:
		1:
			return _hand_preview(state, hand_index)
		2:
			return _unit_preview(state, sel_unit)
		3:
			return _support_preview(state, sel_unit, sel_support)
	return PV.make(K.Kind.NONE)


# ============================================================
#  手牌：部署格 / 指令目标
# ============================================================

static func _hand_preview(state, hand_index: int) -> PreviewData:
	var side: int = state.active
	var hand: Array = state.sides[side]["hand"]
	if hand_index < 0 or hand_index >= hand.size():
		return PV.make(K.Kind.NONE)
	var data: CardData = hand[hand_index]
	if data == null:
		return PV.make(K.Kind.NONE)

	# 单位卡 → 部署可用格
	var ud := data as UnitData
	if ud != null:
		var pv: Resource = PV.make(K.Kind.DEPLOY, "选择部署位置")
		for c in deploy_cells(state, side, ud):
			pv.add_cell(c, K.Kind.DEPLOY)
		return pv

	# 指令卡 → 可作用目标
	var cd := data as CommandData
	if cd != null:
		var pv2: Resource = PV.make(K.Kind.COMMAND, "选择指令目标")
		for u in command_targets(state, side, cd):
			pv2.add_unit(u, K.Kind.COMMAND)
		return pv2
	return PV.make(K.Kind.NONE)


## 部署可用格（a500 卡牌类型）
static func deploy_cells(state, side: int, ud: UnitData) -> Array:
	var out: Array = []
	if state == null or state.board == null or ud == null:
		return out
	## ⭐ 迭代059 G-4：地形「禁区」的格子不可部署 → 预览里也排除
	##    （预览与实际可执行集合**同源**，避免“高亮了却放不下”）
	var md: MapData = state.map_data
	if ud.kind == CardData.CardKind.BUILDING:
		# 建筑：己方领地任意空格
		for x in Board.ROWS:
			for y in Board.COLS:
				var c := Vector2i(x, y)
				if state.board.is_empty(c) and state.board.is_own_territory(c, side) \
						and not _terrain_blocked(md, c):
					out.append(c)
		return out
	if ud.kind == CardData.CardKind.SOLDIER:
		# 兵蜂：蜂王相邻格（空格）
		var q: UnitInstance = state.queen(side)
		if q == null:
			return out
		for n in state.board.neighbors_cardinal(q.cell):
			if state.board.is_empty(n) and not _terrain_blocked(md, n):
				out.append(n)
	return out


## 该格是否因地形禁止部署（禁区）
static func _terrain_blocked(md: MapData, cell: Vector2i) -> bool:
	if md == null:
		return false
	var te = md.effect_at(cell)
	return te != null and bool(te.blocks_deploy)


## 指令卡可作用目标（治疗→己方；伤害→敌方）
static func command_targets(state, side: int, cd: CommandData) -> Array:
	var out: Array = []
	if state == null or state.board == null or cd == null:
		return out
	var want_ally: bool = cd.heal > 0
	for u in state.board.all_units():
		if not u.is_alive():
			continue
		if want_ally and u.side != side:
			continue
		if not want_ally and u.side == side:
			continue
		out.append(u)
	# X 费卡不可对蜂王使用（a500 费用 4）
	if cd.cost < 0:
		var filtered: Array = []
		for u in out:
			if u.data != null and u.data.kind == CardData.CardKind.QUEEN:
				continue
			filtered.append(u)
		return filtered
	return out


# ============================================================
#  单位：移动格 + 攻击目标
# ============================================================

static func _unit_preview(state, inst: UnitInstance) -> PreviewData:
	if inst == null:
		return PV.make(K.Kind.NONE)
	var pv: Resource = PV.make(K.Kind.MOVE, "移动或攻击")
	# 移动可达（走格子 + 被单位阻挡 —— a500 范围 1/3）
	if not inst.has_moved:
		for c in state.board.move_range(inst).keys():
			pv.add_cell(c, K.Kind.MOVE)
	# 攻击目标（曼哈顿射程 + 不被阻挡 —— a500 范围 2）
	if not inst.has_acted:
		var all: Array[UnitInstance] = state.board.all_units()
		for u in state.board.attackable(inst, all):
			pv.add_unit(u, K.Kind.ATTACK)        ## ⚠️ 显式 ATTACK，不能沿用顶层 kind
	return pv


# ============================================================
#  支援：可作用的己方单位
# ============================================================

static func _support_preview(state, inst: UnitInstance, skill: SkillData) -> PreviewData:
	var pv: Resource = PV.make(K.Kind.SUPPORT, "选择支援目标")
	if inst == null or skill == null or state == null or state.board == null:
		return pv
	for u in state.board.units_of(inst.side):
		if not u.is_alive():
			continue
		if state.board.manhattan(inst.cell, u.cell) <= skill.target_range:
			pv.add_unit(u, K.Kind.SUPPORT)
	return pv


## 便捷：某单位**无选中时**的默认可操作预览（视图可用来画"我的单位可行动"提示）
static func availability(state) -> PreviewData:
	var pv: Resource = PV.make(K.Kind.MOVE, "")
	if state == null or state.board == null:
		return pv
	for u in state.board.units_of(state.active):
		if u.has_moved and u.has_acted:
			continue
		var mine: Resource = _unit_preview(state, u)
		for c in mine.cells:
			pv.add_cell(c.cell, c.kind, false)
	return pv
