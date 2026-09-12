extends Node
## ============================================================
## BattleState —— 战斗规则状态机（Model 层）
##   职责：持有并维护全部规则状态；对外只暴露"语义动作"；状态变化统一 emit 信号。
##   不做渲染、不读输入（输入由 BattleInput 转成语义信号后连到本节点的槽）。
##   规则依据: 电子蜂a500规则.md
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

# ---------------- 信号（视图/协调器订阅） ----------------
signal state_changed()                               ## 通用"状态已变，请重绘"
signal turn_started(side: String, round_no: int)     ## 新回合开始
signal phase_changed(phase: int)                     ## 阶段变化
signal log_added(text: String)                       ## 追加一条日志
signal battle_ended(winner: String)                  ## 胜负已定
signal selection_changed()                           ## 选中/待放置状态变化
signal popup_requested(title: String, desc: String)  ## 请求弹出纯文本浮窗（投降确认等，复用 M3 浮窗）

# ---------------- 状态 ----------------
var round_no := 1
var phase: int = D.Phase.REFUND
var current := "green"
var mode: int = D.Mode.IDLE
var cost := {"green": 0, "red": 0}
var hand := {"green": [], "red": []}
var deckl := {"green": [], "red": []}
var grave := {"green": [], "red": []}
var units := {}
var terrain := {}
var next_id := 1
var winner := ""
var log_lines: Array = []
var help_on := false

var armed_card := -1
var selected_unit := -1
var move_range: Array[Vector2i] = []
var atk_range: Array[Vector2i] = []
## A5 UI：支援对象候选格（再次点击当前选中单位后进入支援对象选择）
var support_range: Array[Vector2i] = []
## A5 程序需求「点击确认攻击/部署/移动」：待确认目标（首次点=预览，再点同一目标=执行）
var pending_kind := ""
var pending_cell := Vector2i(-1, -1)
## 待确认预览数据（供视图显示：预计剩余血量 / 伤害等）
var preview := {}
## A5 UI：投降二次确认（确认 → 投降结算；取消 → 返回）
var surrender_pending := false

## a500 对战准备：本局先手方 / 抽取到的地图名（回合数以「先手方再次开始回合」为界）
var first_side := "green"
var map_name := ""
## a500 对战准备 5：准备阶段「调整初始手牌」——逐方剩余次数 + 当前操作的是哪一方的手牌
var exchange_left := {"green": 0, "red": 0}
var armed_side := ""

## 由协调器注入
var combat: Node = null
var skills = null             ## 结构化技能系统（迭代003，RefCounted）
var grid = null               ## 棋盘几何与范围计算（重构第1块，RefCounted）
var pending = null            ## 待确认（二次点击确认）（重构第2块，RefCounted）
var deck = null               ## 手牌/牌库/起手与换牌（重构第3块，RefCounted）
var deploy = null             ## 部署与指令（重构第4块，RefCounted）
var action = null             ## 行动：选中/移动/攻击/支援（重构第5块，RefCounted）
var setup = null              ## 开局准备/地图/生成（重构第6块·上，RefCounted）
var victory = null            ## 胜负判定（重构第6块·下，RefCounted）
var turn = null               ## 回合流程/地形/投降（重构第6块·下之二，RefCounted）
var anim = null                ## 自写动画引擎（迭代004，Node 挂场景树）
var interaction = null        ## 显式交互状态机（重构节点7，RefCounted）
var started := false
## 部署范围被动（机场）：逐方部署半径（a500 兵蜂限蜂王相邻格 → 被动可扩大）
var deploy_radius := {"green": 1, "red": 1}


# ============================================================
# 生命周期 / 对战准备（a500 对战准备）
# ============================================================
## 启动 —— 重构第6块·上：实现已搬至 BattleSetup（battle_setup.gd）
func start() -> void:
	if setup != null:
		setup.start()


## 开局准备 —— 重构第6块·上：实现已搬至 BattleSetup
func _prepare() -> void:
	if setup != null:
		setup.prepare()


## a500 对战准备 5：抽取对战地图（从地图池随机，播报地图名与特殊地形）
## 抽取地图 —— 重构第6块·上：实现已搬至 BattleSetup
func draw_map() -> void:
	if setup != null:
		setup.draw_map()


## 抽 1 张 —— 重构第3块：实现已搬至 BattleDeck（battle_deck.gd）
func draw_one(side: String) -> void:
	if deck != null:
		deck.draw_one(side)


## 生成单位 —— 重构第6块·上：实现已搬至 BattleSetup
func spawn(cell: Vector2i, side: String, card: Dictionary) -> int:
	if setup != null:
		return setup.spawn(cell, side, card)
	return -1


