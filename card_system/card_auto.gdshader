shader_type canvas_item;
render_mode unshaded;

// ============================================================
// Shader 自动卡牌：整个卡面（250x250 设计坐标）由本 shader 程序化绘制
//   - 卡底圆角 / 侧栏格子 / 横带 / 中央条纹底  → 纯数学，零贴图
//   - 数字（0-9 白字）与图标（8 个白色剪影）   → card_atlas.png 图集
//   - 中央立绘 / 自定义类别图标                → 外部贴图 uniform
// 图标顺序：10攻击 11速度 12血量 13射程 14兵蜂 15建筑 16指令 17蜂王
// ============================================================

// ---------------- 设计坐标系常量（比例对齐目标效果图） ----------------
const float W      = 250.0;
const float COL_W  = 40.0;   // 左右侧栏宽
const float COL_RX = 210.0;  // 右栏 x 起点
const float CORNER = 10.0;   // 卡片圆角半径

const float H_COST  = 43.0;  // 费用/类别格高
const float Y_BAND1 = 43.0;  // 横带1
const float H_BAND1 = 19.0;
const float Y_NUM1  = 62.0;  // 数值1（紧贴横带，无白隙）
const float H_TILE  = 39.0;  // 数值/图标格高（所有格子相互紧贴）
const float Y_ICON1 = 101.0; // 图标1
const float Y_SEP   = 140.0; // 分隔条
const float H_SEP   = 18.0;
const float Y_NUM2  = 158.0; // 数值2（紧贴分隔条）
const float Y_ICON2 = 197.0; // 图标2
const float Y_BAND2 = 236.0; // 横带2

// ---------------- 图集常量：18 格 x 96px ----------------
const float CELL    = 96.0;
const float ATLAS_W = 1728.0;

// ---------------- 贴图 ----------------
uniform sampler2D atlas_tex : source_color, filter_linear; // 图集禁用 mipmap：边缘隐式 LOD 异常会拉出灰框
uniform sampler2D art_tex   : source_color, filter_linear_mipmap;
uniform sampler2D tag_tex   : source_color, filter_linear_mipmap;
uniform vec2 art_size = vec2(1.0, 1.0); // 立绘像素尺寸（脚本自动填）
uniform vec2 tag_size = vec2(1.0, 1.0); // 自定义类别图标尺寸（脚本自动填）
uniform int has_art = 0;   // 0=未设立绘（只画条纹底）
uniform int tag_mode = 0;  // 0=内置类别图标  1=自定义 tag_tex
uniform int art_fit = 1;   // 1=裁剪铺满(cover，立绘撑满中央区)  0=完整显示(contain)
uniform float art_zoom = 1.0; // 立绘放大倍率（>1 裁掉素材边缘留白，角色占牌面更大）

// ---------------- 数字（-1 = 不显示，>=10 自动两位） ----------------
uniform int cost_num = 6;
uniform int num_l1   = 5;
uniform int num_l2   = -1;
uniform int num_r1   = -1;
uniform int num_r2   = 3;

// ---------------- 图标（-1 = 不显示） ----------------
uniform int icon_l1  = 0;
uniform int icon_l2  = 1;
uniform int icon_r1  = 2;
uniform int icon_r2  = 3;
uniform int icon_tag = 6;

// ---------------- 配色 ----------------
uniform vec4 col_base      : source_color = vec4(1.0, 1.0, 1.0, 1.0);        // 卡底
uniform vec4 col_cell      : source_color = vec4(0.90, 0.90, 0.90, 1.0);        // 数值格底色（淡灰，与白色图标块自然分割）
uniform vec4 col_band      : source_color = vec4(0.56, 0.56, 0.56, 1.0);     // 横带+分隔条
uniform vec4 col_cost_bg   : source_color = vec4(0.16, 0.16, 0.16, 1.0);     // 费用格底（深灰）
uniform vec4 col_cost_num  : source_color = vec4(0.96, 0.62, 0.04, 1.0);     // 费用数字（橙）
uniform vec4 col_num       : source_color = vec4(0.30, 0.30, 0.30, 1.0);     // 数值数字（深灰）
uniform vec4 col_icon      : source_color = vec4(0.42, 0.42, 0.42, 1.0);     // 侧栏图标（深灰，与数值同层次）
uniform vec4 col_tag_bg    : source_color = vec4(0.55, 0.55, 0.55, 1.0);     // 类别格底
uniform vec4 col_tag_icon  : source_color = vec4(0.78, 0.78, 0.78, 1.0);     // 类别图标
uniform vec4 col_center    : source_color = vec4(0.93, 0.93, 0.93, 1.0);     // 中央底色（指令/默认）
uniform vec4 col_stripe    : source_color = vec4(0.87, 0.87, 0.87, 1.0);     // 中央条纹线（灰白）
uniform float icon_scale    = 0.74;                                          // 侧栏图标占比
uniform float tag_icon_scale = 0.78;                                         // 类别图标占比

