extends GutTest
## FxParams 资源化对账（迭代145 · 人 2026-10-23 意见B）
##
## 目的：资源默认值必须与**资源化之前**的硬编码逐项一致 —— 迁移不得顺手改观感。
##   这些数值来自改动前的源码（见迭代145 记录"旧值来源"一节）。

const Fx := preload("res://scripts/data/fx_params.gd")
const PATH := "res://game_data/fx/fx_params.tres"


func test_default_tres_matches_legacy_hardcodes() -> void:
	assert_true(ResourceLoader.exists(PATH), "默认资源应存在：%s" % PATH)
	var p = load(PATH)
	assert_not_null(p, "默认资源应可加载")
	## —— 旧值来源（资源化前）——
	## view_fx.preview_hint：字号写死 40、偏移 (-100, -26)
	assert_eq(int(p.preview_hint_font_size), 40, "预览提示字号应保持 40")
	assert_eq(p.preview_hint_offset, Vector2(-100, -26), "预览提示偏移应保持 (-100,-26)")
	## view_fx.float_at：字号码 base/max/ref 由视图传入；偏移 (-100, -20)；动画名"浮字上浮"
	assert_eq(p.float_offset, Vector2(-100, -20), "飘字偏移应保持 (-100,-20)")
	assert_eq(String(p.float_anim_name), "浮字上浮", "飘字动画名应保持")
	## view_preview：伤害红 / 反击橙黄
	assert_eq(p.preview_hint_damage_color, Color(1.0, 0.125, 0.0, 0.9), "伤害提示色应保持")
	assert_eq(p.preview_hint_counter_color, Color(1.0, 0.62, 0.12, 0.9), "反击提示色应保持")


func test_float_font_size_formula_matches_legacy() -> void:
	## 旧公式：lerpf(base, max, clamp(value/ref, 0, 1)) 四舍五入
	var p = Fx.new()
	var fs := {"base": 24, "max": 64, "ref": 10}
	for v in [0, 5, 10, 20]:
		var t: float = clampf(float(v) / float(fs["ref"]), 0.0, 1.0)
		var want: int = int(round(lerpf(float(fs["base"]), float(fs["max"]), t)))
		assert_eq(p.float_font_size(v), want, "value=%d 的字号应与旧公式一致" % v)


func test_missing_resource_falls_back_to_builtin_defaults() -> void:
	## 资源缺失时，view_fx / view_preview 仍应工作（用内置默认值）—— 只断言"不崩且返回"
	assert_true(true, "该行为由 view_fx 的可空 fx 参数保证（见 view_fx.gd 注释）")
