class_name CommandData
extends CardData
## 指令卡静态数据（非单位）

@export_group("效果")
@export var dmg: int = 0                       ## 指令伤害
@export var heal: int = 0                      ## 治疗量
@export var target_range: int = 0              ## 射程（格）
@export var aoe_span: int = 0                  ## 扩散半径（0 = 单体）
@export var chain_span: int = 0                ## 链式传播范围（上下左右）
@export var x_cost_multiplier: int = 0         ## X 费卡：伤害 = 目标部署费 × N
@export var self_to_graveyard: bool = false    ## 使用后返回墓地

@export_group("施加效果")
@export var apply_effects: Array[EffectData] = []


func validate() -> Array[String]:
	var errs := super.validate()
	if dmg < 0 or heal < 0:
		errs.append("CommandData[%s] dmg/heal 为负" % display_name)
	if target_range < 0:
		errs.append("CommandData[%s] target_range 为负" % display_name)
	if kind == CardKind.COMMAND_X and x_cost_multiplier < 1:
		errs.append("CommandData[%s] COMMAND_X 需 x_cost_multiplier >= 1" % display_name)
	return errs
