extends Node2D
## 显像管拼接滚动取证：覆盖一个完整周期，逐帧检查
##  ① 三张图是否持续覆盖屏幕（无空白）② 滚动是否平滑 ③ 是否可见
@export_file("*.tscn") var target_scene := "res://scenes/ui/battle_ui_alpha.tscn"
const SNAP := [0, 15, 30, 45, 60, 75, 90]      # 帧号（60FPS 下覆盖 1.5s 周期）

func _ready() -> void:
	var ui: Node = (load(target_scene) as PackedScene).instantiate()
	add_child(ui)
	var anim: AnimationPlayer = ui.get_node_or_null("Background/CrtFx/CrtAnim")
	var mover: Control = ui.get_node_or_null("Background/CrtFx/Mover")
	if anim == null or mover == null:
		printerr("[ANIM] 节点缺失"); get_tree().quit(1); return
	printerr("[ANIM] len=%.2f playing=%s" % [anim.current_animation_length, str(anim.is_playing())])
	var ys: Array[float] = []
	for i in 100:
		await RenderingServer.frame_post_draw
		ys.append(mover.position.y)
		if i in SNAP:
			var img := get_viewport().get_texture().get_image()
			img.save_png("user://crt_%03d.png" % i)
			# 检查屏幕最上方 60px 是否有"空白"（与相邻行的均匀性）
			var top_mean := 0.0
			for y in 60:
				top_mean += img.get_pixel(30, y).r
			top_mean /= 60.0
			printerr("[ANIM] frame=%3d mover.y=%7.3f  顶部60px平均R=%.4f" % [i, mover.position.y, top_mean])
	printerr("[ANIM] mover.y: min=%.2f max=%.2f 取值数=%d 末值=%.2f" % [
		ys.min(), ys.max(), _uniq(ys).size(), ys[-1]])
	get_tree().quit(0)

func _uniq(a: Array) -> Dictionary:
	var d := {}
	for v in a:
		d[snappedf(v, 0.01)] = true
	return d
