class_name BattleEffects
extends RefCounted
## 效果结算（a500「战斗系统 · 效果」）
##
## 口径（逐条对应 a500 原文）：
##  · **相同效果最多一个**（T14）
##  · 单位类型不匹配则无法赋予效果（`EffectData.for_unit_kinds`）
##  · 单位效果作用于单位自身；**地域效果作用于目标格子上的单位**
##  · 若效果的消失与赋予在相同阶段，**先计算消失，再计算赋予**
##  · 伤害在计算过程中减少为 0 则**不参与后续效果计算**

## 回合结束/阶段切换时的效果处理：先结算消失（时长到）再处理持续伤害/回血
## 返回被移除的效果 id 列表
static func tick_effects(inst: UnitInstance) -> Array[String]:
	var removed: Array[String] = []
	if inst == null:
		return removed
	# ① 先算消失（时长递减）
	for i in range(inst.effects.size() - 1, -1, -1):
		var e := inst.effects[i]
		if e.tick():
			removed.append(e.data.id if e.data != null else "?")
			inst.effects.remove_at(i)
	# ② 再算持续效果（灼烧扣血 / 持续回血）—— 在**消失之后**
	var dot := 0
	var hot := 0
	for e in inst.effects:
		if e.data != null:
			dot += e.data.dot_per_turn
			hot += e.data.heal_per_turn
	if dot > 0:
		inst.damage(dot)
	if hot > 0:
		inst.heal(hot)
	inst.effects_changed.emit(inst)
	return removed


## 赋予效果（校验单位类型匹配；T14 不叠加）
static func grant(inst: UnitInstance, eff: EffectData) -> bool:
	if inst == null or eff == null or inst.data == null:
		return false
	if not eff.allows_kind(inst.data.kind):
		return false
	var added := inst.apply_effect(eff)
	return added


## 地域效果：作用于目标格子上的单位
static func apply_terrain(board: Board, cell: Vector2i, eff: EffectData) -> bool:
	if board == null or eff == null:
		return false
	var u := board.unit_at(cell)
	if u == null or not u.is_alive():
		return false
	return grant(u, eff)


## 相邻力场授予（力场蜂巢 / 力场炮台：相邻己方单位获得 1 层力场）
## T14：不叠加 —— 已有同名效果则不再赋
static func grant_adjacent_field(board: Board, source: UnitInstance,
		field_eff: EffectData) -> Array[UnitInstance]:
	var out: Array[UnitInstance] = []
	if board == null or source == null or field_eff == null:
		return out
	for c in board.neighbors_cardinal(source.cell):
		var u := board.unit_at(c)
		if u != null and u.side == source.side and u.is_alive():
			if inst_has(u, field_eff.id):
				continue
			if grant(u, field_eff):
				out.append(u)
	return out


## 重新计算"来源仍在场"的光环类效果（移除失效来源授予的效果）
static func refresh_auras(board: Board, field_eff: EffectData) -> void:
	if board == null or field_eff == null:
		return
	var providers: Array[UnitInstance] = []
	for u in board.all_units():
		if u.data != null and u.data.grants_aura_id == field_eff.id and u.is_alive():
			providers.append(u)
	# 先移除全部该效果（先消失），再按当前来源重新授予（后赋予）—— 符合 a500 顺序
	for u in board.all_units():
		u.remove_effect(field_eff.id)
	for p in providers:
		grant_adjacent_field(board, p, field_eff)


static func inst_has(inst: UnitInstance, effect_id: String) -> bool:
	return inst != null and inst.has_effect(effect_id)
