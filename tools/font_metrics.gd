extends Control
## 量测：Noto Sans SC 在若干字号下，**汉字/数字**的实际字形高度 → 得出 字高/字号 比例
## 用于把设计稿 SVG 中的字形高度换算成 Godot Label 的 font_size
const CASES := [
	["玩家名称", 48, 0], ["玩家名称", 58, 130], ["卡牌名称", 44, 260], ["回合1--先手", 78, 390],
	["0", 24, 520], ["0", 32, 650], ["0", 65, 780], ["主按钮", 49, 910],
]

func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans SC", "Source Han Sans CN", "Microsoft YaHei"])
	for c in CASES:
		var l := Label.new()
		l.text = c[0]
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", c[1])
		l.add_theme_color_override("font_color", Color.WHITE)
		l.position = Vector2(200, 40 + c[2])
		l.size = Vector2(900, 120)
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		add_child(l)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0)
	bg.size = Vector2(1920, 1080)
	bg.show_behind_parent = true
	add_child(bg)
	move_child(bg, 0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	Image.new()
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://font_metrics.png")
	print("[FONT_METRICS] saved")
	get_tree().quit()
