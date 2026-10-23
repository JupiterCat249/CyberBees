extends GutTest
## 视觉参数"是否真的生效"的**可读回归**（迭代108）
##
## 为什么需要：_apply_detail_params / _apply_one_hand_params 是视图里最大的两块（72/53 行），
##   但此前的回归只证明"逻辑/交互"，**证明不了参数有没有落地** ⇒ 切它没有安全网。
##   本册只断言读数：节点尺寸/字号/拉伸模式 == 参数值（或 == 由贴图推导出的值）。
##
## ⚠️ 口径（人 2026-09-19）：字号字段 **默认 0 = 沿用素材原值**，只有显式正数才覆盖 ——
##   所以这里只在"参数 > 0"时断言等于参数，不假设 0 时没有 override（场景可能自带）。

const BattleScene := preload("res://scenes/ui/battle_scene.tscn")

var _scene: Node = null


func before_each() -> void:
	_scene = BattleScene.instantiate()
	add_child(_scene)
	await wait_frames(3)


func after_each() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()
		_scene = null
	await wait_frames(1)


func test_detail_portrait_fits_parent_and_keeps_aspect() -> void:
	## 迭代067 口径：立绘以**父框实测尺寸**铺满、居中不裁、相对父原点定位
	var portrait = _scene.get_node_or_null("HUD/InfoPanel/DetailBlock/Artwork/Portrait")
	assert_not_null(portrait, "前置：详情区应有 Portrait")
	var frame = portrait.get_parent()
	var p = _scene.get("detail_params")
	assert_almost_eq(portrait.size.x, frame.size.x, 0.5, "立绘宽应等于父框宽")
	assert_almost_eq(portrait.size.y, frame.size.y, 0.5, "立绘高应等于父框高")
	assert_almost_eq(portrait.position.x, 0.0, 0.01, "水平应相对父原点（0）")
	var want_y: float = float(p.art_offset_y)
	if portrait.has_meta("art_offset_y"):
		want_y = float(portrait.get_meta("art_offset_y"))
	assert_almost_eq(portrait.position.y, want_y, 0.01, "垂直偏移应取 meta 优先、参数回退")
	assert_eq(int(portrait.stretch_mode), int(TextureRect.STRETCH_KEEP_ASPECT_CENTERED), "按比例居中、不裁切")
	assert_eq(int(portrait.expand_mode), int(TextureRect.EXPAND_IGNORE_SIZE), "不按最小尺寸收缩")


func test_detail_font_sizes_follow_params_when_positive() -> void:
	var p = _scene.get("detail_params")
	var nm = _scene.get_node_or_null("HUD/InfoPanel/CardName")
	var ds = _scene.get_node_or_null("HUD/InfoPanel/SkillDesc")
	if int(p.name_font_size) > 0:
		assert_eq(nm.get_theme_font_size("font_size"), int(p.name_font_size), "卡名字号应等于参数")
	if int(p.desc_font_size) > 0:
		assert_eq(ds.get_theme_font_size("font_size"), int(p.desc_font_size), "技能描述字号应等于参数")
		assert_eq(ds.get_theme_constant("line_spacing"), int(p.desc_line_spacing), "描述行距应等于参数")
	assert_true(nm != null and ds != null, "两个标签都应存在")


func test_attr_rows_show_selected_unit_values() -> void:
	## 迭代108 实测 bug：`_rows()` 曾按 "Row1..Row4" 找节点，而场景里叫 Attack/Health/Speed/Range
	##   ⇒ 详情区四维数值**从未更新过**。本用例锁住"点了单位，四行数值 = 该单位数据"。
	var Pool := preload("res://src/data/card_pool.gd")
	var data = Pool.card("泥蜂")
	assert_not_null(data, "前置：应能取到泥蜂卡数据")
	_scene.show_detail(data)
	await wait_frames(1)
	var attrs = _scene.get_node_or_null("HUD/InfoPanel/Attributes")
	assert_not_null(attrs, "前置：应有属性区")
	var want := [str(data.atk), str(data.hp), str(data.move), str(data.attack_range)]
	var names := ["Attack", "Health", "Speed", "Range"]
	for i in names.size():
		var row = attrs.get_node_or_null(names[i])
		assert_not_null(row, "属性行 %s 应存在" % names[i])
		var v = row.get_node_or_null("Value")
		assert_not_null(v, "属性行 %s 应有 Value" % names[i])
		assert_eq(String(v.text), want[i], "属性行 %s 数值应等于该单位数据" % names[i])


func test_first_hand_card_badge_follows_params() -> void:
	var p = _scene.get("hand_params")
	var nodes: Dictionary = _scene.get("_hand_nodes")
	var card = null
	for id in nodes[0].keys():
		card = nodes[0][id]
		break
	assert_not_null(card, "前置：己方手牌应有卡节点")
	var badge = card.get_node_or_null("BadgeImage")
	assert_not_null(badge, "前置：手牌卡应有 BadgeImage")
	assert_almost_eq(badge.size.x, float(p.badge_size.x), 0.5, "徽章宽应等于参数")
	assert_almost_eq(badge.size.y, float(p.badge_size.y), 0.5, "徽章高应等于参数（正方形，不按贴图拉长）")
	assert_eq(int(badge.stretch_mode), int(TextureRect.STRETCH_KEEP_ASPECT_CENTERED), "贴图按比例居中")
	var line = card.get_node_or_null("InnerLine")
	if line != null:
		assert_almost_eq(line.size.x, float(p.inner_line_size.x), 0.5, "内描边宽应等于参数")


