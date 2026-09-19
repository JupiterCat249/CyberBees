extends Node
## ============================================================
## BattleCombat —— 战斗解算（攻击 / 反击 / 数值修正）
##   职责：只做"数值与结算"，不持有规则状态（状态由 BattleState 持有，经引用读写）。
##   a500 战斗系统：主动攻击与反击同时计算伤害；反击对象不在射程内则无效。
##   a500 效果机制：伤害计算乘法优先于加法，先算攻击、后算防御。
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

signal attack_resolved(aid: int, tid: int, dmg: int, counter: int, countered: bool)

## 由协调器注入
var state: Node = null


# ============================================================
# 数值修正
# ============================================================
## 最终攻击力：攻击力变化（乘法优先于加法）→ 地形加成
func final_atk(id: int) -> int:
	if state == null or not state.units.has(id):
		return 0
	var u: Dictionary = state.units[id]
	var base := int(u["card"].get("atk", 0))
	var add := 0
	var mult := 1.0
	for k in u["effects"]:
		add += int(u["effects"][k].get("atk_add", 0))
		mult *= float(u["effects"][k].get("atk_mult", 1.0))
	var c: Vector2i = u["cell"]
	if state.terrain.has(c):
		add += int(state.terrain[c]["atk_add"])
	return int(round(float(base + add) * mult))


## 最终移动速度（含效果与地形修正）
func final_spd(id: int) -> int:
	if state == null or not state.units.has(id):
		return 0
	var u: Dictionary = state.units[id]
	var s := int(u["card"].get("spd", 0))
	var add := 0
	var mult := 1.0
	# 此前遗漏了效果遍历 ->【疾行】等 spd_add 效果在计算上不生效（与 atk 同构，本处补齐）
	for k in u["effects"]:
		add += int(u["effects"][k].get("spd_add", 0))
		mult *= float(u["effects"][k].get("spd_mult", 1.0))
	var c: Vector2i = u["cell"]
	if state.terrain.has(c):
		add += int(state.terrain[c]["spd_add"])
	return maxi(0, int(round(float(s + add) * mult)))


## 射程（来自卡牌属性；效果可覆盖：range_add 加法 + range_mult 乘法）
func final_range(id: int) -> int:
	if state == null or not state.units.has(id):
		return 0
	var u: Dictionary = state.units[id]
	var r := int(u["card"].get("range", 0))
	var add := 0
	var mult := 1.0
	for k in u["effects"]:
		add += int(u["effects"][k].get("range_add", 0))
		mult *= float(u["effects"][k].get("range_mult", 1.0))
	return maxi(0, int(round(float(r + add) * mult)))


## 最大生命值（基础 hp + 效果 hp_add）—— 治疗封顶 / 显示 / 胜负比较统一走这里
## 此前这几处直接取卡牌基础 hp，导致「提升最大生命」类效果无法生效
func final_hp_max(id: int) -> int:
	if state == null or not state.units.has(id):
		return 0
	var u: Dictionary = state.units[id]
	var base := int(u["card"].get("hp", 0))
	var add := 0
	for k in u["effects"]:
		add += int(u["effects"][k].get("hp_add", 0))
	return maxi(1, base + add)


## 伤害减免合计（护甲/力场/拦截等）
func final_reduce(id: int) -> int:
	return reduce_for_damage(id, true)


## 迭代016：按 A5 效果图鉴计算的减伤 —— 装甲(reduce) + 力场(ff_reduce，仅对**非指令**伤害生效)
##   `is_command=false` 时（指令伤害）不计入力场，符合「力场：每层减少 2 点非指令伤害」
##   拦截（intercept）按 A5 是"减少指令伤害"，本轮**数据未落地**，故暂不参与
func reduce_for_damage(id: int, is_attack: bool) -> int:
	if state == null or not state.units.has(id):
		return 0
	var r := 0
	for k in state.units[id]["effects"]:
		var e: Dictionary = state.units[id]["effects"][k]
		r += int(e.get("reduce", 0))
		if is_attack:
			r += int(e.get("ff_reduce", 0))
	return r


