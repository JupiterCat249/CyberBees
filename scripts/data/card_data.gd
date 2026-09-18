class_name CardData
extends Resource
## 卡牌基类（静态数据 · 值对象）
## 设计要点（见设计案 §3.3 R1）：**本类不含任何运行态字段**
##   —— 无 current_hp / 无 position / 无 has_acted / 无 effects
##   Godot 对同一路径的资源只加载一份实例（手册），写运行态会污染全场 → 运行态放 UnitInstance

enum CardKind { QUEEN, SOLDIER, BUILDING, COMMAND, COMMAND_X }

@export var id: String = ""                       ## UUID（D-4）
@export var display_name: String = ""             ## 卡名
@export var kind: CardKind = CardKind.SOLDIER
@export var cost: int = 0                         ## 部署费；X 费卡 = -1
@export var glossary: String = ""                 ## 技能前缀，如「机场」「指令」「支援」
@export var skill_name: String = ""               ## 技能名（详情区标题：卡名 · 技能名）
@export var description: String = ""              ## 技能描述（详情区正文）
@export var tags: String = ""                     ## 标签，如「被动 · 部署 · 蜂王」
@export var visual: CardVisual                    ## 视觉数据
@export var skills: Array[SkillData] = []         ## 技能（主动/支援/被动）


## 卡牌类型色（A5 §五 颜色图鉴 · D4）
static func type_color_of(k: CardKind) -> Color:
	match k:
		CardKind.QUEEN:    return Color("#FFD07E")
		CardKind.BUILDING: return Color("#DDC29B")
		CardKind.COMMAND, CardKind.COMMAND_X: return Color("#D9D9D9")
		_:             return Color("#FFFFFF")


## 阵营色（D3）
static func faction_color_of(side: int) -> Color:
	return Color("#3B816D") if side == 0 else Color("#A84331")


func is_unit() -> bool:
	return kind == CardKind.QUEEN or kind == CardKind.SOLDIER or kind == CardKind.BUILDING


func validate() -> Array[String]:
	var errs: Array[String] = []
	if id == "" or not Uuid.is_valid(id):
		errs.append("CardData[%s] id 非 UUID：%s" % [display_name, id])
	if display_name == "":
		errs.append("CardData[%s] display_name 为空" % id)
	if kind == CardKind.COMMAND_X:
		if cost != -1:
			errs.append("CardData[%s] COMMAND_X 的 cost 应为 -1" % display_name)
	elif cost < 0:
		errs.append("CardData[%s] cost 为负" % display_name)
	for s in skills:
		if s == null:
			errs.append("CardData[%s] skills 含 null" % display_name)
		elif (s as SkillData).id == "":
			errs.append("CardData[%s] 引用的 SkillData 缺 id" % display_name)
	return errs
