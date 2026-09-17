extends Node2D
## 取证工具：把目标 UI 场景以整幅 1920×1080 取景并截图为 PNG（供视觉复核 / 像素比对）
## 用法：设置 target_scene（或在派生场景里改默认值）后，以 custom scene 运行本场景
@export_file("*.tscn") var target_scene := "res://scenes/ui/battle_ui.tscn"
@export var out_name := "ui_shot.png"

func _ready() -> void:
	var packed: PackedScene = load(target_scene) as PackedScene
	if packed == null:
		printerr("UI_SHOT load failed: " + target_scene); get_tree().quit(1); return
	var ui: Node = packed.instantiate()
	add_child(ui)
	var cam := Camera2D.new()
	cam.position = Vector2(960.0, 540.0)      # 设计空间中心
	cam.zoom = Vector2(0.6, 0.6)              # 1920×1080 → 1152×648
	add_child(cam)
	cam.make_current()
	for i in 4:
		await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://" + out_name)
	printerr("UI_SHOT saved: " + out_name)
	get_tree().quit(0)
