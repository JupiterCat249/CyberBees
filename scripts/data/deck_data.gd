class_name DeckData
extends Resource
## 卡组（替代原 battle_defs.gd 的 DECK_LIST 字符串数组）
## 说明：卡池引用 CardData 资源；同名多张 = 同一资源被多次引用（只读，安全）

@export var id: String = ""                       ## UUID（D-4）
@export var display_name: String = "默认卡组"
@export var cards: Array[CardData] = []           ## 12 张（1 蜂王 + 11 常规，A5 口径）
@export var queen: CardData                       ## 蜂王（单独引用，便于快速取用）


func count_by_id(card_id: String) -> int:
	var n := 0
	for c in cards:
		if c != null and c.id == card_id:
			n += 1
	return n


func validate() -> Array[String]:
	var errs: Array[String] = []
	if id == "" or not Uuid.is_valid(id):
		errs.append("DeckData[%s] id 非 UUID：%s" % [display_name, id])
	if cards.is_empty():
		errs.append("DeckData[%s] cards 为空" % display_name)
	if queen == null:
		errs.append("DeckData[%s] 未设置蜂王" % display_name)
	for c in cards:
		if c == null:
			errs.append("DeckData[%s] cards 含 null" % display_name)
	return errs
