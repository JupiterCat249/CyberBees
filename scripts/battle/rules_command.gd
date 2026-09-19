class_name RulesCommand
extends RefCounted
## 指令卡规则（a500「战斗系统·攻击类型 3：指令攻击」+ 费用 4 + 特殊地形）
##
## ⚠️ **零 UI 依赖**：不 preload 任何 scenes/、不 get_node、不引用 Control/Node。
##
## 覆盖
##  · 单体指令（电击/治疗类）：对单个目标结算
##  · 链式指令（电击 / 电击III）：与目标**接触及间接接触**的单位都受相同伤害
##  · 范围指令（巡航导弹）：**效果范围内所有单位**受伤
##  · 治疗指令（治疗）：己方单位回血
##  · 蜂王**免疫指令伤害**；护盾/力场**抵挡指令伤害**（T14）
##  · X 费卡：使用费用 = 目标单位的**部署费用**，**无法对蜂王使用**

const Bus := preload("res://scripts/battle/battle_signal_bus.gd")
const StateLib := preload("res://scripts/battle/battle_state.gd")
const Combat := preload("res://scripts/battle/rules_combat.gd")


## a500 费用 4：X 费卡的"使用费用" = 目标单位的部署费用（蜂王不可为目标 → 返回 -1）
static func x_cost_of(target: UnitInstance) -> int:
	if target == null or target.data == null:
		return -1
	if target.data.kind == CardData.CardKind.QUEEN:
		return -1
	return maxi(0, target.data.cost)


## 目标是否合法（a500：X 费卡不可对蜂王使用）
static func target_legal(card: CommandData, target: UnitInstance, caster_side: int) -> bool:
	if card == null or target == null:
		return false
	if card.cost < 0 and target.data != null and target.data.kind == CardData.CardKind.QUEEN:
		return false
	if card.heal > 0:
		return target.side == caster_side          ## 治疗类作用于己方
	return target.side != caster_side              ## 伤害类作用于敌方


## 结算指令卡。返回 {"ok", "damage":[{unit, amount, blocked}], "healed":[{unit, amount}]}
static func execute(state, card: CommandData, caster_side: int, target: UnitInstance) -> Dictionary:
	var out := {"ok": false, "damage": [], "healed": []}
	if state == null or card == null or target == null:
		return out
	if state.board == null or not target_legal(card, target, caster_side):
		return out

	# ---------------- 治疗指令 ----------------
	if card.heal > 0:
		var before: int = target.current_hp
		target.heal(card.heal)
		var gained: int = target.current_hp - before
		out["healed"].append({"unit": target, "amount": gained})
		Bus.shared().emit_signal(Bus.SIG_UNIT_HEALED, target, gained, target.current_hp)
		out["ok"] = true
		return out

	# ---------------- 伤害指令 ----------------
	var amount := card.dmg
	if card.cost < 0:                              ## X 费卡：伤害 = 目标部署费 × 倍率
		var xc := x_cost_of(target)
		if xc < 0:
			return out
		amount = xc * maxi(1, card.x_cost_multiplier)
	if amount <= 0:
		return out

	var targets := collect_targets(state, card, target)
	for u in targets:
		## 传入地图数据 → 应用地形减免（迭代059 G-5：水没地形格 -2 指令伤害）
		var had_defense: bool = Combat.has_defense_effect(u)
		var real := Combat.command_damage_after_reduce(u, amount, state.map_data)
		var blocked := real < 0
		if real > 0:
			u.damage(real)
		else:
			real = 0
		## ⭐ 抵挡型效果「参与防御计算则消失」（设计原文）→ 指令伤害同样消耗
		if had_defense:
			Combat.consume_defense_effects(u)
		out["damage"].append({"unit": u, "amount": real, "blocked": blocked})
		if real > 0:
			Bus.shared().emit_signal(Bus.SIG_UNIT_DAMAGED, u, real, u.current_hp, "command")
	out["ok"] = true
	Bus.shared().emit_signal(Bus.SIG_COMMAND_RESOLVED, caster_side, card, targets,
		_total_damage(out), 0)
	return out


## 收集本次指令的作用目标（单体 / 范围 / 链式）
static func collect_targets(state, card: CommandData, primary: UnitInstance) -> Array:
	var out: Array = []
	if primary == null or state == null or state.board == null:
		return out
	# 范围（aoe_span > 0）：目标格周围曼哈顿半径内的所有单位
	if card.aoe_span > 0:
		for u in state.board.all_units():
			if state.board.manhattan(u.cell, primary.cell) <= card.aoe_span:
				out.append(u)
		return out
	# 链式（chain_span > 0）：与目标**接触及间接接触**的单位（BFS 传播）
	if card.chain_span > 0:
		var seen := {primary.cell: true}
		var frontier: Array = [primary.cell]
		var depth := 0
		out.append(primary)
		while not frontier.is_empty() and depth < card.chain_span:
			var next: Array = []
			for c in frontier:
				for n in state.board.neighbors_cardinal(c):
					if seen.has(n):
						continue
					seen[n] = true
					next.append(n)
					var u2: UnitInstance = state.board.unit_at(n)
					if u2 != null:
						out.append(u2)
			frontier = next
			depth += 1
		return out
	# 单体
	out.append(primary)
	return out


static func _total_damage(out: Dictionary) -> int:
	var s := 0
	for d in out["damage"]:
		s += int(d["amount"])
	return s
