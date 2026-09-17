extends Node2D
## 动画时钟探针：逐帧记录 CrtFilter 位置，判断动画是否逐帧平滑推进
@export_file("*.tscn") var target_scene := "res://scenes/ui/battle_ui_alpha.tscn"
@export var frames := 40

func _ready() -> void:
	var ui: Node = (load(target_scene) as PackedScene).instantiate()
	add_child(ui)
	var anim: AnimationPlayer = ui.get_node_or_null("Background/CrtFx/CrtAnim")
	var filt: Control = ui.get_node_or_null("Background/CrtFx/CrtFilter")
	if anim == null or filt == null:
		printerr("[CLOCK] 节点缺失"); get_tree().quit(1); return
	printerr("[CLOCK] is_playing=%s  speed_scale=%.2f  current_anim=%s  length=%.2f  max_fps=%d" % [
		str(anim.is_playing()), anim.speed_scale, str(anim.current_animation),
		anim.current_animation_length, Engine.max_fps])
	var log_y := []
	for i in frames:
		await RenderingServer.frame_post_draw
		log_y.append(filt.position.y)
	var uniq := {}
	for v in log_y:
		uniq[snappedf(v, 0.01)] = true
	printerr("[CLOCK] %d 帧内 position.y 采样: %s" % [frames, str(log_y.slice(0, 12))])
	printerr("[CLOCK] 不同取值数=%d  min=%.3f max=%.3f  逐帧增量(前6)=%s" % [
		uniq.size(), log_y.min(), log_y.max(),
		str(PackedFloat32Array([log_y[1]-log_y[0], log_y[2]-log_y[1], log_y[3]-log_y[2],
			log_y[4]-log_y[3], log_y[5]-log_y[4], log_y[6]-log_y[5]]))])
	get_tree().quit(0)