## 迭代017（G-35）：某单位身上「灼烧」产生的**追加指令伤害**（每层 2 点，A5 效果图鉴）
##   触发时机：该单位**受到攻击时**（主动攻击或指令伤害）
func burn_extra_damage(id: int) -> int:
	if state == null or not state.units.has(id):
		return 0
	var e: Dictionary = state.units[id]["effects"].get("burn", {})
	if e.is_empty():
		return 0
	if e.has("burn_dmg"):
		return int(e["burn_dmg"])
	return EFFECT_BURN_FALLBACK_BASE * maxi(1, int(e.get("layers", 1)))


const EFFECT_BURN_FALLBACK_BASE := 2   ## 旧数据（只有 dot 字段）的兜底每层伤害


## 该单位当前是否有「护盾」（抵挡一次攻击；层数 = layers）
func shield_layers(id: int) -> int:
	if state == null or not state.units.has(id):
		return 0
	if state.units[id]["effects"].has("shield"):
		return maxi(1, int(state.units[id]["effects"]["shield"].get("layers", 1)))
	return 0


## 参与防御计算后消耗「护盾 / 装甲」（A5：两者都是"抵挡一次，参与防御计算则消失"）
func consume_defense_effects(id: int) -> void:
	if state == null or not state.units.has(id):
		return
	for k in ["shield", "armor"]:
		if state.units[id]["effects"].has(k):
			state.units[id]["effects"].erase(k)
			state.push_log("%s 的「%s」参与防御后消失" % [state.unit_name(id), D.EFFECT_DEFS[k]["name"]])


# ============================================================
# 攻击结算
# ============================================================
## 迭代014（IDEA-012）：**纯函数**伤害预估 —— 不改任何状态，口径与 attack() **完全一致**（单一来源）
## 返回：{ok, dmg, counter, countered, target_hp_now, target_hp_after, attacker_hp_now, attacker_hp_after}
##   · dmg            = 主动攻击伤害
##   · countered      = 守方是否反击（条件：守方 atk > 0 且攻方在其射程内 —— **不要求守方存活**）
##   · counter        = 反击伤害
##   · target_hp_after / attacker_hp_after = 结算后双方剩余血量（下限 0）
## ⚠️ attack() 与本函数必须共用同一套公式，避免"预览与实战不符"（迭代013 发现过此漂移风险）。
func preview_damage(aid: int, tid: int) -> Dictionary:
	var res := {"ok": false, "dmg": 0, "counter": 0, "countered": false, "blocked": false,
		"target_hp_now": 0, "target_hp_after": 0, "attacker_hp_now": 0, "attacker_hp_after": 0,
		"coverage": []}
	if state == null or not state.units.has(aid) or not state.units.has(tid):
		return res
	var units: Dictionary = state.units
	# 迭代016：力场只减**非指令**伤害；主动攻击属非指令 → is_attack = true
	var dmg := maxi(0, final_atk(aid) - reduce_for_damage(tid, true))
	# 护盾：抵挡一次攻击 → 预览显示"本次伤害 0、血量不变、护盾会被消耗"
	var blocked := false
	if dmg > 0 and shield_layers(tid) > 0:
		blocked = true
		dmg = 0
	var cdmg := 0
	var in_range := _in_range_of(units[aid]["cell"], units[tid]["cell"], final_range(tid))
	if final_atk(tid) > 0 and in_range:
		cdmg = maxi(0, final_atk(tid) - reduce_for_damage(aid, true))
	res["ok"] = true
	res["dmg"] = dmg
	res["counter"] = cdmg
	res["countered"] = cdmg > 0 or (final_atk(tid) > 0 and in_range)
	res["target_hp_now"] = int(units[tid]["hp"])
	res["target_hp_after"] = maxi(0, int(units[tid]["hp"]) - dmg)
	res["attacker_hp_now"] = int(units[aid]["hp"])
	# 攻方剩余血量：反击按"同时结算"照扣（即使守方被一击打死）
	res["attacker_hp_after"] = maxi(0, int(units[aid]["hp"]) - cdmg)
	res["blocked"] = blocked
	# 迭代017（G-35）：预览把「灼烧追加指令伤害」也计入（与实战同源）
	var burn_v: int = burn_extra_damage(tid)
	if burn_v > 0:
		var bd: int = maxi(0, burn_v - reduce_for_damage(tid, false))
		if bd > 0 and shield_layers(tid) > 0:
			bd = 0
		if bd > 0:
			res["burn_dmg"] = bd
			res["target_hp_after"] = maxi(0, int(res["target_hp_after"]) - bd)
	# 迭代014（IDEA-012）：**伤害覆盖格** —— 普攻只覆盖目标格；攻击者技能带溅射时按曼哈顿半径展开
	#   口径与 battle_skills 的 `targets.mode=cell + splash` 一致（战斗系统按射程/范围结算）
	var cell: Vector2i = units[tid]["cell"]
	var splash := attack_splash(aid)
	var cov: Array = []
	for r in D.ROWS:
		for c in D.COLS:
			var p := Vector2i(r, c)
			if absi(p.x - cell.x) + absi(p.y - cell.y) <= splash:
				cov.append(p)
	res["coverage"] = cov
	return res


