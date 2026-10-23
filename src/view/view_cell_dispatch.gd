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
const EngLib := preload("res://scripts/battle/battle_engine.gd")

const MSG_DEPLOY := "该格不能部署（兵蜂需蜂王相邻空格；建筑需己方领地空格）"
const MSG_MOVE := "该格不可到达"
const MSG_NO_TARGET := "该格没有目标单位"
const MSG_COMMAND := "指令目标不合法或费用不足"
const MSG_SUPPORT := "再次点击（或点主按钮「确认」）才执行【支援】"
const MSG_ATTACK := "不能攻击该目标（射程外 / 已行动过 / 非行动阶段）"
const MSG_DEPLOY_PHASE := "部署阶段：点手牌选卡后点高亮格部署；要操作单位请先点右侧「完成部署 → 进入行动」"
const MSG_SELECT_HINT := "点是自己的单位来选中它（选中后才能移动/攻击/支援）"
const MSG_FOE_UNIT := "这是对方的单位（要攻击请先选中自己的单位）"
const MSG_COMMAND_TARGET := "该单位不是该指令的合法目标"
const MSG_ATTACK_UNIT := "不能攻击 %s（需先选中自己的单位，且目标在射程内）"
const MSG_DISCARD_FAIL := "弃牌失败：需 %d 费，当前 %d"


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


## 手牌执行路由（自 arena_view._execute_hand_on_cell 切出 —— 迭代101）
##   在交互范围内点击格 → 按**手牌交互模式**执行：
##     DEPLOY → 就地部署；TARGET → 指令卡（AOE 走"以格为中心"，空地也能放）
##   ⚠️ 与 decide() 一样只负责**路由**：真正的 intent 调用与提示由参数传入（flash），
##      这样视图不必把整张网都暴露给模块。
static func execute_hand(engine, intent, cell: Vector2i, flash: Callable) -> void:
	var side: int = engine.state.active
	match int(engine.hand_mode):
		int(EngLib.HandMode.DEPLOY):
			if not intent.request_deploy(side, engine.sel_hand_index, cell):
				flash.call(MSG_DEPLOY)
		int(EngLib.HandMode.TARGET):
			var u: UnitInstance = engine.state.board.unit_at(cell)
			## ⭐ 迭代064 P-19（清单 机制-4）：**AOE 卡改走"以格为中心"** —— 空地也能放；
			##   阶段1 只挂待确认（引擎返回 false ⇒ 不发 op），预览随即显示**效果范围**，按钮变「确认」。
			var hcard: CardData = null
			var hh: Array = engine.state.sides[side]["hand"]
			if engine.sel_hand_index >= 0 and engine.sel_hand_index < hh.size():
				hcard = hh[engine.sel_hand_index]
			if hcard is CommandData:
				intent.request_use_command_at(side, engine.sel_hand_index, cell)
			elif u == null or not intent.request_use_command(side, engine.sel_hand_index, u):
				flash.call(MSG_COMMAND_TARGET)
		_:
			pass


## 手牌点击的**纯决策**（自 arena_view._on_hand_clicked 切出 —— 迭代103）
##   idx = 该卡在 hand 数组里的下标（视图从 _hand_order 解析后传入；-1 = 不在手牌）
##   返回：
##     none        —— 无事可做（引擎未就绪 / idx 无效）
##     show_only   —— 只想"看"（对手手牌）：可带 card（无效则 null）；clear_selection 表示顺带取消当前选中
##     blocked     —— 是自己的牌但**不是自己回合**：可带 card + 一条 msg（先展示，后判权限）
##     select      —— 正常选中：带 idx 与 card
static func decide_hand(engine, my_seat: int, side: int, idx: int) -> Dictionary:
	if engine == null or engine.state == null:
		return {"type": "none"}
	var hand: Array = engine.state.sides[side]["hand"]
	var card = hand[idx] if idx >= 0 and idx < hand.size() else null
	## 对手的手牌：不可操作，但**必须可看**；这一下点击在语义上=「点非交互区域」⇒ 顺带取消选中
	if side != my_seat:
		return {"type": "show_only", "card": card, "clear_selection": int(engine.sel_kind) != 0}
	if idx < 0:
		return {"type": "none"}
	## 非行动方的手牌不可操作（本地双人热座）——但详情栏恒开放
	if side != int(engine.state.active):
		var who := "绿方" if int(side) == 0 else "红方"
		return {"type": "blocked", "card": card, "msg": "现在不是%s的回合" % who}
	return {"type": "select", "idx": idx, "card": card}

