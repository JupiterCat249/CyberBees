class_name FxParams
extends Resource
## **视觉特效参数资源**（人 2026-10-23 意见B）
##
## 目标：把散在 view_fx / view_preview / arena_view 里的**颜色 / 字号 / 偏移 / 动画名**收进一个 Resource，
##   让美术可以直接在编辑器里改数值，并配合 `addons/fx_inspector` 的**预览面板**即时看效果。
##
## ⚠️ 默认值必须与"资源化之前的硬编码"逐项一致（改前先跑 test_fx_params 读数对账）。

## ===== 飘字（伤害/治疗等结算浮字）=====
@export_group("飘字")
## 数值越大字体越大：value/ref 的比例在 [base, max] 之间线性映射
@export var float_font_base: int = 24
@export var float_font_max: int = 64
@export var float_font_ref: int = 10
## 相对锚点（单位卡）中心的偏移：x 为"卡宽一半再左移 100"，y 为"卡顶上方多少"
@export var float_offset: Vector2 = Vector2(-100, -20)
@export var float_anim_name: String = "浮字上浮"

## ===== 预览提示（攻击后果：伤害 / 抵挡 / 反击）=====
@export_group("预览提示")
@export var preview_hint_font_size: int = 40
@export var preview_hint_offset: Vector2 = Vector2(-100, -26)
## 我方造成伤害（红）
@export var preview_hint_damage_color: Color = Color(1.0, 0.125, 0.0, 0.9)
## 我方被反击（橙黄）
@export var preview_hint_counter_color: Color = Color(1.0, 0.62, 0.12, 0.9)

## ===== 动画名（与 anims/*.tres 对应）=====
@export_group("动画名")
@export var anim_hit_shake: String = "受击抖动"
@export var anim_retire: String = "单位退场"
@export var anim_card_enter: String = "卡牌登场"


## 便捷：按数值取飘字字号（与资源化前 lerpf 公式一致）
func float_font_size(value: int) -> int:
	var t: float = clampf(float(value) / float(maxi(1, float_font_ref)), 0.0, 1.0)
	return int(round(lerpf(float(float_font_base), float(float_font_max), t)))
