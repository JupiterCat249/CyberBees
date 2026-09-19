class_name TerrainEffect
extends Resource
## **特殊地形效果资源**（供规则层判定、供 UI 渲染）
##
## a500 依据
##   · 「场地效果」表：铁锈=地形格力场 / 寒潮=回合性掉血 / 禁区=障碍地形无法部署 /
##     丰饶=回合性额外回费 / 水没=地形格减 2 指令伤害 / 默认=无特殊效果
##   · 「效果 3」：地域效果作用于**目标格子上的单位**（不是区域）
##   · 「禁区」明确：障碍地形**不会阻挡移动与攻击**
##
## 设计：语义 + 表现**同在一个资源里** —— UI 直接读本资源渲染（人要求：UI 也资源化）
##
## ⚠️ 工厂方法一律加 `make_` 前缀（避免与 @export 属性同名冲突）

## 地形种类
enum Kind {
	NONE,             ## 无特殊效果（默认地图）
	GRANT_FIELD,      ## 地形格上的单位获得指定效果（铁锈：力场）
	BLOCK_DEPLOY,     ## 地形格不可部署（禁区）；**不阻挡移动与攻击**
	COMMAND_REDUCE,   ## 地形格上的单位受到的指令伤害减少（水没：2）
}

@export var kind: int = Kind.NONE
@export var display_name: String = ""          ## 如「锈蚀地形」
@export var description: String = ""           ## 给玩家看的说明

@export_group("语义参数")
## kind=GRANT_FIELD 时赋予的效果（如力场）
@export var grant_effect: EffectData
## kind=COMMAND_REDUCE 时减免的指令伤害量（水没 = 2）
@export var command_reduce: int = 0
## kind=BLOCK_DEPLOY：是否禁止在该格部署
@export var blocks_deploy: bool = false
## ⚠️ a500 禁区：「无法部署单位，**但不会阻挡移动与攻击**」→ 保持 false
@export var blocks_move: bool = false
@export var blocks_attack: bool = false

@export_group("表现（UI 直接读）")
@export var icon: Texture2D = null             ## 地形图标
@export var tint: Color = Color(1, 1, 1, 0.25) ## 地形格叠加色


## ============ 工厂（make_ 前缀）============

static func make_none():
	var t = load("res://scripts/data/terrain_effect.gd").new()
	t.kind = Kind.NONE
	return t


static func make_grant_field(eff: EffectData, name_: String = "地形"):
	var t = load("res://scripts/data/terrain_effect.gd").new()
	t.kind = Kind.GRANT_FIELD
	t.grant_effect = eff
	t.display_name = name_
	return t


static func make_block_deploy(name_: String = "障碍地形",
		desc: String = "无法部署单位（不阻挡移动与攻击）"):
	var t = load("res://scripts/data/terrain_effect.gd").new()
	t.kind = Kind.BLOCK_DEPLOY
	t.blocks_deploy = true
	t.blocks_move = false          ## a500：不阻挡移动
	t.blocks_attack = false        ## a500：不阻挡攻击
	t.display_name = name_
	t.description = desc
	return t


static func make_command_reduce(n: int, name_: String = "特殊地形"):
	var t = load("res://scripts/data/terrain_effect.gd").new()
	t.kind = Kind.COMMAND_REDUCE
	t.command_reduce = n
	t.display_name = name_
	return t


func is_meaningful() -> bool:
	return kind != Kind.NONE


func describe() -> String:
	return "TerrainEffect(%s, kind=%d, reduce=%d, blockDeploy=%s)" % [
		display_name, kind, command_reduce, str(blocks_deploy)]
