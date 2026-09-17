extends Control
## 主菜单：最小可玩入口（开始对战 / 卡组 / 设置 / 退出）
## 只做页面跳转；后续界面在此扩展为独立场景并在此挂按钮即可

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/level_battle.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
