shader_type canvas_item;

// 费用角标：**换色** + **随卡叠加滤镜**（人 2026-10-17 口径）
//   ① 换色（dim = 1）：填充 → fill_grey、描边 → stroke_grey（两区各自换成指定色，不是乘色）
//   ② 叠加滤镜（card_dim）：整张图标乘同一系数，使其与卡面一起被“盖暗”
//      —— 由本 shader 自己乘，而不是靠父级 modulate：
//         卡面滤镜已改为施加在 `Body` / `Artwork` / `InnerLine` 上，费用数字 `Value` 被排除在外；
//         图标必须自己接这一层，否则会被“跳过”（人报过这个现象）。
// 实测贴图：深棕外描边（luma≈0.24）+ 亮橙内部填充（luma≈0.68），实心不透明、扁平风格。

// 0 = 正常原色；1 = 完全换成指定色
uniform float dim : hint_range(0.0, 1.0) = 0.0;
// 整卡叠加滤镜系数（1.0 = 行动方；0.22 = 非行动方）
uniform float card_dim : hint_range(0.0, 1.0) = 1.0;
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
	// ① 换色：两区各自换成指定色
	vec3 target = mix(stroke_grey, fill_grey, is_fill);
	vec3 recolored = mix(c.rgb, target, dim);
	// ② 叠加滤镜：与卡面同一系数
	COLOR = vec4(recolored * card_dim, c.a);
}
