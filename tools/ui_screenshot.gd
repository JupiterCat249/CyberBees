extends Node2D
## 取证工具：把目标 UI 场景按 1:1 取景并截图（供视觉复核 / 像素比对 / 动画验证）
## wait_frames：截图前等待的帧数（验证动画时可设不同值，比较同一位置是否变化）
@export_file("*.tscn") var target_scene := "res://scenes/ui/battle_ui_alpha.tscn"
@export var out_name := "ui_shot.png"
@export var wait_frames := 4

func _ready() -> void:
	var packed: PackedScene = load(target_scene) as PackedScene
	if packed == null:
		printerr("UI_SHOT load failed: " + target_scene); get_tree().quit(1); return
	add_child(packed.instantiate())
	var vp := get_viewport().get_visible_rect().size
	var z := 1.0
	if vp.x > 0.0 and vp.y > 0.0 and (vp.x != 1920.0 or vp.y != 1080.0):
		z = minf(vp.x / 1920.0, vp.y / 1080.0)
	var cam := Camera2D.new()
	cam.position = Vector2(960.0, 540.0)
	cam.zoom = Vector2(z, z)
	add_child(cam)
	cam.make_current()
	for i in maxi(1, wait_frames):
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://" + out_name)
	printerr("UI_SHOT saved %s (frames=%d zoom=%.3f)" % [out_name, wait_frames, z])
	get_tree().quit(0)
