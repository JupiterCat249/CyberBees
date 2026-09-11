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
	if state == null or not state.units.has(id):
		return 0
	var r := 0
	for k in state.units[id]["effects"]:
		r += int(state.units[id]["effects"][k].get("reduce", 0))
	return r


# ============================================================
# 攻击结算
# ============================================================
## 主动攻击 + 反击。返回 {dmg, counter, countered}
func attack(aid: int, tid: int) -> Dictionary:
	var res := {"dmg": 0, "counter": 0, "countered": false}
	if state == null:
		return res
	if not state.units.has(aid) or not state.units.has(tid):
		return res
	var units: Dictionary = state.units
	var dmg := maxi(0, final_atk(aid) - final_reduce(tid))
	units[tid]["hp"] = int(units[tid]["hp"]) - dmg
	res["dmg"] = dmg
	state.push_log("%s 攻击 %s：%d" % [state.unit_name(aid), state.unit_name(tid), dmg])
	# 反击：攻击方存活且反击方射程覆盖对方才触发
	var ac: Vector2i = units[aid]["cell"]
	var tc: Vector2i = units[tid]["cell"]
	if int(units[tid]["hp"]) > 0 and abs(tc.x - ac.x) + abs(tc.y - ac.y) <= final_range(tid):
		var cdmg := maxi(0, final_atk(tid) - final_reduce(aid))
		units[aid]["hp"] = int(units[aid]["hp"]) - cdmg
		res["counter"] = cdmg
		res["countered"] = true
		state.push_log("%s 反击：%d" % [state.unit_name(tid), cdmg])
	attack_resolved.emit(aid, tid, int(res["dmg"]), int(res["counter"]), bool(res["countered"]))
	return res
