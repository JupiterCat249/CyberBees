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
## 迭代014（IDEA-012）：**纯函数**伤害预估 —— 不改任何状态，口径与 attack() **完全一致**（单一来源）
## 返回：{ok, dmg, counter, countered, target_hp_now, target_hp_after, attacker_hp_now, attacker_hp_after}
##   · dmg            = 主动攻击伤害
##   · countered      = 守方是否反击（条件：守方 atk > 0 且攻方在其射程内 —— **不要求守方存活**）
##   · counter        = 反击伤害
##   · target_hp_after / attacker_hp_after = 结算后双方剩余血量（下限 0）
## ⚠️ attack() 与本函数必须共用同一套公式，避免"预览与实战不符"（迭代013 发现过此漂移风险）。
func preview_damage(aid: int, tid: int) -> Dictionary:
	var res := {"ok": false, "dmg": 0, "counter": 0, "countered": false,
		"target_hp_now": 0, "target_hp_after": 0, "attacker_hp_now": 0, "attacker_hp_after": 0,
		"coverage": []}
	if state == null or not state.units.has(aid) or not state.units.has(tid):
		return res
	var units: Dictionary = state.units
	var dmg := maxi(0, final_atk(aid) - final_reduce(tid))
	var cdmg := 0
	var in_range := _in_range_of(units[aid]["cell"], units[tid]["cell"], final_range(tid))
	if final_atk(tid) > 0 and in_range:
		cdmg = maxi(0, final_atk(tid) - final_reduce(aid))
	res["ok"] = true
	res["dmg"] = dmg
	res["counter"] = cdmg
	res["countered"] = cdmg > 0 or (final_atk(tid) > 0 and in_range)
	res["target_hp_now"] = int(units[tid]["hp"])
	res["target_hp_after"] = maxi(0, int(units[tid]["hp"]) - dmg)
	res["attacker_hp_now"] = int(units[aid]["hp"])
	# 攻方剩余血量：反击按"同时结算"照扣（即使守方被一击打死）
	res["attacker_hp_after"] = maxi(0, int(units[aid]["hp"]) - cdmg)
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
	# 日志保持「攻击 → 反击」的阅读顺序（数值结算顺序与之无关）
	state.push_log("%s 攻击 %s：%d" % [state.unit_name(aid), state.unit_name(tid), dmg])
	if bool(res["countered"]):
		state.push_log("%s 反击：%d" % [state.unit_name(tid), cdmg])
	attack_resolved.emit(aid, tid, int(res["dmg"]), int(res["counter"]), bool(res["countered"]))
	return res
