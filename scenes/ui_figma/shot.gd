extends Node2D
## 取证：加载目标场景 → 以整幅 1920×1080 取景 → 存 PNG（文件名带时间戳）
const TARGET := "res://scenes/ui_figma/figma_base.tscn"

func _ready() -> void:
	var packed: PackedScene = load(TARGET) as PackedScene
	if packed == null:
		printerr("SHOT: load failed"); get_tree().quit(1); return
	var ui: Node = packed.instantiate()
	add_child(ui)
	var cam := Camera2D.new()
	cam.position = Vector2(960.0, 540.0)          # 设计空间中心
	cam.zoom = Vector2(0.6, 0.6)                  # 1920×1080 → 1152×648
	add_child(cam)
	cam.make_current()
	for i in 4:
		await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var nm := "shot_%d.png" % Time.get_ticks_msec()
	img.save_png("user://" + nm)
	printerr("SAVED " + nm)
	get_tree().quit(0)
