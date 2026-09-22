extends RefCounted
## ============================================================
## BattleTurn —— 回合流程 / 地形 / 投降 块（可维护性重构 第6块·下·之二）
##
## 从 battle_state.gd 搬出：advance_phase / begin_turn / end_turn / apply_terrain(原 _apply_terrain) /
##                          refund_of / surrender / request_surrender / cancel_surrender / on_small_pressed
##
## 规则依据（a500 回合流程）：回费（基础+资源建筑，第7回合起+2，上限10）→ 场地 → 部署 → 行动；
##   回合数以「先手方再次开始回合」为界（先手方随机，不可写死绿方）；
##   回合结束补手牌至 4 张；超过 12 回合按蜂王生命比较；第 4 回合起允许主动投降（需二次确认）。
##
## 主按钮（advance_phase）优先级：投降确认 > 准备阶段(开始对局) > 已持牌(弃卡) > 待确认 > 阶段推进
## 注：迭代005.1 起准备阶段不再有「换牌」分支（换牌机制已移除）。
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

## 由协调器注入（共享 Model）
var state: Node = null


## 主按钮：按优先级裁决
func advance_phase() -> void:
	var s := state
	if s.winner != "":
		return
	if s.surrender_pending:
		s.surrender_pending = false
		surrender()
		return
	if s.phase == D.Phase.PREPARE:
		# 迭代005.1：准备阶段只有「开始对局」一个动作（换牌已移除）
		s.start_battle()
		return
	if s.armed_card >= 0:
		s.discard_armed()
		return
	if s.pending_kind != "":
		s.confirm_pending()
		return
	match s.phase:
		D.Phase.DEPLOY:
			s.phase = D.Phase.ACTION
			s.phase_changed.emit(s.phase)
			s.clear_sel()
			s.refresh()
		D.Phase.ACTION:
			end_turn()


## 回合开始（回费 → 场地 → 停在部署阶段等玩家操作）
## 迭代005.2（人明确的回费口径）：
##   ① **只有当前行动方回费**（后手在**先手的回合**不回费，先手在后手的回合也不回费）；
##   ② 后手的「开局额外回费 +2」是**一次性**的（在 BattleSetup.prepare 发放），此后不再有任何额外机制回费；
##   ③ 本函数只对 `side`（= 本回合行动方）加费 —— 这是上述口径的唯一实现入口，勿改为"双方都加"。
func begin_turn(side: String) -> void:
	var s := state
	s.current = side
	s.turn_started.emit(side, s.round_no)
	s.push_log("—— 第 %d 回合 · %s方 ——" % [s.round_no, s.cn(side)])
	# 迭代005.2（人明确）：后手的「额外回费 +2」在**后手自己的第一个回合**发放（一次性），
	#   不在对战准备阶段预支 —— 因此双方在对战准备时费用都为 0，后手要到自己的回合才拿到这 2 费。
	#   （`second_bonus_pending/granted` 保证只发一次；实现见 battle_setup.prepare 的登记）
	var bonus := 0
	if s.second_bonus_pending and not s.second_bonus_granted and side != s.first_side:
		bonus = D.SECOND_PLAYER_BONUS
		s.second_bonus_pending = false
		s.second_bonus_granted = true
		s.push_log("【后手额外回费】%s方 +%d（**仅此一次**，在自己的回合开始时结算）" % [s.cn(side), bonus])
	s.phase = D.Phase.REFUND
	s.phase_changed.emit(s.phase)
	var gain: int = D.BASE_REFUND + (D.ROUND7_EXTRA if s.round_no >= 7 else 0)
	var rf: int = refund_of(side)
	s.cost[side] = mini(s.cost[side] + gain + rf + bonus, D.COST_MAX)
	if rf > 0:
		s.push_log("【回费】%s方 +%d（基础%d + 资源建筑%d）→ 费用 %d（上限 %d）" % [s.cn(side), gain + rf, gain, rf, s.cost[side], D.COST_MAX])
	else:
		s.push_log("【回费】%s方 +%d → 费用 %d（上限 %d）" % [s.cn(side), gain, s.cost[side], D.COST_MAX])
	# 迭代016（A5 效果图鉴）：**己方回费阶段消失**的效果 —— 护盾 / 冻结 / 灼烧 / 速攻 / 诱饵
	expire_refund_effects(side)
	# 迭代017（G-37）：**地域效果「力场」的相邻授予** —— 清除上一轮光环授予的力场，再按当前场上光环重算
	apply_force_field_auras(side)
	# 迭代004 检查点7/8：回费**数值文本**（#FFA300 + 字号随数值）浮在己方费用六边形上方
	if s.anim != null:
		var hex_at: Vector2 = D.HEX_L if side == "green" else D.HEX_R
		s.anim.float_text(gain + rf, "refund", hex_at + Vector2(0.0, -34.0))
	s.phase = D.Phase.FIELD
	s.phase_changed.emit(s.phase)
	apply_terrain()
	s.phase = D.Phase.DEPLOY
	s.phase_changed.emit(s.phase)
	for id in s.units:
		s.units[id]["acted"] = false
		s.units[id]["moved"] = false
	s.clear_sel()
	s.refresh()


