extends RefCounted
## 棋盘点击的**纯决策**（自 arena_view._on_cell_clicked 切出 —— 迭代100 · B5 第十三刀）
##
## 判据：只**读**引擎状态，返回"这一下该做什么"；真正调 intent / 改选中 / 弹提示仍由视图执行。
##   这样决策层可以**脱离场景树单测**（谁来执行、执行后长什么样，不是它的问题）。
##
## ⚠️ 行为契约（切分时必须逐分支一致 —— 本文件与切分前的 match 一一对应）：
##   · 有预览：按 preview.kind 分派 deploy / move / command / support / attack；
##   · 无预览：点空格 → 只给"为什么没反应"的提示（或什么都不做）；点敌方单位 → 提示；
##     点己方单位 → select_unit（详情/可用动作由视图补）。

const K := preload("res://scripts/battle/preview_kind.gd")

const MSG_DEPLOY := "该格不能部署（兵蜂需蜂王相邻空格；建筑需己方领地空格）"
const MSG_MOVE := "该格不可到达"
const MSG_NO_TARGET := "该格没有目标单位"
const MSG_COMMAND := "指令目标不合法或费用不足"
const MSG_SUPPORT := "再次点击（或点主按钮「确认」）才执行【支援】"
const MSG_ATTACK := "不能攻击该目标（射程外 / 已行动过 / 非行动阶段）"
const MSG_DEPLOY_PHASE := "部署阶段：点手牌选卡后点高亮格部署；要操作单位请先点右侧「完成部署 → 进入行动」"
const MSG_SELECT_HINT := "点是自己的单位来选中它（选中后才能移动/攻击/支援）"
const MSG_FOE_UNIT := "这是对方的单位（要攻击请先选中自己的单位）"


## 返回字典：{"type": "...", "msg": "...", "unit": UnitInstance?}
##   type ∈ deploy / move / command / support / attack / select_unit / msg / none
static func decide(engine, cell: Vector2i) -> Dictionary:
	if engine == null or engine.state == null:
		return {"type": "none"}
	var spec = engine.current_preview()
	var kind: int = int(spec.kind) if spec != null else 0
	match kind:
		K.Kind.DEPLOY:
			return {"type": "deploy", "msg": MSG_DEPLOY}
		K.Kind.MOVE:
			return {"type": "move", "msg": MSG_MOVE}
		K.Kind.COMMAND, K.Kind.SUPPORT, K.Kind.ATTACK:
			var target: UnitInstance = engine.state.board.unit_at(cell)
			if target == null:
				return {"type": "msg", "msg": MSG_NO_TARGET}
			if kind == K.Kind.COMMAND:
				return {"type": "command", "unit": target, "msg": MSG_COMMAND}
			if kind == K.Kind.SUPPORT:
				## 支援不针对特定单位（人澄清 Y-5）→ 点任意己方单位即进入待确认
				return {"type": "support", "msg": MSG_SUPPORT}
			return {"type": "attack", "unit": target, "msg": MSG_ATTACK}
		_:
			var here: UnitInstance = engine.state.board.unit_at(cell)
			if here == null:
				## 空且无预览：最常见的原因是阶段不对
				if int(engine.state.phase) == 2:
					return {"type": "msg", "msg": MSG_DEPLOY_PHASE}
				if int(engine.state.phase) == 3 and engine.sel_unit == null:
					return {"type": "msg", "msg": MSG_SELECT_HINT}
				return {"type": "none"}
			if int(here.side) != int(engine.state.active):
				return {"type": "msg", "msg": MSG_FOE_UNIT}
			return {"type": "select_unit", "unit": here}
