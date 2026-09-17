extends Node2D
## 动画取证：按约 0.5 秒间隔连续取帧，验证特效在动（并可用于任何 UI 动画复核）
@export_file("*.tscn") var target_scene := "res://scenes/ui/battle_ui_alpha.tscn"
@export var count := 6
@export var interval := 0.5

func _ready() -> void:
	var ui: Node = (load(target_scene) as PackedScene).instantiate()
	add_child(ui)
	var filt: Control = ui.get_node_or_null("Background/CrtFx/CrtFilter")
	if filt == null:
		printerr("[ANIM] CrtFilter 未找到"); get_tree().quit(1); return
	for i in count:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < int(interval * 1000.0):
			await RenderingServer.frame_post_draw
		printerr("[ANIM] t=%.2fs pos=%s a=%.4f" % [i * interval, str(filt.position), filt.modulate.a])
		get_viewport().get_texture().get_image().save_png("user://anim_%02d.png" % i)
	get_tree().quit(0)
