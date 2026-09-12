extends RefCounted
## ============================================================
## BattleSetup —— 开局准备 / 地图 / 单位生成 块（可维护性重构 第6块·上）
##
## 从 battle_state.gd 搬出：start / _prepare / draw_map / spawn / unit_at
## （draw_one 已在第3块 BattleDeck 中，本块不再重复）
##
## ⚠️ 跨对象赋值：hand/deckl 等容器一律用**带类型/独立局部变量**再赋值
##
## 规则依据（a500）：
##   · 构筑 2：1 蜂王 + 8 常规卡（前 4 初始手牌、后 4 备卡）
##   · 对战准备 5/6：抽取地图；随机决定先后手（后手初始费用 +2）
##   · 对战准备 8/9：部署蜂王 → 进入「准备」阶段调整初始手牌 → 开始第一回合
##   · 行动机会 3：部署当回合没有行动机会（spawn 时 acted/moved 置 true）
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

## 由协调器注入（共享 Model）
var state: Node = null


## 启动（幂等）
func start() -> void:
	var s := state
	if s.started:
		return
	s.started = true
	prepare()


## 开局准备（a500 对战准备全流程）
func prepare() -> void:
	var s := state
	# a500 构筑 2：前 4 张常规卡为初始手牌、后 4 张为备卡
	for side in ["green", "red"]:
		var cards: Array = []
		for nm in D.DECK_LIST:
			cards.append(D.card(nm))
		var empty: Array = []
		s.hand[side] = empty.duplicate()
		s.deckl[side] = empty.duplicate()
		for i in cards.size():
			if i < D.HAND_MAX:
				s.hand[side].append(cards[i])
			else:
				s.deckl[side].append(cards[i])
	# a500 对战准备 6：随机决定先后手（后手初始费用 +2）
	var order := ["green", "red"]
	order.shuffle()
	s.first_side = order[0]
	s.cost["green"] = 0
	s.cost["red"] = 0
	s.cost[order[1]] = D.SECOND_PLAYER_BONUS
	# a500 对战准备 5：抽取对战地图；提前部署蜂王并载入手牌
	draw_map()
	spawn(Vector2i(3, 1), "green", D.card("金刚蜂王"))
	spawn(Vector2i(0, 2), "red", D.card("金刚蜂王"))
	s.push_log("对战开始：%s方先手 · %s方后手（初始费用 +2）" % [s.cn(order[0]), s.cn(order[1])])
	s.push_log("牌组：初始手牌 %d 张 + 备卡 %d 张（a500 构筑 2）" % [s.hand[s.first_side].size(), s.deckl[s.first_side].size()])
	# a500 对战准备 5 + 9：进入「准备」阶段调整初始手牌（一次性），由主按钮开始第一回合
	s.current = s.first_side
	s.armed_side = ""
	s.exchange_left = {"green": D.EXCHANGE_MAX, "red": D.EXCHANGE_MAX}
	s.phase = D.Phase.PREPARE
	s.phase_changed.emit(s.phase)
	s.push_log("对战准备：可调整初始手牌（每方 %d 次），点主按钮「开始对局」进入第一回合" % D.EXCHANGE_MAX)
	s.refresh()


## 抽取地图并写入特殊地形
func draw_map() -> void:
	var s := state
	var maps: Array = D.MAP_POOL
	var m: Dictionary = maps[randi() % maps.size()]
	s.map_name = str(m["name"])
	s.terrain.clear()
	for c in m["terrain_cells"]:
		s.terrain[c] = {"id": m["terrain_id"], "name": m["terrain_name"],
			"atk_add": int(m["terrain_atk_add"]), "spd_add": int(m["terrain_spd_add"])}
	s.push_log("地图「%s」：特殊地形 %d 格「%s」（%s）" % [s.map_name, s.terrain.size(), m["terrain_name"], m["terrain_desc"]])


## 生成单位（a500 行动机会 3：部署当回合没有行动机会 —— acted/moved 置 true）
func spawn(cell: Vector2i, side: String, card: Dictionary) -> int:
	var s := state
	var id: int = s.next_id
	s.next_id += 1
	s.units[id] = {"cell": cell, "side": side, "card": card, "hp": int(card["hp"]),
		"acted": true, "moved": true, "effects": {}}
	return id


## 该格上的单位 id（无则 -1）
func unit_at(cell: Vector2i) -> int:
	var s := state
	for id in s.units:
		if s.units[id]["cell"] == cell:
			return id
	return -1
