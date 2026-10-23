extends RefCounted
## 手牌卡 / 单位卡**节点创建**（自 arena_view._render_hand / _spawn_unit 切出 —— 迭代113）
##
## 判据：只做"实例化 + 放进容器 + 位置/元数据"这类**机械构造**；
##   绑定数据、加参数、滤镜、鼠标穿透仍由视图按原顺序执行（顺序一变就可能改观感/输入）。
##
## 为什么不把 bind 也放进来：手牌卡的 filter 与单位卡的 mouse_filter 处理夹在
##   "add_child" 与 "bind" 之间（迭代058 实测：漏设会让新单位卡吞掉整块棋盘的点击）——
##   保留调用顺序比少传一个参数更重要。


## 造一张手牌卡：实例化 + 进容器（**不 bind**；绑定与连接由视图做，保持原有顺序）
static func create_hand_card(parent: Control, scene: PackedScene, data: CardData) -> Control:
	var node: Control = scene.instantiate()
	parent.add_child(node)
	if node.has_method("bind"):
		node.call("bind", data)
	return node


## 造一张单位卡：实例化 + 命名 + 规范格元数据 + 视角坐标 + 不旋转（**不 bind、不设鼠标穿透**）
##   name 用实例 id 前 8 位（与原实现一致，便于排障时认卡）
static func create_unit_card(host: Control, scene: PackedScene, inst: UnitInstance,
		cell: Vector2i, cell_pos: Vector2) -> Control:
	var node: Control = scene.instantiate()
	node.name = "Unit_" + inst.instance_id.substr(0, 8)
	## 规范格记进 metadata/cell，供切座位时 _relayout_units() 重算；卡面本身不旋转
	node.set_meta("cell", cell)
	node.position = cell_pos
	node.rotation = 0.0
	node.pivot_offset = Vector2.ZERO
	host.add_child(node)
	return node


## 手牌卡种键（供 UI 参数查表）—— 参数类不得引用 \`CardData\`，故转换放在视图侧
static func hand_kind_key(cd: CardData) -> String:
	if cd == null:
		return ""
	match cd.kind:
		CardData.CardKind.QUEEN:
			return "queen"
		CardData.CardKind.BUILDING:
			return "building"
		CardData.CardKind.COMMAND, CardData.CardKind.COMMAND_X:
			return "order"
	return "unit"
