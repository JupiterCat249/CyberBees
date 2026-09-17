extends Node2D
## 显像管特效诊断（修正取帧）：用 process_frame 保证每帧真的推进
@export_file("*.tscn") var target_scene := "res://scenes/ui/battle_ui_alpha.tscn"

func _ready() -> void:
	var ui: Node = (load(target_scene) as PackedScene).instantiate()
	add_child(ui)
	for child in ui.get_children():
		if child.name != "Background":
			(child as CanvasItem).visible = false
	var mover: Control = ui.get_node_or_null("Background/CrtFx/Mover")
	var anim: AnimationPlayer = ui.get_node_or_null("Background/CrtFx/CrtAnim")
	printerr("[FX] sheets=%d clip=%s playing=%s" % [
		mover.get_child_count(), str((ui.get_node("Background/CrtFx") as Control).clip_contents), str(anim.is_playing())])
	for i in 90:
		await get_tree().process_frame          # 每帧推进一次
		if i % 15 == 0:
			var f0 := Engine.get_frames_drawn()
			var img := get_viewport().get_texture().get_image()
			img.save_png("user://fx_%03d.png" % i)
			printerr("[FX] i=%3d drawn=%d mover.y=%8.2f a=%.4f saved" % [
				i, f0, mover.position.y, mover.modulate.a])
	get_tree().quit(0)
