class_name CardPool
extends RefCounted
## **卡池 —— 唯一权威来源**（迭代055 重建）
##
## 数据来源：`单位文字图鉴/单位表格-测试用.xlsx`（人指定：**只有这 10 张卡，其他内容不需要**）
## 素材来源：`电子蜂A5策划案/素材/电子蜂素材9-19/` → 已复制进 `assets/card_art/`
##
## 与旧 `sample_deck.gd` 的关系：**取代它**。旧卡（护盾单元/力场蜂巢/扩散毒雾/精确打击/回收/
## 补给/轮换/蜂群突袭/X费·毁灭 等）**全部不在本表内 → 已删除**。
##
## ⚠️ 数值以表格为准，与迭代054 之前的旧实现有出入处已按表改正（见迭代055 记录 §1.1）。

const ART_DIR := "res://assets/card_art/"

## 技能描述文本（与表格「技能机制」列一致）
const D_QUEEN := "[回费]回复四点费用\n[部署]获得[装甲]效果"
const D_LEAF := "[被动]在敌方领地时，攻击造成[2]倍伤害"
const D_NONE := "无"
const D_BUMBLE := "[被动]对蜂王伤害[*2]\n[支援]回复[3]点费用"
const D_SHOCK := "[指令]与目标接触及间接接触的单位都会受到相同伤害"
const D_MISSILE := "[指令]对效果范围内的所有单位造成伤害"
const D_HEAL := "[指令]为一个己方单位回复[3]点血量"
const D_HIVE1 := "[回费]回复[1]点费用"
const D_HIVE3 := "[回费]回复[3]点费用"

## 技能名（详情区标题）
const S_QUEEN := "回费 / 装甲"
const S_LEAF := "领地突袭"
const S_BUMBLE := "重击蜂王 / 补给"
const S_SHOCK := "接触传导"
const S_MISSILE := "范围轰炸"
const S_HEAL := "治疗"
const S_HIVE := "回费"

## 标签
const T_QUEEN := "蜂王 · 回费 · 装甲"
const T_SOLDIER := "兵蜂 · 被动"
const T_COMMAND := "指令 · 攻击"
const T_HEAL := "指令 · 支援"
const T_BUILDING := "建筑 · 回费"


## 由 spec 构造卡对象（UnitData / CommandData）
static func make(spec: Dictionary) -> CardData:
	var kind: CardData.CardKind = spec["kind"] as CardData.CardKind
	var c: CardData
	if kind == CardData.CardKind.COMMAND or kind == CardData.CardKind.COMMAND_X:
		var cd := CommandData.new()
		cd.dmg = spec["dmg"]
		cd.heal = spec["heal"]
		cd.target_range = spec["range"]
		cd.aoe_span = spec["aoe"]
		cd.chain_span = spec["chain"]
		cd.self_to_graveyard = true
		c = cd
	else:
		var ud := UnitData.new()
		ud.atk = spec["atk"]
		ud.hp = maxi(1, spec["hp"])
		ud.move = spec["move"]
		ud.attack_range = spec["range"]
		ud.refund = spec["refund"]
		ud.immune_command = kind == CardData.CardKind.QUEEN
		ud.passives = _make_passives(spec)
		c = ud
	c.id = Uuid.generate()
	c.display_name = spec["name"]
	c.kind = kind
	c.cost = spec["cost"]
	c.glossary = spec["glossary"]
	c.skill_name = spec["skill"]
	c.description = spec["desc"]
	c.tags = spec["tags"]
	c.skills = _make_skills(spec)
	var vis := CardVisual.new()
	var art_path := ART_DIR + str(spec["name"]) + ".png"
	if ResourceLoader.exists(art_path):
		vis.artwork = load(art_path)
	c.visual = vis
	return c


## 无条件加成用的倍伤，走 `passives`（battle_combat 读取）
static func _make_passives(spec: Dictionary) -> Array[EffectData]:
	var out: Array[EffectData] = []
	var q: float = float(spec.get("mul_vs_queen", 1.0))
	var t: float = float(spec.get("mul_foe_territory", 1.0))
	if not is_equal_approx(q, 1.0):
		var e := EffectData.new()
		e.id = Uuid.generate()
		e.display_name = "对蜂王倍伤"
		e.atk_mul_vs_queen = q
		out.append(e)
	if not is_equal_approx(t, 1.0):
		var e2 := EffectData.new()
		e2.id = Uuid.generate()
		e2.display_name = "领地倍伤"
		e2.atk_mul_in_foe_territory = t
		out.append(e2)
	return out


