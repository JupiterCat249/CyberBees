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
