extends Control
## 【工具】UI 组合冒烟：实例化新战斗场景 battle_scene.tscn，验证素材场景组合可用
## 注：本工具只做"能否实例化 + 渲染"的冒烟，详细接线校验见 verification/iter054_wiring_check.tscn

const TARGET := "res://scenes/ui/battle_scene.tscn"

func _ready() -> void:
	var packed: PackedScene = load(TARGET)
	if packed == null:
		printerr("[UI_PROBE] 场景加载失败: " + TARGET)
		get_tree().quit(1)
		return
	var scene: Control = packed.instantiate()
	add_child(scene)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	print("[UI_PROBE] OK 已实例化并渲染: ", TARGET)
	get_viewport().get_texture().get_image().save_png("user://ui_probe.png")
	get_tree().quit(0)