## 单位占位查询 —— 重构第6块·上：实现已搬至 BattleSetup
func unit_at(cell: Vector2i) -> int:
	if setup != null:
		return setup.unit_at(cell)
	return -1


# ============================================================
# 回合流程（a500：回费/场地自动 → 部署 → 行动）
# ============================================================
## 主按钮：只服务"需要玩家确认"的 部署 / 行动 两个阶段；选中手牌时执行「弃卡过牌」
## 主按钮（阶段推进/确认/弃卡/换牌）—— 重构第6块·下之二：实现已搬至 BattleTurn
func advance_phase() -> void:
	if turn != null:
		turn.advance_phase()

## a500 抽卡 6：丢弃手牌消耗 = 该卡部署费用；X 费卡丢弃消耗 10 点
## 弃卡后该卡入墓地，并补充 1 张手牌（保持 a500 抽卡 4「补至 4 张」的节奏）
## 弃卡过牌 / 可否弃卡 —— 重构第3块：实现已搬至 BattleDeck（battle_deck.gd）
func discard_armed() -> void:
	if deck != null:
		deck.discard_armed()


## 当前是否可以弃卡（供 HUD 决定主按钮文案）
func can_discard() -> bool:
	return deck != null and deck.can_discard()


# ============================================================
# 对战准备：调整初始手牌（a500 对战准备 5；决策一：一次性，不引入每回合换牌机会）
# ============================================================
## 换牌：指定手牌回墓地 → 从备卡补 1 张（手牌仍为 4 张）；每方上限 EXCHANGE_MAX
## 换牌 / 起手调度 与 可否换牌 —— 重构第3块：实现已搬至 BattleDeck（battle_deck.gd）
func exchange_hand() -> void:
	if deck != null:
		deck.exchange_hand()


## 当前是否可以换牌（供 HUD 决定主按钮文案）
func can_exchange() -> bool:
	return deck != null and deck.can_exchange()


## 准备阶段结束，进入第一回合（a500 对战准备 9）
## 开始对局（a500 对战准备 9）—— 重构第3块：实现已搬至 BattleDeck（battle_deck.gd）
func start_battle() -> void:
	if deck != null:
		deck.start_battle()


## 已选中的手牌属于哪一方（未选中/越界返回 ""）
func side_of_armed() -> String:
	if armed_card < 0:
		return ""
	var s := armed_side if armed_side != "" else current
	if s == "" or not hand.has(s) or armed_card >= hand[s].size():
		return ""
	return s


## ============================================================
## 回合流程 / 地形 —— 重构第6块·下之二：实现已搬至 BattleTurn（battle_turn.gd）
## 以下保留同签名转发，调用点零改动（行为不变）
## ============================================================
func begin_turn(side: String) -> void:
	if turn != null:
		turn.begin_turn(side)


func end_turn() -> void:
	if turn != null:
		turn.end_turn()


func _apply_terrain() -> void:
	if turn != null:
		turn.apply_terrain()


## 主动投降 —— 重构第6块·下之二：实现已搬至 BattleTurn（battle_turn.gd）
func surrender() -> void:
	if turn != null:
		turn.surrender()


## 资源建筑回费合计（a500 基础术语·资源建筑）—— 实现已搬至 BattleTurn
func refund_of(side: String) -> int:
	if turn != null:
		return turn.refund_of(side)
	return 0


# ============================================================
# 出牌
# ============================================================
## 点击手牌 —— 重构第3块：实现已搬至 BattleDeck（battle_deck.gd）
func select_hand(index: int) -> void:
	if deck != null:
		deck.select_hand(index)


## 部署合法性 / 部署范围 —— 重构第4块：实现已搬至 BattleDeploy（battle_deploy.gd）
func legal_place(cell: Vector2i) -> bool:
	return deploy != null and deploy.legal_place(cell)


## 是否在己方部署范围内 —— 重构第4块：实现已搬至 BattleDeploy
func within_deploy_radius(cell: Vector2i) -> bool:
	return deploy != null and deploy.within_deploy_radius(cell)


## （收尾清理）adjacent_own_queen 已删除 —— 迭代003.1 起部署范围改由**被动技能 deploy_radius** 驱动，
## 该函数自 legal_place 改用 within_deploy_radius 后即**零调用**，属死代码。


## 落子 / 指令结算 —— 重构第4块：实现已搬至 BattleDeploy（battle_deploy.gd）
func place_at(cell: Vector2i) -> void:
	if deploy != null:
		deploy.place_at(cell)


func cmd_at(cell: Vector2i) -> void:
	if deploy != null:
		deploy.cmd_at(cell)




