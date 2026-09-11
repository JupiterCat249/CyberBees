extends RefCounted
## ============================================================
## BattleAction —— 行动（选中 / 移动 / 攻击 / 支援）块（可维护性重构 第5块）
##
## 从 battle_state.gd 搬出：select_unit_at / act_at / can_support_at / support_at /
##                          enter_support_mode / _leave_support_mode / support_targets
##
## ⚠️ 跨对象赋值注意：move_range / atk_range / support_range 是 **Array[Vector2i]（带类型）**，
##    无类型的 [] 不能赋给它们（运行期才报错）——本脚本统一用带类型局部变量 empty_cells。
##
## 规则依据（a500）：
##   · 行动机会 3/4/5：行动 = 1 次移动 + 1 次（主动攻击 或 支援技能）；移动不结束行动；
##     使用攻击/支援后结束行动；没有攻击力无法主动攻击；没有移动速度无法移动
##   · 范围 3：攻击范围按曼哈顿距离、不被单位阻挡；移动按走格子、被阻挡
##   · 卡牌类型：支援技能 = 兵蜂/建筑可提供的支援（技能数据 source == "support"）
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

## 由协调器注入（共享 Model）
var state: Node = null


## 选中单位：任何单位都可选中用于**查看**（详情/技能区/属性栏跟随）；
## 仅「己方 + 行动阶段 + 未行动」才给出可行动范围
func select_unit_at(cell: Vector2i) -> void:
	var s := state
	var id: int = s.unit_at(cell)
	if id < 0:
		return
	var u: Dictionary = s.units[id]
	var can_act: bool = u["side"] == s.current and s.phase == D.Phase.ACTION and not u["acted"]
	var empty_cells: Array[Vector2i] = []
	# 改选单位 -> 使旧的待确认失效（待确认独立状态，只在明确改选/取消/执行时清除）
	s.clear_pending()
	s.selected_unit = id
	s.armed_card = -1
	s.mode = D.Mode.IDLE
	s.support_range = empty_cells
	s.move_range = empty_cells
	s.atk_range = empty_cells
	if can_act:
		var c: Vector2i = u["cell"]
		# a500 行动机会 4：本回合已移动则移动范围为 0
		if not u["moved"]:
			s.move_range = s.move_cells(c, s.combat.final_spd(id))
		# a500 范围 3：攻击范围按曼哈顿距离；行动机会 5：无攻击力不给攻击范围
		if s.combat.final_atk(id) > 0:
			s.atk_range = s.range_cells(c, s.combat.final_range(id), false)
	s.selection_changed.emit()
	s.refresh()


## 对已选中单位的目标格执行行动（移动 / 攻击）；move_range/atk_range 为空时不做任何事
func act_at(cell: Vector2i) -> void:
	var s := state
	if s.selected_unit < 0:
		return
	if not s.units.has(s.selected_unit):
		s.clear_sel()
		s.refresh()
		return
	if cell in s.move_range and s.unit_at(cell) < 0:
		# a500 行动机会 4：移动不结束行动 —— 移动后仍可攻击/支援；仅消耗"本回合移动"
		var uid: int = s.selected_unit
		s.units[uid]["cell"] = cell
		s.units[uid]["moved"] = true
		s.push_log("%s 移动到 (%d,%d)" % [s.unit_name(uid), cell.x, cell.y])
		select_unit_at(cell)      # 就地重新选中：刷新为「不可再移动 + 仍可攻击/支援」
		return
	if cell in s.atk_range:
		var tid: int = s.unit_at(cell)
		if tid >= 0 and s.units[tid]["side"] != s.current:
			# a500 行动机会 5：没有攻击力无法主动攻击（兜底校验）
			if s.combat.final_atk(s.selected_unit) <= 0:
				s.push_log("%s 攻击力为 0，无法主动攻击" % s.unit_name(s.selected_unit))
				s.refresh()
				return
			# 先消耗行动机会再结算战斗：攻击方可能被反击打死，结算后会从 units 移除
			var aid: int = s.selected_unit
			s.units[aid]["acted"] = true
			if s.combat != null:
				s.combat.attack(aid, tid)
			s.remove_dead()
			s.clear_sel()
			s.check_victory()
			s.refresh()


