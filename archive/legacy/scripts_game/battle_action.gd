class_name BattleAction
extends RefCounted
## 单位行动处理（a500「行动机会」）
##
## 口径（逐条对应 a500 原文）：
##  · 单位行动**只能在行动阶段**进行
##  · 每个单位每回合**有一次行动机会**，己方回费阶段重置
##  · 单位**部署时没有行动机会**（部署时即已标记 has_moved/has_acted）
##  · 行动 = **1 次移动** + **1 次[主动攻击]或[支援技能]**；使用攻击/支援后**自动结束行动**
##  · 行动中没有移动速度无法移动；没有攻击力无法主动攻击；技能无支援条件无法使用支援技能
##  · **单位行动顺序不限**，行动结束前也可以操作其他单位

const Combat := preload("res://scripts/game/battle_combat.gd")
const Effects := preload("res://scripts/game/battle_effects.gd")

## 供外部（GameState）注入：本类不持有状态，只按传入的 state 执行
static func can_move(state: GameState, inst: UnitInstance) -> bool:
	if state == null or inst == null:
		return false
	if state.phase != GameState.Phase.ACTION:
		return false
	if inst.side != state.active or not inst.is_alive():
		return false
	if inst.has_moved or inst.has_acted:
		return false
	return inst.move_range() > 0          # a500：没有移动速度无法移动


static func can_attack(state: GameState, inst: UnitInstance) -> bool:
	if state == null or inst == null:
		return false
	if state.phase != GameState.Phase.ACTION:
		return false
	if inst.side != state.active or not inst.is_alive():
		return false
	if inst.has_acted:
		return false
	return inst.atk() > 0 and inst.attack_range() > 0   # a500：没有攻击力/射程无法主动攻击


static func can_support(state: GameState, inst: UnitInstance) -> bool:
	if state == null or inst == null:
		return false
	if state.phase != GameState.Phase.ACTION:
		return false
	if inst.side != state.active or not inst.is_alive():
		return false
	if inst.has_acted:
		return false
	return _has_support(inst)             # a500：技能没有支援条件无法使用支援技能


static func _has_support(inst: UnitInstance) -> bool:
	if inst.data == null:
		return false
	for s in inst.data.skills:
		if s != null and s.kind == SkillData.Kind.SUPPORT:
			return true
	return false


## 移动一次
static func move(state: GameState, inst: UnitInstance, to: Vector2i) -> bool:
	if not can_move(state, inst):
		return false
	var cells := state.board.move_range(inst)
	if not cells.has(to):
		return false
	if not state.board.move_unit(inst, to):
		return false
	inst.mark_moved()
	state.unit_moved.emit(inst)
	state.log_added.emit("%s 移动到 (%d,%d)" % [inst.card_name(), to.x, to.y])
	state.state_changed.emit()
	return true


## 主动攻击（含同时反击；使用后**自动结束该单位行动**）
static func attack(state: GameState, inst: UnitInstance, target: UnitInstance) -> bool:
	if not can_attack(state, inst):
		return false
	if target == null or target.side == inst.side or not target.is_alive():
		return false
	if state.board.manhattan(inst.cell, target.cell) > inst.attack_range():
		return false
	var res := Combat.resolve_attack(inst, target, state.board)
	inst.mark_acted()                     # a500：使用主动攻击后自动结束行动
	state.unit_damaged.emit(target, res["damage_to_defender"])
	if res["damage_to_attacker"] > 0:
		state.unit_damaged.emit(inst, res["damage_to_attacker"])
	state.log_added.emit("%s 攻击 %s：造成 %d；%s反击 %d" % [
		inst.card_name(), target.card_name(), res["damage_to_defender"],
		"有效" if res["counter_valid"] else "无效（射程外）", res["damage_to_attacker"]])
	_cleanup_and_check(state, [target, inst])
	state.state_changed.emit()
	return true


## 使用支援技能（使用后自动结束行动）
static func support(state: GameState, inst: UnitInstance, skill: SkillData,
		target: UnitInstance) -> bool:
	if not can_support(state, inst) or skill == null:
		return false
	if skill.kind != SkillData.Kind.SUPPORT:
		return false
	if target == null or not target.is_alive():
		return false
	if target.side != inst.side:          # 支援技能作用于己方
		return false
	if state.board.manhattan(inst.cell, target.cell) > skill.target_range:
		return false
	var applied := 0
	for e in skill.effects:
		if Effects.grant(target, e):
			applied += 1
	# 迭代055：**支援回费**（熊蜂 `[支援]回复[3]点费用`）—— 给施放者一方加费
	var refunded := 0
	if skill.refund > 0:
		var st: GameState = state
		var before: int = int(st.cost[inst.side])
		st.cost[inst.side] = mini(st.MAX_COST, before + skill.refund)
		refunded = int(st.cost[inst.side]) - before
		st.cost_changed.emit(inst.side, st.cost[inst.side])
	# 迭代055：**支援治疗**（支持 heal 字段的技能）
	var healed := 0
	if skill.heal > 0:
		var hp_before: int = target.current_hp
		target.heal(skill.heal)                 ## heal() 内部直接改血（返回 void）
		healed = target.current_hp - hp_before
	inst.mark_acted()
	state.effect_changed.emit(target)
	var extra := ""
	if refunded > 0:
		extra += "，回费 +%d" % refunded
	if healed > 0:
		extra += "，回血 +%d" % healed
	state.log_added.emit("%s 对 %s 使用【支援】%s（生效 %d 个效果%s）" % [
		inst.card_name(), target.card_name(), skill.display_name, applied, extra])
	state.state_changed.emit()
	return true


## 场地阶段后：按 a500「先消失，后赋予」处理全部单位的效果时长
static func tick_all_effects(state: GameState) -> void:
	if state == null:
		return
	for u in state.board.all_units():
		var removed := Effects.tick_effects(u)
		if not removed.is_empty():
			state.effect_changed.emit(u)
		if not u.is_alive():
			state.log_added.emit("%s 因持续伤害退场" % u.card_name())
	_cleanup_and_check(state, state.board.all_units())


## 移除已退场单位 + 胜负判定
static func _cleanup_and_check(state: GameState, touched: Array) -> void:
	for u in touched:
		var inst: UnitInstance = u
		if inst == null or inst.is_alive():
			continue
		state.board.remove(inst)
		state.unit_removed.emit(inst)
		state.log_added.emit("%s 退场" % inst.card_name())
	state.check_victory()