## 回合结束：结算持续效果 → 补手牌 → 胜负检查 → 交给对方
func end_turn() -> void:
	var s := state
	# 迭代017（G-35 修正）：**灼烧不再是回合结束扣血** —— A5 效果图鉴为
	#   「受攻击时每层追加 2 点指令伤害，己方回费阶段消失」；受攻击时的追加伤害见 battle_combat。
	#   本处仅保留回合收尾的死亡清理。
	s.remove_dead()
	if s.winner != "":
		s.refresh()
		return
	var next := "red" if s.current == "green" else "green"
	if next == s.first_side:
		s.round_no += 1
	for side in ["green", "red"]:
		while s.hand[side].size() < D.HAND_MAX:
			s.draw_one(side)
	s.check_victory()
	if s.round_no > D.ROUND_MAX:
		s.round12_result()
	if s.winner != "":
		s.refresh()
		return
	begin_turn(next)


## 场地阶段：播报地形影响
func apply_terrain() -> void:
	var s := state
	for id in s.units:
		var c: Vector2i = s.units[id]["cell"]
		if s.terrain.has(c):
			s.push_log("%s 受地形 %s 影响（攻+%d）" % [s.unit_name(id), s.terrain[c]["name"], int(s.terrain[c]["atk_add"])])


## 资源建筑回费合计
func refund_of(side: String) -> int:
	var s := state
	var sum := 0
	for id in s.units:
		var u: Dictionary = s.units[id]
		if u["side"] == side:
			sum += int(u["card"].get("refund", 0))
	return sum


## 主动投降（a500 胜利条件 4：第 4 回合起）
func surrender() -> void:
	var s := state
	if s.round_no < 4:
		s.push_log("第 4 回合起才可投降")
		s.refresh()
		return
	s.winner = "red" if s.current == "green" else "green"
	s.push_log("%s方 投降，%s方 获胜" % [s.cn(s.current), s.cn(s.winner)])
	s.battle_ended.emit(s.winner)
	s.refresh()


## 右下小按钮（0 帮助 / 2 状态播报 / 3 投降）
func on_small_pressed(index: int) -> void:
	var s := state
	match index:
		0:
			s.help_on = not s.help_on
		2:
			s.push_log("回合%d/%d · %s方 · 费%d" % [s.round_no, D.ROUND_MAX, s.cn(s.current), s.cost[s.current]])
		3:
			request_surrender()
	s.refresh()


