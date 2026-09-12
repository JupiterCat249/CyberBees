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
## 主按钮（advance_phase）优先级：投降确认 > 准备阶段(换牌/开始对局) > 已持牌(弃卡) > 待确认 > 阶段推进
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
		if s.can_exchange():
			s.exchange_hand()
		else:
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
func begin_turn(side: String) -> void:
	var s := state
	s.current = side
	s.turn_started.emit(side, s.round_no)
	s.push_log("—— 第 %d 回合 · %s方 ——" % [s.round_no, s.cn(side)])
	s.phase = D.Phase.REFUND
	s.phase_changed.emit(s.phase)
	var gain: int = D.BASE_REFUND + (D.ROUND7_EXTRA if s.round_no >= 7 else 0)
	var rf: int = refund_of(side)
	s.cost[side] = mini(s.cost[side] + gain + rf, D.COST_MAX)
	if rf > 0:
		s.push_log("【回费】%s方 +%d（基础%d + 资源建筑%d）→ 费用 %d（上限 %d）" % [s.cn(side), gain + rf, gain, rf, s.cost[side], D.COST_MAX])
	else:
		s.push_log("【回费】%s方 +%d → 费用 %d（上限 %d）" % [s.cn(side), gain, s.cost[side], D.COST_MAX])
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
	for id in s.units.keys():
		var eff: Dictionary = s.units[id]["effects"]
		if eff.has("burn"):
			s.units[id]["hp"] = int(s.units[id]["hp"]) - int(eff["burn"]["dot"])
			s.push_log("%s 受灼烧 -%d" % [s.unit_name(id), int(eff["burn"]["dot"])])
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
