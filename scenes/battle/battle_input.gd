extends Node
## ============================================================
## BattleInput —— 输入路由（Controller 层）
##   职责：把鼠标事件翻译成"语义信号"（点了哪张手牌 / 哪个格子 / 哪个按钮），
##         完全不判断规则——规则判断由 BattleState 决定。
##   坐标：先把屏幕坐标换算为 1920x1080 设计坐标（逆用框架 Holder 的变换）。
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

signal hand_clicked(side: String, index: int)   ## 点了手牌
signal cell_clicked(cell: Vector2i)             ## 点了地图格
signal support_clicked(cell: Vector2i)          ## Shift+点格（支援技能）
signal main_pressed()                           ## 点了主按钮
signal small_pressed(index: int)                ## 点了右下小按钮
signal click_empty()                            ## 点了非交互区域（A5：取消当前选中）

## 由协调器注入
var holder: Node2D = null


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var p := to_design(mb.position)

	# ① 主按钮
	if Rect2(D.BTN_MAIN, D.BTN_MAIN_SZ).has_point(p):
		main_pressed.emit()
		return
	# ② 右下 4 个小按钮
	for k in 4:
		var c := D.SBTN0 + Vector2(k * D.SBTN_DX, 0.0)
		if Rect2(c - Vector2(D.SBTN_HIT, D.SBTN_HIT), Vector2(D.SBTN_HIT * 2.0, D.SBTN_HIT * 2.0)).has_point(p):
			small_pressed.emit(k)
			return
	# ③ 两侧手牌面板
	for side in ["green", "red"]:
		var base: Vector2 = D.PANEL_L if side == "green" else D.PANEL_R
		if not Rect2(base, Vector2(D.PANEL_SZ, D.PANEL_SZ)).has_point(p):
			continue
		var lp := p - base
		@warning_ignore("integer_division")
		var col := int(lp.x / D.HAND_CARD_STEP)
		@warning_ignore("integer_division")
		var rowi := int(lp.y / D.HAND_CARD_STEP)
		hand_clicked.emit(side, rowi * 2 + col)
		return
	# ④ 地图格
	var cell := D.pos_cell(p)
	if not D.in_map(cell):
		# A5 程序需求：点击非交互区域取消当前选中（主按钮/小按钮/手牌面板已在上面处理）
		click_empty.emit()
		return
	if Input.is_key_pressed(KEY_SHIFT):
		support_clicked.emit(cell)
	else:
		cell_clicked.emit(cell)


## 屏幕坐标 -> 设计坐标（逆用框架 Holder 的等比缩放/居中）
func to_design(screen_pos: Vector2) -> Vector2:
	if holder == null:
		return screen_pos
	var xf := (holder.get_global_transform() as Transform2D).affine_inverse()
	return xf * screen_pos
