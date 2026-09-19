class_name BattleCombat
extends RefCounted
## 战斗结算（a500「战斗系统」）
##
## 关键口径（逐条对应 a500 原文）：
##  · 主动攻击与**反击同时计算伤害**
##  · 反击对象**在射程外则反击无效**
##  · **攻击力变化优先于伤害计算**，**乘法优先于加法**，**攻击计算优先于伤害减免**
##  · 伤害在计算过程中**减少为 0 则不参与后续效果计算**
##  · **攻击/反击的计算优先于根据生命值条件发动的技能**
##  · 蜂王**免疫指令卡伤害**
##  · 护盾抵挡指令伤害（T14 人明确）

## 计算一次「攻击方 → 防守方」的基础伤害（含攻击力修正与**条件倍伤**，未扣减免）
## ⚠️ 迭代055：**条件倍伤**（卡牌自带被动）在**攻击计算阶段**生效，
##    仍遵守 a500 的「乘法优先于加法」「攻击计算优先于伤害减免」两条口径。
static func raw_damage(attacker: UnitInstance, defender: UnitInstance,
		board: Board = null) -> int:
	if attacker == null or defender == null:
		return 0
	# 攻击力已在 UnitInstance.atk() 内按「乘优先于加」算好；再乘条件倍伤
	var dmg := int(round(float(attacker.atk()) * conditional_mul(attacker, defender, board)))
	# 伤害减免（装甲/护盾等）—— 攻击计算优先于伤害减免
	var reduce := 0
	for e in defender.effects:
		if e.data != null:
			reduce += e.data.dmg_reduce
	return maxi(0, dmg - reduce)


## 条件倍伤总系数（各条被动相乘）
##  · `atk_mul_vs_queen`          目标为蜂王时生效（熊蜂 `对蜂王伤害[*2]`）
##  · `atk_mul_in_foe_territory`  攻击方处于**敌方领地**时生效（叶蜂 `[被动]`）
static func conditional_mul(attacker: UnitInstance, defender: UnitInstance,
		board: Board = null) -> float:
	if attacker == null or attacker.data == null:
		return 1.0
	var m := 1.0
	var is_queen := defender != null and defender.data != null 		and defender.data.kind == CardData.CardKind.QUEEN
	var in_foe := in_enemy_territory(attacker, board)
	for e in attacker.data.passives:
		if e == null:
			continue
		if is_queen and not is_equal_approx(e.atk_mul_vs_queen, 1.0):
			m *= e.atk_mul_vs_queen
		if in_foe and not is_equal_approx(e.atk_mul_in_foe_territory, 1.0):
			m *= e.atk_mul_in_foe_territory
	return m


## 攻击方是否处于**敌方领地**（⚠️ 沿用项目坐标约定：cell.x < 2 = 敌方领地）
static func in_enemy_territory(inst: UnitInstance, board: Board = null) -> bool:
	if inst == null:
		return false
	if board != null:
		return not board.is_own_territory(inst.cell, inst.side)
	return inst.cell.x < 2 if inst.side == 0 else inst.cell.x >= 2


## 主动攻击（含同时反击）。返回 {damage_to_defender, damage_to_attacker, counter_valid}
static func resolve_attack(attacker: UnitInstance, defender: UnitInstance,
		board: Board) -> Dictionary:
	var res := {"damage_to_defender": 0, "damage_to_attacker": 0, "counter_valid": false}
	if attacker == null or defender == null:
		return res
	# ① 双方伤害**同时计算**（先算好，再一起施加 —— 保证同归于尽成立）
	var dmg_to_def := raw_damage(attacker, defender, board)
	var counter_valid := false
	var dmg_to_atk := 0
	if defender.atk() > 0 and board != null \
			and board.manhattan(attacker.cell, defender.cell) <= defender.attack_range():
		counter_valid = true
		dmg_to_atk = raw_damage(defender, attacker, board)
	# ② 同时施加
	if dmg_to_def > 0:
		defender.damage(dmg_to_def)
	if dmg_to_atk > 0:
		attacker.damage(dmg_to_atk)
	res["damage_to_defender"] = dmg_to_def
	res["damage_to_attacker"] = dmg_to_atk
	res["counter_valid"] = counter_valid
	return res


## 指令伤害（对指定单位）
## 蜂王免疫指令伤害（a500）；护盾抵挡指令伤害（T14）
static func resolve_command_damage(target: UnitInstance, amount: int) -> int:
	if target == null or amount <= 0:
		return 0
	if target.data != null and target.data.immune_command:
		return 0
	# 护盾/力场抵挡指令伤害（T14 人明确）：有此类效果则本次指令伤害归零
	var blocked := false
	for e in target.effects:
		if e.data != null and e.data.blocks_command:
			blocked = true
			break
	if blocked:
		return 0
	target.damage(amount)
	return amount


## 预览（纯函数，不改变状态）—— 供 UI 显示预计结果
static func preview_attack(attacker: UnitInstance, defender: UnitInstance,
		board: Board) -> Dictionary:
	var res := {"defender_hp_after": 0, "attacker_hp_after": 0, "defender_dies": false,
		"attacker_dies": false, "counter_valid": false, "damage_to_defender": 0,
		"damage_to_attacker": 0}
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
	res["defender_dies"] = res["defender_hp_after"] <= 0
	res["attacker_dies"] = res["attacker_hp_after"] <= 0
	return res
