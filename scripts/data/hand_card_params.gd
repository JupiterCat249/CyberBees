class_name HandCardParams
extends Resource
## **手牌卡内部元素参数**（供 UI 调用的资源类）
##
## ⚠️ 人指示（迭代057）：详情区与手牌卡**各自用一套 UI 参数**，不要混用。
##   本类只管**手牌卡**（`card_hand.tscn`）的内部元素；详情区用 `DetailParams`。
##
## 为什么要分开（两者量级差很大，是实测值不是拍脑袋）：
##   · 手牌卡：卡只有 **200×200**；但立绘源图基准是 **400×454**（快赶上卡的两倍）
##     → 所以立绘必须靠 **缩放 + 偏移** 才能把要的部分塞进 200×200 的裁剪窗；
##       徽章只有 **60×65**，字号也小。
##   · 详情区：立绘槽直接是 **300×300**，卡名 38px / 描述 25px。
##   若两处共用一套参数，必然一边被裁掉或一边过小。

## ============ 卡尺寸（容器靠它算 cell）============
@export var card_size: Vector2 = Vector2(200, 200)

## ============ 立绘（Image 在 ArtPlane 裁剪窗内的位置与缩放）============
## 基准位置（原始设计值）：ArtPlane 在 (0,0)，Image 相对它偏 (-5, -100) 左右
@export var art_base_offset: Vector2 = Vector2(-100, -100)
@export var art_base_scale: Vector2 = Vector2(1.0, 1.0)
## 逐卡微调增量（推荐平时只改这个）
@export var crop_offset: Vector2 = Vector2.ZERO
@export var crop_scale: float = 0.0            ## <=0 = 用 base_scale

## ============ 徽章（费用数字）============
@export var badge_size: Vector2 = Vector2(60, 65)
@export var badge_pos: Vector2 = Vector2(0, 0)
## ⚠️ 0 = 沿用素材场景原值（当前 48）。人 2026-09-19：不要改字号（曾被覆盖成 26 → 变小）
@export var badge_font_size: int = 0
@export var badge_color: Color = Color(1, 1, 1, 1)

## ============ 描边 ============
@export var inner_line_size: Vector2 = Vector2(200, 200)


## 由卡视觉数据 + 本参数算出最终立绘位置（视图直接拿去设 offset）
func final_art_offset(vis: CardVisual) -> Vector2:
	var off := art_base_offset + crop_offset
	if vis != null:
		off += vis.crop_offset
	return off


func final_art_scale(vis: CardVisual) -> Vector2:
	if vis != null and vis.crop_scale > 0.0:
		return Vector2(vis.crop_scale, vis.crop_scale)
	if crop_scale > 0.0:
		return Vector2(crop_scale, crop_scale)
	return art_base_scale


func describe() -> String:
	return "HandCardParams(card=%s, art=%.0fx%.0f, badge=%s)" % [
		str(card_size), art_base_scale.x * 400.0, art_base_scale.y * 454.0, str(badge_size)]
