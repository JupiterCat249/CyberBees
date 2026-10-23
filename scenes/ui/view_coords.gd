extends RefCounted
## 棋盘**视角坐标**（纯计算）—— 自 arena_view._view_cell_pos 切出（迭代129）
##
## 判据：只吃 (规范格, PITCH, 棋盘边长, 是否需要镜像) → 视图坐标；不碰节点、不读场景。
##   ⚠️ 关于「减一个 PITCH」的历史（人 2026-10-10 实测抓到）：格节点的 position 是**左上角**，
##      而 180° 关于**格心**对称 ⇒ mirror(左上角) = EXT − 左上角 − PITCH。
##      漏掉该项 ⇒ 每格 +250,+250（整盘右下移一格 + Cell_0_0 越界到 y=1000）。


## 规范格 → 未镜像的像素坐标（左上角）
static func cell_pos(cell: Vector2i, pitch: float) -> Vector2:
	return Vector2(float(cell.x) * pitch, float(cell.y) * pitch)


## 规范格 → **当前座位视角**的像素坐标（左上角）
##   mirrored=false ⇒ 规范坐标；true ⇒ 关于棋盘中心 180° 镜像（并减一个格宽）
static func view_cell_pos(cell: Vector2i, pitch: float, board_px: float, mirrored: bool) -> Vector2:
	var p := cell_pos(cell, pitch)
	if not mirrored:
		return p
	return Vector2(board_px, board_px) - p - Vector2(pitch, pitch)
