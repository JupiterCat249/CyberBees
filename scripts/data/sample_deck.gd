class_name SampleDeck
extends RefCounted
## 样例卡组 —— **从旧 `scenes/battle/battle_defs.gd` 的 POOL 原样搬运**（同一份数据，未改数值）
## 用途：让 `battle_scene.tscn` 与自检可独立跑起来（卡片数据正式迁 .tres 属后续检查点）

const ART_DIR := "res://card-system/card_system/art/"   ## 旧素材目录（只读引用，不修改它）

## 卡组构成：**蜂王 + 12 张常规卡**（沿用旧 `battle_defs.gd` 的 DECK_LIST 口径）
## ⚠️ a500 规定为「1 蜂王 + 8 张常规卡」；本样例保留旧版 12 张以**保持与旧实现数据一致**，
##    卡组规模调整属玩法确认项（T10 口径），不在本轮擅自改动。
const DECK_NAMES := ["叶蜂", "叶蜂", "泥蜂", "泥蜂", "熊蜂", "蜂巢", "蜂巢III", "电击", "治疗", "护盾单元", "力场蜂巢", "力场炮台"]


static func build(side_tag: String = "") -> DeckData:
	var dd := DeckData.new()
	dd.id = Uuid.generate()
	dd.display_name = "样例卡组" + ("" if side_tag == "" else "·" + side_tag)
	var by_name := {}
	for spec in CARD_SPECS:
		var c := _make(spec)
		by_name[spec["name"]] = c
		dd.queen = c if c.kind == CardData.CardKind.QUEEN else dd.queen
	for nm in DECK_NAMES:
		if by_name.has(nm):
			dd.cards.append(by_name[nm])
	return dd


## 由 spec 构造卡对象（UnitData / CommandData）
static func _make(spec: Dictionary) -> CardData:
	var kind: int = spec["kind"]
	if kind == CardData.CardKind.COMMAND or kind == CardData.CardKind.COMMAND_X:
		var cd := CommandData.new()
		cd.id = Uuid.generate()
		cd.display_name = spec["name"]
		cd.kind = kind
		cd.cost = spec["cost"]
		cd.dmg = spec["dmg"]
		cd.heal = spec["heal"]
		cd.target_range = spec["range"]
		cd.x_cost_multiplier = spec["xmul"]
		cd.aoe_span = spec["aoe"]
		cd.chain_span = spec["chain"]
		cd.self_to_graveyard = true
		_common(cd, spec)
		return cd
	var ud := UnitData.new()
	ud.id = Uuid.generate()
	ud.display_name = spec["name"]
	ud.kind = kind
	ud.cost = spec["cost"]
	ud.atk = spec["atk"]
	ud.hp = maxi(1, spec["hp"])
	ud.move = spec["move"]
	ud.attack_range = spec["range"]
	ud.refund = spec["refund"]
	ud.immune_command = kind == CardData.CardKind.QUEEN
	_common(ud, spec)
	return ud


static func _common(c: CardData, spec: Dictionary) -> void:
	c.glossary = spec["glossary"]
	c.skill_name = spec["skill"]
	c.description = spec["desc"]
	c.tags = spec["tags"]
	var vis := CardVisual.new()
	var p: String = ART_DIR + str(spec["art"]) + ".png"
	if ResourceLoader.exists(p):
		vis.artwork = load(p)
	c.visual = vis


