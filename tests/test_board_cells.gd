extends GutTest
## 棋盘格**装配**的读数回归（迭代130 · P6 第二刀的前置网兜）
##
## 覆盖 `_adopt_cells` 的可见事实：16 格齐全、规范格正确、视角坐标正确、
##   全都完整落在棋盘内、鼠标可点、点击信号已接。这些读数在切片前后必须一致。

const BattleScene := preload("res://scenes/ui/battle_scene.tscn")

var _scene: Node = null


func before_all() -> void:
	_scene = BattleScene.instantiate()
	add_child(_scene)
	await wait_frames(3)


func after_all() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()


func test_all_sixteen_cells_adopted() -> void:
	var cells: Dictionary = _scene.get("_cells")
	assert_eq(cells.size(), 16, "必须恰好 16 个格（4×4）")
	for x in 4:
		for y in 4:
			var c := Vector2i(x, y)
			assert_true(cells.has(c), "缺格 %s" % str(c))
			var node = cells[c]
			assert_eq(String(node.name), "Cell_%d_%d" % [x, y], "节点名应按坐标")
			assert_eq(node.get("cell"), c, "格节点应记住**规范格**（数据侧）")


func test_cells_positioned_by_view_coords_and_inside_board() -> void:
	var cells: Dictionary = _scene.get("_cells")
	var board_px: float = float(_scene.get("BOARD_PX"))
	var pitch: float = float(_scene.get("PITCH"))
	for c in cells.keys():
		var node = cells[c]
		assert_eq(node.position, _scene._view_cell_pos(c), "位置必须走视角坐标换算（%s）" % str(c))
		assert_true(node.position.x >= 0.0 and node.position.y >= 0.0, "左上角不得为负（%s）" % str(c))
		assert_true(node.position.x + pitch <= board_px + 0.01, "不得越右边界（%s）" % str(c))
		assert_true(node.position.y + pitch <= board_px + 0.01, "不得越下边界（%s）" % str(c))


func test_cells_are_clickable_and_wired() -> void:
	var cells: Dictionary = _scene.get("_cells")
	var on_click: Callable = Callable(_scene, "_on_cell_clicked")
	for c in cells.keys():
		var node = cells[c]
		assert_eq(int(node.mouse_filter), int(Control.MOUSE_FILTER_STOP), "格必须可接收点击（%s）" % str(c))
		assert_true(node.has_signal("cell_clicked"), "格应声明 cell_clicked（%s）" % str(c))
		assert_true(node.cell_clicked.is_connected(on_click), "点击应已接到视图（%s）" % str(c))
