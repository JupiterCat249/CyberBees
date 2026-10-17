shader_type canvas_item;

// 费用角标「换色」。人 2026-10-17 第三轮口径：
//   **底色（内部填充）与描边都是「换色」，不是加滤镜，也不是保持原色**。
//   ⇒ 灰化时：填充换成 fill_grey、描边换成 stroke_grey（两者都是**直接指定的颜色**，
//     而不是把原色乘一个系数）；正常时（dim=0）完全保留贴图原色。
//   ⚠️ 不能用 self_modulate / modulate：那是**乘色**，深棕描边会被乘成另一个暗色、
//     而不是我们指定的那个灰。
// 实测贴图：深棕外描边（luma≈0.24）+ 亮橙内部填充（luma≈0.68），实心不透明、扁平风格。

// 0 = 正常原色；1 = 完全换成指定色
uniform float dim : hint_range(0.0, 1.0) = 0.0;
// 填充/描边的亮度分界（默认按“橙≈0.68、深棕≈0.24”取中）
uniform float fill_luma_min : hint_range(0.0, 1.0) = 0.35;
uniform float fill_luma_max : hint_range(0.0, 1.0) = 0.55;
// 灰化后的目标色：填充（浅灰）与描边（深灰）
uniform vec3 fill_grey : source_color = vec3(0.42, 0.42, 0.42);
uniform vec3 stroke_grey : source_color = vec3(0.24, 0.24, 0.24);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float is_fill = smoothstep(fill_luma_min, fill_luma_max, luma);
	// 两区各自的目标色
	vec3 target = mix(stroke_grey, fill_grey, is_fill);
	// dim=1 时**两区都完全换成 target**（描边也换，不是保持原色）
	COLOR = vec4(mix(c.rgb, target, dim), c.a);
}
