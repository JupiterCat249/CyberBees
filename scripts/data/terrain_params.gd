class_name TerrainParams
extends Resource
## **特殊地形格的渲染参数**（供 UI 调用的资源类）
##
## 人要求（迭代059）：「相关 UI 同样使用资源实现以便后续更新」+
##                     Q-5「地形格要画」（否则地形格对玩家是不可见的隐藏信息）
##
## 分工
##   · `TerrainEffect`（另一资源）= **语义**（这个格子有什么效果）
##   · `TerrainParams`（本资源）= **怎么画**（叠加色 / 图标尺寸 / 描边 / 提示样式）
##   → 改表现只动本资源，不动代码

## ============ 地形格叠加 ============
## 叠加色透明度（0~1）；底色由 TerrainEffect.tint 提供，这里控整体强度
@export var fill_alpha: float = 0.25
## 是否在地形格上画描边
@export var outline: bool = true
@export var outline_color: Color = Color(1.0, 1.0, 1.0, 0.45)
@export var outline_width: float = 3.0
## 描边向内缩进（避免压住格子边缘）
@export var outline_inset: float = 4.0

## ============ 地形图标 ============
@export var icon_size: Vector2 = Vector2(64, 64)
## 图标位置（相对格子左上角；负数 = 居中）
@export var icon_pos: Vector2 = Vector2(-1, -1)
@export var icon_alpha: float = 0.85

## ============ 提示 ============
## 是否在鼠标悬停时在反馈区显示地形名称/说明
@export var show_hover_hint: bool = true


## 图标在格子内的实际位置（icon_pos 为负时居中）
func icon_offset(cell_size: float) -> Vector2:
	if icon_pos.x < 0.0 or icon_pos.y < 0.0:
		return Vector2((cell_size - icon_size.x) * 0.5, (cell_size - icon_size.y) * 0.5)
	return icon_pos


## 描边矩形（格子尺寸 → 内缩后的 Rect2）
func outline_rect(cell_size: float) -> Rect2:
	var i := outline_inset
	return Rect2(Vector2(i, i), Vector2(cell_size - i * 2.0, cell_size - i * 2.0))


func fill_color_from(tint: Color) -> Color:
	return Color(tint.r, tint.g, tint.b, fill_alpha if fill_alpha > 0.0 else tint.a)


func describe() -> String:
	return "TerrainParams(alpha=%.2f, icon=%s, outline=%s)" % [
		fill_alpha, str(icon_size), str(outline)]
