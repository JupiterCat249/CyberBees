extends GutTest
## 视角坐标纯回归（迭代129 —— 与 view_coords 同一批交付）
##
## 为什么要这条：迭代065 的"镜像少减一个 PITCH"曾让整盘右下移一格、Cell_0_0 越界到 y=1000，
##   而当时的"对拍验证"拿被替换掉的旧实现当基准 ⇒ 把"与错误等价"当成了正确。
##   这里改为**设计事实**断言：镜像后的左上角必须落在 [0, BOARD-PITCH] 内。

const Coords := preload("res://src/view/view_coords.gd")
const PITCH := 250.0
const BOARD := 1000.0


func test_seat0_is_canonical_grid() -> void:
	assert_eq(Coords.view_cell_pos(Vector2i(0, 0), PITCH, BOARD, false), Vector2(0, 0))
	## ⚠️ 规范坐标：cell.x = 行 → 像素 y；cell.y = 列 → 像素 x
	assert_eq(Coords.view_cell_pos(Vector2i(1, 2), PITCH, BOARD, false), Vector2(500, 250))
	assert_eq(Coords.view_cell_pos(Vector2i(3, 3), PITCH, BOARD, false), Vector2(750, 750))


func test_mirrored_corner_maps_to_opposite_corner() -> void:
	assert_eq(Coords.view_cell_pos(Vector2i(0, 0), PITCH, BOARD, true), Vector2(750, 750))
	assert_eq(Coords.view_cell_pos(Vector2i(3, 3), PITCH, BOARD, true), Vector2(0, 0))


func test_mirrored_cells_stay_inside_board() -> void:
	## 设计事实断言（替代"与旧实现对比"）：16 个格镜像后都必须完整落在棋盘内
	for x in 4:
		for y in 4:
			var p: Vector2 = Coords.view_cell_pos(Vector2i(x, y), PITCH, BOARD, true)
			assert_true(p.x >= 0.0 and p.y >= 0.0, "镜像后不得为负：%s" % str(p))
			assert_true(p.x + PITCH <= BOARD and p.y + PITCH <= BOARD, "镜像后不得越界：%s" % str(p))
