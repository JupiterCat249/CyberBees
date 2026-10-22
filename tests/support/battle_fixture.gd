extends RefCounted
## 回归夹具：用**真实卡组资源**起一局纯逻辑战斗（不碰 UI、不挂场景树）
##
## 为什么不用 `battle_scene.tscn`：视图会带来引擎级警告与 3~4s 启动开销，
## 而规则契约应当在**最窄的装配**上验证；场景级冒烟另有一支（test_battle_smoke）。

const Pool := preload("res://scripts/data/card_pool.gd")
const ConfigLib := preload("res://scripts/battle/battle_config.gd")

const SIDE_ALLY := 0
const SIDE_ENEMY := 1


static func new_engine() -> BattleEngine:
	var e := BattleEngine.new()
	var cfg := ConfigLib.make(Pool.build("示范卡组"), Pool.build("示范卡组·敌"))
	e.start(cfg)
	return e


static func queen(e: BattleEngine, side: int) -> UnitInstance:
	return e.state.sides[side]["queen"]


static func queen_cell(e: BattleEngine, side: int) -> Vector2i:
	return queen(e, side).cell


## 往手牌最前面塞一张卡（测试构造用；走资源层取卡，与运行时同一真值来源）
static func push_card(e: BattleEngine, side: int, card_name: String) -> int:
	var c = Pool.card(card_name)
	if c == null:
		return -1
	e.state.sides[side]["hand"].insert(0, c)
	return 0


## 直接在棋盘上放一个单位（构造战场态势用，不经过部署费/领地检查）
static func place_unit(e: BattleEngine, side: int, card_name: String,
		cell: Vector2i) -> UnitInstance:
	var data = Pool.card(card_name)
	if data == null:
		return null
	var inst := UnitInstance.create(data as UnitData, side, cell)
	e.state.board.place(inst)
	return inst


## 己方领地（行 2..3）的第一个空格
static func empty_own_cell(e: BattleEngine) -> Vector2i:
	for row in [2, 3]:
		for col in 4:
			var c := Vector2i(row, col)
			if e.state.board.is_empty(c):
				return c
	return Vector2i(-1, -1)


## 手牌里第一个「可负担的单位卡」的下标（找不到 → -1）
static func first_affordable_unit_index(e: BattleEngine, side: int) -> int:
	var hand: Array = e.state.sides[side]["hand"]
	var money: int = e.state.cost(side)
	for i in hand.size():
		var c = hand[i]
		if c is UnitData and int(c.cost) >= 0 and int(c.cost) <= money:
			return i
	return -1
