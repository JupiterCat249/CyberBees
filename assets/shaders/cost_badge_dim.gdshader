shader_type canvas_item;

// 费用角标：「换色 + 随卡压暗」。人 2026-10-17 要求两点：
//   ① **非行动方时，费用图标要跟着卡面一起变暗**（不能“跳过图标”）；
//   ② **费用数字必须始终保持白色**（不能被整卡滤镜压暗）。
//
// ⇒ 因此**不能用 `HandCard.modulate` 做整卡滤镜**：按引擎文档，`modulate` 会作用到
//   自身**与所有子节点**（`self_modulate` 才只作用于自身）⇒ 必然把 `BadgeImage/Value`
//   （费用数字）一起乘暗，而这正是人要求“始终白”的东西。
//   改为三路分开：
//     · 卡面（Body / Artwork / InnerLine）→ 各自 `self_modulate` 压暗；
//     · 费用图标 → 本 shader 自乘 `card_dim`（即“随卡压暗”）；
//     · 费用数字 → **完全不动**（不在任何 modulate 链下）⇒ 恒白。

// 费用不足 → 换灰（0=原色，1=换成指定色）
uniform float dim : hint_range(0.0, 1.0) = 0.0;
// 整卡压暗系数（1.0 = 行动方正常；0.22 = 非行动方）
uniform float card_dim : hint_range(0.0, 1.0) = 1.0;
// 填充/描边的亮度分界（默认按“橙≈0.68、深棕≈0.24”取中）
uniform float fill_luma_min : hint_range(0.0, 1.0) = 0.35;
uniform float fill_luma_max : hint_range(0.0, 1.0) = 0.55;
// 灰化后的目标色：填充（浅灰）与描边（深灰）
uniform vec3 fill_grey : source_color = vec3(0.42, 0.42, 0.42);
uniform vec3 stroke_grey : source_color = vec3(0.24, 0.24, 0.24);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// 用纹理原色判定区域（不受压暗影响）
	float luma = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float is_fill = smoothstep(fill_luma_min, fill_luma_max, luma);
	// ① 换色：两区各自换成指定色
	vec3 target = mix(stroke_grey, fill_grey, is_fill);
	vec3 recolored = mix(tex.rgb, target, dim);
	// ② 随卡压暗：乘 card_dim（非行动方 0.22）
	COLOR = vec4(recolored * card_dim, tex.a);
}