func test_first_hand_card_art_uses_texture_aspect() -> void:
	## 迭代064/067 口径：基准宽固定 400，窗高按**贴图自身宽高比**推导（避免拉伸变形）
	var nodes: Dictionary = _scene.get("_hand_nodes")
	var card = null
	for id in nodes[0].keys():
		card = nodes[0][id]
		break
	assert_not_null(card, "前置：应有手牌卡")
	var img = card.get_node_or_null("Artwork/ArtPlane/Image")
	if img == null or img.texture == null:
		pending("本卡无立绘贴图，跳过")
		return
	var w: float = img.offset_right - img.offset_left
	var h: float = img.offset_bottom - img.offset_top
	assert_almost_eq(w, 400.0, 0.5, "基准宽应为 400")
	var tsz: Vector2 = img.texture.get_size()
	assert_almost_eq(h, 400.0 * tsz.y / tsz.x, 1.0, "窗高应按贴图宽高比推导（不得拉伸）")

## ── 手牌重建 / 单位卡生成的**可读读数**（迭代111：切它们的前置网兜）─────────────

func test_hand_render_matches_engine_hand() -> void:
	## 手牌一有变化就整体重绘 ⇒ 渲染结果必须与引擎手牌**一一对应**（数量/顺序/id 集合）
	var e = _scene.get("engine")
	_scene._on_hand_changed(0, e.state.sides[0]["hand"], [])
	await wait_frames(1)
	var nodes: Dictionary = _scene.get("_hand_nodes")[0]
	var order: Array = _scene.get("_hand_order")[0]
	var hand: Array = e.state.sides[0]["hand"]
	assert_eq(nodes.size(), hand.size(), "手牌节点数应等于引擎手牌数")
	assert_eq(order.size(), hand.size(), "顺序表长度应与手牌一致")
	for i in hand.size():
		assert_true(nodes.has(String(hand[i].id)), "第 %d 张应有对应节点" % i)
		assert_eq(String(order[i]), String(hand[i].id), "顺序应与引擎手牌一致（第 %d 张）" % i)


func test_unit_spawn_creates_bound_node_at_cell() -> void:
	## 单位卡生成：进册 · 绑定同一份卡数据 · 位置按视角坐标 · 规范格记进 meta
	var e = _scene.get("engine")
	var FixtureLib := preload("res://tests/support/battle_fixture.gd")
	var u = FixtureLib.place_unit(e, 1, "泥蜂", Vector2i(1, 2))
	assert_not_null(u, "前置：应能放下单位")
	_scene._on_unit_spawned(u, u.cell)
	await wait_frames(1)
	var nodes: Dictionary = _scene.get("_unit_nodes")
	assert_true(nodes.has(u.instance_id), "应在 _unit_nodes 里注册")
	var node = nodes[u.instance_id]
	assert_not_null(node, "节点应有效")
	assert_eq(node.get_meta("cell"), u.cell, "规范格应记入 meta（供切座位时重算）")
	assert_eq(node.position, _scene._view_cell_pos(u.cell), "位置应按视角坐标摆放")
	assert_eq(String(node.get("unit_id")), u.instance_id, "单位卡应绑定该实例 id（_unit_view 的 id 字段）")

func test_badge_value_fills_badge_and_uses_project_font() -> void:
	## 锁住迭代065/067 的两条修复：① 费用数字**铺满徽章**并对齐居中（不按行盒算尺寸）
	##   ② 显式绑定**项目自带字体**（两端行盒一致，否则"对端数字偏下"）
	var nodes: Dictionary = _scene.get("_hand_nodes")
	var card = null
	for id in nodes[0].keys():
		card = nodes[0][id]
		break
	assert_not_null(card, "前置：应有手牌卡")
	var badge = card.get_node_or_null("BadgeImage")
	assert_not_null(badge, "前置：应有徽章")
	var bv = badge.get_node_or_null("Value")
	assert_not_null(bv, "前置：徽章应有 Value（路径 BadgeImage/Value 被多处按路径取用）")
	assert_almost_eq(bv.size.x, badge.size.x, 0.5, "Value 宽应铺满徽章")
	assert_almost_eq(bv.size.y, badge.size.y, 0.5, "Value 高应铺满徽章")
	assert_eq(int(bv.horizontal_alignment), int(HORIZONTAL_ALIGNMENT_CENTER), "水平居中")
	assert_eq(int(bv.vertical_alignment), int(VERTICAL_ALIGNMENT_CENTER), "垂直居中")
	var f = bv.get_theme_font("font")
	assert_true(f is FontFile, "费用数字应绑定具体字体文件（不是 SystemFont）")
	var fp := String(f.resource_path)
	assert_true(fp.contains("NotoSansSC"), "应为项目自带 NotoSansSC：%s" % fp)

func test_detail_attr_icon_keeps_scene_size() -> void:
	## ⭐ 人 2026-10-23 裁定：详情区**以场景设计为权威** —— 属性行图标保持场景值（40×40），
	##   参数（默认 24×24）**不得**缩小它；若冲突，应改参数而不是改设计。
	_scene.apply_params()
	await wait_frames(1)
	var attrs = _scene.get_node_or_null("HUD/InfoPanel/Attributes")
	assert_not_null(attrs, "前置：应有属性行容器")
	var row = attrs.get_node_or_null("Attack")
	assert_not_null(row, "四维行应以**真实节点名**存在（不是 Row1）")
	var ic: TextureRect = row.get_node_or_null("Icon")
	assert_not_null(ic, "前置：该行应有 Icon")
	var prm = _scene.get("detail_params")
	assert_ne(ic.size, prm.attr_icon_size, "图标尺寸不得被参数覆盖（参数 %s）" % str(prm.attr_icon_size))
	assert_true(ic.size.x >= 30.0, "场景图标应保持设计尺寸（实测 %s）" % str(ic.size))
