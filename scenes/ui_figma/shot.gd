extends Node2D
## 取证：加载目标场景 → 渲染一帧 → 存 PNG
const TARGET := "res://scenes/ui_figma/figma_base.tscn"

func _ready() -> void:
	var packed: PackedScene = load(TARGET) as PackedScene
	if packed == null:
		printerr("SHOT: load failed")
		get_tree().quit(1)
		return
	var ui: Node = packed.instantiate()
	add_child(ui)
	var cam := Camera2D.new()
	cam.position = Vector2(960.0, 540.0)
	add_child(cam)
	cam.make_current()
	for i in 4:
		await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var e := img.save_png("user://shot_134502.png")
	printerr("SHOT done err=" + str(e))
	get_tree().quit(0)