## 迭代016③（修迭代014 遗留）：**指令卡伤害预估**（纯函数）—— 与 battle_skills.apply_effect 的实伤口径一致
##   管线：基础值（或用「目标部署费×2」）→ 按 reduce_for_damage(false) 减伤（**力场不计入指令伤害**）
##        → 若仍有伤害且目标有护盾 → 本次归 0（护盾抵挡）
##   `skill_name` 为指令卡对应的技能名；返回 {ok, dmg, blocked, cells, target_id, hp_now, hp_after}
func preview_command(skill_name: String, cell: Vector2i) -> Dictionary:
	var res := {"ok": false, "dmg": 0, "blocked": false, "cells": [], "target_id": -1, "hp_now": 0, "hp_after": 0}
	if state == null or not D.in_map(cell):
		return res
	var def: Dictionary = D.skill(skill_name)
	if def.is_empty():
		return res
	var tg: Dictionary = def.get("targets", {})
	var v := 0
	var by_cost := false
	for e in (def.get("effects", []) as Array):
		if str(e.get("type", "")) == "damage":
			v = int(e.get("value", 0))
			by_cost = bool(e.get("by_target_cost", false))
			break
	# 覆盖格：cell 模式按 splash 半径；chain 模式 = 目标格 + 上下左右
	var cells: Array = []
	if str(tg.get("mode", "")) == "cell":
		var sp := int(tg.get("splash", 0))
		for r in D.ROWS:
			for c in D.COLS:
				var p := Vector2i(r, c)
				if absi(p.x - cell.x) + absi(p.y - cell.y) <= sp:
					cells.append(p)
	else:
		cells.append(cell)
		if bool(tg.get("chain", false)):
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nc := Vector2i(cell.x + d.x, cell.y + d.y)
				if D.in_map(nc):
					cells.append(nc)
	res["cells"] = cells
	var tid: int = state.unit_at(cell)
	if tid < 0:
		res["ok"] = true      # 地格类指令可对空格使用（无单位目标）
		return res
	if str(state.units[tid]["card"]["kind"]) == "queen":
		res["ok"] = true      # 蜂王免疫指令卡伤害与减益
		res["target_id"] = tid
		res["hp_now"] = int(state.units[tid]["hp"])
		res["hp_after"] = int(state.units[tid]["hp"])
		return res
	var dmg := v
	if by_cost:
		dmg = int(state.units[tid]["card"]["cost"]) * 2
	dmg = maxi(0, dmg - reduce_for_damage(tid, false))
	var blocked := false
	if dmg > 0 and shield_layers(tid) > 0:
		blocked = true
		dmg = 0
	res["ok"] = true
	res["dmg"] = dmg
	res["blocked"] = blocked
	res["target_id"] = tid
	res["hp_now"] = int(state.units[tid]["hp"])
	res["hp_after"] = maxi(0, int(state.units[tid]["hp"]) - dmg)
	return res


