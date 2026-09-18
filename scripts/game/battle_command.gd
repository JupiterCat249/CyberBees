class_name BattleCommand
extends RefCounted
## 指令卡结算（a500「卡牌类型 · 指令」+「战斗系统 · 指令攻击」）
##
## 口径：
##  · 指令卡在**部署与行动阶段均可使用**，用完后退场（进墓地）
##  · **蜂王免疫指令卡伤害与减益**
##  · **X 费卡：使用费用 = 目标单位的部署费用；伤害 = 部署费 × x_cost_multiplier；不可指定蜂王**
##  · **护盾/力场抵挡指令伤害**（T14 人明确）
##  · 扩散（aoe_span）：对目标格周围的单位同样造成伤害
##  · 链式（chain_span）：向上下左右传播
##  · 目标合法性：同阵营（治疗）或敌方（伤害）由卡自身语义决定

const Combat := preload("res://scripts/game/battle_combat.gd")
const Effects := preload("res://scripts/game/battle_effects.gd")


## X 费卡的实际费用（a500：= 目标单位的部署费用）
static func x_cost_of(target: UnitInstance) -> int:
	if target == null or target.data == null:
		return 0
	return maxi(0, target.data.cost)


## 目标是否合法（含"不可指定蜂王"等限制）
static func target_legal(cmd: CommandData, caster_side: int, target: UnitInstance) -> bool:
	if cmd == null or target == null or not target.is_alive():
		return false
	if cmd.kind == CardData.CardKind.COMMAND_X:
		# a500：X 费卡不可对蜂王使用
		if target.data != null and target.data.kind == CardData.CardKind.QUEEN:
			return false
	var is_heal := cmd.heal > 0
	if is_heal:
		return target.side == caster_side        # 治疗作用于己方
	if cmd.dmg > 0:
		return target.side != caster_side        # 伤害作用于敌方
	return true                                   # 纯功能卡（回收/补给/轮换）由各自逻辑处理


## 计算对某目标的最终指令伤害（含 X 费、扩散、蜂王免疫、护盾）
static func damage_to(cmd: CommandData, target: UnitInstance) -> int:
	if cmd == null or target == null or target.data == null:
		return 0
	if target.data.immune_command:
		return 0                                  # 蜂王免疫指令伤害
	var base := cmd.dmg
	if cmd.kind == CardData.CardKind.COMMAND_X:
		base = x_cost_of(target) * maxi(1, cmd.x_cost_multiplier)
	return maxi(0, base)


## 执行指令卡（spend_x：X 费卡由调用方先扣费）
## 返回 {ok, damage_records: Array[{unit, amount}], healed: int}
static func execute(state: GameState, card: CommandData, target: UnitInstance) -> Dictionary:
	var out := {"ok": false, "damage": [], "healed": 0, "extra": ""}
	if state == null or card == null or target == null:
		return out
	# 射程校验（以"最近的己方单位/蜂王"为源；本项目指令卡为全图指定，故仅校验卡面射程 <= 自身蜂王射程外）
	if not target_legal(card, state.active, target):
		return out

	# ① 伤害类
	if card.dmg > 0 or card.kind == CardData.CardKind.COMMAND_X:
		var hit := _damage_targets(state, card, target)
		for u in hit:
			var amt := damage_to(card, u)
			if amt <= 0:
				continue
			# 护盾抵挡（T14）
			var blocked := false
			for e in u.effects:
				if e.data != null and e.data.blocks_command:
					blocked = true
					break
			var real := 0 if blocked else amt
			if real > 0:
				u.damage(real)
			out["damage"].append({"unit": u, "amount": real, "blocked": blocked})
			state.unit_damaged.emit(u, real)
			if not u.is_alive():
				state.board.remove(u)
				state.unit_removed.emit(u)
		out["ok"] = true
		return out

	# ② 治疗类
	if card.heal > 0:
		target.heal(card.heal)
		out["healed"] = card.heal
		out["ok"] = true
		state.effect_changed.emit(target)
		return out

	# ③ 功能类（回收 / 补给 / 轮换 / 蜂粮储备）：由 name 语义分派
	match card.display_name:
		"回收":
			# 射程 1 内的己方单位：回到手牌（从场上移除，卡进手牌）
			var u := target
			if u.side == state.active and state.hand[state.active].size() < GameState.HAND_MAX:
				state.board.remove(u)
				state.unit_removed.emit(u)
				state.hand[state.active].append(u.data)
				state.hand_changed.emit(state.active)
				out["extra"] = "回收 %s 入手" % u.card_name()
				out["ok"] = true
		"补给":
			state.cost[state.active] = mini(GameState.MAX_COST, state.cost[state.active] + 3)
			state.cost_changed.emit(state.active, state.cost[state.active])
			out["extra"] = "补费 +3"
			out["ok"] = true
		"轮换":
			# 抽 1 张（从牌库）
			state.draw_card(state.active, 1)
			out["extra"] = "抽 1 张"
			out["ok"] = true
		"蜂粮储备":
			state.cost[state.active] = mini(GameState.MAX_COST, state.cost[state.active] + 2)
			state.cost_changed.emit(state.active, state.cost[state.active])
			out["extra"] = "补费 +2"
			out["ok"] = true
		_:
			out["extra"] = "（该指令卡尚未实现细分效果）"
			out["ok"] = true
	# 施加类效果（burn 等）
	for e in card.apply_effects:
		if Effects.grant(target, e):
			state.effect_changed.emit(target)
	return out


## 计算伤害覆盖的目标集合（单体 / 扩散 / 链式）
static func _damage_targets(state: GameState, card: CommandData,
		primary: UnitInstance) -> Array[UnitInstance]:
	var out: Array[UnitInstance] = [primary]
	var board := state.board
	if card.aoe_span > 0:
		for u in board.all_units():
			if u == primary or not u.is_alive():
				continue
			if board.manhattan(u.cell, primary.cell) <= card.aoe_span:
				out.append(u)
	if card.chain_span > 0:
		var frontier: Array[Vector2i] = [primary.cell]
		var seen := {primary.cell: true}
		var depth := 0
		while not frontier.is_empty() and depth < card.chain_span:
			var next: Array[Vector2i] = []
			for c in frontier:
				for n in board.neighbors_cardinal(c):
					if seen.has(n):
						continue
					seen[n] = true
					next.append(n)
					var u := board.unit_at(n)
					if u != null and u.is_alive() and not out.has(u):
						out.append(u)
			frontier = next
			depth += 1
	return out
