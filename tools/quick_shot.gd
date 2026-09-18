extends Node
## 【工具】加载指定场景并输出一张全分辨率截图到 res://verification/quick_shot.png
@export_file("*.tscn") var target_scene := "res://scenes/ui/battle_scene.tscn"

func _ready() -> void:
	var ps: PackedScene = load(target_scene)
	if ps == null:
		printerr("[QUICK_SHOT] 加载失败: ", target_scene); get_tree().quit(1); return
	add_child(ps.instantiate())
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://verification/quick_shot.png")
	print("[QUICK_SHOT] saved: ", target_scene)
	get_tree().quit(0)
