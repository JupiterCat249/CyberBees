class_name MapData
extends Resource
## 地图（场地）：本体数据 + 场地效果
## D-5：本轮建立并测试基础；6 张地图的**场地效果细则**策划案尚缺（G-26）→ 此处先定型 schema

@export var id: String = ""                       ## UUID（D-4）
@export var display_name: String = ""             ## 地图名，如「丰饶」
@export var terrain_texture: Texture2D            ## 棋盘底图（1000×1000）
@export var background_texture: Texture2D         ## 全屏背景（1920×1080，可选）
@export var description: String = ""              ## 场地效果描述文本（HUD 显示）

@export_group("场地效果（细则待策划 · G-26）")
@export var effect_rounds: PackedInt32Array = PackedInt32Array()   ## 生效回合，如 [3, 9]
@export var refund_bonus: int = 0                 ## 这些回合额外的回费量
@export var damage_per_round: int = 0             ## 这些回合的掉血（蜂王除外）
@export var grant_field_on_terrain: bool = false  ## 地形格获得「力场」


func validate() -> Array[String]:
	var errs: Array[String] = []
	if id == "" or not Uuid.is_valid(id):
		errs.append("MapData[%s] id 非 UUID：%s" % [display_name, id])
	if display_name == "":
		errs.append("MapData[%s] display_name 为空" % id)
	if terrain_texture == null:
		errs.append("MapData[%s] 缺 terrain_texture" % display_name)
	return errs
