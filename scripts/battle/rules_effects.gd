class_name RulesEffects
extends RefCounted
## 效果规则（a500「战斗系统·效果」1~7）
##
## ⚠️ **零 UI 依赖**：本文件不 preload 任何 scenes/、不 get_node、不引用 Control/Node。
## 只接受 BattleState + UnitInstance，通过 BattleSignalBus 广播结果。

const Bus := preload("res://scripts/battle/battle_signal_bus.gd")
const StateLib := preload("res://scripts/battle/battle_state.gd")
const TerrainEff := preload("res://scripts/data/terrain_effect.gd")

## a500 效果 4：若效果的消失与赋予在相同阶段 —— **先计算消失，再计算赋予**
static func tick_and_grant(state, inst: UnitInstance,
		to_grant: Array) -> Dictionary:
	var expired: Array = tick_effects(inst)
	var granted: Array = []
	for e in to_grant:
		if e != null and grant(inst, e):
			granted.append(e)
	return {"expired": expired, "granted": granted}


## 效果时长递减（a500 效果 4 的"消失"半步）；返回本次消失的效果
static func tick_effects(inst: UnitInstance) -> Array:
	var gone: Array = []
	if inst == null:
		return gone
	for e in inst.effects:
		if e.turns > 0:
			e.turns -= 1
		if e.turns == 0:
			gone.append(e)
		elif e.turns < 0:
			pass   # -1 = 永久
	for e in gone:
		if e.data == null:
			continue
		inst.remove_effect(e.data.id)          ## 返回 void，不能当条件用
		Bus.shared().emit_signal(Bus.SIG_EFFECT_EXPIRED, inst, e.data)
	return gone


## 赋予效果（a500 效果 1~3）
##   1：**相同效果最多一个**（T14）→ 已存在则只刷新时长，不叠加
##   2：**单位类型不匹配则无法赋予**
##   3：单位效果作用于自身（本函数）；地域效果由 apply_terrain / grant_terrain_effects 处理
##
## ⭐ 迭代059 修正 G-8：去重**按效果名称**而非仅按 id
##   原因：`CardPool.make_armor()` 每次 `Uuid.generate()` 生成新 id，
##   若仅比 id，两个**同名的「装甲」**会被视为不同效果而叠层 → 违反 a500「相同效果最多一个」。
##   现改为：先按 `display_name` 比（同为「装甲」即同一效果），名字空时退回比 id。
static func grant(inst: UnitInstance, eff: EffectData) -> bool:
	if inst == null or eff == null or inst.data == null:
		return false
	# 类型匹配（a500 效果 2）
	if not eff.allows_kind(inst.data.kind):
		return false
	# 相同效果最多一个（a500 效果 1 / T14）：刷新时长，不再加一层
	for e in inst.effects:
		if e.data == null:
			continue
		if _same_effect(e.data, eff):
			e.turns = eff.duration
			Bus.shared().emit_signal(Bus.SIG_UNIT_STATS, inst)
			return false
	if inst.apply_effect(eff):
		Bus.shared().emit_signal(Bus.SIG_EFFECT_GRANTED, inst, eff, "unit")
		Bus.shared().emit_signal(Bus.SIG_UNIT_STATS, inst)
		return true
	return false


## 两个效果是否视为「同一效果」（a500：相同效果最多一个）
## 优先比名称（名称非空时），否则比 id
static func _same_effect(a: EffectData, b: EffectData) -> bool:
	if a.display_name != "" and b.display_name != "":
		return a.display_name == b.display_name
	return a.id == b.id


## 地域效果（a500 效果 3：地域效果作用于**目标格子上的单位**）
static func apply_terrain(state, cell: Vector2i, eff: EffectData) -> bool:
	if state == null or state.board == null or eff == null:
		return false
	var inst: UnitInstance = state.board.unit_at(cell)
	if inst == null:
		return false
	return grant(inst, eff)


## ⭐ 迭代059 G-3：地形格效果结算（铁锈=地形格上的单位获得力场）
## a500：地域效果作用于**目标格子上的单位**（不是区域）
## 返回本次被赋予效果的单位数
static func grant_terrain_effects(state) -> int:
	if state == null or state.board == null or state.map_data == null:
		return 0
	var md: MapData = state.map_data
	var n := 0
	for cell in md.terrain_cells:
		var te: TerrainEffect = md.effect_at(cell)
		if te == null or te.kind != TerrainEffect.Kind.GRANT_FIELD or te.grant_effect == null:
			continue
		var inst: UnitInstance = state.board.unit_at(cell)
		if inst == null or not inst.is_alive():
			continue
		if grant(inst, te.grant_effect):
			n += 1
	return n


## 场地阶段：按地图数据结算（a500 特殊地形 + 项目 6 张地图）
##   回合性伤害 damage_per_round（寒潮：第 3/6/9/12 回合，蜂王除外）
##   回合性回费 refund_bonus（丰饶：第 3/9 回合 +4）—— **只作用于当前行动方**
##   地形格效果 grant_terrain_effects（铁锈）
static func resolve_terrain_phase(state, side: int) -> Dictionary:
	var out := {"damaged": 0, "field_granted": 0, "refund": 0}
	if state == null or state.map_data == null:
		return out
	var md: MapData = state.map_data
	## 回合筛选：effect_rounds 非空时只在列出的回合生效
	var round_ok: bool = md.effect_rounds.is_empty() or md.effect_rounds.has(state.round_no)
	# 回合性伤害（寒潮）
	if round_ok and md.damage_per_round > 0:
		for u in state.units(side):
			if u.data == null or u.data.kind == CardData.CardKind.QUEEN:
				continue
			var before: int = u.current_hp
			u.damage(md.damage_per_round)
			Bus.shared().emit_signal(Bus.SIG_UNIT_DAMAGED, u,
				before - u.current_hp, u.current_hp, "terrain")
			out["damaged"] += 1
	# 回合性额外回费（丰饶）
	if round_ok and md.refund_bonus > 0:
		var c0: int = state.cost(side)
		state.sides[side]["cost"] = mini(StateLib.MAX_COST, c0 + md.refund_bonus)
		var got: int = state.cost(side) - c0
		if got > 0:
			Bus.shared().emit_signal(Bus.SIG_COST_CHANGED, side, state.cost(side), got)
			out["refund"] = got
	# 地形格效果（铁锈：地形格上的单位获得力场）
	out["field_granted"] = grant_terrain_effects(state)
	return out


## 清除某单位全部效果（退场时用）
static func clear_all(inst: UnitInstance) -> void:
	if inst == null:
		return
	for e in inst.effects.duplicate():
		if e.data != null:
			Bus.shared().emit_signal(Bus.SIG_EFFECT_EXPIRED, inst, e.data)
	inst.effects.clear()
