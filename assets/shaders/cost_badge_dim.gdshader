shader_type canvas_item;

// 费用角标「**底色变灰**」。人 2026-10-17 口径：变的是**底色（六边形内部填充）**，
// 不是给整张图叠一层滤镜 —— 所以不能用 `self_modulate`/`modulate`（那会把深棕描边一起染灰）。
// 做法：按度把像素分成「填充（亮）」与「描边（暗）」，**只把填充替换成灰**，描边保持原色。
// 实测贴图：深棕外描边 + 亮橙内部填充（实心不透明、扁平风格）。
uniform float dim : hint_range(0.0, 1.0) = 0.0;
// 填充/描边的亮度分界（默认值按“橙≈0.68、深棕≈0.24”取中）
uniform float fill_luma_min : hint_range(0.0, 1.0) = 0.35;
uniform float fill_luma_max : hint_range(0.0, 1.0) = 0.55;
// 灰色底色的亮度
uniform float grey_level : hint_range(0.0, 1.0) = 0.42;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float is_fill = smoothstep(fill_luma_min, fill_luma_max, luma);
	vec3 grey = vec3(grey_level);
	COLOR = vec4(mix(c.rgb, grey, is_fill * dim), c.a);
}
