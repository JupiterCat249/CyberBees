extends RefCounted
## 棋盘**视角坐标**（纯计算）—— 自 arena_view._view_cell_pos / _cell_pos 切出（迭代129）
##
## ⚠️ **坐标约定（本项目规范）**：`cell.x = 行`、`cell.y = 列` ⇒ 像素是 `(cell.y*PITCH, cell.x*PITCH)`。
##   ⚠️ 迭代129 切片时我漏掉这层转置（写成 x→x）—— 被同批新写的读数网兜（test_board_cells）当场抓到，
##      已在提交前修正。**这就是"先补网兜再切片"的价值**。
##
## ⚠️ 关于「减一个 PITCH」的历史（人 2026-10-10 实测抓到）：格节点的 position 是**左上角**，
##      而 180° 关于**格心**对称 ⇒ mirror(左上角) = EXT − 左上角 − PITCH。
##      漏掉该项 ⇒ 每格 +250,+250（整盘右下移一格 + Cell_0_0 越界到 y=1000）。


## 规范格 → 未镜像的像素坐标（左上角）
static func cell_pos(cell: Vector2i, pitch: float) -> Vector2:
	return Vector2(float(cell.y) * pitch, float(cell.x) * pitch)


## 规范格 → **当前座位视角**的像素坐标（左上角）
##   mirrored=false ⇒ 规范坐标；true ⇒ 关于棋盘中心 180° 镜像（并减一个格宽）
static func view_cell_pos(cell: Vector2i, pitch: float, board_px: float, mirrored: bool) -> Vector2:
	var p := cell_pos(cell, pitch)
	if not mirrored:
		return p
	return Vector2(board_px, board_px) - p - Vector2(pitch, pitch)
