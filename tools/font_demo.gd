extends Control
## 字重对照演示：设计规范「Source Han Sans CN / 粗体 Bold / 细体 Medium」→ Godot 实际字体
## 运行后截图即得到对照表；也可在编辑器里直接改字重查看效果。
const TEXTS := ["玩家名称", "卡牌名称", "技能描述-行1", "回合1--先手", "地图名"]
const SIZES := [51, 38, 42, 32, 37]

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#666666")
	bg.size = Vector2(1920, 1080)
	add_child(bg)

	var medium := load("res://assets/fonts/NotoSansSC-Medium.ttf")
	var bold := load("res://assets/fonts/NotoSansSC-Bold.ttf")
	var vf: FontFile = load("res://assets/fonts/NotoSansSC-VF.ttf")

	var faces := [
		["Medium（设计：细体统一 Medium）", medium],
		["Bold（设计：粗体统一 Bold）", bold],
		["VF wght=400（Regular，对照）", vf],
	]

	var y := 40.0
	var head := Label.new()
	head.text = "字体对照演示 — 设计规范 Source Han Sans CN → 包体 Noto Sans SC（同源字形）"
	head.position = Vector2(60, y); head.size = Vector2(1800, 60)
	head.add_theme_font_override("font", bold); head.add_theme_font_size_override("font_size", 40)
	head.add_theme_color_override("font_color", Color.WHITE)
	add_child(head)
	y += 90

	for pair in faces:
		var name_lbl := Label.new()
		name_lbl.text = pair[0]
		name_lbl.position = Vector2(60, y); name_lbl.size = Vector2(700, 48)
		name_lbl.add_theme_font_override("font", pair[1])
		name_lbl.add_theme_font_size_override("font_size", 30)
		name_lbl.add_theme_color_override("font_color", Color("#FFA300"))
		add_child(name_lbl)
		y += 56
		var x := 80.0
		for i in TEXTS.size():
			var l := Label.new()
			l.text = TEXTS[i]
			l.position = Vector2(x, y); l.size = Vector2(360, 90)
			# VF 行用 FontVariation 指定 wght
			if pair[1] == vf:
				var fv := FontVariation.new()
				fv.base_font = vf
				fv.variation_opentype = {"wght": 400}
				l.add_theme_font_override("font", fv)
			else:
				l.add_theme_font_override("font", pair[1])
			l.add_theme_font_size_override("font_size", SIZES[i])
			l.add_theme_color_override("font_color", Color.WHITE)
			add_child(l)
			x += 370
		y += 120
	# 自行截图（供取证）
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://font_demo.png")
	printerr("[FONT_DEMO] saved")
