@tool
extends Control
## ============================================================
## 静态 UI（节点化）—— 依据《电子蜂对战空间_静态UI说明.md》§1/§2 与
## `横版UI底座.svg` 的【矢量实测】坐标构建（设计空间 1920×1080，原点左上）。
##
## 本场景是**纯静态骨架**，不绑定游戏逻辑；节点名 = 设计稿对象名，
## 后续把游戏逻辑接到对应节点即可。
##
## ⚠️ GDScript 注意：`instantiate()` / `load()` 返回 Variant，
##    不要用 `var x := ` 推导；跨脚本取色也要显式转换。
## ============================================================

const W := 1920.0
const H := 1080.0

# ---------------- 全局配色（§1.3） ----------------
const C_BG := Color("666666")            # 全屏战斗背景
const C_BOARD := Color("999999")         # 地图板底
const C_BOARD_LINE := Color(1, 1, 1, 0.5)
const C_HAND_BG := Color(0, 0, 0, 0.2)   # 手牌区 #000000-20%
const C_PANEL := Color("ffffff")
const C_DETAIL_BG := Color("333333")
const C_DETAIL_LINE := Color("000000")
const C_BTN_DISABLED := Color("999999")
const C_BTN_READY := Color("499169")
const C_BTN_LINE := Color(1, 1, 1, 0.1)
const C_BTN_SEG := Color(0, 0, 0, 0.2)
const C_FUNC_BG := Color(1, 1, 1, 0.5)
const C_ORANGE := Color("FFA300")

# ---------------- 布局常量（§2 · 矢量实测） ----------------
const BOARD := Rect2(459, 40, 1000, 1000)
const BOARD_FRAME := Rect2(457, 38, 1004, 1004)
const HAND_L := Rect2(30, 150, 400, 400)
const HAND_R := Rect2(1490, 150, 400, 400)
const PANEL := Rect2(30, 570, 400, 470)
const DETAIL := Rect2(30, 740, 300, 300)
const BTN_MAIN := Rect2(1490, 570, 400, 100)
const BTN_SEG := Rect2(1752, 570, 138, 100)
const FUNC_Y := 960.0
const FUNC_X0 := 1540.0
const FUNC_DX := 90.0
const FUNC_SIZE := 80.0

const ASSETS := "res://assets/static_ui/"
const ICON_FILES := [
	"base-image1-40x40.png",   # 剑（攻击）
	"base-image2-40x40.png",   # 盾（生命/护甲）
	"base-image3-40x40.png",   # 》》（移动）
	"base-image4-40x40.png",   # 十字（射程/治疗）
]

var _font: Font = null


func _ready() -> void:
	_build()


## 编辑器内重建：改坐标后可立即在编辑器中看到结果
func _rebuild_in_editor() -> void:
	for c in get_children():
		c.queue_free()
	_build()


# ============================================================
# 基础构件
# ============================================================
func _bg(nm: String, r: Rect2, col: Color, radius := 10.0, par: Node = null) -> Panel:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = int(radius)
	sb.corner_radius_top_right = int(radius)
	sb.corner_radius_bottom_left = int(radius)
	sb.corner_radius_bottom_right = int(radius)
	var p := Panel.new()
	p.name = nm
	p.add_theme_stylebox_override("panel", sb)
	p.position = r.position
	p.size = r.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(par if par != null else self).add_child(p)
	return p


func _line(nm: String, r: Rect2, col: Color, width: float, radius := 8.0, par: Node = null) -> Panel:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.draw_center = false
	sb.border_color = col
	sb.border_width_left = int(width)
	sb.border_width_top = int(width)
	sb.border_width_right = int(width)
	sb.border_width_bottom = int(width)
	sb.corner_radius_top_left = int(radius)
	sb.corner_radius_top_right = int(radius)
	sb.corner_radius_bottom_left = int(radius)
	sb.corner_radius_bottom_right = int(radius)
	var p := Panel.new()
	p.name = nm
	p.add_theme_stylebox_override("panel", sb)
	p.position = r.position
	p.size = r.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(par if par != null else self).add_child(p)
	return p


