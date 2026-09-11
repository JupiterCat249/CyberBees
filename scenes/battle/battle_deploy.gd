extends RefCounted
## ============================================================
## BattleDeploy —— 部署与指令 块（可维护性重构 第4块）
##
## 从 battle_state.gd 搬出：legal_place / within_deploy_radius / place_at / cmd_at
## 拆分原则：只经共享 Model(state) 交互；本块负责"部署合法性 + 落子 + 指令结算"。
##
## 规则依据（a500）：
##   · 卡牌类型：兵蜂部署在蜂王相邻格；建筑部署在己方领地
##   · 费用 4：X 费卡费用 = 目标部署费（不可指定蜂王）
##   · 卡牌类型：蜂王免疫指令卡伤害与减益
##   · 抽卡 1：使用卡牌需以「合法目标」为前提（违规不得扣费、不得弃卡 —— 审计 B1）
##   · 指令效果自迭代003.1 起走**结构化技能管线**（技能结构.md），本块不再含伤害/治疗硬编码
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

## 由协调器注入（共享 Model）
var state: Node = null


## 该格是否可部署当前所持卡
func legal_place(cell: Vector2i) -> bool:
	var s := state
	if not D.in_map(cell):
		return false
	if s.unit_at(cell) >= 0:
		return false
	if s.armed_card < 0 or s.armed_card >= s.hand[s.current].size():
		return false
	var c: Dictionary = s.hand[s.current][s.armed_card]
	match c["kind"]:
		"building":
			return (cell.x >= 2) if s.current == "green" else (cell.x < 2)
		"soldier":
			# 迭代003.1：部署范围由**被动技能**驱动（机场 → deploy_radius），不再硬编码"蜂王相邻"
			return within_deploy_radius(cell)
	return false


## 是否在己方部署范围内（半径由【机场】被动写入；a500：兵蜂默认限蜂王相邻 -> 默认半径 1）
func within_deploy_radius(cell: Vector2i) -> bool:
	var s := state
	var q: int = s.queen_id_of(s.current)
	if q < 0 or not s.units.has(q):
		return false
	var qc: Vector2i = s.units[q]["cell"]
	return abs(cell.x - qc.x) + abs(cell.y - qc.y) <= int(s.deploy_radius.get(s.current, 1))


## 落子：扣费 → 生成单位 → 卡入墓地 → 出手牌
func place_at(cell: Vector2i) -> void:
	var s := state
	if s.winner != "" or s.armed_card < 0 or not legal_place(cell):
		return
	var c: Dictionary = s.hand[s.current][s.armed_card]
	if s.cost[s.current] < int(c["cost"]):
		s.push_log("费用不足")
		return
	s.cost[s.current] -= int(c["cost"])
	s.spawn(cell, s.current, c)
	s.grave[s.current].append(c)
	s.hand[s.current].remove_at(s.armed_card)
	s.push_log("%s方 部署 %s @(%d,%d)" % [s.cn(s.current), c["name"], cell.x, cell.y])
	s.clear_sel()
	s.refresh()


## 指令卡结算（费用 / 目标校验 / 免疫 / 效果；**效果全部由技能数据驱动**）
func cmd_at(cell: Vector2i) -> void:
	var s := state
	if s.winner != "" or s.armed_card < 0:
		return
	var c: Dictionary = s.hand[s.current][s.armed_card]
	var tid: int = s.unit_at(cell)
	# 自身目标的指令（补给 / 轮换等）不要求单位目标
	var is_self_target: bool = str(D.skill(str(c["name"])).get("targets", {}).get("mode", "")) == "self"
	# a500 抽卡 1：使用卡牌需以「合法目标」为前提 —— 无目标时不得扣费、不得弃卡（审计 B1 修复）
	if tid < 0 and not is_self_target:
		s.push_log("指令「%s」需指定一个单位目标（该格无单位）" % c["name"])
		s.refresh()
		return
	var target: Dictionary = s.units[tid]["card"] if tid >= 0 else {}
	# 辅助指令（治疗）只能对己方单位使用
	if c.has("heal") and s.units[tid]["side"] != s.current:
		s.push_log("「%s」只能对己方单位使用" % c["name"])
		s.refresh()
		return
	var pc: int = int(c["cost"])
	if c["kind"] == "command_x":
		pc = int(target["cost"])          # a500 费用 4：X 费卡费用 = 目标部署费（不可指定蜂王）
	if s.cost[s.current] < pc:
		s.push_log("费用不足（需 %d）" % pc)
		s.refresh()
		return
	# 蜂王免疫指令卡伤害与减益（a500 卡牌类型）—— 仅当存在单位目标时判定
	if tid >= 0 and str(target.get("kind", "")) == "queen":
		s.push_log("蜂王免疫指令卡效果")
		s.refresh()
		return
	# ---- 迭代003.1：指令效果改走**结构化技能管线**（技能结构.md），删除原硬编码 伤害/治疗/减益 分支 ----
	var res: Dictionary = s.use_skill(str(c["name"]), cell)
	if not bool(res.get("ok", false)):
		s.refresh()
		return
	s.cost[s.current] -= pc
	s.grave[s.current].append(c)
	s.hand[s.current].remove_at(s.armed_card)
	s.remove_dead()
	s.clear_sel()
	s.check_victory()
	s.refresh()
