class_name DetailParams
extends Resource
## **详情区（信息面板）参数**（供 UI 调用的资源类）
##
## ⚠️ 人指示（迭代057）：详情区与手牌卡**各自用一套 UI 参数**，不要混用。
##   本类只管**详情区**（`HUD/InfoPanel`）；手牌卡用 `HandCardParams`。
##
## 与手牌卡的关键差异（所以必须分开）：
##   | 项 | 详情区 | 手牌卡 |
##   |---|---|---|
##   | 立绘槽 | 300 x 300（**原尺寸直接放**） | 200 x 200（卡小，立绘源图 400x454 必须缩放 + 偏移） |
##   | 卡名字号 | 38 px | 无（手牌不显示卡名） |
##   | 描述字号 | 25 px | 无 |
##   | 四维行数 | 4 行（图标 + 数值） | 无（手牌只有费用徽章） |
##   | 费用徽章 | 无 | 60 x 65 + 26px |

## ============ 立绘槽 ============
@export var art_size: Vector2 = Vector2(300, 300)
## 立绘源图基准尺寸（详情区与手牌卡共用同一批卡面素材，但显示尺寸不同）
@export var art_base_scale: Vector2 = Vector2(1.0, 1.0)
@export var crop_offset: Vector2 = Vector2.ZERO
@export var crop_scale: float = 0.0            ## <=0 = 用 base_scale

## ============ 文字（**默认 0 = 沿用素材场景原值，不覆盖字号**）============
## ⚠️ 人 2026-09-19 明确：不要改字号。故默认全 0（不改），
##    只有显式设成正数时才覆盖 —— 便于日后按实测反馈单独调整某处。
@export var name_font_size: int = 0            ## 0 = 沿用素材（当前 38）
@export var desc_font_size: int = 0            ## 0 = 沿用素材（当前 25）
@export var desc_line_spacing: int = 0
@export var name_color: Color = Color(1, 1, 1, 1)
@export var desc_color: Color = Color(0.86, 0.88, 0.9, 1)

## ============ 四维行 ============
@export var attr_rows: int = 4
@export var attr_value_font_size: int = 0      ## 0 = 沿用素材（当前 42；曾被误覆盖成 24）
@export var attr_icon_size: Vector2 = Vector2(24, 24)

## 操作反馈提示标签（**运行时新建的节点**，非既有素材节点）
@export var msg_font_size: int = 24


func final_art_scale(vis: CardVisual) -> Vector2:
	if vis != null and vis.crop_scale > 0.0:
		return Vector2(vis.crop_scale, vis.crop_scale)
	if crop_scale > 0.0:
		return Vector2(crop_scale, crop_scale)
	return art_base_scale


func final_art_offset(vis: CardVisual) -> Vector2:
	var off := crop_offset
	if vis != null:
		off += vis.crop_offset
	return off


func describe() -> String:
	return "DetailParams(art=%s, name=%dpx, desc=%dpx)" % [str(art_size), name_font_size, desc_font_size]
