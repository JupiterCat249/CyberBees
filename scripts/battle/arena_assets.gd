class_name ArenaAssets
extends Resource
## 战斗场景**资产资源**（地图板 + 背景）—— **供 UI 调用的资源类**
##
## 人指示（迭代057）：「`Battle/MapView/MapPlate/TextureRect` 和 `Background/TextureRect`
##   已经完成了（图片 UI 节点），你需要做的是**解耦调用**（如信号 + 信号传参）两个节点来实现地图变化」
##
## 设计
##   · 两个 TextureRect **互不引用**：各自订阅 `BattleSignalBus.SIG_MAP_ASSETS`，
##     从**同一条信号的不同参数**取自己要的贴图 —— 这就是"信号 + 信号传参"的解耦。
##   · 地图变化（换图）时只需引擎再广播一次，两个节点自动跟着变。
##   · 本资源**只管资产**，不碰规则、不碰节点。
##
## 两类资产
##   · `map_texture`        -> `Battle/MapView/MapPlate/TextureRect`（地图板，盖在棋盘下）
##   · `background_texture` -> `Background/TextureRect`（全局背景）

## 地图板贴图（来自 MapData.terrain_texture）
@export var map_texture: Texture2D
## 全局背景贴图（来自 MapData.background_texture）
@export var background_texture: Texture2D
## 地图显示名（UI 可显示）
@export var map_name: String = ""
## 地图描述（UI 可显示）
@export var map_desc: String = ""
## 地图板是否应显示（无贴图时视图可隐藏它）
@export var has_map: bool = false


## 由 MapData 构造（md 可为 null，此时只填背景回退值）
static func make(md: MapData, fallback_bg: Texture2D = null):
	## ⚠️ 返回值不写 `-> ArenaAssets`：新建 class_name 注册前自引用会报 Identifier not found
	var a = load("res://scripts/battle/arena_assets.gd").new()
	if md != null:
		a.map_texture = md.terrain_texture
		a.background_texture = md.background_texture
		a.map_name = md.display_name
		a.map_desc = md.description
		a.has_map = md.terrain_texture != null
	if a.background_texture == null:
		a.background_texture = fallback_bg
	return a


## 仅换背景（主题/灯光切换用）
func with_background(tex: Texture2D):
	background_texture = tex
	return self


## 仅换地图板
func with_map(tex: Texture2D, name_: String = ""):
	map_texture = tex
	has_map = tex != null
	if name_ != "":
		map_name = name_
	return self


func describe() -> String:
	return "ArenaAssets(map=%s, bg=%s, has_map=%s)" % [
		"有" if map_texture != null else "无",
		"有" if background_texture != null else "无",
		str(has_map)]
