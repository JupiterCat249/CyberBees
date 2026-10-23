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
@export var refund_bonus: int = 0                 ## 这些回合额外的回费量（丰饶）
@export var damage_per_round: int = 0             ## 这些回合的掉血（蜂王除外）（寒潮）
@export var grant_field_on_terrain: bool = false  ## 兼容旧字段（新的走 terrain_effect）

@export_group("特殊地形（迭代059 新增 · 人给坐标）")
## 特殊地形格坐标（a500：场地效果作用于**格子上的单位**）
## ⚠️ 内部约定 `Vector2i(行, 列)` 0-based；人给的是 1-based（行,列）→ **减 1**
## 依据：策划案「地形由地图**素材**自带」→ 坐标在制作地图时画好
@export var terrain_cells: Array[Vector2i] = []
## 地形效果资源（语义 + 表现）；为 null 或 kind=NONE 时地形格不产生效果
@export var terrain_effect: TerrainEffect = null


## 该格是否属于特殊地形
func is_terrain_cell(cell: Vector2i) -> bool:
	return terrain_cells.has(cell)


## 取该格的地形效果（无则返回 null）
func effect_at(cell: Vector2i) -> TerrainEffect:
	if terrain_effect == null or not terrain_effect.is_meaningful():
		return null
	if not terrain_cells.has(cell):
		return null
	return terrain_effect


func validate() -> Array[String]:
	var errs: Array[String] = []
	if id == "" or not Uuid.is_valid(id):
		errs.append("MapData[%s] id 非 UUID：%s" % [display_name, id])
	if display_name == "":
		errs.append("MapData[%s] display_name 为空" % id)
	if terrain_texture == null:
		errs.append("MapData[%s] 缺 terrain_texture" % display_name)
	return errs