// 数字宽高比（Segoe UI Bold 实测值，供两位数排版）
const float DIGW[10] = float[10](0.7021, 0.4239, 0.6522, 0.617, 0.7667, 0.6196, 0.6809, 0.7111, 0.6915, 0.6809);

// 圆角矩形 SDF：b=半尺寸，r=圆角半径（直边位于 |p|=b 处，圆角四角为半径 r 的圆弧）
float sd_round(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

// 矩形内等比采样（fit 0=contain 1=cover），zoom>1 时居中放大裁边，越界返回透明
vec4 sample_fit(sampler2D tex, vec2 tsz, vec2 px, vec4 r, int fit, float zoom) {
	vec2 uv = (px - r.xy) / r.zw;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return vec4(0.0);
	}
	vec2 asp = r.zw / max(tsz, vec2(1.0));
	float s = (fit == 0) ? min(asp.x, asp.y) : max(asp.x, asp.y);
	vec2 fr = (uv - 0.5) * asp / s + 0.5;
	fr = (fr - 0.5) / max(zoom, 0.01) + 0.5; // 居中放大
	if (fr.x < 0.0 || fr.x > 1.0 || fr.y < 0.0 || fr.y > 1.0) {
		return vec4(0.0);
	}
	return texture(tex, fr);
}

// 数字绘制：格子内水平垂直居中（v<0 不显示，>=10 自动两位）
float digit_alpha(vec2 px, float x0, float y0, float cell_h, int v, float dig_h) {
	if (v < 0) {
		return 0.0;
	}
	int d1 = v - (v / 10) * 10;
	int n = (v >= 10) ? 2 : 1;
	int i0 = (v >= 10) ? v / 10 : d1;
	float w0 = DIGW[i0] * dig_h;
	float w1 = DIGW[d1] * dig_h;
	float gap = 1.5;
	float total = (n == 2) ? (w0 + gap + w1) : w0;
	float lx = px.x - x0;
	float sx = (COL_W - total) * 0.5;
	if (lx < sx || lx >= sx + total) {
		return 0.0;
	}
	float sy = y0 + (cell_h - dig_h) * 0.5;
	if (px.y < sy || px.y >= sy + dig_h) {
		return 0.0;
	}
	int ci;
	float u;
	if (n == 1 || lx < sx + w0) {
		ci = i0;
		u = (lx - sx) / w0;
	} else {
		ci = d1;
		u = (lx - sx - w0 - gap) / w1;
	}
	float pad = (1.0 - DIGW[ci]) * 0.5;
	float ty = clamp((px.y - sy) / dig_h, 0.0, 1.0);
	vec2 auv = vec2((float(ci) + pad + u * DIGW[ci]) * CELL / ATLAS_W, (4.0 + ty * 88.0) / CELL);
	return texture(atlas_tex, auv).a;
}

// 图标绘制：格子内居中（idx<0 不显示）
float icon_alpha(vec2 px, float x0, float y0, float cw, float ch, int idx, float scale) {
	if (idx < 0) {
		return 0.0;
	}
	float s = min(cw, ch) * scale;
	float sx = x0 + (cw - s) * 0.5;
	float sy = y0 + (ch - s) * 0.5;
	if (px.x < sx || px.x >= sx + s || px.y < sy || px.y >= sy + s) {
		return 0.0;
	}
	vec2 f = (px - vec2(sx, sy)) / s;
	vec2 auv = vec2((float(idx) + 10.0 + f.x) * CELL / ATLAS_W, f.y);
	return texture(atlas_tex, auv).a;
}

// ============================================================
// 类别中央底纹：按右上角类别图标 tag 决定条纹样式（只改底，立绘永远画在其上）
//   4 兵蜂(soldier)  → 纯色无条纹
//   5 建筑(building) → 淡棕色密条纹
//   6 指令(command)  → 灰白密条纹
//   7 蜂王(queen)    → 金色密条纹
// 输出：base=底色 line=条纹色 period=周期(px) on=是否有条纹
// ============================================================
void category_style(int tag, out vec3 base, out vec3 line, out float period, out float on) {
	on = 1.0;
	period = 6.0; // 条纹粗度 = 间隔 = 3px（50% 占空比，周期 6px）
	// 默认 / 指令：灰白
	base = col_center.rgb;
	line = col_stripe.rgb;
	if (tag == 4) {
		// 兵蜂：纯色底，无条纹
		on = 0.0;
		base = vec3(0.96, 0.96, 0.96);
	} else if (tag == 5) {
		// 建筑：淡棕
		base = vec3(0.88, 0.80, 0.65);
		line = vec3(0.80, 0.70, 0.53);
	} else if (tag == 7) {
		// 蜂王：金色
		base = vec3(0.97, 0.80, 0.42);
		line = vec3(0.91, 0.69, 0.33);
	}
}

