extends GutTest
## 手牌立绘窗**几何**的纯回归（迭代114 —— 与 view_card_art 同一批交付）
##
## 不起场景：几何只吃参数 + 两个尺寸 ⇒ 可直接手算核对"居中公式"与"原偏移链"。

const Art := preload("res://src/view/view_card_art.gd")
const Params := preload("res://src/data/hand_card_params.gd")


func _p():
	return Params.new()


func test_soldier_uses_base_offset_chain() -> void:
	## 兵蜂（kind_key=""）→ 不居中，走 art_base_offset + crop_offset 的原偏移链
	var p = _p()
	var g: Dictionary = Art.window(p, null, "", Vector2(250, 258), Vector2(194, 196))
	assert_almost_eq(g["size"].x, 400.0, 0.01, "基准宽应为 400")
	assert_almost_eq(g["size"].y, 400.0 * 258.0 / 250.0, 0.01, "窗高应按贴图宽高比推导")
	assert_eq(g["scale"], p.art_base_scale, "缩放应回落到基准")
	assert_eq(g["offset"], p.art_base_offset + p.crop_offset, "偏移应为基准 + 逐卡增量")


func test_queen_centers_with_scale_and_adjust() -> void:
	## 蜂王 → 50% 缩放 + 居中；参数 crop_offset 作**微调**（增量式，不覆盖居中）
	var p = _p()
	var tsz := Vector2(250, 258)
	var plane := Vector2(194, 196)
	var g: Dictionary = Art.window(p, null, "queen", tsz, plane)
	assert_eq(g["scale"], Vector2(0.5, 0.5), "蜂王缩放应为卡种表的 0.5")
	var sz: Vector2 = g["size"]
	var draw := Vector2(sz.x * 0.5, sz.y * 0.5)
	var want: Vector2 = (plane - draw) * 0.5 + p.crop_offset
	assert_almost_eq(g["offset"].x, want.x, 0.01, "居中公式：x")
	assert_almost_eq(g["offset"].y, want.y, 0.01, "居中公式：y")


func test_crop_offset_works_as_increment_on_centered_kind() -> void:
	## 人 2026-10-15 修过的口径：填参数后应"居中 + 偏移"，而不是把居中整段替换掉
	var p = _p()
	p.crop_offset = Vector2(10, 20)
	var base: Dictionary = Art.window(_p(), null, "queen", Vector2(250, 258), Vector2(194, 196))
	var moved: Dictionary = Art.window(p, null, "queen", Vector2(250, 258), Vector2(194, 196))
	assert_almost_eq(moved["offset"].x - base["offset"].x, 10.0, 0.01, "x 应正好偏移 10")
	assert_almost_eq(moved["offset"].y - base["offset"].y, 20.0, 0.01, "y 应正好偏移 20")


func test_missing_texture_falls_back_to_base_window() -> void:
	var p = _p()
	var g: Dictionary = Art.window(p, null, "", Vector2.ZERO, Vector2.ZERO)
	assert_eq(g["size"], Vector2(400, 454), "无贴图时应用 400×454 基准窗")

## ── 详情区立绘适配（迭代131 切出，与手牌同法）──────────────────────────────

func test_detail_portrait_fit_uses_frame_size() -> void:
	## 尺寸 = 父框实测（曾写死 300×300 ⇒ 溢出 26px）
	var g: Dictionary = Art.detail_portrait_fit(
		Vector2(274, 274), Vector2(300, 300), 0.0, 0.0, false)
	assert_eq(g["size"], Vector2(274, 274), "应铺满父框（而不是用参数 art_size）")
	assert_almost_eq(g["y"], 0.0, 0.01, "无 meta 无参数时 y=0")


func test_detail_portrait_fit_frame_fallback_and_meta_priority() -> void:
	## 父框无效 ⇒ 回退 art_size；meta art_offset_y 优先于参数
	var g1: Dictionary = Art.detail_portrait_fit(Vector2(0, 0), Vector2(300, 300), 0.0, 7.0, false)
	assert_eq(g1["size"], Vector2(300, 300), "父框无效应回退参数尺寸")
	assert_almost_eq(g1["y"], 7.0, 0.01, "无 meta 时用参数偏移")
	var g2: Dictionary = Art.detail_portrait_fit(
		Vector2(274, 274), Vector2(300, 300), -12.0, 7.0, true)
	assert_almost_eq(g2["y"], -12.0, 0.01, "meta 优先于参数")