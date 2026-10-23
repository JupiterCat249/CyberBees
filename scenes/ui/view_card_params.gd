extends RefCounted
## 手牌卡**徽章与描边**的参数落地（自 arena_view._apply_one_hand_params 切出 —— 迭代115）
##
## 判据：只做"参数 → 节点尺寸/拉伸/字号/几何居中"这类既有机械动作；
##   立绘窗几何仍由 view_card_art（纯计算）负责，视图只负责"取节点 + 调本模块"。
##
## ⚠️ 守住人 2026-09-19 的硬约束：**字号只在参数显式给正数时才覆盖**（0 = 沿用素材原值）。
## ⚠️ 迭代067 的两个实测结论也在这里：徽章本体是**正方形**（贴图按比例居中，不按贴图拉长），
##   费用数字用**与信息栏同一套几何居中**（Layout.center_badge_value_geometry），杜绝分叉。

const Layout := preload("res://scenes/ui/view_layout.gd")
const CardArt := preload("res://scenes/ui/view_card_art.gd")
const Cards := preload("res://scenes/ui/view_cards.gd")


## 应用徽章（BadgeImage）与内描边（InnerLine）
static func apply_hand_extras(node: Node, p) -> void:
	var badge: TextureRect = node.get_node_or_null("BadgeImage")
	if badge != null:
		## 节点保持参数给的**正方形**；贴图按比例居中（曾按贴图宽高比撑高 ⇒ 数字显得靠下 ✗）
		badge.size = p.badge_size
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var bv: Label = badge.get_node_or_null("Value")
		## 只覆盖字号（素材原值 48；曾覆盖成 26 变小）
		if bv != null and int(p.badge_font_size) > 0:
			bv.add_theme_font_size_override("font_size", int(p.badge_font_size))
		## 与信息栏共用同一套几何居中（人反馈"对端数字过度靠下"）
		Layout.center_badge_value_geometry(badge)
	var line: Panel = node.get_node_or_null("InnerLine")
	if line != null:
		line.size = p.inner_line_size


## 手牌卡的**视觉参数**（徽章/描边 + 立绘窗）—— 自 _apply_one_hand_params 整体搬入（迭代118）
##   ⚠️ 立绘段的来历写在这里（原注释）：迭代064 逐字恢复 \`254d42a~1\` 的原始正确版本
##   （基准窗固定 400×454、裁剪靠 ArtPlane.clip_contents、偏移走 final_art_offset），
##   仅加"三型缩到 50% 并在窗内居中"这一条修正；贴图宽高比问题见 view_card_art。
static func apply_hand_card_visuals(node: Node, p) -> void:
	apply_hand_extras(node, p)
	var img: TextureRect = node.get_node_or_null("Artwork/ArtPlane/Image")
	if img == null or node.get("card_data") == null:
		return
	var cd: CardData = node.get("card_data") as CardData
	var key := Cards.hand_kind_key(cd)
	var tsz: Vector2 = img.texture.get_size() if img.texture != null else Vector2.ZERO
	var plane: Control = img.get_parent()
	var plane_sz: Vector2 = plane.size if plane != null else Vector2.ZERO
	var g: Dictionary = CardArt.window(p, cd.visual, key, tsz, plane_sz)
	var sz: Vector2 = g["size"]
	img.offset_left = g["offset"].x
	img.offset_top = g["offset"].y
	img.offset_right = g["offset"].x + sz.x
	img.offset_bottom = g["offset"].y + sz.y
	img.scale = g["scale"]


## 手牌卡的**状态滤镜**（对称滤镜 + 费用可用性）—— 自 _render_hand 循环体搬入（迭代118）
##   口径：整卡滤镜 = "该侧是不是当前行动方"（与费用够不够无关）；
##         费用够不够由费用图标/数字单独表达（hand_affordable 是显示口径）。
static func apply_hand_card_filters(node: Node, engine, side: int, my_seat: int,
		index: int) -> void:
	var active_side0: int = int(engine.state.active) if engine != null else my_seat
	_call_opt(node, "set_playable", [true, int(side) != active_side0])
	var cost_ok0: bool = engine.hand_affordable(side, index) if engine != null else false
	_call_opt(node, "set_cost_affordable", [cost_ok0])


static func _call_opt(node: Object, method: String, args: Array) -> void:
	if node != null and is_instance_valid(node) and node.has_method(method):
		node.callv(method, args)
