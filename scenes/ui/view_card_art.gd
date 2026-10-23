extends RefCounted
## 手牌立绘窗**几何**（纯计算）—— 自 arena_view._apply_one_hand_params 的立绘段切出（迭代114）
##
## 判据：只吃参数与两个尺寸（贴图尺寸、裁剪窗尺寸），吐 {size, offset, scale}；
##   不碰节点、不读视图状态 ⇒ 可单测，且"居中 vs 原偏移链"的分支不再埋在 20 行视图代码里。
##
## ⚠️ 口径（与切分前逐行一致）：
##   · 基准宽恒为 **400**；窗高按**贴图自身宽高比**推导（不给贴图时用 400×454 基准）；
##   · 命中"按卡种居中"（HandCardParams.should_center_key）⇒ 居中作基准、参数作微调；
##   · 未命中 ⇒ 直接沿用 final_art_offset(vis)（兵蜂的原始偏移链）；
##   · 裁剪窗小于 4px 视为无效（用 194×196 基准，原实现的同一回退）。

const BASE := Vector2(400, 454)          ## 无贴图时的基准窗
const FALLBACK_PLANE := Vector2(194, 196)  ## 裁剪窗无效时的回退尺寸


static func window(p, vis, kind_key: String, tex_size: Vector2, plane_size: Vector2) -> Dictionary:
	var tsz: Vector2 = tex_size if (tex_size.x > 0.0 and tex_size.y > 0.0) else BASE
	var sz := Vector2(400.0, 400.0 * tsz.y / maxf(tsz.x, 1.0))
	var sc: Vector2 = p.art_scale_for_key(kind_key, vis)
	var off: Vector2 = p.final_art_offset(vis)
	if p.should_center_key(kind_key):
		var pw: Vector2 = plane_size
		if not (pw.x > 4.0 and pw.y > 4.0):
			pw = FALLBACK_PLANE
		var draw: Vector2 = Vector2(sz.x * sc.x, sz.y * sc.y)
		## 增量式：居中作基准、参数作微调 —— 不填参数时与"纯居中"逐字一致
		var adjust: Vector2 = p.crop_offset + (vis.crop_offset if vis != null else Vector2.ZERO)
		off = (pw - draw) * 0.5 + adjust
	return {"size": sz, "offset": off, "scale": sc}


## 详情区立绘**适配几何**（自 arena_view._apply_detail_params 的立绘段切出 —— 迭代131）
##   规则（与人 2026-10-10 的两条修正一致）：
##     · 尺寸 = **父框实测尺寸**（父框无效时才回退参数 art_size）；定位相对父框原点 (0,0)；
##     · 垂直微调：meta `art_offset_y` **优先**，回退参数；不动比例、不改字号。
##   返回 {size: Vector2, y: float}
static func detail_portrait_fit(frame_size: Vector2, art_size: Vector2, offset_meta: float,
		offset_param: float, has_meta: bool) -> Dictionary:
	var size: Vector2 = frame_size if (frame_size.x > 1.0 and frame_size.y > 1.0) else art_size
	return {"size": size, "y": (offset_meta if has_meta else offset_param)}