# ============================================================
# 行动（移动 / 攻击 / 支援）—— a500：1 次移动 + 1 次攻击或支援
# ============================================================
## 选中单位 —— 重构第5块：实现已搬至 BattleAction（battle_action.gd）
func select_unit_at(cell: Vector2i) -> void:
	if action != null:
		action.select_unit_at(cell)


## 执行行动（移动/攻击）—— 重构第5块：实现已搬至 BattleAction（battle_action.gd）
func act_at(cell: Vector2i) -> void:
	if action != null:
		action.act_at(cell)


## 可否直接以该格为支援目标 —— 重构第5块：实现已搬至 BattleAction
func can_support_at(cell: Vector2i) -> bool:
	return action != null and action.can_support_at(cell)


## 支援结算 —— 重构第5块：实现已搬至 BattleAction（battle_action.gd）
func support_at(cell: Vector2i) -> void:
	if action != null:
		action.support_at(cell)


func enter_support_mode() -> void:
	if action != null:
		action.enter_support_mode()


func _leave_support_mode() -> void:
	if action != null:
		action._leave_support_mode()


func support_targets() -> Array[Vector2i]:
	if action != null:
		return action.support_targets()
	return [] as Array[Vector2i]


## a500 效果机制：①相同效果最多一个 ②效果 2：单位类型不匹配则无法赋予
## 效果字典可选带 `allow`（允许的单位类型列表，如 ["soldier"]）；不带则对任意单位类型生效。
func add_effect(id: int, eff: Dictionary) -> void:
	if not units.has(id):
		return
	var eid: String = eff["id"]
	var kind: String = str(units[id]["card"]["kind"])
	if eff.has("allow") and not (kind in eff["allow"]):
		push_log("%s 为 %s 类型，无法赋予效果「%s」（类型不匹配）" % [unit_name(id), kind, eff.get("name", eid)])
		return
	var existing: Dictionary = units[id]["effects"]
	if existing.has(eid):
		push_log("%s 已有相同效果「%s」，不再叠加" % [unit_name(id), eff.get("name", eid)])
		return
	existing[eid] = eff
	push_log("%s 获得效果「%s」" % [unit_name(id), eff.get("name", eid)])


func remove_dead() -> void:
	var dead: Array = []
	for id in units:
		if int(units[id]["hp"]) <= 0:
			dead.append(id)
	for id in dead:
		push_log("%s 退场" % unit_name(id))
		units.erase(id)


## 移动范围：走格子寻路（BFS 最短路；等权网格上与 A* 结果等价）
## —— 重构第1块：实现已搬至 BattleGrid（battle_grid.gd），此处保留转发以保持调用点不变
func move_cells(from: Vector2i, steps: int) -> Array[Vector2i]:
	if grid != null:
		return grid.move_cells(from, steps)
	return []


## 攻击范围：按曼哈顿距离（a500 范围 3：攻击范围不会被单位阻挡）—— 实现已搬至 BattleGrid
func range_cells(from: Vector2i, rng: int, need_free: bool) -> Array[Vector2i]:
	if grid != null:
		return grid.range_cells(from, rng, need_free)
	return []


## 全盘格子 —— 实现已搬至 BattleGrid
func all_cells() -> Array[Vector2i]:
	if grid != null:
		return grid.all_cells()
	return []


# ============================================================
# 数值查询（转发给 BattleCombat，供视图显示）
# ============================================================
func final_atk(id: int) -> int:
	return int(combat.final_atk(id)) if combat != null else 0


func final_spd(id: int) -> int:
	return int(combat.final_spd(id)) if combat != null else 0


func final_range(id: int) -> int:
	return int(combat.final_range(id)) if combat != null else 0


func final_reduce(id: int) -> int:
	return int(combat.final_reduce(id)) if combat != null else 0


# ============================================================
# 胜负（a500 胜利条件）
# ============================================================
## ============================================================
## 胜负判定（a500 胜利条件）—— 重构第6块·下：实现已搬至 BattleVictory（battle_victory.gd）
## 以下保留同签名转发，调用点零改动（行为不变）
## ============================================================
func check_victory() -> void:
	if victory != null:
		victory.check_victory()


func queen_alive(side: String) -> bool:
	return victory != null and victory.queen_alive(side)


func queen_hp(side: String) -> int:
	if victory != null:
		return victory.queen_hp(side)
	return 0


func round12_result() -> void:
	if victory != null:
		victory.round12_result()