void fragment() {
	vec2 px = UV * W;
	float d = sd_round(px - vec2(W * 0.5), vec2(W * 0.5), CORNER);
	float aa = clamp(0.75 - d, 0.0, 1.0); // 圆角边缘抗锯齿
	if (aa <= 0.0) {
		COLOR = vec4(0.0);
	} else {
	vec3 col = col_base.rgb;

	if (px.x >= COL_W && px.x < COL_RX) {
		// ===== 中央区：按类别的条纹底（底层） + 立绘（上层，条纹永不覆盖纹理） =====
		vec3 sbase; vec3 sline; float speriod; float son;
		category_style(icon_tag, sbase, sline, speriod, son);
		col = sbase;
		if (son > 0.5) {
			float s = step(fract(px.y / speriod), 0.5); // 条纹与间隔等宽（50% 占空比）
			col = mix(sbase, sline, s);
		}
		if (has_art == 1) {
			vec4 a = sample_fit(art_tex, art_size, px, vec4(COL_W, 0.0, COL_RX - COL_W, W), art_fit, art_zoom);
			col = mix(col, a.rgb, a.a);
		}
	} else {
		// ===== 左右侧栏：按行分层填色 =====
		bool left = px.x < COL_W;
		float x0 = left ? 0.0 : COL_RX;
		float y = px.y;
		if (y < H_COST)                 { col = left ? col_cost_bg.rgb : col_tag_bg.rgb; }
		else if (y < Y_BAND1 + H_BAND1) { col = col_band.rgb; }  // 横带1（灰）
		else if (y < Y_NUM1 + H_TILE)   { col = col_cell.rgb; }  // 数值格：淡灰色块（紧贴横带）
		else if (y < Y_ICON1 + H_TILE)  { col = col_base.rgb; }  // 图标格：白底
		else if (y < Y_SEP + H_SEP)     { col = col_band.rgb; }  // 中分隔条（灰）
		else if (y < Y_NUM2 + H_TILE)   { col = col_cell.rgb; }  // 数值格：淡灰色块（紧贴分隔条）
		else if (y < Y_ICON2 + H_TILE)  { col = col_base.rgb; }  // 图标格：白底
		else                            { col = col_band.rgb; }  // 底带（灰）

		// ===== 叠加内容 =====
		float g;
		if (left) {
			g = digit_alpha(px, x0, 0.0, H_COST, cost_num, 28.0);
			col = mix(col, col_cost_num.rgb, g);
			g = digit_alpha(px, x0, Y_NUM1, H_TILE, num_l1, 24.0);
			col = mix(col, col_num.rgb, g);
			g = digit_alpha(px, x0, Y_NUM2, H_TILE, num_l2, 24.0);
			col = mix(col, col_num.rgb, g);
			g = icon_alpha(px, x0, Y_ICON1, COL_W, H_TILE, icon_l1, icon_scale);
			col = mix(col, col_icon.rgb, g);
			g = icon_alpha(px, x0, Y_ICON2, COL_W, H_TILE, icon_l2, icon_scale);
			col = mix(col, col_icon.rgb, g);
		} else {
			g = digit_alpha(px, x0, Y_NUM1, H_TILE, num_r1, 24.0);
			col = mix(col, col_num.rgb, g);
			g = digit_alpha(px, x0, Y_NUM2, H_TILE, num_r2, 24.0);
			col = mix(col, col_num.rgb, g);
			g = icon_alpha(px, x0, Y_ICON1, COL_W, H_TILE, icon_r1, icon_scale);
			col = mix(col, col_icon.rgb, g);
			g = icon_alpha(px, x0, Y_ICON2, COL_W, H_TILE, icon_r2, icon_scale);
			col = mix(col, col_icon.rgb, g);
			// 右上角：类别图标（自定义贴图优先）
			if (tag_mode == 1) {
				vec4 t = sample_fit(tag_tex, tag_size, px, vec4(COL_RX, 0.0, COL_W, H_COST), 0, 1.0);
				col = mix(col, t.rgb, t.a);
			} else {
				g = icon_alpha(px, x0, 0.0, COL_W, H_COST, icon_tag, tag_icon_scale);
				col = mix(col, col_tag_icon.rgb, g);
			}
		}
	}

	// 卡边阴影：一整圈薄薄压暗 ~2px（无描边线，柔和过渡，贴合效果图）
	float rim = 1.0 - smoothstep(0.5, 3.0, -d);
	col *= mix(vec3(1.0), vec3(0.62), rim);

	COLOR = vec4(col, aa);
	}
}