func _tex(nm: String, r: Rect2, path: String, tile := false, par: Node = null,
		tint := Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.name = nm
	var tex := load(path) as Texture2D
	if tex != null:
		t.texture = tex
		if tile:
			t.stretch_mode = TextureRect.STRETCH_TILE
			t.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	t.position = r.position
	t.size = r.size
	t.modulate = tint
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(par if par != null else self).add_child(t)
	return t


func _font_get() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Noto Sans SC", "Source Han Sans CN", "Microsoft YaHei"])
		_font = f
	return _font


func _text(nm: String, pos: Vector2, txt: String, fs: int, col: Color, par: Node = null) -> Label:
	var l := Label.new()
	l.name = nm
	l.text = txt
	l.position = pos
	l.add_theme_font_override("font", _font_get())
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(par if par != null else self).add_child(l)
	return l


func _new_group(nm: String) -> Control:
	var c := Control.new()
	c.name = nm
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


# ============================================================
# 构建
# ============================================================
func _build() -> void:
	size = Vector2(W, H)
	_build_background()
	_build_board()
	_build_hands_and_badges()
	_build_left_panel()
	_build_main_button()
	_build_func_buttons()


## ① 全屏背景（§2.1）
func _build_background() -> void:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = C_BG
	bg.size = Vector2(W, H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


## ② 中央地图板（§2.1/§2.2）：1000×1000 + 外描边 1004×1004
func _build_board() -> void:
	var g := _new_group("Board")
	_bg("BoardPlate", BOARD, C_BOARD, 10.0, g)
	_tex("BoardTexture", BOARD, ASSETS + "fill-image0-1000x1000.png", false, g)
	_tex("CrossPattern", BOARD, ASSETS + "base-image0-2000x2000.png", true, g, Color(1, 1, 1, 0.1))
	_line("BoardFrame", BOARD_FRAME, C_BOARD_LINE, 4.0, 12.0, g)


## ③ 手牌区 + ④ 费用徽章（§2.3/§2.4）
func _build_hands_and_badges() -> void:
	var g := _new_group("HandsAndBadges")
	_bg("HandLeft", HAND_L, C_HAND_BG, 10.0, g)
	_bg("HandRight", HAND_R, C_HAND_BG, 10.0, g)
	_badge(g, "Left", 81.0, Rect2(61, 63, 37, 54))
	_badge(g, "Right", 1539.88, Rect2(1521, 63, 37, 54))


## 费用六边形（橙底 + 黑 50% 描边 4px）+ 内白色数字块
func _badge(g: Control, side: String, cx: float, num_rect: Rect2) -> void:
	var hex := HexBadge.new()
	hex.name = "CostBadge" + side
	hex.center = Vector2(cx, 90.0)
	hex.radius = 49.3
	hex.build()
	g.add_child(hex)
	_bg("BadgeNumberBlock" + side, num_rect, Color.WHITE, 0.0, g)


## ⑤ 左下信息面板（§2.5）
func _build_left_panel() -> void:
	var g := _new_group("LeftPanel")
	_bg("InfoPanel", PANEL, C_PANEL, 10.0, g)
	_bg("DetailBlock", DETAIL, C_DETAIL_BG, 10.0, g)
	_line("DetailBlockLine", Rect2(32, 742, 296, 296), C_DETAIL_LINE, 4.0, 8.0, g)
	for i in 4:
		var ic := Rect2(340.0, 780.0 + 60.0 * i, 40.0, 40.0)
		_tex("AttrIcon%d" % (i + 1), ic, ASSETS + ICON_FILES[i], false, g)
		_text("AttrValue%d" % (i + 1), Vector2(381.0, 786.0 + 60.0 * i), "0", 30, Color.WHITE, g)


## ⑥ 主按钮（§2.7）
func _build_main_button() -> void:
	var g := _new_group("MainButton")
	_bg("MainButtonBg", BTN_MAIN, C_BTN_DISABLED, 10.0, g)
	_line("MainButtonLine", Rect2(1492, 572, 396, 96), C_BTN_LINE, 4.0, 8.0, g)
	_bg("MainButtonSeg", BTN_SEG, C_BTN_SEG, 0.0, g)


## ⑦ 右下功能按钮组（§2.8）
func _build_func_buttons() -> void:
	var g := _new_group("FuncButtons")
	for i in 4:
		var x: float = FUNC_X0 + FUNC_DX * i
		var r := Rect2(x, FUNC_Y, FUNC_SIZE, FUNC_SIZE)
		_bg("FuncButton%d" % (i + 1), r, C_FUNC_BG, 10.0, g)
		_line("FuncButtonLine%d" % (i + 1), Rect2(x + 2, FUNC_Y + 2, 76, 76), C_BTN_LINE, 4.0, 8.0, g)


# ============================================================
# 费用六边形徽章（尖顶六边形 + 黑 50% 描边 4px）
#   实测外轮廓：86.6 宽 × 98.6 高，中心 (81,90) 与 (1539.88,90)
# ============================================================
class HexBadge extends Node2D:
	var center := Vector2.ZERO
	var radius := 49.3
	var _poly := PackedVector2Array()

	func build() -> void:
		var rr := radius
		var hw := rr * 0.8660254
		_poly = PackedVector2Array([
			Vector2(0, -rr), Vector2(hw, -rr * 0.5), Vector2(hw, rr * 0.5),
			Vector2(0, rr), Vector2(-hw, rr * 0.5), Vector2(-hw, -rr * 0.5),
		])

	func _draw() -> void:
		var pts := PackedVector2Array()
		for v in _poly:
			pts.append(center + v)
		draw_colored_polygon(pts, Color("FFA300"))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0, 0, 0, 0.5), 4.0, true)
