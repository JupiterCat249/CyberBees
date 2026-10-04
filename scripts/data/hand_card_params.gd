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
## ============ 共通：卡面类型底色与条纹（人 2026-10-05 修正口径）============
## ⚠️ **底色＝「单位类型底色」，不是阵营色**（人明确修正："阵营底色不用搞，这个是我的口误"）。
##   类型色的**唯一真值来源＝`CardData.type_color_of(kind)`**，与策划案 §五 颜色图鉴逐字一致：
##     蜂王 `#FFD07E` · 建筑 `#DDC29B` · 指令 `#D9D9D9` · 兵蜂/普通 `#FFFFFF`
##   （⚠️ 迭代064 机制-3 曾在这四个里自造三个错色：建筑用灰 `#5D5D5D`、指令用阵营红 `#A84331`、
##     普通用阵营绿 `#3B816D` —— 与策划案冲突，已被本参数口径取代。）
##   条纹＝**白色条纹 10% 透明度**，原色复用素材 `assets/ui/fx/crt_scanline_tile.png`
##   （单位卡 `CrtFx` 已在用同一素材）。路径由使用方 `load()`，本类不做 preload。
@export_range(0.0, 1.0) var type_base_alpha: float = 1.0   ## 类型底色不透明度（策划案：100%）
@export_range(0.0, 1.0) var stripe_alpha: float = 0.1      ## 白色条纹不透明度（策划案：10%）
const STRIPE_TEXTURE_PATH := "res://assets/ui/fx/crt_scanline_tile.png"

## ============ 按卡种的手牌立绘参数（人 2026-10-05 指示）============
##   兵蜂（`SOLDIER`，键 `"unit"`）= **UI 参数不变** → 沿用 `art_base_offset` / `art_base_scale` / 逐卡 crop
##   其余三型（蜂王 `"queen"` / 建筑 `"building"` / 指令 `"order"`）= **缩放 50% 并居中展示**
##   ⚠️ 键用**字符串**（由调用方 `arena_view` 从 `CardData.kind` 转好传入）——
##      参数类**不得**引用 `CardData`，否则 Resource 间 class_name 依赖会导致 reload 失败（实测 ✗）。
@export var kind_art_scale: Dictionary = {"queen": 0.5, "building": 0.5, "order": 0.5}
@export var kind_center: bool = true


## 该卡种的立绘缩放：命中 `kind_art_scale` → 用表值；否则（兵蜂/未知）→ 沿用原参数链
func art_scale_for_key(kind_key: String, vis: CardVisual) -> Vector2:
	if kind_key != "" and kind_art_scale.has(kind_key):
		var v := float(kind_art_scale[kind_key])
		if v > 0.0:
			return Vector2(v, v)
	return final_art_scale(vis)


## 该卡种是否"缩放后居中展示"（兵蜂不居中、保持原偏移链）
func should_center_key(kind_key: String) -> bool:
	return kind_center and kind_key != "" and kind_art_scale.has(kind_key)


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