## ⚠️ 数值与旧 battle_defs.gd 的 POOL **逐字段一致**（迁移不改数值）
const CARD_SPECS: Array = [
	{
		"name": "金刚蜂王", "kind": CardData.CardKind.QUEEN, "art": "卡牌a-金刚蜂王",
		"cost": 8, "atk": 7, "hp": 8, "move": 1, "range": 2, "refund": 4,
		"dmg": 0, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "机场", "skill": "【机场】蜂王巢口",
		"desc": "部署阶段可在自身相邻格部署兵蜂；蜂王免疫指令卡伤害与减益。",
		"tags": "被动 · 部署 · 蜂王",
	},
	{
		"name": "叶蜂", "kind": CardData.CardKind.SOLDIER, "art": "卡牌c1-叶蜂",
		"cost": 2, "atk": 2, "hp": 3, "move": 1, "range": 1, "refund": 0,
		"dmg": 0, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "支援", "skill": "【支援】鼓舞",
		"desc": "选择 2 格内的 1 个己方单位，赋予「攻击提升」：攻击力 +1。使用后结束该单位行动。",
		"tags": "支援 · 单位效果 · 增益",
	},
	{
		"name": "泥蜂", "kind": CardData.CardKind.SOLDIER, "art": "卡牌c1-泥蜂",
		"cost": 2, "atk": 3, "hp": 4, "move": 1, "range": 2, "refund": 0,
		"dmg": 0, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "", "skill": "（无技能）",
		"desc": "纯战斗兵蜂：攻击 3 / 速度 1 / 生命 4 / 射程 2。",
		"tags": "兵蜂",
	},
	{
		"name": "力场蜂巢", "kind": CardData.CardKind.BUILDING, "art": "卡牌b1-蜂巢",
		"cost": 3, "atk": 0, "hp": 3, "move": 0, "range": 0, "refund": 1,
		"dmg": 0, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "被动", "skill": "【被动】力场",
		"desc": "相邻己方单位获得 1 层「力场」：每层减少 2 点非指令伤害。",
		"tags": "被动 · 地域效果 · 增益 · 力场",
	},
	{
		"name": "力场炮台", "kind": CardData.CardKind.BUILDING, "art": "卡牌b1-蜂巢III",
		"cost": 2, "atk": 4, "hp": 2, "move": 0, "range": 2, "refund": 0,
		"dmg": 0, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "被动", "skill": "【被动】力场",
		"desc": "相邻己方单位获得 1 层「力场」：每层减少 2 点非指令伤害。",
		"tags": "被动 · 地域效果 · 增益 · 力场",
	},
	{
		"name": "护盾单元", "kind": CardData.CardKind.BUILDING, "art": "卡牌d2-治疗",
		"cost": 2, "atk": 0, "hp": 2, "move": 0, "range": 0, "refund": 1,
		"dmg": 0, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "支援", "skill": "【支援】护盾",
		"desc": "选择 2 格内的 1 个己方兵蜂，赋予「护盾」：抵挡一次攻击（参与防御计算或己方回费阶段消失）。",
		"tags": "支援 · 单位效果 · 增益 · 套盾",
	},
	{
		"name": "熊蜂", "kind": CardData.CardKind.SOLDIER, "art": "卡牌c2-熊蜂",
		"cost": 5, "atk": 5, "hp": 8, "move": 1, "range": 1, "refund": 0,
		"dmg": 0, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "支援", "skill": "【支援】护卫",
		"desc": "选择 1 格内的 1 个己方单位，赋予「护甲」：受到的每次伤害 -1。使用后结束该单位行动。",
		"tags": "支援 · 单位效果 · 增益",
	},
	{
		"name": "蜂巢", "kind": CardData.CardKind.BUILDING, "art": "卡牌b1-蜂巢",
		"cost": 4, "atk": 0, "hp": 5, "move": 0, "range": 0, "refund": 1,
		"dmg": 0, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "回费", "skill": "【回费】采集",
		"desc": "每个己方回费阶段，额外回复 1 点费用。部署在己方领地任意格。",
		"tags": "回费 · 资源建筑",
	},
	{
		"name": "蜂巢III", "kind": CardData.CardKind.BUILDING, "art": "卡牌b1-蜂巢III",
		"cost": 9, "atk": 0, "hp": 12, "move": 0, "range": 0, "refund": 2,
		"dmg": 0, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "回费", "skill": "【回费】集群采集",
		"desc": "每个己方回费阶段，额外回复 2 点费用。生命值 12，可作前场肉盾。",
		"tags": "回费 · 资源建筑",
	},
	{
		"name": "电击", "kind": CardData.CardKind.COMMAND, "art": "卡牌d1-电击",
		"cost": 3, "atk": 0, "hp": 0, "move": 0, "range": 2, "refund": 0,
		"dmg": 4, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "指令", "skill": "【指令】电击",
		"desc": "对射程 2 内的 1 个单位造成 4 点指令伤害。蜂王免疫。使用后返回墓地。",
		"tags": "指令 · 攻击指令",
	},
	{
		"name": "治疗", "kind": CardData.CardKind.COMMAND, "art": "卡牌d2-治疗",
		"cost": 3, "atk": 0, "hp": 0, "move": 0, "range": 2, "refund": 0,
		"dmg": 0, "heal": 4, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "指令", "skill": "【指令】治疗",
		"desc": "为射程 2 内的 1 个己方单位回复 4 点生命值（不超过上限）。使用后返回墓地。",
		"tags": "指令 · 辅助指令",
	},
	{
		"name": "巡航导弹", "kind": CardData.CardKind.COMMAND, "art": "卡牌d1-巡航导弹",
		"cost": 6, "atk": 0, "hp": 0, "move": 0, "range": 3, "refund": 0,
		"dmg": 5, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "指令", "skill": "【指令】巡航导弹",
		"desc": "对射程 3 内的 1 个单位造成 5 点指令伤害，并赋予「灼烧」：其回合结束时 -1 生命。蜂王免疫。",
		"tags": "指令 · 攻击指令 · 减益",
	},
	{
		"name": "X费·毁灭", "kind": CardData.CardKind.COMMAND_X, "art": "卡牌d1-电击III",
		"cost": -1, "atk": 0, "hp": 0, "move": 0, "range": 3, "refund": 0,
		"dmg": 0, "heal": 0, "xmul": 2, "aoe": 0, "chain": 0,
		"glossary": "指令", "skill": "【指令】毁灭（X费）",
		"desc": "费用 = 目标单位的部署费用；对其造成「部署费用 ×2」的指令伤害。不可指定蜂王。",
		"tags": "指令 · 攻击指令 · X费",
	},
	{
		"name": "回收", "kind": CardData.CardKind.COMMAND, "art": "卡牌d2-治疗",
		"cost": 2, "atk": 0, "hp": 0, "move": 0, "range": 1, "refund": 0,
		"dmg": 0, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "指令", "skill": "【指令】回收",
		"desc": "使射程 1 内的 1 个己方兵蜂退场，并返还 2 点费用。",
		"tags": "指令 · 辅助指令 · 回收",
	},
	{
		"name": "补给", "kind": CardData.CardKind.COMMAND, "art": "卡牌d2-治疗",
		"cost": 1, "atk": 0, "hp": 0, "move": 0, "range": 0, "refund": 0,
		"dmg": 0, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "指令", "skill": "【指令】补给",
		"desc": "若当前回合 ≥3，则本回合费用 +3（不超过上限 10）。",
		"tags": "指令 · 辅助指令 · 资源",
	},
	{
		"name": "轮换", "kind": CardData.CardKind.COMMAND, "art": "卡牌d2-治疗",
		"cost": 1, "atk": 0, "hp": 0, "move": 0, "range": 0, "refund": 0,
		"dmg": 0, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "指令", "skill": "【指令】轮换",
		"desc": "抽取 1 张手牌（手牌上限 4 张）。",
		"tags": "指令 · 辅助指令 · 手牌",
	},
	{
		"name": "蜂群突袭", "kind": CardData.CardKind.COMMAND, "art": "卡牌d1-电击",
		"cost": 4, "atk": 0, "hp": 0, "move": 0, "range": 3, "refund": 0,
		"dmg": 4, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "指令", "skill": "【指令】蜂群突袭",
		"desc": "第 3 回合起且手牌 ≥2 时可用；对射程 3 内 1 个敌方单位造成 4×1.5 点伤害。",
		"tags": "指令 · 攻击指令 · 条件 · 倍率",
	},
	{
		"name": "扩散毒雾", "kind": CardData.CardKind.COMMAND, "art": "卡牌d1-巡航导弹",
		"cost": 4, "atk": 0, "hp": 0, "move": 0, "range": 2, "refund": 0,
		"dmg": 2, "heal": 0, "xmul": 0, "aoe": 1, "chain": 0,
		"glossary": "指令", "skill": "【指令】扩散毒雾",
		"desc": "对目标单位造成 2 点伤害，并链式传播给其上下左右相邻单位各 2 点。",
		"tags": "指令 · 攻击指令 · 链式传播",
	},
	{
		"name": "精确打击", "kind": CardData.CardKind.COMMAND, "art": "卡牌d1-电击III",
		"cost": 5, "atk": 0, "hp": 0, "move": 0, "range": 3, "refund": 0,
		"dmg": 5, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "指令", "skill": "【指令】精确打击",
		"desc": "仅对敌方兵蜂造成 5 点伤害（1 格溅射），不会误伤己方。",
		"tags": "指令 · 攻击指令 · 过滤",
	},
	{
		"name": "蜂粮储备", "kind": CardData.CardKind.COMMAND, "art": "卡牌d2-治疗",
		"cost": 1, "atk": 0, "hp": 0, "move": 0, "range": 0, "refund": 0,
		"dmg": 0, "heal": 0, "xmul": 0, "aoe": 0, "chain": 0,
		"glossary": "指令", "skill": "【指令】蜂粮储备",
		"desc": "当前费用 ≤5 时可用；本回合费用 +2。",
		"tags": "指令 · 辅助指令 · 资源",
	},
]
