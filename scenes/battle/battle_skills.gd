extends RefCounted
## ============================================================
## BattleSkills —— 结构化技能系统（依据《电子蜂A5策划案/技能结构.md》）
##
## 结算管线： [技能源] → [条件[] AND/OR/NOT] → [倍率值] → [生效对象[]] → [效果[]]
##           最终效果Int值 = 效果基础Int值 × 倍率值
##
## 术语基准：a500 为最高规则标准（T10）
##   技能源   ：指令（a500 卡牌类型）/ 支援（a500 行动机会 4）/ 被动
##   条件维度 ：玩家费用 · 手牌状态 · 回合信息 · 单位操作 · 单位数值 · 单位定位 · 单位行动
##   生效对象 ：仅自身 · 任意单体(类型+距离) · 任意地格(溅射) · 链式传播
##   效果类别 ：伤害 · 增益减益 · 资源 · 部署 · 回收 · 位移 · 手牌
##
## 效果机制遵循 a500 战斗系统·效果：
##   ①相同效果最多一个 ②类型不匹配不赋予 ③单位效果作用于自身/地域效果作用于格子上的单位
##   ④同阶段先结算消失再结算赋予 ⑤伤害归零不参与后续 ⑥乘法优先于加法、攻击计算优先于伤害减免
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

## 技能源（技能结构.md 二·1）
const SRC_COMMAND := "command"    ## 使用指令卡
const SRC_SUPPORT := "support"    ## 支援技能
const SRC_PASSIVE := "passive"    ## 被动技能

## 条件维度（技能结构.md 二·2）
const COND_COST := "cost"         ## 玩家费用 / 费用变化
const COND_HAND := "hand"         ## 手牌内容 / 手牌轮换
const COND_ROUND := "round"       ## 回合数 / 回合阶段
const COND_UNIT_OP := "unit_op"   ## 部署 / 退场
const COND_UNIT_VALUE := "unit_value"  ## 数值 / buff
const COND_UNIT_POS := "unit_pos" ## 是否在场 / 坐标
const COND_UNIT_ACT := "unit_act" ## 战斗交互 / 移动 / 支援

## 效果类别（技能结构.md 二·4）
const EFF_DAMAGE := "damage"      ## 伤害类
const EFF_MODIFY := "modify"      ## 增益/减益类
const EFF_RESOURCE := "resource"  ## 资源类（费用）
const EFF_DEPLOY := "deploy"      ## 部署类（机场：部署范围被动）
const EFF_RECYCLE := "recycle"    ## 回收类（单位退场）
const EFF_MOVE := "move"          ## 位移类
const EFF_HAND := "hand"          ## 手牌类（轮换 / 换牌机会）

## 由协调器注入
var state: Node = null


# ============================================================
# 结算管线
# ============================================================
## 运行一个技能定义。ctx 至少含 {source, source_id(施放单位id), target(格), card(可选)}
## 返回 {ok, reason, hits:[{cell,id,effects:[]}]}
func run_skill(def: Dictionary, ctx: Dictionary) -> Dictionary:
	var res := {"ok": false, "reason": "", "hits": []}
	if state == null:
		res["reason"] = "未接入 BattleState"
		return res
	# ① 技能源：仅接受三类源（技能结构.md 二·1）
	var src := str(def.get("source", SRC_PASSIVE))
	if not (src in [SRC_COMMAND, SRC_SUPPORT, SRC_PASSIVE]):
		res["reason"] = "未知技能源：%s" % src
		return res
	ctx["source"] = src
	# ② 条件[]：AND/OR/NOT 组合求值
	var cond: Dictionary = def.get("conditions", {})
	if not eval_conditions(cond, ctx):
		res["reason"] = "条件未满足"
		return res
	# ③ 倍率值：条件满足后产生并向下传递
	var mult: float = float(cond.get("multiplier", def.get("multiplier", 1.0)))
	# ④ 生效对象[]
	var cells: Array[Vector2i] = resolve_targets(def.get("targets", {}), ctx)
	if cells.is_empty():
		res["reason"] = "无有效目标"
		return res
	# ⑤ 效果[]：最终效果Int值 = 基础Int值 × 倍率值
	for cell in cells:
		var hid: int = state.unit_at(cell)
		var applied: Array = []
		for eff in def.get("effects", []):
			if apply_effect(eff, cell, hid, mult, ctx):
				applied.append(str(eff.get("id", "?")))
		res["hits"].append({"cell": cell, "id": hid, "effects": applied})
		# 链式传播：同效果传递给相邻单位（技能结构.md 二·3）
		if bool(def.get("targets", {}).get("chain", false)):
			var chain_cells: Array[Vector2i] = []
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = cell + dir
				if D.in_map(nb) and state.unit_at(nb) >= 0:
					chain_cells.append(nb)
			for cc in chain_cells:
				var cid: int = state.unit_at(cc)
				for eff in def.get("effects", []):
					if bool(eff.get("chainable", true)):
						apply_effect(eff, cc, cid, mult, ctx)
	res["ok"] = true
	return res


