extends RefCounted
## ============================================================
## BattleDeck —— 手牌 / 牌库 / 起手 块（可维护性重构 第3块）
##   职责：抽牌、弃卡过牌、备卡拆分、开始对局。
##   注：**换牌（exchange_hand / can_exchange）已于迭代005.1 整体移除**（人明确：开局前无换牌机会）。
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


## 点击手牌：准备阶段=不可选（开局前无换牌机会）；行动阶段=持牌进入「部署」或「指令」目标选择
func select_hand(index: int) -> void:
	var s := state
	if s.winner != "":
		return
	if index < 0 or index >= s.hand[s.current].size():
		return
	# 准备阶段（迭代005.1 人明确）：**开局前无任何换牌/调整手牌机会**，手牌一经发出即锁定；
	# 此阶段点击手牌不选中、不进入任何模式（换牌机制已整体移除）
	if s.phase == D.Phase.PREPARE:
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


## 换牌 / 起手调度 —— **迭代005.1 已整体移除**（人明确：开局前不应有任何换牌机会）。
## 原实现（a500 对战准备 5 的一次性换牌 + 每方 1 次上限）见 git 历史 `iter/005` 之前版本。
## 现保留的空号仅用于回退定位；不要再在此处新增换牌逻辑。


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
