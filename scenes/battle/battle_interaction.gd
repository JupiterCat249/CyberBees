extends RefCounted
## ============================================================
## BattleInteraction —— **显式交互状态机**（可维护性重构 节点7）
##
## 背景：迭代003.1 期间"支援卡死""反复输出待确认""浮窗吃掉点击"等问题，
## 根因都是 **pending_kind / armed_card / selected_unit / mode / surrender_pending 的隐式耦合** ——
## 一次点击要同时裁决 长按详情 / 待确认执行 / 模式目标选择 / 改选 / 取消，规则散落在各处。
##
## 本模块把"一次点击"的裁决**收敛到单一入口 + 显式优先级表**：
##   ① 待确认（最高）：点==待确认目标 → 执行；支援待确认点范围外 → 退出
##   ② 部署目标选择（持牌 + DEPLOY_TARGET）
##   ③ 指令目标选择（持牌 + CMD_TARGET）
##   ④ 支援对象选择（SUPPORT_TARGET）
##   ⑤ 已选中单位：点自身→进支援模式 / 移动 / 攻击 / 支援 / 改选
##   ⑥ 取消（点非交互区域）
##
## 约束：本模块**只做裁决与分派**，动作实现仍在 BattleDeploy / BattleAction / BattlePending /
##       BattleTurn 中；不新增游戏状态，行为与重构前**逐条等价**。
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

## 交互状态（显式化，供日志/调试/后续扩展）
enum St {
	IDLE,            ## 空闲：无待确认、无持牌、无选中
	CONFIRM,         ## 待确认中（二次点击确认）
	MODE_TARGET,     ## 目标选择模式（部署/指令/支援对象）
	UNIT_SELECTED,   ## 已选中单位（可移动/攻击/支援/改选）
	FINISHED,        ## 对局已结束
}

## 由协调器注入（共享 Model）
var state: Node = null


## 由现有字段**推导**当前交互状态（幂等、无副作用；用于调试与长按判定）
func derive() -> int:
	var s := state
	if s == null:
		return St.IDLE
	if s.winner != "":
		return St.FINISHED
	if s.pending_kind != "":
		return St.CONFIRM
	if s.mode != D.Mode.IDLE:
		return St.MODE_TARGET
	if s.armed_card >= 0:
		return St.MODE_TARGET
	if s.selected_unit >= 0:
		return St.UNIT_SELECTED
	return St.IDLE


func state_name(st: int = -1) -> String:
	var v: int = derive() if st < 0 else st
	match v:
		St.CONFIRM:
			return "待确认"
		St.MODE_TARGET:
			return "目标选择"
		St.UNIT_SELECTED:
			return "已选单位"
		St.FINISHED:
			return "对局结束"
	return "空闲"


## 长按查看详情是否允许：**仅空闲态**（有待确认/持牌/选中单位/选目标时禁止，
## 否则长按浮窗会抢走确认点击 —— 迭代003.1 实测的支援卡死根因）
func can_long_press() -> bool:
	return derive() == St.IDLE


## 优先级表（文档化；与 dispatch_cell 的实现逐条对应，便于核对与测试）
func priority_table() -> Array:
	return [
		{"order": 1, "when": "点击 == 待确认目标", "action": "执行待确认", "state": "CONFIRM"},
		{"order": 2, "when": "支援待确认 且 点击在蓝色候选范围外", "action": "退出支援选择", "state": "CONFIRM"},
		{"order": 3, "when": "持牌 且 mode=DEPLOY_TARGET 且 合法落点", "action": "待确认「部署」", "state": "MODE_TARGET"},
		{"order": 4, "when": "持牌 且 mode=CMD_TARGET", "action": "待确认「指令」", "state": "MODE_TARGET"},
		{"order": 5, "when": "mode=SUPPORT_TARGET 且 点击在候选内", "action": "待确认「支援」", "state": "MODE_TARGET"},
		{"order": 6, "when": "mode=SUPPORT_TARGET 且 点击在候选外", "action": "退出支援选择", "state": "MODE_TARGET"},
		{"order": 7, "when": "已选中单位 且 点击自身格", "action": "进入支援对象选择", "state": "UNIT_SELECTED"},
		{"order": 8, "when": "已选中单位 且 点击移动范围空格", "action": "待确认「移动」", "state": "UNIT_SELECTED"},
		{"order": 9, "when": "已选中单位 且 点击攻击范围内敌方", "action": "待确认「攻击」", "state": "UNIT_SELECTED"},
		{"order": 10, "when": "已选中单位 且 点击射程内己方（有支援技能/未行动）", "action": "待确认「支援」", "state": "UNIT_SELECTED"},
		{"order": 11, "when": "点击其它单位 / 其余情况", "action": "改选或落入默认处理", "state": "UNIT_SELECTED"},
	]


## **单一入口**：按优先级表分派一次「棋盘格点击」。等价于重构前 on_cell_clicked 的分支顺序。
func dispatch_cell(cell: Vector2i) -> void:
	var s := state
	if s == null or s.winner != "":
		return
	# 迭代004 检查点5/11：动画运行期间的**禁 UI 交互**（block_ui Pattern 会置 ui_locked）
	if s.anim != null and s.anim.ui_locked:
		return
	# ① 待确认优先：点击与待确认相同的目标 → 执行（不依赖 mode/选中是否仍在）
	if s.pending_kind != "" and s.pending_cell == cell:
		s.confirm_pending_at(cell)
		return
	# ② 支援待确认：点在蓝色候选范围之外 → 退出该状态
	if s.pending_kind == "支援" and not (cell in s.support_range):
		s.clear_pending()
		s.action._leave_support_mode()
		s.clear_sel()
		s.push_log("已退出支援对象选择")
		s.refresh()
		return
	# ③ 部署目标选择
	if s.armed_card >= 0 and s.mode == D.Mode.DEPLOY_TARGET:
		if s.deploy.legal_place(cell) and s.confirm("部署", cell):
			s.deploy.place_at(cell)
		return
	# ④ 指令目标选择
	if s.armed_card >= 0 and s.mode == D.Mode.CMD_TARGET:
		if s.confirm("指令", cell):
			s.deploy.cmd_at(cell)
		return
	# ⑤ 支援对象选择
	if s.mode == D.Mode.SUPPORT_TARGET:
		if cell in s.support_range:
			if s.confirm("支援", cell):
				s.support_at(cell)
		else:
			s.clear_pending()
			s.action._leave_support_mode()
			s.clear_sel()
			s.push_log("已退出支援对象选择")
			s.refresh()
		return
	# ⑥ 已选中单位
	if s.selected_unit >= 0 and s.units.has(s.selected_unit):
		if cell == s.units[s.selected_unit]["cell"]:
			s.enter_support_mode()
			return
		if cell in s.move_range and s.unit_at(cell) < 0:
			if s.confirm("移动", cell):
				s.act_at(cell)
			return
		if cell in s.atk_range and s.unit_at(cell) >= 0 and s.units[s.unit_at(cell)]["side"] != s.current:
			if s.confirm("攻击", cell):
				s.act_at(cell)
			return
		if s.can_support_at(cell):
			if s.confirm("支援", cell):
				s.support_at(cell)
			return
	# ⑦ 其余情况：交给调用方的默认处理（改选单位 / 点空取消）
	s.on_cell_clicked_fallback(cell)