## 技能（支援 / 被动）：本轮先把「支援回费」「部署装甲」建成 SkillData，供详情区与规则层使用
static func _make_skills(spec: Dictionary) -> Array[SkillData]:
	var out: Array[SkillData] = []
	# 支援：回复费用（熊蜂）
	var sup: int = int(spec.get("support_refund", 0))
	if sup > 0:
		var sk := SkillData.new()
		sk.id = Uuid.generate()
		sk.display_name = "补给"
		sk.kind = SkillData.Kind.SUPPORT
		sk.glossary = "支援"
		sk.description = "回复 [%d] 点费用" % sup
		sk.target_range = int(spec.get("support_range", 0))
		sk.affects_enemies = false
		sk.ends_actor_action = true
		sk.refund = sup
		sk.effects = []
		out.append(sk)
	# 部署：获得装甲（蜂王）
	var armor: int = int(spec.get("deploy_armor", 0))
	if armor > 0:
		var sk2 := SkillData.new()
		sk2.id = Uuid.generate()
		sk2.display_name = "装甲"
		sk2.kind = SkillData.Kind.PASSIVE
		sk2.glossary = "部署"
		sk2.description = "[部署]获得 [%d] 层装甲效果（受到的每次伤害 -1）" % armor
		sk2.effects = [make_armor(armor)]
		out.append(sk2)
	return out


## 造一个「装甲」效果（减伤 N）
static func make_armor(n: int) -> EffectData:
	var e := EffectData.new()
	e.id = Uuid.generate()
	e.display_name = "装甲"
	e.dmg_reduce = n
	e.duration = -1
	e.is_debuff = false
	e.allow_queen = true
	e.allow_soldier = true
	e.allow_building = true
	return e


