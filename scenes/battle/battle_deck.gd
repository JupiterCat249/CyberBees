extends RefCounted
## ============================================================
## BattleDeck —— 手牌 / 牌库 / 起手与换牌 块（可维护性重构 第3块）
##
## 从 battle_state.gd 搬出：select_hand / draw_one / discard_armed / can_discard /
##                          exchange_hand / can_exchange / start_battle
## 拆分原则：只经共享 Model(state) 交互；本块负责"手牌与牌库"这一组字段。
##
## 规则依据（a500）：
##   · 构筑 2：1 蜂王 + 8 常规卡（前 4 初始手牌 + 后 4 备卡）
##   · 抽卡 1：卡入墓地；回合结束补至 4 张；牌库抽完 -> 墓地前 4 张洗回
##   · 抽卡：丢弃消耗 = 部署费；X 费卡 = 10
##   · 对战准备 5/9：调整卡组的初始手牌（每方 1 次）-> 备卡入牌库底 -> 开始对局
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

## 由协调器注入（共享 Model）
var state: Node = null


## 点击手牌：准备阶段=仅选中（供换牌）；行动阶段=持牌进入「部署」或「指令」目标选择
func select_hand(index: int) -> void:
	var s := state
	if s.winner != "":
		return
	if index < 0 or index >= s.hand[s.current].size():
		return
	# 准备阶段（a500 对战准备 5）：只做选中，供「换牌」使用，不进入部署/指令模式
	if s.phase == D.Phase.PREPARE:
		s.armed_side = s.current
		s.armed_card = index
		s.mode = D.Mode.IDLE
		s.selection_changed.emit()
		s.refresh()
		return
	var c: Dictionary = s.hand[s.current][index]
	var empty_cells: Array[Vector2i] = []      # 跨对象赋值必须显式带类型（无类型 [] 不能赋给 Array[Vector2i]）
	if c["kind"] == "command" or c["kind"] == "command_x":
		if s.phase == D.Phase.REFUND or s.phase == D.Phase.FIELD:
			return
		s.armed_card = index
		s.mode = D.Mode.CMD_TARGET
		s.selected_unit = -1
		s.move_range = empty_cells
		s.atk_range = s.all_cells()
	else:
		if s.phase != D.Phase.DEPLOY:
			return
		s.armed_card = index
		s.mode = D.Mode.DEPLOY_TARGET
		s.selected_unit = -1
		s.move_range = empty_cells
		s.atk_range = empty_cells
	s.selection_changed.emit()
	s.refresh()


## 抽 1 张（a500 抽卡 1）：手牌满不加；牌库空则把墓地前 4 张随机洗回
func draw_one(side: String) -> void:
	var s := state
	if s.hand[side].size() >= D.HAND_MAX:
		return
	if s.deckl[side].is_empty():
		if s.grave[side].is_empty():
			return
		var back: Array = []
		for i in mini(4, s.grave[side].size()):
			back.append(s.grave[side].pop_front())
		back.shuffle()
		s.deckl[side].append_array(back)
		s.push_log("%s方 牌库抽完 → 墓地 4 张洗回" % s.cn(side))
	if s.deckl[side].is_empty():
		return
	s.hand[side].append(s.deckl[side].pop_front())


## 弃卡过牌：消耗 = 部署费（X 费卡 = 10，a500 抽卡 2）
func discard_armed() -> void:
	var s := state
	if s.armed_card < 0 or s.armed_card >= s.hand[s.current].size():
		return
	var c: Dictionary = s.hand[s.current][s.armed_card]
	var pc: int = int(c["cost"])
	if pc < 0:
		pc = D.COST_MAX
	if s.cost[s.current] < pc:
		s.push_log("费用不足（弃卡需 %d，现有 %d）" % [pc, s.cost[s.current]])
		s.refresh()
		return
	s.cost[s.current] -= pc
	s.grave[s.current].append(c)
	s.hand[s.current].remove_at(s.armed_card)
	draw_one(s.current)
	s.push_log("%s方 弃置「%s」（-%d 费）→ 补充 1 张手牌" % [s.cn(s.current), c["name"], pc])
	s.clear_sel()
	s.refresh()


func can_discard() -> bool:
	var s := state
	return s.winner == "" and s.armed_card >= 0 and s.armed_card < s.hand[s.current].size()


## 换牌 / 起手调度（a500 对战准备 5；决策一：准备阶段**一次性**，每方 1 次）
func exchange_hand() -> void:
	var s := state
	if s.phase != D.Phase.PREPARE or s.armed_card < 0:
		return
	var side: String = s.side_of_armed()
	if side == "" or s.exchange_left[side] <= 0:
		s.push_log("%s方 已无换牌次数（对战准备阶段每方 %d 次）" % [s.cn(side), D.EXCHANGE_MAX])
		s.clear_sel()
		s.refresh()
		return
	if s.armed_card >= s.hand[side].size():
		s.clear_sel()
		s.refresh()
		return
	var c: Dictionary = s.hand[side][s.armed_card]
	if s.deckl[side].is_empty():
		s.push_log("%s方 备卡已空，无法换牌" % s.cn(side))
		s.clear_sel()
		s.refresh()
		return
	s.exchange_left[side] -= 1
	s.grave[side].append(c)
	s.hand[side].remove_at(s.armed_card)
	draw_one(side)
	s.push_log("%s方 调整初始手牌：%s 回墓地 → 备卡补入（剩余 %d 次）" % [s.cn(side), c["name"], s.exchange_left[side]])
	s.clear_sel()
	s.refresh()


func can_exchange() -> bool:
	var s := state
	if s.phase != D.Phase.PREPARE:
		return false
	var side: String = s.side_of_armed()
	return side != "" and s.armed_card >= 0 and s.exchange_left[side] > 0


## 开始对局（a500 对战准备 9）：先结算被动技能（【机场】设定部署范围），再进入第一回合
func start_battle() -> void:
	var s := state
	if s.phase != D.Phase.PREPARE:
		return
	for side in ["green", "red"]:
		var q: int = s.queen_id_of(side)
		if q >= 0 and s.skills != null:
			var prev: String = s.current
			s.current = side
			s.run_passive("机场", q)
			s.current = prev
	s.push_log("对战准备结束，开始第一回合")
	s.clear_sel()
	s.begin_turn(s.first_side)
