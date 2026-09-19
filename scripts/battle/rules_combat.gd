class_name RulesCombat
extends RefCounted
## 战斗规则（a500「战斗系统」攻击类型 1~3 + 效果 5~7 + 范围 1~3）
##
## ⚠️ **零 UI 依赖**：不 preload 任何 scenes/、不 get_node、不引用 Control/Node。
##
## 关键口径（逐条对应 a500 原文）
##  · 主动攻击与**反击同时计算伤害**（先算完双方，再一并施加 → 同归于尽成立）
##  · 反击对象**在射程外则反击无效**
##  · **攻击力变化优先于伤害计算**；**乘法优先于加法**；**攻击计算优先于伤害减免**
##  · 伤害在计算过程中**减少为 0 则不参与后续效果计算**
##  · 攻击/反击的计算**优先于**根据生命值条件发动的技能
##  · **攻击不会被单位阻挡**；**移动会被单位阻挡**

const Bus := preload("res://scripts/battle/battle_signal_bus.gd")
const StateLib := preload("res://scripts/battle/battle_state.gd")


## 攻击力修正后的伤害（含条件倍伤），再扣伤害减免 —— 减免只在此处算一次
static func raw_damage(attacker: UnitInstance, defender: UnitInstance, board: Board) -> int:
	if attacker == null or defender == null:
		return 0
	var dmg := int(round(float(attacker.atk()) * conditional_mul(attacker, defender, board)))
	var reduce := 0
	for e in defender.effects:
		if e.data != null:
			reduce += e.data.dmg_reduce
	return maxi(0, dmg - reduce)


## 条件倍伤（卡牌自带被动）：对蜂王 / 在敌方领地
static func conditional_mul(attacker: UnitInstance, defender: UnitInstance, board: Board) -> float:
	if attacker == null or attacker.data == null:
		return 1.0
	var m := 1.0
	var is_queen: bool = defender != null and defender.data != null \
		and defender.data.kind == CardData.CardKind.QUEEN
	var in_foe := in_enemy_territory(attacker, board)
	for e in attacker.data.passives:
		if e == null:
			continue
		if is_queen and not is_equal_approx(e.atk_mul_vs_queen, 1.0):
			m *= e.atk_mul_vs_queen
		if in_foe and not is_equal_approx(e.atk_mul_in_foe_territory, 1.0):
			m *= e.atk_mul_in_foe_territory
	return m


## 是否处于敌方领地（⚠️ 沿用项目坐标约定：cell.x < 2 = 敌方领地）
static func in_enemy_territory(inst: UnitInstance, board: Board) -> bool:
	if inst == null:
		return false
	if board != null:
		return not board.is_own_territory(inst.cell, inst.side)
	return inst.cell.x < 2 if inst.side == 0 else inst.cell.x >= 2


## 主动攻击 + 反击**同时结算**（a500 战斗 1~2）
## 返回 {"damage_to_defender", "damage_to_attacker", "counter_valid"}
static func resolve_attack(attacker: UnitInstance, defender: UnitInstance,
		board: Board) -> Dictionary:
	var res := {"damage_to_defender": 0, "damage_to_attacker": 0, "counter_valid": false}
	if attacker == null or defender == null:
		return res
	# ① 先算完双方（同时计算）
	var dmg_to_def := raw_damage(attacker, defender, board)
	var counter_valid := false
	var dmg_to_atk := 0
	# 反击条件：有攻击力 + 攻击方在反击者射程内（范围 2：距离用曼哈顿，攻击不被阻挡）
	if defender.atk() > 0 and board != null \
			and board.manhattan(attacker.cell, defender.cell) <= defender.attack_range():
		counter_valid = true
		dmg_to_atk = raw_damage(defender, attacker, board)
	# ② 一并施加
	if dmg_to_def > 0:
		defender.damage(dmg_to_def)
	if dmg_to_atk > 0:
		attacker.damage(dmg_to_atk)
	res["damage_to_defender"] = dmg_to_def
	res["damage_to_attacker"] = dmg_to_atk
	res["counter_valid"] = counter_valid
	# ③ 广播（信号带全部参数 → 视图无需反查）
	Bus.shared().emit_signal(Bus.SIG_ATTACK_RESOLVED, attacker, defender,
		dmg_to_def, dmg_to_atk, counter_valid)
	if dmg_to_def > 0:
		Bus.shared().emit_signal(Bus.SIG_UNIT_DAMAGED, defender, dmg_to_def,
			defender.current_hp, "attack")
	if dmg_to_atk > 0:
		Bus.shared().emit_signal(Bus.SIG_UNIT_DAMAGED, attacker, dmg_to_atk,
			attacker.current_hp, "counter")
	return res


## 指令伤害的最终数值（a500 效果 6 + 蜂王免疫 + 护盾抵挡）
## 返回 -1 = 完全不可造成伤害（免疫 / 被抵挡）
static func command_damage_after_reduce(target: UnitInstance, amount: int) -> int:
	if target == null or amount <= 0:
		return -1
	if target.data != null and target.data.immune_command:
		return -1
	for e in target.effects:
		if e.data != null and e.data.blocks_command:
			return -1
	var reduce := 0
	for e in target.effects:
		if e.data != null:
			reduce += e.data.dmg_reduce
	return maxi(0, amount - reduce)


## 预览（纯函数，不改状态；供 UI 显示预计结果）
static func preview_attack(attacker: UnitInstance, defender: UnitInstance,
		board: Board) -> Dictionary:
	var res := {"damage_to_defender": 0, "damage_to_attacker": 0, "counter_valid": false,
		"defender_hp_after": 0, "attacker_hp_after": 0}
	if attacker == null or defender == null:
		return res
	var d2 := raw_damage(attacker, defender, board)
	var counter_valid := false
	var d2a := 0
	if defender.atk() > 0 and board != null \
			and board.manhattan(attacker.cell, defender.cell) <= defender.attack_range():
		counter_valid = true
		d2a = raw_damage(defender, attacker, board)
	res["damage_to_defender"] = d2
	res["damage_to_attacker"] = d2a
	res["counter_valid"] = counter_valid
	res["defender_hp_after"] = maxi(0, defender.current_hp - d2)
	res["attacker_hp_after"] = maxi(0, attacker.current_hp - d2a)
	return res
