extends GutTest
## 手牌立绘窗**几何**的纯回归（迭代114 —— 与 view_card_art 同一批交付）
##
## 不起场景：几何只吃参数 + 两个尺寸 ⇒ 可直接手算核对"居中公式"与"原偏移链"。

const Art := preload("res://scenes/ui/view_card_art.gd")
const Params := preload("res://scripts/data/hand_card_params.gd")


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