## 请求投降：首次=进入待确认并弹浮窗；再次=直接执行
func request_surrender() -> void:
	var s := state
	if s.winner != "":
		return
	if s.round_no < 4:
		s.push_log("第 4 回合起才可投降（当前第 %d 回合）" % s.round_no)
		s.refresh()
		return
	if s.surrender_pending:
		s.surrender_pending = false
		surrender()
		return
	s.surrender_pending = true
	s.push_log("投降确认：再次点击投降按钮，或按主按钮「确认投降」")
	s.popup_requested.emit("确认投降",
		"点击任意处取消；点主按钮「确认投降」执行投降。\n\n（a500 胜利条件 4：从第 4 回合开始，允许主动投降）")
	s.refresh()


## 取消投降
func cancel_surrender() -> void:
	var s := state
	if s.surrender_pending:
		s.surrender_pending = false
		s.push_log("已取消投降")
		s.refresh()

## 迭代016（A5 效果图鉴）：清除该方单位身上「己方回费阶段消失」的效果
##   A5：效果消失与赋予同阶段时**先算消失、再算赋予** → 故本函数在 begin_turn（回费结算）内、部署/行动之前调用
func expire_refund_effects(side: String) -> void:
	var s := state
	for id in s.units.keys():
		if str(s.units[id]["side"]) != side:
			continue
		for k in D.EFFECT_EXPIRE_ON_REFUND:
			if s.units[id]["effects"].has(k):
				s.units[id]["effects"].erase(k)
				s.push_log("%s 的「%s」在回费阶段消失" % [s.unit_name(id), str(D.EFFECT_DEFS[k]["name"])])

## 迭代017（G-37）：**地域效果「力场」** —— 持有该被动的单位，使其相邻己方单位获得 1 层力场
##   A5：地域效果作用于目标格上的单位；「力场蜂巢 / 力场炮台」的被动为"相邻己方单位获得 1 层力场"。
##   实现：每个回费阶段**整体重算**（先清除上一轮 aura，再按当前场上光环赋予）——
##   ⚠️ 迭代018（人明确）：**buff 不能叠加** —— 已有「力场」的单位不再被光环重复赋予（a500「相同效果最多一个」）
##   自愈式：提供者离场 / 单位走开时力场随之消失，无需额外钩子。
func apply_force_field_auras(side: String) -> void:
	var s := state
	# ① 清除该方单位身上由光环产生的力场（aura 标记）
	for id in s.units.keys():
		if str(s.units[id]["side"]) != side:
			continue
		var e: Dictionary = s.units[id]["effects"].get("force_field", {})
		if bool(e.get("aura", false)):
			s.units[id]["effects"].erase("force_field")
	# ② 按当前场上光环重新赋予（相邻四格内的己方单位，不含提供者自身）
	for pid in s.units.keys():
		var pcard: Dictionary = s.units[pid]["card"]
		var sk: Dictionary = D.skill(str(pcard.get("sk", "").replace("【被动】", "")))
		if sk.is_empty():
			continue
		var tg: Dictionary = sk.get("targets", {})
		if str(tg.get("aura", "")) != "force_field":
			continue
		if str(s.units[pid]["side"]) != side:
			continue
		var layers: int = int(tg.get("aura_layers", D.EFFECT_AURA_FORCE_FIELD))
		var pc: Vector2i = s.units[pid]["cell"]
		var granted := 0
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc := Vector2i(pc.x + d.x, pc.y + d.y)
			if not D.in_map(nc):
				continue
			var uid: int = s.unit_at(nc)
			if uid < 0 or str(s.units[uid]["side"]) != side:
				continue
			# 迭代018（人明确）：**buff 不能叠加** —— a500「相同效果最多一个」
			#   该单位已有「力场」（无论来自哪个光环或手动赋予）→ 不再重复赋予层数
			if s.units[uid]["effects"].has("force_field"):
				continue
			s.units[uid]["effects"]["force_field"] = D.make_effect("force_field", layers, true)
			granted += 1
		if granted > 0:
			s.push_log("%s 的「力场」授予相邻 %d 个己方单位 %d 层" % [s.unit_name(pid), granted, layers])