# ============================================================
# 输入语义槽（由 BattleInput 的信号连接）
# ============================================================
func on_hand_clicked(side: String, index: int) -> void:
	# a500 对战准备 5：准备阶段双方手牌均可点击（本地对战无 AI），用于「调整初始手牌」
	if phase == D.Phase.PREPARE:
		if index < 0 or index >= hand[side].size():
			return
		if armed_side == side and armed_card == index:
			armed_side = ""
			armed_card = -1          # 再次点击同一张 = 取消选中
		else:
			armed_side = side
			armed_card = index
		selection_changed.emit()
		refresh()
		return
	if side != current:
		return
	select_hand(index)


## ============================================================
## 棋盘格点击 —— 重构节点7：裁决已收敛到 BattleInteraction（battle_interaction.gd）
## 优先级表：①待确认执行 ②支援待确认退出 ③部署 ④指令 ⑤支援候选 ⑥支援候选外退出
##           ⑦点自身进支援模式 ⑧移动 ⑨攻击 ⑩射程内己方支援 ⑪默认
## ============================================================
func on_cell_clicked(cell: Vector2i) -> void:
	if interaction != null:
		interaction.dispatch_cell(cell)


## 默认处理：不属于任何"待确认/模式/已选单位"分支时 —— 改选单位 或 取消
func on_cell_clicked_fallback(cell: Vector2i) -> void:
	# 点其他己方单位 = 改选；点空 = 取消选中
	clear_pending()
	select_unit_at(cell)


# ============================================================
# A5 程序需求：点击确认（首次点目标=预览，再次点同一目标=执行）
# ============================================================
## 返回 true 表示"这是对同一目标的第二次点击，可以执行"
## ============================================================
## 待确认（二次点击确认）—— 重构第2块：实现已搬至 BattlePending（battle_pending.gd）
## 以下保留同签名转发，调用点零改动（行为不变）
## ============================================================
func confirm(kind: String, cell: Vector2i) -> bool:
	if pending == null:
		return false
	return pending.confirm(kind, cell)


func confirm_pending_at(cell: Vector2i) -> void:
	if pending != null:
		pending.confirm_pending_at(cell)


func clear_pending() -> void:
	if pending != null:
		pending.clear_pending()


func confirm_pending() -> bool:
	if pending == null:
		return false
	return pending.confirm_pending()




func on_support_clicked(cell: Vector2i) -> void:
	support_at(cell)


## A5 程序需求：点击非交互区域取消当前选中（三种选中态通吃：待放置卡 / 选中单位 / 指令目标）
## 同时清除待确认（明确取消语义）
func on_click_empty() -> void:
	if armed_card >= 0 or selected_unit >= 0 or pending_kind != "":
		clear_pending()
		clear_sel()
		refresh()


## 右下小按钮 / 投降三件套 —— 重构第6块·下之二：实现已搬至 BattleTurn（battle_turn.gd）
func on_small_pressed(index: int) -> void:
	if turn != null:
		turn.on_small_pressed(index)


## A5 UI：投降需二次确认（确认 → 投降结算；取消 → 返回）—— 实现已搬至 BattleTurn
func request_surrender() -> void:
	if turn != null:
		turn.request_surrender()


## 取消投降（点击任意处关闭浮窗时）—— 实现已搬至 BattleTurn
func cancel_surrender() -> void:
	if turn != null:
		turn.cancel_surrender()


# ============================================================
# 工具
# ============================================================
func clear_sel() -> void:
	armed_card = -1
	selected_unit = -1
	mode = D.Mode.IDLE
	move_range = []
	atk_range = []
	support_range = []
	# 注意：**不清除待确认**（pending 是独立状态）——
	# 此前此处连带 clear_pending()，而 clear_sel() 有 16 处调用，
	# 任何一次顺手的清选中都会杀掉待确认，导致"反复点击只输出待确认、永远匹配不上"（人实测现象）
	selection_changed.emit()


func push_log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 60:
		log_lines.pop_front()
	log_added.emit(s)


func cn(side: String) -> String:
	return "绿" if side == "green" else ("红" if side == "red" else "—")