## 攻击者的溅射半径（来自其卡牌的技能 targets.splash；无技能/无溅射 = 0）
func attack_splash(id: int) -> int:
	if state == null or not state.units.has(id):
		return 0
	var nm := str(state.units[id]["card"].get("name", ""))
	var sk: Dictionary = D.skill(nm)
	var tg: Dictionary = sk.get("targets", {})
	if str(tg.get("mode", "")) != "cell":
		return 0
	return int(tg.get("splash", 0))


## 曼哈顿距离是否在射程内（预览与结算共用）
func _in_range_of(from: Vector2i, to: Vector2i, rng: int) -> bool:
	return absi(to.x - from.x) + absi(to.y - from.y) <= rng


## 主动攻击 + 反击。返回 {dmg, counter, countered}
## 结算顺序（a500 战斗系统 1：「主动攻击与反击**同时计算**伤害」+ 迭代005.1 人明确）：
##   ① 先算**反击**并即刻扣攻方血（此时守方尚未掉血）
##   ② 再结算主伤害
## → 因此**目标即使被直接打死，其反击依然成立并造成伤害**（此前用「守方 hp>0」作反击前置条件，
##   导致一击致死的目标无法反击 ✗，已修正）。
## 反击条件（a500 战斗系统 2）：守方攻击力 > 0 且攻击方在其射程内。
## 迭代014：伤害与反击**改用 preview_damage() 的统一公式**（预览与实战同源）。
func attack(aid: int, tid: int) -> Dictionary:
	var res := {"dmg": 0, "counter": 0, "countered": false}
	if state == null:
		return res
	if not state.units.has(aid) or not state.units.has(tid):
		return res
	var pv: Dictionary = preview_damage(aid, tid)
	if not bool(pv["ok"]):
		return res
	var units: Dictionary = state.units
	var dmg: int = int(pv["dmg"])
	var cdmg: int = int(pv["counter"])
	if bool(pv["countered"]):
		units[aid]["hp"] = int(units[aid]["hp"]) - cdmg
		res["counter"] = cdmg
		res["countered"] = true
	units[tid]["hp"] = int(units[tid]["hp"]) - dmg
	res["dmg"] = dmg
	res["blocked"] = bool(pv.get("blocked", false))
	# 迭代017（G-35）：**灼烧在受攻击时追加指令伤害**（A5：每层 2 点；经减伤、可被护盾抵挡）
	var burn_v: int = burn_extra_damage(tid)
	if burn_v > 0:
		var bd: int = maxi(0, burn_v - reduce_for_damage(tid, false))
		if bd > 0 and shield_layers(tid) > 0:
			bd = 0
			res["burn_blocked"] = true
		if bd > 0:
			units[tid]["hp"] = int(units[tid]["hp"]) - bd
			res["burn_dmg"] = bd
			state.push_log("%s 受灼烧追加指令伤害 -%d" % [state.unit_name(tid), bd])
	# 迭代016：护盾/装甲"参与防御计算后消失"（护盾抵挡成功时也消耗）
	consume_defense_effects(tid)
	# 日志保持「攻击 → 反击」的阅读顺序（数值结算顺序与之无关）
	state.push_log("%s 攻击 %s：%d" % [state.unit_name(aid), state.unit_name(tid), dmg])
	if bool(res["countered"]):
		state.push_log("%s 反击：%d" % [state.unit_name(tid), cdmg])
	attack_resolved.emit(aid, tid, int(res["dmg"]), int(res["counter"]), bool(res["countered"]))
	return res
