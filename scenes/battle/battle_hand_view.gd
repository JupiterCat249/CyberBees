extends Node2D
## ============================================================
## BattleHandView —— 手牌视图
##   ① 两侧手牌面板内 2x2 渲染手牌（复用框架 card_auto，0.76 缩放 = 190px）
##   ② 六边形徽章内的费用数字：用框架图集字形（0-9）拼出，不用自制字体
##   只读 BattleState；节点位置全部取 BattleDefs 常量。
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

var holder: Node2D = null
var overlay: Node2D = null
var state: Node = null

var _cards_node: Node2D = null
var _hand_nodes := {"green": [], "red": []}
var _badge_digits: Array = []


func setup(h: Node2D, ov: Node2D, st: Node) -> void:
	holder = h
	overlay = ov
	state = st
	_cards_node = Node2D.new()
	_cards_node.name = "HandCards"
	holder.add_child(_cards_node)
	state.state_changed.connect(_on_state_changed)


func _on_state_changed() -> void:
	render_hand("green")
	render_hand("red")
	render_cost_badges()


# ---------------- 手牌 ----------------
func render_hand(side: String) -> void:
	for n in _hand_nodes[side]:
		if is_instance_valid(n):
			n.queue_free()
	_hand_nodes[side] = []
	if state == null:
		return
	var base: Vector2 = D.PANEL_L if side == "green" else D.PANEL_R
	var cards: Array = state.hand[side]
	for i in cards.size():
		# 迭代006（人要求）：手牌改用「图标」素材作立绘（复用框架卡牌节点；无图标素材 → 自动回退旧卡面）
		var ic: String = D.icon_path(str(cards[i]["name"]))
		if ic == "":
			ic = D.icon_path(str(cards[i].get("art", "")))
		var node := D.make_card(cards[i], D.HAND_CARD_SCALE, ic)
		var col := i % 2
		@warning_ignore("integer_division")
		var rowi := i / 2
		node.position = base + Vector2(
			D.HAND_CARD_PAD + col * D.HAND_CARD_STEP,
			D.HAND_CARD_PAD + rowi * D.HAND_CARD_STEP)
		_cards_node.add_child(node)
		# 卡名文字：贴在每格**面板下沿留白**里（卡面视觉高 114px，格高 190px，故 118~145 是空带）
		var nm := D.make_name_label(str(cards[i]["name"]), D.HAND_CARD_SCALE,
			node.position + Vector2(95.0, 133.0), 176.0, 20)
		_cards_node.add_child(nm)
		_hand_nodes[side].append(nm)
		# A5：待放置/待使用的手牌显示框架「卡牌x-选中」边框（扩展既有素材）
		var armed_here: bool = state.armed_card == i and (state.armed_side == side or (state.armed_side == "" and side == state.current))
		if armed_here:
			var tex := load(D.CARD_SELECTED_PATH) as Texture2D
			if tex != null:
				var fr := Sprite2D.new()
				fr.texture = tex
				fr.centered = false
				fr.position = node.position
				var sc := (D.CELL * D.HAND_CARD_SCALE) / float(tex.get_width())
				fr.scale = Vector2(sc, sc)
				_cards_node.add_child(fr)
				_hand_nodes[side].append(fr)
		_hand_nodes[side].append(node)


# ---------------- 费用徽章数字 ----------------
func render_cost_badges() -> void:
	for n in _badge_digits:
		if is_instance_valid(n):
			n.queue_free()
	_badge_digits = []
	if overlay == null or state == null:
		return
	var ink := Color(0.11, 0.09, 0.02)
	var g := D.digit_node(int(state.cost["green"]), D.HEX_DIGIT_H, ink, D.HEX_L)
	overlay.add_child(g)
	_badge_digits.append(g)
	var r := D.digit_node(int(state.cost["red"]), D.HEX_DIGIT_H, ink, D.HEX_R)
	overlay.add_child(r)
	_badge_digits.append(r)
