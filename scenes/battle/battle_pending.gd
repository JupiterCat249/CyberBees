extends RefCounted
## ============================================================
## BattlePending —— 「待确认（二次点击确认）」块（可维护性重构 第2块）
##
## 从 battle_state.gd 搬出：confirm / confirm_pending_at / clear_pending / build_preview / confirm_pending
## 拆分原则：只经共享 Model(state) 交互；本块不改动其它块的状态，只读写"待确认"这一组字段。
##
## 设计要点（A5 程序需求「点击确认」，与迭代002/003.1 的经验教训一致）：
##   · 待确认是**独立状态**：不随 clear_sel() 清除，只在 执行 / 取消 / 改选 时清除
##   · 执行优先级最高：on_cell_clicked 中「点击==待确认目标」直接结算，**不依赖 mode/选中是否仍在**
##   · 预览记录 source_id：即使选中被清掉，也能在结算时补回施放者
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

## 由协调器注入（共享 Model）
var state: Node = null


## 首次调用=建立待确认并返回 false；再次以同一 (kind, cell) 调用=清除并返回 true（表示可以执行）
func confirm(kind: String, cell: Vector2i) -> bool:
	if state.pending_kind == kind and state.pending_cell == cell:
		clear_pending()
		return true
	state.pending_kind = kind
	state.pending_cell = cell
	state.preview = build_preview(kind, cell)
	state.preview["source_id"] = state.selected_unit
	state.push_log("待确认：%s @(%d,%d) —— 再次点击同一目标或按主按钮确认" % [kind, cell.x, cell.y])
	state.selection_changed.emit()
	state.refresh()
	return false


## 待确认优先执行：按记录的 kind 直接结算（供 on_cell_clicked 的最高优先分支调用）
func confirm_pending_at(cell: Vector2i) -> void:
	var kind: String = state.pending_kind
	var src: int = int(state.preview.get("source_id", -1))
	clear_pending()
	match kind:
		"部署":
			state.place_at(cell)
		"指令":
			state.cmd_at(cell)
		"支援":
			# 支援需要施放者：若选中已被清掉，用待确认时记录的来源单位补回
			if state.selected_unit < 0 and src >= 0 and state.units.has(src):
				state.selected_unit = src
			state.support_at(cell)
		_:
			state.act_at(cell)


func clear_pending() -> void:
	state.pending_kind = ""
	state.pending_cell = Vector2i(-1, -1)
	state.preview = {}


## 预览数据：攻击给出预计伤害与预计剩余血量（含反击预估）；移动/部署/支援给出目标格
## 迭代014（IDEA-012）：伤害/反击**统一走 BattleCombat.preview_damage()**（纯函数、与实战同源）。
## ⚠️ 此处此前**自己重算**且反击条件写成"守方存活才算" → 与 attack() 漂移（一击必杀时预览不显示反击，实战却照扣）。
func build_preview(kind: String, cell: Vector2i) -> Dictionary:
	var p := {"kind": kind, "cell": cell}
	if kind != "攻击":
		return p
	var aid: int = state.selected_unit
	var tid: int = state.unit_at(cell)
	if aid < 0 or tid < 0 or state.combat == null:
		return p
	var pv: Dictionary = state.combat.preview_damage(aid, tid)
	if not bool(pv["ok"]):
		return p
	p["attacker_id"] = aid
	p["target_id"] = tid
	p["dmg"] = int(pv["dmg"])
	p["hp_now"] = int(pv["target_hp_now"])
	p["hp_after"] = int(pv["target_hp_after"])
	p["counter"] = int(pv["counter"])
	p["attacker_hp_now"] = int(pv["attacker_hp_now"])
	p["attacker_hp_after"] = int(pv["attacker_hp_after"])
	p["coverage"] = pv["coverage"]   # 迭代014：伤害覆盖格（供棋盘高亮）
	return p


## 主按钮在待确认态 = 确认执行（与「再次点击同一目标」等价）
func confirm_pending() -> bool:
	if state.pending_kind == "":
		return false
	var kind: String = state.pending_kind
	var cell: Vector2i = state.pending_cell
	clear_pending()
	match kind:
		"部署":
			state.place_at(cell)
		"指令":
			state.cmd_at(cell)
		"支援":
			state.support_at(cell)
		_:
			state.act_at(cell)
	return true