# ============================================================
# 条件求值（AND / OR / NOT + 7 维度断言）
# ============================================================
## 条件结构：{"all":[...], "any":[...], "not":{...}, "multiplier":1.5}
## 叶子：{"dim": COND_*, "key": ..., "op": ">=|<=|==|>|<|has|in", "value": ...}
func eval_conditions(cond: Dictionary, ctx: Dictionary) -> bool:
	if cond.is_empty():
		return true
	if cond.has("all"):
		for c in cond["all"]:
			if not eval_conditions(c, ctx):
				return false
	if cond.has("any"):
		var hit := false
		for c in cond["any"]:
			if eval_conditions(c, ctx):
				hit = true
				break
		if not hit:
			return false
	if cond.has("not"):
		if eval_conditions(cond["not"], ctx):
			return false
	if cond.has("dim"):
		return eval_leaf(cond, ctx)
	return true


func eval_leaf(c: Dictionary, ctx: Dictionary) -> bool:
	var dim := str(c.get("dim", ""))
	var key := str(c.get("key", ""))
	var op := str(c.get("op", "=="))
	var want: Variant = c.get("value", 0)
	var got: Variant = _pluck(dim, key, ctx)
	if got == null:
		return false
	match op:
		">=":
			return float(got) >= float(want)
		"<=":
			return float(got) <= float(want)
		">":
			return float(got) > float(want)
		"<":
			return float(got) < float(want)
		"!=":
			return got != want
		"has":
			return want in got
		"in":
			return got in want
		_:
			return got == want


## 按条件维度取值（未提供的维度返回 null = 条件不满足）
func _pluck(dim: String, key: String, ctx: Dictionary) -> Variant:
	var sid := int(ctx.get("source_id", -1))
	var side := str(ctx.get("side", state.current if state != null else ""))
	var unit: Dictionary = {}
	if sid >= 0 and state != null and state.units.has(sid):
		unit = state.units[sid]
	match dim:
		COND_COST:
			match key:
				"now":
					return int(state.cost.get(side, 0))
				"max":
					return D.COST_MAX
		COND_HAND:
			match key:
				"count":
					return state.hand.get(side, []).size()
				"max":
					return D.HAND_MAX
		COND_ROUND:
			match key:
				"now":
					return int(state.round_no)
				"phase":
					return int(state.phase)
				"max":
					return D.ROUND_MAX
		COND_UNIT_OP:
			match key:
				"kind":
					return str(unit.get("card", {}).get("kind", ""))
				"just_deployed":
					return bool(ctx.get("just_deployed", false))
		COND_UNIT_VALUE:
			match key:
				"hp":
					return int(unit.get("hp", 0))
				"hp_max":
					return int(unit.get("card", {}).get("hp", 0))
				"atk":
					return int(unit.get("card", {}).get("atk", 0))
				"effects":
					return unit.get("effects", {}).keys()
		COND_UNIT_POS:
			match key:
				"in_map":
					return unit.has("cell")
				"x":
					return int(unit.get("cell", Vector2i(-1, -1)).x)
				"y":
					return int(unit.get("cell", Vector2i(-1, -1)).y)
		COND_UNIT_ACT:
			match key:
				"acted":
					return bool(unit.get("acted", false))
				"moved":
					return bool(unit.get("moved", false))
				"is_attacker":
					return bool(ctx.get("is_attacker", false))
	return null


