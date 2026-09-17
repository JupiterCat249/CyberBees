extends Control
## 临时取证：实例化可复用卡组件 + 用 level_battle 的 spawn_unit 验证复用 API
func _ready() -> void:
	var bg := ColorRect.new(); bg.color = Color("#666666"); bg.size = Vector2(1920, 1080)
	add_child(bg)
	var level: Control = load("res://scenes/ui/level_battle.tscn").instantiate()
	add_child(level)
	var unit_scene: PackedScene = load("res://scenes/ui/card_unit.tscn")
	var hand_scene: PackedScene = load("res://scenes/ui/card_hand.tscn")
	# 通过复用 API 在地图格挂单位卡（2 个：我方/敌方）
	level.call("spawn_unit", unit_scene, 1, 0, {"id": "u1", "cost": 4, "atk": 2, "hp": 18, "move": 1, "range": 1, "mine": false, "type": "queen"})
	level.call("spawn_unit", unit_scene, 1, 2, {"id": "u2", "cost": 8, "atk": 5, "hp": 10, "move": 1, "range": 2, "mine": true, "type": "queen"})
	# 手牌：四张不同类型
	var types := ["order", "building", "order", "unit"]
	var costs := [2, 3, 2, 2]
	var slot := 0
	for sx in [0, 200]:
		for sy in [0, 200]:
			var c: Control = hand_scene.instantiate()
			c.get_node("Body").add_theme_stylebox_override("panel",
				_flat(Color({"order": "#D9D9D9", "building": "#DDC29B", "unit": "#FFFFFF"}[types[slot]]), 10))
			c.get_node("Cost").text = str(costs[slot])
			c.position = Vector2(30 + sx, 150 + sy)
			level.get_node("SideEnemy/Hand").add_child(c)
			slot += 1
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://ui_probe.png")
	printerr("[UI_PROBE] saved")
	get_tree().quit()

func _flat(c: Color, r: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = c
	s.corner_radius_top_left = int(r); s.corner_radius_top_right = int(r)
	s.corner_radius_bottom_left = int(r); s.corner_radius_bottom_right = int(r)
	return s
