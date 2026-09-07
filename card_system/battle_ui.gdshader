shader_type canvas_item;
render_mode unshaded;

// ============================================================
// 战斗 UI 骨架（1920x1080 设计坐标，全程序化定量绘制）
//   - 面板 / 棋盘 + 十字网格 / 徽章 / 按钮 → 纯 SDF + 内置常量
//   - 左下 4 个状态图标（剑/盾/速度/准星）→ card_atlas.png（与卡牌同套）
//   - 右下 4 个小按钮图标（螺母/笑脸/信息/退出）→ SDF 内置绘制
//   文字与数字一律不渲染，待游戏逻辑接入后由上层节点补充
// ============================================================

uniform sampler2D atlas_tex : source_color, filter_linear;

const vec2 RES = vec2(1920.0, 1080.0);

// ---------------- 布局定量 ----------------
// 中央棋盘：1008x1008 完全居中（地图本体 1000x1000 + 外描边 4px×2），通用圆角 10px
const vec4 BOARD = vec4(456.0, 36.0, 1464.0, 1044.0); // x0,y0,x1,y1
const float BOARD_RR = 10.0;   // 通用圆角 10px
const float CROSS_A = 26.0;    // 十字半臂长
const float CROSS_T = 9.0;     // 十字线宽

// 两侧手牌背景 400x400（左列 x 32-432，右列镜像 x 1488-1888；徽章行 40-140 + 间隙 10）
const vec4 PANEL_L = vec4(32.0, 150.0, 432.0, 550.0);
const vec4 PANEL_R = vec4(1488.0, 150.0, 1888.0, 550.0);
const float PANEL_RR = 10.0;

// 左下卡牌详情 300x300（描边 #000000），右接状态图标列
const vec4 ART = vec4(32.0, 758.0, 332.0, 1058.0);
const float ART_RR = 10.0;

// 状态图标列（剑/盾/速度/准星 = 图集 10+idx 格，数字留白）
const float STAT_X = 381.0;
const float STAT_Y0 = 800.0;
const float STAT_DY = 76.0;
const float STAT_SIZE = 34.0;

// 玩家六边形徽章（各自 400 列左缘的 100x100 区块 y40-140，#FFA300 底 + 黑 50% 外描边，数字留白）
const vec2 HEX_L = vec2(82.0, 90.0);
const vec2 HEX_R = vec2(1538.0, 90.0);
const float HEX_RAD = 44.0;

// 主按钮 400x100（面板下间隙 10，右段变暗 100 宽），通用圆角 10px
const vec4 BTN_MAIN = vec4(1488.0, 560.0, 1888.0, 660.0);
const float BTN_MAIN_RR = 10.0;
const float BTN_DIV_X = 1785.0; // 右侧深色分段起点 x

// 右下 4 个小按钮（行宽 400：88px 键 + 16px 间隙，底边距 34；螺母/笑脸/信息/退出）
const vec2 SBTN0 = vec2(1532.0, 1002.0);
const float SBTN_DX = 104.0;
const float SBTN_HALF = 44.0;
const float SBTN_RR = 10.0;
const float SICON_R = 21.0;    // 小按钮图标半径

// 图集常量（与 card_auto.gdshader 一致）
const float CELL = 96.0;
const float ATLAS_W = 1728.0;

// ---------------- 配色定量 ----------------
const vec3 COL_BG = vec3(0.35);           // 背景灰
const vec3 COL_PANEL = vec3(0.27);        // 预览面板深灰
const vec3 COL_BOARD = vec3(0.66);        // 棋盘灰
const vec3 COL_BOARD_LINE = vec3(0.79);   // 棋盘细描边
const vec3 COL_CROSS = vec3(0.72);        // 十字网格
const vec3 COL_ART = vec3(0.03);          // 卡面区黑
const vec3 COL_ART_LINE = vec3(0.0);       // 卡面区描边 #000000
const vec3 COL_ORANGE = vec3(1.0, 0.639, 0.0); // 徽章橙 #FFA300
const vec3 COL_WHITE = vec3(0.97);        // 徽章白环
const vec3 COL_STAT = vec3(0.93);         // 状态图标（白）
const vec3 COL_BTN = vec3(0.71);          // 主按钮
const vec3 COL_BTN_LINE = vec3(0.90);     // 主按钮描边
const vec3 COL_BTN_SEG = vec3(0.64);      // 主按钮右段
const vec3 COL_SBTN = vec3(0.64);         // 小按钮
const vec3 COL_SBTN_LINE = vec3(0.78);    // 小按钮描边
const vec3 COL_SICON = vec3(0.23);        // 小按钮图标（深灰）

