class_name RulesEffects
extends RefCounted
## 效果规则（a500「战斗系统·效果」1~7）
##
## ⚠️ **零 UI 依赖**：本文件不 preload 任何 scenes/、不 get_node、不引用 Control/Node。
## 只接受 BattleState + UnitInstance，通过 BattleSignalBus 广播结果。

## ⚠️ 信号总线在 project.godot 注册为 Autoload（运行时全局名 `BattleSignalBus` 可用）；
##    但 `--check-only` 模式下 **autoload 全局名不参与编译** → 这里显式 preload 一份类型引用，
##    两种模式都能解析，且不依赖加载顺序。（引的是同层规则文件与总线，**不引任何 UI**）
const Bus := preload("res://scripts/battle/battle_signal_bus.gd")
const StateLib := preload("res://scripts/battle/battle_state.gd")

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
	# 先收集要移除的，再移除（避免遍历中改集合）
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
##   3：单位效果作用于自身（本函数）；地域效果由 apply_terrain() 处理
static func grant(inst: UnitInstance, eff: EffectData) -> bool:
	if inst == null or eff == null or inst.data == null:
		return false
	# 类型匹配（a500 效果 2）
	if not eff.allows_kind(inst.data.kind):
		return false
	# 相同效果最多一个（a500 效果 1 / T14）：刷新时长，不再加一层
	for e in inst.effects:
		if e.data != null and e.data.id == eff.id:
			e.turns = eff.duration
			Bus.shared().emit_signal(Bus.SIG_UNIT_STATS, inst)
			return false
	if inst.apply_effect(eff):
		Bus.shared().emit_signal(Bus.SIG_EFFECT_GRANTED, inst, eff, "unit")
		Bus.shared().emit_signal(Bus.SIG_UNIT_STATS, inst)
		return true
	return false


## 地域效果（a500 效果 3：地域效果作用于**目标格子上的单位**）
static func apply_terrain(state, cell: Vector2i, eff: EffectData) -> bool:
	if state == null or state.board == null or eff == null:
		return false
	var inst: UnitInstance = state.board.unit_at(cell)
	if inst == null:
		return false
	return grant(inst, eff)


## 场地阶段：按地图数据结算（a500 特殊地形 + 项目 6 张地图）
## map_data.damage_per_round / refund_bonus / grant_field_on_terrain / effect_rounds
static func resolve_terrain_phase(state, side: int) -> Dictionary:
	var out := {"damaged": 0, "field_granted": 0}
	if state == null or state.map_data == null:
		return out
	var md: MapData = state.map_data
	if not md.effect_rounds.is_empty() and not md.effect_rounds.has(state.round_no):
		return out
	# 回合性伤害（寒潮：第 3/6/9/12 回合 -2 生命，蜂王除外）
	if md.damage_per_round > 0:
		for u in state.units(side):
			if u.data == null or u.data.kind == CardData.CardKind.QUEEN:
				continue
			var before: int = u.current_hp
			u.damage(md.damage_per_round)
			Bus.shared().emit_signal(Bus.SIG_UNIT_DAMAGED, u, before - u.current_hp, u.current_hp, "terrain")
			out["damaged"] += 1
	return out


## 清除某单位全部效果（退场时用）
static func clear_all(inst: UnitInstance) -> void:
	if inst == null:
		return
	for e in inst.effects.duplicate():
		if e.data != null:
			Bus.shared().emit_signal(Bus.SIG_EFFECT_EXPIRED, inst, e.data)
	inst.effects.clear()
