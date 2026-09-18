class_name UnitData
extends CardData
## 单位（蜂王 / 兵蜂 / 建筑）静态数据
## R1：只有 hp **上限**，运行态血量在 UnitInstance

@export_group("四维")
@export var atk: int = 0                       ## 攻击力
@export var hp: int = 1                        ## 生命上限
@export var move: int = 0                      ## 移动速度（格）
@export var attack_range: int = 0              ## 攻击 / 效果范围

@export_group("经济")
@export var refund: int = 0                    ## 每回合回费（蜂王 / 资源建筑）；0 = 不回费

@export_group("规则标记")
@export var immune_command: bool = false       ## 蜂王：免疫指令卡伤害与减益
@export var deploy_adjacent: bool = false      ## 蜂王巢口：只能在自身相邻格部署兵蜂


func validate() -> Array[String]:
	var errs := super.validate()
	if hp < 1:
		errs.append("UnitData[%s] hp 应 >= 1" % display_name)
	if atk < 0:
		errs.append("UnitData[%s] atk 为负" % display_name)
	if move < 0:
		errs.append("UnitData[%s] move 为负" % display_name)
	if attack_range < 0:
		errs.append("UnitData[%s] attack_range 为负" % display_name)
	if refund < 0:
		errs.append("UnitData[%s] refund 为负" % display_name)
	if refund > 0 and kind != CardKind.QUEEN and kind != CardKind.BUILDING:
		errs.append("UnitData[%s] 仅蜂王/建筑可有回费" % display_name)
	return errs
