extends RefCounted
## 鼠标穿透 / 忽略子树（自 arena_view 切出 —— 迭代076 · B5 第三刀）
##
## 判据：**只改 Control.mouse_filter，不参与绘制、不改布局** ⇒ 对画面零影响，
##   因此这一刀不需要人目视即可判定「观感不变」。
##
## 背景（迭代059 三次实测）：
##   · 全屏扫描线叠加层 `CrtFx` 默认 STOP，会**吃掉棋盘点击**；
##   · 卡片内部立绘节点也是 STOP，点击到不了卡根的 `_gui_input` ⇒ `unit_pressed` / `hand_pressed` 永不触发。
## 修法一律是「递归设 IGNORE，但保留卡根可点」。


## 一次性铺开：全树的 CrtFx 穿透 + 卡片内部穿透
static func make_overlays_click_through(root: Node, units_root: Node, hand_l: Node,
		hand_r: Node) -> void:
	ignore_crtfx_recursive(root)
	make_card_children_click_through(units_root, hand_l, hand_r)


## 让**卡片内部的所有子节点**鼠标透明；卡根节点保持 STOP（由 card_unit/card_hand 的 _ready 设）
static func make_card_children_click_through(units_root: Node, hand_l: Node, hand_r: Node) -> void:
	if units_root != null:
		for node in units_root.get_children():
			ignore_descendants(node)
	ignore_descendants(hand_l)
	ignore_descendants(hand_r)


## 扫描容器：处理**每张卡的内部**节点，跳过容器的直接子节点（= 卡根）
##   ⚠️ 若把卡根也设成 IGNORE，整张卡都点不到（迭代059 实测）
static func ignore_descendants(container: Node) -> void:
	if container == null:
		return
	for card in container.get_children():
		ignore_children(card)


## 递归把 n 的**所有子 Control** 设为鼠标透明（n 自身不动）
static func ignore_children(n: Node) -> void:
	if n == null:
		return
	for ch in n.get_children():
		if ch is Control:
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		ignore_children(ch)


## 按节点名识别扫描线叠加层（含卡内叠加层）→ 一律鼠标穿透
static func ignore_crtfx_recursive(n: Node) -> void:
	for ch in n.get_children():
		if ch is Control:
			var c := ch as Control
			if String(c.name) == "CrtFx" or String(c.name).begins_with("CrtFx"):
				c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ignore_crtfx_recursive(ch)
