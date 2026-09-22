class_name BoardMirror
extends RefCounted
## 棋盘镜像（《边界约束》T7：「棋盘镜像（双方视角镜像）」）
## ---------------------------------------------------------------------------
## ⚠️ **只影响呈现层**：中继消息里一律使用引擎的**规范坐标** `cell`
##   → 两端引擎状态天然一致；镜像只在「把规范格转成某玩家视角屏幕格」时使用。
## 约定：引擎 `cell.x = 行` 自上而下 0..3（0-1 为红方/敌方领地，2-3 为绿方/我方领地）
##   对手（seat 1，红方）视角 = 把棋盘**旋转 180°**（x、y 双轴翻转）→ 自己一侧落到屏幕下方
## ---------------------------------------------------------------------------

const N := 4


## 规范格 → 镜像格（对合：镜像两次 = 恒等）
static func mirror_cell(c: Vector2i) -> Vector2i:
	return Vector2i(N - 1 - c.x, N - 1 - c.y)


## 该 seat 是否需要镜像呈现（seat 0 = 绿方 = 规范视角）
static func needs_mirror(seat: int) -> bool:
	return seat != 0


## 按 seat 把规范格转成该玩家视角格
static func to_view(c: Vector2i, seat: int) -> Vector2i:
	return mirror_cell(c) if needs_mirror(seat) else c


## 按 seat 把玩家视角格转回规范格（对合，可用于把点击转成操作坐标）
static func to_canonical(c: Vector2i, seat: int) -> Vector2i:
	return mirror_cell(c) if needs_mirror(seat) else c


## 自检（供验证脚本调用）：返回问题列表，空 = 通过
static func self_test() -> Array[String]:
	var errs: Array[String] = []
	for x in N:
		for y in N:
			var c := Vector2i(x, y)
			if mirror_cell(mirror_cell(c)) != c:
				errs.append("非对合: %s" % str(c))
			if to_view(to_canonical(c, 1), 1) != c:
				errs.append("seat1 往返不一致: %s" % str(c))
	if mirror_cell(Vector2i(0, 0)) != Vector2i(N - 1, N - 1):
		errs.append("180° 旋转定义错")
	## 领地对调：规范行 0-1（敌）↔ 行 2-3（我）
	if mirror_cell(Vector2i(0, 2)).x != N - 1:
		errs.append("领地未对调")
	return errs
