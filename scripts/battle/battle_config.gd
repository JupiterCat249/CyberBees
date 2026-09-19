class_name BattleConfig
extends RefCounted
## 对战配置（a500「对战准备」1~9 的输入参数）
##
## 纯数据容器：**不引用任何场景 / 节点 / UI**。
## 由外层（菜单 / 测试 / 存档）构造后交给 BattleEngine.start()。

## a500 对战准备 3：选择出战卡组（含 1 蜂王 + 8 常规卡）
var deck_ally: DeckData = null
var deck_enemy: DeckData = null

## a500 对战准备 2：红绿方与玩家信息
var ally_name: String = "绿方"
var enemy_name: String = "红方"

## a500 对战准备 4：抽取对战地图（None = 无场地效果）
var map_data: MapData = null

## a500 对战准备 6：决定先后手；后手初始费用 +2
var first_side: int = 0
var second_side_bonus: int = 2

## a500 对战准备 7~8：前 4 张为初始手牌、后 4 张为备卡（入牌库底）
var initial_hand_size: int = 4

## a500 构筑 3：相同卡不得超过 4 张（校验用）
var max_same_card: int = 4

## a500 抽卡 4：回合结束后补手牌到 N 张
var hand_max: int = 4


## 用两个卡组快速构造（同一份卡组会各自复制，避免共享实例）
static func make(deck_ally: DeckData, deck_enemy: DeckData,
		ally_name_: String = "绿方", enemy_name_: String = "红方") -> BattleConfig:
	var c := BattleConfig.new()
	c.deck_ally = deck_ally
	c.deck_enemy = deck_enemy
	c.ally_name = ally_name_
	c.enemy_name = enemy_name_
	return c


func deck_of(side: int) -> DeckData:
	return deck_ally if side == 0 else deck_enemy


func name_of(side: int) -> String:
	return ally_name if side == 0 else enemy_name


## 配置合法性校验（返回问题列表；空 = 合法）
func validate() -> Array[String]:
	var errs: Array[String] = []
	for side in [0, 1]:
		var dd := deck_of(side)
		var who := name_of(side)
		if dd == null:
			errs.append("%s 缺卡组" % who)
			continue
		if dd.queen == null:
			errs.append("%s 卡组缺蜂王" % who)
		elif dd.queen.kind != CardData.CardKind.QUEEN:
			errs.append("%s 的蜂王卡 kind 不是 QUEEN" % who)
		# a500 构筑 1：1 蜂王 + 8 张常规卡
		if dd.cards.size() != 8:
			errs.append("%s 常规卡应为 8 张（实际 %d）" % [who, dd.cards.size()])
		# a500 构筑 3：相同卡 ≤ 4 张
		var count := {}
		for c in dd.cards:
			if c == null:
				continue
			var n: String = c.display_name
			count[n] = int(count.get(n, 0)) + 1
		for n in count.keys():
			if int(count[n]) > max_same_card:
				errs.append("%s 的「%s」超过 %d 张（实际 %d）" % [who, n, max_same_card, count[n]])
	return errs
