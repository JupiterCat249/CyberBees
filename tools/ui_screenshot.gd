extends Node2D
## 取证工具：把目标 UI 场景以整幅 1920×1080 取景并截图为 PNG（供视觉复核 / 像素比对）
## 用法：设置 target_scene（或在派生场景里改默认值）后，以 custom scene 运行本场景
@export_file("*.tscn") var target_scene := "res://scenes/ui/level_battle.tscn"
@export var out_name := "ui_shot.png"

func _ready() -> void:
	var packed: PackedScene = load(target_scene) as PackedScene
	if packed == null:
		printerr("UI_SHOT load failed: " + target_scene); get_tree().quit(1); return
	var ui: Node = packed.instantiate()
	add_child(ui)
	# 视口已是设计尺寸（project.godot: window/size/viewport_* = 1920×1080）→ 1:1 取景，
	# 保证截图与设计稿可直接像素比对（此前写死 0.6 是配合 1152×648 视口，已过时）
	var vp := get_viewport().get_visible_rect().size
	var z := 1.0
	if vp.x > 0.0 and vp.y > 0.0 and (vp.x != 1920.0 or vp.y != 1080.0):
		z = minf(vp.x / 1920.0, vp.y / 1080.0)   # 视口非设计尺寸时按比例适配
	var cam := Camera2D.new()
	cam.position = Vector2(960.0, 540.0)
	cam.zoom = Vector2(z, z)
	add_child(cam)
	cam.make_current()
	printerr("UI_SHOT viewport=%s zoom=%.3f" % [str(vp), z])
	for i in 4:
		await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://" + out_name)
	printerr("UI_SHOT saved: " + out_name)
	get_tree().quit(0)
