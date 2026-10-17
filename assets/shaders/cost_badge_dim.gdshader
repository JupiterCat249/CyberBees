shader_type canvas_item;

// 费用角标「换色」（人 2026-10-17 第三轮定案）：填充与描边**各自换成指定色**，
// 而不是乘色（`self_modulate` / `modulate` 会把深棕描边乘成别的暗色，而非我们指定的灰）。
//
// ⚠️ **2026-10-17 第四轮补：必须把父级的 modulate 级联乘回来**。
//   `texture(TEXTURE, UV)` 只拿纹理、**丢掉顶点色 `COLOR`**（其中含父节点级联下来的 modulate），
//   于是“非行动方整卡变黑 0.22”在这个图标上不生效 —— 表现为
//   “只有费用数字被压暗、费用图标没被压暗”（数字是普通 Label，不走本 shader，所以照常被压暗）。
//   修法：最终色 = （换色后的纹理色）× COLOR。
//   注意 `luma` 判定仍用**纹理原色**（不受 modulate 影响），否则暗环境会把填充误判成描边。

// 0 = 正常原色；1 = 换成指定色（但都会被父级 modulate 再乘一次）
uniform float dim : hint_range(0.0, 1.0) = 0.0;
uniform float fill_luma_min : hint_range(0.0, 1.0) = 0.35;
uniform float fill_luma_max : hint_range(0.0, 1.0) = 0.55;
// 灰化后的目标色：填充（浅灰）与描边（深灰）
uniform vec3 fill_grey : source_color = vec3(0.42, 0.42, 0.42);
uniform vec3 stroke_grey : source_color = vec3(0.24, 0.24, 0.24);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// 用纹理原色判断区域，不受父级变黑影响
	float luma = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float is_fill = smoothstep(fill_luma_min, fill_luma_max, luma);
	vec3 target = mix(stroke_grey, fill_grey, is_fill);
	vec3 recolored = mix(tex.rgb, target, dim);
	// ★ 乘 COLOR：保留父级 modulate（整卡变黑/变灰都会作用到本图标上）
	COLOR = vec4(recolored, tex.a) * COLOR;
}