## ============================================================
## 卡池（**10 张**，逐行对照 `单位表格-测试用.xlsx`）
##   cost      = 部署费用
##   atk/hp    = 攻击力 / 血量（指令卡用 dmg/heal）
##   move/range= 移动速度 / 射程
##   refund    = 每回合回费（蜂王 / 资源建筑）
## ============================================================
const CARDS: Array = [
	# ① 金刚蜂王 · 蜂王 · 攻2 射1 移1 血12 费0 · [回费]回复四点费用 / [部署]获得[装甲]
	{
		"name": "金刚蜂王", "kind": CardData.CardKind.QUEEN,
		"cost": 0, "atk": 2, "hp": 12, "move": 1, "range": 1, "refund": 4,
		"dmg": 0, "heal": 0, "aoe": 0, "chain": 0,
		"deploy_armor": 2, "support_refund": 0, "support_range": 0,
		"glossary": "[回费]", "skill": S_QUEEN, "desc": D_QUEEN, "tags": T_QUEEN,
	},
	# ② 叶蜂 · 兵蜂 · 攻2 射1 移2 血2 费2 · [被动]在敌方领地时攻击 ×2
	{
		"name": "叶蜂", "kind": CardData.CardKind.SOLDIER,
		"cost": 2, "atk": 2, "hp": 2, "move": 2, "range": 1, "refund": 0,
		"dmg": 0, "heal": 0, "aoe": 0, "chain": 0,
		"mul_foe_territory": 2.0,
		"glossary": "[被动]", "skill": S_LEAF, "desc": D_LEAF, "tags": T_SOLDIER,
	},
	# ③ 泥蜂 · 兵蜂 · 攻4 射2 移1 血6 费4 · 无
	{
		"name": "泥蜂", "kind": CardData.CardKind.SOLDIER,
		"cost": 4, "atk": 4, "hp": 6, "move": 1, "range": 2, "refund": 0,
		"dmg": 0, "heal": 0, "aoe": 0, "chain": 0,
		"glossary": "", "skill": "", "desc": D_NONE, "tags": T_SOLDIER,
	},
	# ④ 熊蜂 · 兵蜂 · 攻5 射2 移1 血10 费8 · [被动]对蜂王 ×2 / [支援]回复 3 费
	{
		"name": "熊蜂", "kind": CardData.CardKind.SOLDIER,
		"cost": 8, "atk": 5, "hp": 10, "move": 1, "range": 2, "refund": 0,
		"dmg": 0, "heal": 0, "aoe": 0, "chain": 0,
		"mul_vs_queen": 2.0, "support_refund": 3, "support_range": 0,
		"glossary": "[被动]", "skill": S_BUMBLE, "desc": D_BUMBLE, "tags": T_SOLDIER,
	},
	# ⑤ 电击 · 指令 · 伤2 费2 · 与目标接触及间接接触的单位同受伤害
	{
		"name": "电击", "kind": CardData.CardKind.COMMAND,
		"cost": 2, "atk": 0, "hp": 0, "move": 0, "range": 0, "refund": 0,
		"dmg": 2, "heal": 0, "aoe": 0, "chain": 99,
		"glossary": "[指令]", "skill": S_SHOCK, "desc": D_SHOCK, "tags": T_COMMAND,
	},
	# ⑥ 电击III · 指令 · 伤8 费6 · 同上（表里写「电机III」，按素材判为错别字 → 电击III）
	{
		"name": "电击III", "kind": CardData.CardKind.COMMAND,
		"cost": 6, "atk": 0, "hp": 0, "move": 0, "range": 0, "refund": 0,
		"dmg": 8, "heal": 0, "aoe": 0, "chain": 99,
		"glossary": "[指令]", "skill": S_SHOCK, "desc": D_SHOCK, "tags": T_COMMAND,
	},
	# ⑦ 巡航导弹 · 指令 · 伤6 射1 费6 · 对效果范围内所有单位造成伤害
	{
		"name": "巡航导弹", "kind": CardData.CardKind.COMMAND,
		"cost": 6, "atk": 0, "hp": 0, "move": 0, "range": 1, "refund": 0,
		"dmg": 6, "heal": 0, "aoe": 1, "chain": 0,
		"glossary": "[指令]", "skill": S_MISSILE, "desc": D_MISSILE, "tags": T_COMMAND,
	},
	# ⑧ 治疗 · 指令 · 回复3 费2 · 为一个己方单位回复 3 血（**示范卡组不含它**）
	{
		"name": "治疗", "kind": CardData.CardKind.COMMAND,
		"cost": 2, "atk": 0, "hp": 0, "move": 0, "range": 0, "refund": 0,
		"dmg": 0, "heal": 3, "aoe": 0, "chain": 0,
		"glossary": "[指令]", "skill": S_HEAL, "desc": D_HEAL, "tags": T_HEAL,
	},
	# ⑨ 蜂巢 · 建筑 · 血5 费3 · [回费]回复 1 费
	{
		"name": "蜂巢", "kind": CardData.CardKind.BUILDING,
		"cost": 3, "atk": 0, "hp": 5, "move": 0, "range": 0, "refund": 1,
		"dmg": 0, "heal": 0, "aoe": 0, "chain": 0,
		"glossary": "[回费]", "skill": S_HIVE, "desc": D_HIVE1, "tags": T_BUILDING,
	},
	# ⑩ 蜂巢III · 建筑 · 血9 费5 · [回费]回复 3 费
	{
		"name": "蜂巢III", "kind": CardData.CardKind.BUILDING,
		"cost": 5, "atk": 0, "hp": 9, "move": 0, "range": 0, "refund": 3,
		"dmg": 0, "heal": 0, "aoe": 0, "chain": 0,
		"glossary": "[回费]", "skill": S_HIVE, "desc": D_HIVE3, "tags": T_BUILDING,
	},
]


## ============================================================
## 示范卡组（**1 蜂王 + 8 常规卡；不含治疗**）
##   ⚠️ 顺序有语义：**前 4 张 = 初始手牌**（a500）→ 故意排成不同费用便于目视验证
## ============================================================
const DECK_NAMES: Array = [
	"叶蜂", "泥蜂", "熊蜂", "电击",          # 前 4 张 = 初始手牌（费 2 / 4 / 8 / 2）
	"电击III", "巡航导弹", "蜂巢", "蜂巢III",  # 后 4 张 = 备卡
]


## 构造示范卡组（每次调用生成**新的 UUID**，可安全用于双方各一份）
static func build(deck_name: String = "示范卡组") -> DeckData:
	var dd := DeckData.new()
	dd.id = Uuid.generate()
	dd.display_name = deck_name
	var by_name := {}
	for spec in CARDS:
		var c := make(spec)
		by_name[spec["name"]] = c
		if c.kind == CardData.CardKind.QUEEN:
			dd.queen = c
	for nm in DECK_NAMES:
		if by_name.has(nm):
			dd.cards.append(by_name[nm])
	return dd


## 按卡名取一张新卡（不在表中 → null）
static func card(nm: String) -> CardData:
	for spec in CARDS:
		if spec["name"] == nm:
			return make(spec)
	return null


## 卡名清单
static func names() -> Array:
	var out: Array = []
	for spec in CARDS:
		out.append(spec["name"])
	return out