// ---------------- SDF 基础 ----------------
float sd_round(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}
float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}
float sd_circle(vec2 p, float r) {
	return length(p) - r;
}
float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}
// 尖顶六边形（上下为顶点）
float sd_hexagon(vec2 p, float r) {
	const vec3 k = vec3(-0.8660254, 0.5, 0.5773503);
	p = abs(p.yx);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}
// 填充抗锯齿：d<0 内部
float am(float d) {
	return clamp(0.75 - d, 0.0, 1.0);
}
// 描边带宽 2w（沿轮廓）
float band(float d, float w) {
	return am(abs(d) - w);
}
// 矩形便捷：r = x0,y0,x1,y1
float drect(vec2 px, vec4 r, float rad) {
	return sd_round(px - vec2((r.x + r.z) * 0.5, (r.y + r.w) * 0.5),
			vec2((r.z - r.x) * 0.5, (r.w - r.y) * 0.5), rad);
}

// ---------------- 图标 ----------------
// 图集图标（idx + 10 格）
float icon_atlas(vec2 px, vec2 c, float s, int idx) {
	vec2 f = (px - c) / s + 0.5;
	if (f.x < 0.0 || f.x > 1.0 || f.y < 0.0 || f.y > 1.0) {
		return 0.0;
	}
	vec2 auv = vec2((float(idx) + 10.0 + f.x) * CELL / ATLAS_W, f.y);
	return texture(atlas_tex, auv).a;
}
// 六角螺母：六边形减圆孔
float ico_nut(vec2 p, float R) {
	float hex = sd_hexagon(p, R * 0.85);
	float hole = sd_circle(p, R * 0.34);
	return am(max(hex, -hole));
}
// 笑脸：圆环 + 双眼 + 嘴弧
float ico_smile(vec2 p, float R) {
	float m = band(sd_circle(p, R * 0.92), 1.8);
	m = max(m, am(sd_circle(p - vec2(-0.34, -0.30) * R, R * 0.13)));
	m = max(m, am(sd_circle(p - vec2(0.34, -0.30) * R, R * 0.13)));
	float mouth = band(sd_circle(p - vec2(0.0, -0.18) * R, R * 0.55), 1.8);
	m = max(m, mouth * step(0.28 * R, p.y));
	return m;
}
// 信息：圆环 + i（点 + 杆）
float ico_info(vec2 p, float R) {
	float m = band(sd_circle(p, R * 0.92), 1.8);
	m = max(m, am(sd_circle(p - vec2(0.0, -0.48) * R, R * 0.11)));
	m = max(m, am(sd_box(p - vec2(0.0, 0.18) * R, vec2(R * 0.11, R * 0.34))));
	return m;
}
// 退出：右侧开口的门框 + 向右箭头
float ico_exit(vec2 p, float R) {
	float door = band(sd_box(p - vec2(-0.12 * R, 0.0), vec2(R * 0.66, R * 0.80)), 1.8);
	float notch = am(0.28 * R - p.x) * am(0.42 * R - abs(p.y));
	door *= 1.0 - notch;
	float ax = sd_seg(p, vec2(-0.05 * R, 0.0), vec2(0.52 * R, 0.0));
	float a1 = sd_seg(p, vec2(0.52 * R, 0.0), vec2(0.20 * R, 0.34 * R));
	float a2 = sd_seg(p, vec2(0.52 * R, 0.0), vec2(0.20 * R, -0.34 * R));
	float arrow = min(min(ax, a1), a2);
	return max(door, band(arrow, 2.0));
}

