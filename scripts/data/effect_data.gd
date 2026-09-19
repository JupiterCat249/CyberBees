class_name EffectData
extends Resource
## 效果（buff / 减益）静态数据 —— A5 十种效果
## id 为 UUID（D-4）；T14：相同效果最多一个 → stacking 固定 NONE
##
## 迭代055 新增「条件倍伤」字段，用于卡牌自带被动的落地：
##   · `atk_mul_vs_queen`         攻击**蜂王**时倍伤（1.0 = 不生效）→ 熊蜂 `对蜂王伤害[*2]`
##   · `atk_mul_in_foe_territory` 在**敌方领地**时倍伤（1.0 = 不生效）→ 叶蜂 `在敌方领地攻击[2]倍`

enum Stacking { NONE }

@export var id: String = ""                          ## UUID（D-4）
@export var display_name: String = ""                ## 显示名（如「灼烧」）
@export var icon: Texture2D                          ## 状态图标（assets/status_icons/）
@export var stacking: Stacking = Stacking.NONE       ## T14：不叠加
@export var duration: int = -1                       ## -1 = 永久（直到被移除）

@export_group("数值修正")
@export var atk_add: int = 0                         ## 攻击力 +N
@export var atk_mul: float = 1.0                     ## 攻击力 ×N（乘优先于加）
@export var dmg_reduce: int = 0                      ## 伤害减免（**已不用于装甲**；装甲走 blocks_attack）
@export var dot_per_turn: int = 0                    ## 回合结束扣血（灼烧）
@export var heal_per_turn: int = 0                   ## 回合结束回血

@export_group("条件倍伤（被动）")
@export var atk_mul_vs_queen: float = 1.0            ## 攻击蜂王时 ×N（熊蜂 [对蜂王伤害*2]）
@export var atk_mul_in_foe_territory: float = 1.0    ## 在敌方领地时 ×N（叶蜂 [被动]）

@export_group("标记")
@export var is_debuff: bool = false                  ## true=减益（上侧） / false=增益（下侧）
@export var grants_field: bool = false               ## 力场：相邻授予
@export var blocks_command: bool = false             ## 护盾/力场：抵挡指令卡伤害（T14 人明确）
## ⭐ 抵挡型效果（迭代059）：**抵挡一次攻击，参与防御计算则消失**（设计原文）
##   装甲 / 护盾 / 力场 均为 true。不论伤害高低都**完全抵挡**，随后消失。
##   ⚠️ 这是**显式语义字段**，不要用"dmg_reduce > 0"来推断（装甲的 dmg_reduce 为 0）。
@export var blocks_attack: bool = false

@export_group("可赋予的单位类型（a500：单位类型不匹配则无法赋予效果）")
@export var allow_queen: bool = true
@export var allow_soldier: bool = true
@export var allow_building: bool = true


## 单位类型是否可被赋予本效果（a500：单位类型不匹配则无法赋予效果）
func allows_kind(k: CardData.CardKind) -> bool:
	match k:
		CardData.CardKind.QUEEN:    return allow_queen
		CardData.CardKind.SOLDIER:  return allow_soldier
		CardData.CardKind.BUILDING: return allow_building
		_:                          return false


func validate() -> Array[String]:
	var errs: Array[String] = []
	if id == "" or not Uuid.is_valid(id):
		errs.append("EffectData[%s] id 非 UUID：%s" % [display_name, id])
	if display_name == "":
		errs.append("EffectData[%s] display_name 为空" % id)
	if atk_mul < 0.0:
		errs.append("EffectData[%s] atk_mul 为负" % display_name)
	if atk_mul_vs_queen < 0.0 or atk_mul_in_foe_territory < 0.0:
		errs.append("EffectData[%s] 条件倍伤为负" % display_name)
	return errs
