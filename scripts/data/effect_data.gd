class_name EffectData
extends Resource
## 效果（buff / 减益）静态数据 —— A5 十种效果
## id 为 UUID（D-4）；T14：相同效果最多一个 → stacking 固定 NONE

enum Stacking { NONE }

@export var id: String = ""                          ## UUID（D-4）
@export var display_name: String = ""                ## 显示名（如「灼烧」）
@export var icon: Texture2D                          ## 状态图标（assets/status_icons/）
@export var stacking: Stacking = Stacking.NONE       ## T14：不叠加
@export var duration: int = -1                       ## -1 = 永久（直到被移除）

@export_group("数值修正")
@export var atk_add: int = 0                         ## 攻击力 +N
@export var atk_mul: float = 1.0                     ## 攻击力 ×N（乘优先于加）
@export var dmg_reduce: int = 0                      ## 伤害减免
@export var dot_per_turn: int = 0                    ## 回合结束扣血（灼烧）
@export var heal_per_turn: int = 0                   ## 回合结束回血

@export_group("标记")
@export var is_debuff: bool = false                  ## true=减益（上侧） / false=增益（下侧）
@export var grants_field: bool = false               ## 力场：相邻授予


func validate() -> Array[String]:
	var errs: Array[String] = []
	if id == "" or not Uuid.is_valid(id):
		errs.append("EffectData[%s] id 非 UUID：%s" % [display_name, id])
	if display_name == "":
		errs.append("EffectData[%s] display_name 为空" % id)
	if atk_mul < 0.0:
		errs.append("EffectData[%s] atk_mul 为负" % display_name)
	return errs
