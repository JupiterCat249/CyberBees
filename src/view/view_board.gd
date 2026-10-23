extends RefCounted
## 棋盘格**装配**（自 arena_view._adopt_cells 切出 —— 迭代130）
##
## 判据：只做"取或造节点 + 设脚本/规范格/鼠标过滤"；**信号连接与 _cells 登记留在视图**
##   （连接顺序与回调身份属于视图契约，搬走只会多一层间接）。
##
## ⚠️ 位置只在**新建**时设置（与原实现一致）：场景里已有的格由 .tscn 给位置；
##   切座位时统一由 `_relayout_cells()` 重排。


static func ensure_cell(root: Node, node_name: String, cell_size: Vector2, pos: Vector2,
		cell_script: Script, cell: Vector2i) -> Control:
	var node: Control = root.get_node_or_null(node_name) as Control
	if node == null:
		node = Control.new()
		node.name = node_name
		node.position = pos
		node.size = cell_size
		root.add_child(node)
	node.set_script(cell_script)
	node.set("cell", cell)
	node.set("mouse_filter", Control.MOUSE_FILTER_STOP)
	return node