## 是否可直接把该格作为支援目标（无需先进支援模式）
func can_support_at(cell: Vector2i) -> bool:
	var s := state
	if s.selected_unit < 0 or not s.units.has(s.selected_unit) or s.phase != D.Phase.ACTION:
		return false
	var u: Dictionary = s.units[s.selected_unit]
	if u["side"] != s.current or u["acted"]:
		return false
	var nm := str(u["card"].get("support", {}).get("name", ""))
	if nm == "" or D.skill(nm).is_empty() or str(D.skill(nm).get("source", "")) != "support":
		return false
	var tid: int = s.unit_at(cell)
	if tid < 0 or tid == s.selected_unit or s.units[tid]["side"] != s.current:
		return false
	return cell in support_targets()


## 支援结算（走结构化技能管线；a500 行动机会 4：使用支援技能后结束行动）
func support_at(cell: Vector2i) -> void:
	var s := state
	if s.selected_unit < 0 or s.phase != D.Phase.ACTION:
		return
	if not s.units.has(s.selected_unit):
		s.clear_sel()
		s.refresh()
		return
	var u: Dictionary = s.units[s.selected_unit]
	if u["side"] != s.current or u["acted"]:
		s.push_log("只能由己方未行动单位提供支援")
		s.refresh()
		return
	var skill_name := str(u["card"].get("support", {}).get("name", ""))
	if skill_name == "" or D.skill(skill_name).is_empty():
		s.push_log("%s 无支援技能（未在技能表中定义）" % u["card"]["name"])
		s.refresh()
		return
	if str(D.skill(skill_name).get("source", "")) != "support":
		s.push_log("%s 的技能非支援类" % u["card"]["name"])
		s.refresh()
		return
	var res: Dictionary = s.use_skill(skill_name, cell)
	if bool(res.get("ok", false)):
		s.units[s.selected_unit]["acted"] = true   # a500 行动机会 4
		s.push_log("%s 支援 %s" % [u["card"]["name"], s.unit_name(s.unit_at(cell))])
	s.clear_sel()
	s.refresh()


## A5 UI：再次点击当前选中单位 → 进入「支援对象选择」
func enter_support_mode() -> void:
	var s := state
	if s.selected_unit < 0 or not s.units.has(s.selected_unit):
		return
	var u: Dictionary = s.units[s.selected_unit]
	if not u["card"].has("support"):
		s.push_log("%s 没有支援技能" % u["card"]["name"])
		s.refresh()
		return
	var empty_cells: Array[Vector2i] = []
	s.mode = D.Mode.SUPPORT_TARGET
	s.move_range = empty_cells
	s.atk_range = empty_cells
	s.support_range = support_targets()
	s.push_log("选择支援对象：「%s」射程 %d（点其他单位可改选）" % [u["card"]["support"]["name"], int(u["card"]["support"]["rng"])])
	s.selection_changed.emit()
	s.refresh()


func _leave_support_mode() -> void:
	var s := state
	var empty_cells: Array[Vector2i] = []
	s.mode = D.Mode.IDLE
	s.support_range = empty_cells


## 支援候选格：射程内的己方单位（含自身？不含 —— 自身不能作为支援对象）
func support_targets() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s := state
	if s.selected_unit < 0 or not s.units.has(s.selected_unit):
		return out
	var u: Dictionary = s.units[s.selected_unit]
	if not u["card"].has("support"):
		return out
	var rng: int = int(u["card"]["support"]["rng"])
	for id in s.units:
		if id == s.selected_unit or s.units[id]["side"] != s.current:
			continue
		var c: Vector2i = s.units[id]["cell"]
		if abs(c.x - u["cell"].x) + abs(c.y - u["cell"].y) <= rng:
			out.append(c)
	return out