# ============================================================
# 生效对象解析
# ============================================================
## targets 结构：{"mode":"self|single|cell","cell":Vector2i,"kind":"soldier|building|queen|any",
##                "range":1,"splash":1,"side":"ally|enemy|any","chain":false}
func resolve_targets(t: Dictionary, ctx: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if state == null:
		return out
	var sid := int(ctx.get("source_id", -1))
	var side := str(ctx.get("side", state.current))
	var cell: Vector2i = ctx.get("target", Vector2i(-1, -1))
	match str(t.get("mode", "self")):
		"self":
			if sid >= 0 and state.units.has(sid):
				out.append(state.units[sid]["cell"])
		"single":
			var id: int = state.unit_at(cell)
			if id >= 0 and _match_unit(id, t, side):
				out.append(cell)
		"cell":
			# 任意地格：以目标格为中心，溅射范围（曼哈顿半径）内的全部单位
			var splash := int(t.get("splash", 0))
			for r in D.ROWS:
				for c in D.COLS:
					var p := Vector2i(r, c)
					if abs(p.x - cell.x) + abs(p.y - cell.y) > splash:
						continue
					var uid: int = state.unit_at(p)
					if uid >= 0 and _match_unit(uid, t, side):
						out.append(p)
	return out


func _match_unit(id: int, t: Dictionary, side: String) -> bool:
	var u: Dictionary = state.units[id]
	var want_kind := str(t.get("kind", "any"))
	if want_kind != "any" and str(u["card"]["kind"]) != want_kind:
		return false
	var want_side := str(t.get("side", "any"))
	if want_side == "ally" and u["side"] != side:
		return false
	if want_side == "enemy" and u["side"] == side:
		return false
	var rng := int(t.get("range", -1))
	if rng >= 0 and side != "":
		var sid := int(t.get("_source_id", -1))
		if sid >= 0 and state.units.has(sid):
			var a: Vector2i = state.units[sid]["cell"]
			var b: Vector2i = u["cell"]
			if abs(a.x - b.x) + abs(a.y - b.y) > rng:
				return false
	return true


# ============================================================
# 效果执行（最终值 = 基础Int值 × 倍率值）
# ============================================================
func apply_effect(eff: Dictionary, cell: Vector2i, id: int, mult: float, ctx: Dictionary) -> bool:
	var kind := str(eff.get("type", ""))
	var base := int(eff.get("value", 0))
	var final_v := int(round(float(base) * mult))
	match kind:
		EFF_DAMAGE:
			if id < 0:
				return false
			if str(state.units[id]["card"]["kind"]) == "queen":
				return false          # a500：蜂王免疫指令卡伤害与减益
			var dmg_v := final_v
			if bool(eff.get("by_target_cost", false)):
				dmg_v = int(state.units[id]["card"]["cost"]) * 2   # X 费卡：伤害 = 目标部署费 × 2（a500 费用 4）
			state.units[id]["hp"] = int(state.units[id]["hp"]) - dmg_v
			state.push_log("%s 受指令伤害 -%d" % [state.unit_name(id), dmg_v])
			return true
		EFF_MODIFY:
			if id < 0:
				return false
			var e: Dictionary = eff.get("effect", {}).duplicate()
			# 即时回复类（治疗）：不进效果槽，直接结算（含上限）
			if bool(e.get("instant_heal", false)):
				var maxhp := int(state.units[id]["card"]["hp"])
				state.units[id]["hp"] = mini(int(state.units[id]["hp"]) + final_v, maxhp)
				state.push_log("%s 治疗 +%d" % [state.unit_name(id), final_v])
				return true
			e["id"] = str(eff.get("id", "skill_buff"))
			state.add_effect(id, e)   # 内部已含「相同效果最多一个」「类型不匹配不赋予」
			return true
		EFF_RESOURCE:
			var side := str(ctx.get("side", state.current))
			var sign := 1 if bool(eff.get("gain", true)) else -1
			state.cost[side] = clampi(int(state.cost[side]) + sign * final_v, 0, D.COST_MAX)
			state.push_log("%s方 费用 %+d（技能）" % [state.cn(side), sign * final_v])
			return true
		EFF_RECYCLE:
			if id >= 0:
				state.push_log("%s 被回收退场" % state.unit_name(id))
				state.units[id]["hp"] = 0
				return true
			return false
		EFF_MOVE:
			if id >= 0 and state.unit_at(cell) < 0:
				state.units[id]["cell"] = cell
				return true
			return false
		EFF_DEPLOY:
			# 机场：部署范围被动（由 battle_state 的 legal_place 读取该被动生效）
			state.deploy_radius[ctx.get("side", state.current)] = final_v
			state.push_log("部署范围被动生效（半径 %d）" % final_v)
			return true
		EFF_HAND:
			var side2 := str(ctx.get("side", state.current))
			state.draw_one(side2)
			state.push_log("%s方 技能抽卡 1 张" % state.cn(side2))
			return true
	return false
