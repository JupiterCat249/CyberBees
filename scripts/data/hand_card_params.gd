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
## ⚠️ **已废弃（人 2026-10-05 裁定「标记废弃」）**：全项目**无任何代码消费本字段** ——
##   `arena_view._apply_one_hand_params()` 只读 `badge_size` 与 `badge_font_size`。
##   保留字段仅为兼容既有 `.tres` 的反序列化；**新代码勿用**。
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


## 该卡种的立绘缩放。
## ⭐ 迭代067 补（人 2026-10-15 反馈「除兵蜂外其他单位的 UI 参数都无法改变其手牌的牌面」）：
##   **优先级改为「显式逐卡缩放 > 参数全局缩放 > 卡种表 > 基准」** —— 此前是"卡种表优先"，
##   于是蜂王/建筑/指令三型**永远拿表值 0.5**，`crop_scale` 怎么调都不生效 ✗。
##   改后：表值仍是**默认**（不调参时行为与之前逐字一致），但**显式给了 crop_scale 就能覆盖** ✓
func art_scale_for_key(kind_key: String, vis: CardVisual) -> Vector2:
	## ① 逐卡视觉数据显式给的缩放（最强）—— **同样要过 `_scale_ok`**：
	##    ⚠️ 漏了这一处，实测那张 `crop_scale=80` 的指令卡仍会 `img.scale=(80,80)` ✗
	##    （第一次修就踩了：只钳了 `final_art_scale`，而本函数才是 `_apply_one_hand_params` 走的那条）
	if vis != null and _scale_ok(vis.crop_scale):
		return Vector2(vis.crop_scale, vis.crop_scale)
	## ② 参数资源显式给的全局缩放
	if _scale_ok(crop_scale):
		return Vector2(crop_scale, crop_scale)
	## ③ 卡种表（兵蜂 key="unit" 不在表里 ⇒ 落到 ④）
	if kind_key != "" and kind_art_scale.has(kind_key):
		var v := float(kind_art_scale[kind_key])
		if v > 0.0:
			return Vector2(v, v)
	## ④ 基准
	return final_art_scale(vis)


## 该卡种是否"缩放后居中展示"（兵蜂不居中、保持原偏移链）
func should_center_key(kind_key: String) -> bool:
	return kind_center and kind_key != "" and kind_art_scale.has(kind_key)


func final_art_offset(vis: CardVisual) -> Vector2:
	var off := art_base_offset + crop_offset
	if vis != null:
		off += vis.crop_offset
	return off


## ⭐ 迭代067 补（人 2026-10-15 反馈「除兵蜂外其他单位的 UI 参数都无法改变其手牌的牌面」）：
##   **真因**：`CardVisual.crop_scale` 的默认值是 **1.0**（而注释与参数侧都约定"0 = 不覆盖"），
##   于是**每张卡都算"显式给了缩放"** ⇒ 参数侧的 `crop_scale` **永远被抢先**，改参数当然没反应 ✗。
##   个别卡还把它填成了 **80**（量级明显误填：实测该卡 `img.scale=(80,80)`、偏移 -15903，卡面早废）。
##   **修法**：① 只接受**合理区间**内的值（越界视为误填 ⇒ 忽略并回落）；
##           ② `CardVisual.crop_scale` 默认值改为 0.0（与"0 = 不覆盖"一致，见 card_visual.gd）。
const ART_SCALE_MIN := 0.05      ## 小于此视为"没填/误填"
const ART_SCALE_MAX := 4.0       ## 大于此视为误填（正常立绘缩放不会超过 4 倍）


## 读作"有效缩放"：必须落在 [ART_SCALE_MIN, ART_SCALE_MAX]
func _scale_ok(v: float) -> bool:
	return v >= ART_SCALE_MIN and v <= ART_SCALE_MAX


func final_art_scale(vis: CardVisual) -> Vector2:
	if vis != null and _scale_ok(vis.crop_scale):
		return Vector2(vis.crop_scale, vis.crop_scale)
	if _scale_ok(crop_scale):
		return Vector2(crop_scale, crop_scale)
	return art_base_scale


func describe() -> String:
	return "HandCardParams(card=%s, art=%.0fx%.0f, badge=%s)" % [
		str(card_size), art_base_scale.x * 400.0, art_base_scale.y * 454.0, str(badge_size)]