# ============================================================
# 结构化技能系统入口（迭代003 · 依据技能结构.md 四段管线）
# ============================================================
## 以结构化技能定义施放：管线由 BattleSkills.run_skill 执行
func use_skill(skill_name: String, target: Vector2i) -> Dictionary:
	if skills == null:
		# 绝不静默：接线丢失时大声报错（G-01 教训）
		push_error("[BattleState] 技能系统未接入（skills == null）—— 技能调用被忽略")
		push_log("技能系统未接入，无法使用「%s」" % skill_name)
		refresh()
		return {"ok": false, "reason": "技能系统未接入"}
	var def: Dictionary = D.skill(skill_name)
	if def.is_empty():
		push_log("未找到技能定义：%s" % skill_name)
		return {"ok": false, "reason": "无技能定义"}
	var sid: int = selected_unit if selected_unit >= 0 else -1
	var ctx := {"source_id": sid, "side": current, "target": target}
	var res: Dictionary = skills.run_skill(def, ctx)
	if bool(res.get("ok", false)):
		push_log("技能「%s」生效（命中 %d 处）" % [str(def.get("name", skill_name)), res["hits"].size()])
		remove_dead()
		check_victory()
	else:
		push_log("技能「%s」未生效：%s" % [str(def.get("name", skill_name)), str(res.get("reason", ""))])
	refresh()
	return res


## 被动技能：进入场地时结算（部署 / 回合开始）
func run_passive(skill_name: String, owner_id: int) -> Dictionary:
	if skills == null:
		return {"ok": false, "reason": "技能系统未接入"}
	var def: Dictionary = D.skill(skill_name)
	if def.is_empty() or str(def.get("source", "")) != "passive":
		return {"ok": false, "reason": "非被动技能"}
	return skills.run_skill(def, {"source_id": owner_id, "side": current,
		"target": units[owner_id]["cell"] if units.has(owner_id) else Vector2i(-1, -1)})


func unit_name(id: int) -> String:
	return str(units[id]["card"]["name"]) if units.has(id) else "?"


## 当前"被查看"的卡（详情块与技能区共用）：选中卡 → 选中单位 → 当前方手牌首张
func current_detail_card() -> Dictionary:
	if armed_card >= 0 and armed_card < hand[current].size():
		return hand[current][armed_card]
	if selected_unit >= 0 and units.has(selected_unit):
		return units[selected_unit]["card"]
	if not hand[current].is_empty():
		return hand[current][0]
	return {}


## 长按查看详情是否允许
## 仅当「有待确认目标 / 已持牌 / 处于部署·指令·支援目标选择模式」时禁止 ——
## 目的：避免长按浮窗抢走确认点击（本轮支援卡死根因）；
## **选中单位本身不禁止**（长按查看详情正是要点单位；之前误加 selected_unit<0 导致浮窗永不弹出）
func can_long_press() -> bool:
	return winner == "" and pending_kind == "" and armed_card < 0 and mode == D.Mode.IDLE


## 当前查看对象的单位 id（无则退回当前方蜂王）
func focus_unit_id() -> int:
	if selected_unit >= 0 and units.has(selected_unit):
		return selected_unit
	return queen_id_of(current)


## 指定单位的**实时**卡面数据（含 buff 与地形加成）—— 显示层统一入口
func unit_card_live(id: int) -> Dictionary:
	if not units.has(id):
		return {}
	var out: Dictionary = units[id]["card"].duplicate()
	out["hp"] = int(units[id]["hp"])
	out["atk"] = final_atk(id)
	out["spd"] = final_spd(id)
	out["range"] = final_range(id)
	return out


## 当前查看对象的卡面数据：若焦点是场上单位，用**实时数值**覆盖基础值（保证卡面与状态一致）
func detail_card_live() -> Dictionary:
	var d: Dictionary = current_detail_card()
	if d.is_empty():
		return d
	var id := focus_unit_id()
	if id < 0 or not units.has(id):
		return d
	if str(units[id]["card"]["name"]) != str(d.get("name", "")):
		return d
	var out := d.duplicate()
	out["hp"] = int(units[id]["hp"])
	out["atk"] = final_atk(id)
	out["spd"] = final_spd(id)
	out["range"] = final_range(id)
	return out


## 详情栏「属性值」：与当前查看对象一致（场上单位=实时值；手牌=卡牌基础值）
func focus_values() -> Array:
	var d: Dictionary = current_detail_card()
	if d.is_empty():
		return ["-", "-", "-", "-"]
	var id := focus_unit_id()
	if id >= 0 and units.has(id) and str(units[id]["card"]["name"]) == str(d.get("name", "")):
		return [str(final_atk(id)), str(final_reduce(id)), str(final_spd(id)), str(final_range(id))]
	if d["kind"] == "command" or d["kind"] == "command_x":
		return ["—", "—", "—", str(int(d.get("range", 0)))]
	return [str(int(d.get("atk", 0))), "0", str(int(d.get("spd", 0))), str(int(d.get("range", 0)))]


func queen_id_of(side: String) -> int:
	for id in units:
		if units[id]["side"] == side and units[id]["card"]["kind"] == "queen":
			return id
	return -1


## 通用刷新（视图订阅 state_changed 后各自重绘）
func refresh() -> void:
	state_changed.emit()