// ---------------- 片元 ----------------
void fragment() {
	vec2 px = UV * RES;
	vec3 col = COL_BG;

	// 两侧卡牌预览面板
	col = mix(col, COL_PANEL, am(drect(px, PANEL_L, PANEL_RR)));
	col = mix(col, COL_PANEL, am(drect(px, PANEL_R, PANEL_RR)));

	// 左下卡牌详情（描边 #000000 3px）
	float dArt = drect(px, ART, ART_RR);
	col = mix(col, COL_ART_LINE, am(dArt) - am(dArt + 3.0));
	col = mix(col, COL_ART, am(dArt + 3.0));

	// 中央棋盘：底色 → 十字网格（裁剪进棋盘）→ 细描边
	float dBoard = drect(px, BOARD, BOARD_RR);
	col = mix(col, COL_BOARD, am(dBoard));
	vec2 b0 = BOARD.xy;
	vec2 bsz = BOARD.zw - BOARD.xy;
	for (int i = 0; i < 5; i++) {
		for (int j = 0; j < 5; j++) {
			vec2 g = px - (b0 + vec2(float(i), float(j)) * bsz * 0.25);
			float dc = min(sd_box(g, vec2(CROSS_A, CROSS_T * 0.5)),
					sd_box(g, vec2(CROSS_T * 0.5, CROSS_A)));
			col = mix(col, COL_CROSS, am(dc) * am(dBoard));
		}
	}
	col = mix(col, COL_BOARD_LINE, am(dBoard) - am(dBoard + 4.0)); // 通用内描边 4px

	// 玩家六边形徽章（#FFA300 底 + 白环 + 黑 50% 外描边，数字留白）
	float dh = sd_hexagon(px - HEX_L, HEX_RAD);
	col = mix(col, COL_ORANGE, am(dh));
	col = mix(col, COL_WHITE, am(dh + 5.0) - am(dh + 9.0));
	col = mix(col, vec3(0.16), band(dh, 2.0) * 0.6);
	dh = sd_hexagon(px - HEX_R, HEX_RAD);
	col = mix(col, COL_ORANGE, am(dh));
	col = mix(col, COL_WHITE, am(dh + 5.0) - am(dh + 9.0));
	col = mix(col, vec3(0.16), band(dh, 2.0) * 0.6);

	// 左下状态图标列（剑/盾/速度/准星，数字留白）
	col = mix(col, COL_STAT, icon_atlas(px, vec2(STAT_X, STAT_Y0 + 0.0 * STAT_DY), STAT_SIZE, 0));
	col = mix(col, COL_STAT, icon_atlas(px, vec2(STAT_X, STAT_Y0 + 1.0 * STAT_DY), STAT_SIZE, 2));
	col = mix(col, COL_STAT, icon_atlas(px, vec2(STAT_X, STAT_Y0 + 2.0 * STAT_DY), STAT_SIZE, 1));
	col = mix(col, COL_STAT, icon_atlas(px, vec2(STAT_X, STAT_Y0 + 3.0 * STAT_DY), STAT_SIZE, 3));

	// 主按钮（右侧深色分段，文字留白）
	float dB = drect(px, BTN_MAIN, BTN_MAIN_RR);
	col = mix(col, COL_BTN_LINE, am(dB) - am(dB + 2.0));
	col = mix(col, COL_BTN, am(dB + 2.0));
	vec4 seg = vec4(BTN_DIV_X, BTN_MAIN.y + 3.0, BTN_MAIN.z - 3.0, BTN_MAIN.w - 3.0);
	col = mix(col, COL_BTN_SEG, am(drect(px, seg, BTN_MAIN_RR - 3.0)));

	// 右下 4 个小按钮 + 内置 SDF 图标
	for (int k = 0; k < 4; k++) {
		vec2 c = SBTN0 + vec2(float(k) * SBTN_DX, 0.0);
		float ds = sd_round(px - c, vec2(SBTN_HALF), SBTN_RR);
		col = mix(col, COL_SBTN_LINE, am(ds) - am(ds + 2.0));
		col = mix(col, COL_SBTN, am(ds + 2.0));
		vec2 p = px - c;
		float m = 0.0;
		if (k == 0) {
			m = ico_nut(p, SICON_R);
		} else if (k == 1) {
			m = ico_smile(p, SICON_R);
		} else if (k == 2) {
			m = ico_info(p, SICON_R);
		} else {
			m = ico_exit(p, SICON_R);
		}
		col = mix(col, COL_SICON, m * am(ds + 4.0));
	}

	COLOR = vec4(col, 1.0);
}