## 单位卡点击的**纯决策**（自 arena_view._on_unit_clicked 切出 —— 迭代104）
##   ⚠️ 详情栏「先展示、后判权限」由视图完成（与决策无关）；
##     本函数只回答"这一下该做什么"。
##   返回：
##     none            —— 引擎未就绪 / 单位不存在 / **不是自己回合**（权限门）
##     hand_exec       —— 该单位是当前指令卡的合法目标 ⇒ 就地执行指令（带 cell）
##     support_confirm —— 支援双击确认（已选中带支援的单位时点另一友方）
##     select          —— 选中该单位
##     attack          —— 以当前选中单位攻击它（失败时用 msg）
##   leave_first：手牌选中态**不在交互范围内**时需先 hand_range_leave()（原实现就是"退出选中后继续"）。
static func decide_unit(engine, my_seat: int, inst) -> Dictionary:
	if engine == null or engine.state == null or inst == null:
		return {"type": "none"}
	if int(engine.state.active) != my_seat:
		return {"type": "none"}
	var side: int = int(engine.state.active)
	var leave_first := false
	if int(engine.sel_kind) == 1:
		if engine.hand_range_has_cell(inst.cell):
			return {"type": "hand_exec", "cell": inst.cell}
		leave_first = true
	## ── 同侧 ──
	if int(inst.side) == side:
		## 支援双击确认（原设计）：已选中带支援技能的单位时，点友方 → 待确认 → 再点执行
		if int(engine.sel_kind) == 3 and engine.sel_unit != null and engine.sel_support != null \
				and engine.sel_unit.instance_id != inst.instance_id:
			return {"type": "support_confirm"}
		return {"type": "select", "leave_first": leave_first}
	return {"type": "attack", "leave_first": leave_first,
		"msg": MSG_ATTACK_UNIT % inst.card_name()}

## 主按钮的**纯决策**（自 arena_view._on_main_pressed 切出 —— 迭代107）
##   返回 type：confirm_move / confirm_attack / confirm_command（待确认格）
##              confirm_support（支援待确认）/ discard（选中手牌）/ end_phase（推进阶段）/ none
##   ⚠️ 目标解析（z 值）留在视图：本函数只回答"该走哪条路"。
static func decide_main(engine) -> Dictionary:
	if engine == null or engine.state == null:
		return {"type": "none"}
	if int(engine.command_cell.x) >= 0:
		var pa := String(engine.pending_action)
		if pa == "move" and engine.sel_unit != null:
			return {"type": "confirm_move"}
		if pa == "attack" and engine.sel_unit != null:
			return {"type": "confirm_attack"}
		return {"type": "confirm_command"}
	if engine.support_pending != null:
		return {"type": "confirm_support"}
	if int(engine.sel_kind) == 1 and int(engine.sel_hand_index) >= 0:
		return {"type": "discard"}
	return {"type": "end_phase"}

## 本地选中变化时**广播什么**（自 arena_view._on_selection_changed 切出 —— 迭代129）
##   纯读引擎状态，返回 {cell: Vector2i(-1,-1)=取消, hand_index: int(-1)=无, name: String}
##   口径（人 2026-10-05）：
##     · 双步确认的**阶段1**（command_cell）就要广播 ⇒ 对手在"确认之前"看到落点/范围；
##     · 否则播当前选中单位的格；
##     · 选中的是**手牌**时一并带卡号与卡名（对手看到"选中手牌 <卡名>"；旧端忽略未知键 ⇒ 兼容）。
static func selection_broadcast(engine) -> Dictionary:
	var out := {"cell": Vector2i(-1, -1), "hand_index": -1, "name": ""}
	if engine == null or engine.state == null:
		return out
	if int(engine.command_cell.x) >= 0:
		out["cell"] = engine.command_cell
	elif engine.sel_unit != null:
		out["cell"] = engine.sel_unit.cell
	if int(engine.sel_kind) == 1 and int(engine.sel_hand_index) >= 0:
		var h: Array = engine.state.sides[engine.state.active]["hand"]
		if int(engine.sel_hand_index) < h.size():
			out["hand_index"] = int(engine.sel_hand_index)
			out["name"] = String(h[out["hand_index"]].display_name)
	return out
