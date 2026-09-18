extends Control
## BattleScene —— 战斗场景**接线控制器**（组合素材场景 + 驱动 GameState）
##
## 定位：本脚本**不是规则引擎**。它只做三件事，把"素材场景"与"游戏逻辑"接起来：
##   ① 把逻辑层的数据绑到节点（set_hand / add_unit / set_* …）
##   ② 把节点发出的交互信号**翻译**为规则调用，并转发给外层（emit）
##   ③ 把逻辑层下发的"可操作态"翻译成视图表现
##
## 通信原则（D-1）：组件只 emit 自己的信号、**不认识**本类；规则层只发状态信号、**不引用 UI**；
##   本类夹在中间做翻译。
##
## ⚠️ **场景内已有"烤好的"预览内容**（16 格 + 双方蜂王 + 双方各 4 张手牌）：
##   目的是"在编辑器里打开场景就能看到内容"（不必运行）。
##   运行时本类会**接手**这些节点（按名字认领格子、清掉预览手牌后按真实数据重建），
##   因此预览与运行时不会重复堆叠。
##
## 素材场景（勿改结构）：battle_ui_alpha.tscn（本场景继承）· card_hand.tscn · card_unit.tscn

const HAND_CARD_SCENE := preload("res://scenes/ui/card_hand.tscn")
const UNIT_CARD_SCENE := preload("res://scenes/ui/card_unit.tscn")
const CELL_SCRIPT := preload("res://scenes/ui/board_cell.gd")
const GameStateScript := preload("res://scripts/game/game_state.gd")
const SampleDeckLib := preload("res://scripts/data/sample_deck.gd")
const AnimDriverScript := preload("res://scripts/game/battle_anim_driver.gd")

const PITCH := 250.0                        ## 格宽 = 单位卡尺寸
const HAND_SLOT := Vector2(200.0, 200.0)
const HAND_GAP := Vector2(30.0, 30.0)

@export var auto_start := true              ## 直接运行本场景时用样例卡组自动开局
@export var first_player: int = 0           ## 0 = 我方先手
@export var ally_name: String = "玩家·绿"
@export var enemy_name: String = "玩家·红"
@export var ally_hand_side: String = "right"

# ---------------- 对外信号 ----------------
signal battle_ended(result: int, reason: String)
signal request_quit()
signal hand_card_clicked(card_id: String)
signal hand_card_long_pressed(card_id: String)
signal unit_clicked(instance_id: String)
signal unit_long_pressed(instance_id: String)

# ---------------- 内部引用 ----------------
var state: Node = null                      ## GameState（规则层）
var anim: Node = null                       ## BattleAnimDriver（表现层）
var _cells := {}                            ## Vector2i → BoardCell
var _unit_nodes := {}                       ## instance_id → UnitCard
var _hand_nodes := {}                       ## card_id → HandCard
var _hand_order: Array = []
var _fading := {}                           ## 正在播退场动画的 instance_id

@onready var _cells_root: Control = $Battle/MapView/MapCells
@onready var _units_root: Control = $Battle/MapView/Units
@onready var _hand_r: Control = $Battle/HandPanelRight/HandRight
@onready var _hand_l: Control = $Battle/HandPanelLeft/HandLeft


func _ready() -> void:
	state = GameStateScript.new()
	state.name = "GameState"
	add_child(state)
	anim = AnimDriverScript.new()
	anim.name = "AnimDriver"
	add_child(anim)
	anim.set_node_provider(func(id: String) -> Node: return _unit_nodes.get(id, null))
	anim.set_fx_parent(self)
	anim.unit_fade_out_done.connect(_on_fade_out_done)
	anim.reposition_needed.connect(_snap_units)
	_connect_rules()
	_connect_static_ui()
	_build_cells()
	set_player_names(ally_name, enemy_name)
	if auto_start:
		start_battle({0: SampleDeckLib.build("绿"), 1: SampleDeckLib.build("红")},
			first_player, {0: ally_name, 1: enemy_name})


## 开局：传入双方卡组（DeckData）与先手方
func start_battle(decks: Dictionary, first_player_side: int = 0, names: Dictionary = {}) -> void:
	state.setup(decks, first_player_side, names)
	_refresh_all()


func _connect_static_ui() -> void:
	var main: Button = $HUD/ActionBar/MainButton
	if main and not main.pressed.is_connected(_on_main_pressed):
		main.pressed.connect(_on_main_pressed)
	for nm in ["Settings", "Emote", "Info", "Back"]:
		var b: Button = $HUD/FuncButtonGroup.get_node_or_null(nm + "/Button")
		if b and not b.pressed.is_connected(_on_func_pressed):
			b.pressed.connect(_on_func_pressed.bind(nm))


# ============================================================
#  规则层 → 视图（信号翻译）
# ============================================================

func _connect_rules() -> void:
	state.state_changed.connect(_refresh_all)
	state.hand_changed.connect(func(_s: int) -> void: _refresh_hand())
	state.cost_changed.connect(func(_s: int, _v: int) -> void: _refresh_cost())
	state.unit_spawned.connect(func(i: UnitInstance) -> void: anim.on_unit_spawned(i))
	state.unit_moved.connect(func(i: UnitInstance) -> void: anim.on_unit_moved(i))
	state.unit_damaged.connect(func(i: UnitInstance, v: int) -> void: anim.on_unit_damaged(i, v))
	state.effect_changed.connect(func(i: UnitInstance) -> void: anim.on_effect_changed(i))
	state.unit_removed.connect(func(i: UnitInstance) -> void: anim.on_unit_removed(i))
	state.unit_spawned.connect(_on_unit_spawned)
	state.unit_moved.connect(_on_unit_moved)
	state.unit_removed.connect(_on_unit_removed)
	state.effect_changed.connect(_refresh_unit)
	state.phase_changed.connect(func(_a: int, _p: int, _r: int) -> void: _refresh_highlights())
	state.selection_changed.connect(func(_k: String, _id: String) -> void: _refresh_highlights())
	state.turn_started.connect(_on_turn_started)
	state.log_added.connect(_on_log)
	state.main_button_state.connect(_set_main)
	state.battle_ended.connect(_on_battle_ended)


func _on_battle_ended(r: int, why: String) -> void:
	_set_main("对局结束", false)
	battle_ended.emit(r, why)


func _set_main(text: String, enabled: bool) -> void:
	var b: Button = $HUD/ActionBar/MainButton
	b.disabled = not enabled
	$HUD/ActionBar/Label.text = text


func _on_turn_started(active: int, round_no: int) -> void:
	$HUD/MatchInfo/TurnInfo.text = "回合%d--%s" % [round_no, "先手" if active == 0 else "后手"]
	_refresh_cost()


func _refresh_cost() -> void:
	for side in [0, 1]:
		var node := $Battle/PlayerBesaInfoLift if side == 0 else $Battle/PlayerBesaInfoRight
		var lb: Label = node.get_node_or_null("BadgeImage/Value")
		if lb:
			lb.text = str(int(state.cost[side]))


func _on_log(t: String) -> void:
	print("[BATTLE] ", t)
	var m := t.find(" 回费 +")
	if m < 0:
		return
	var rest := t.substr(m + 5)
	var num := ""
	for ch in rest:
		if ch >= "0" and ch <= "9":
			num += ch
		elif num != "":
			break
	if num == "":
		return
	var mine: bool = t.begins_with(str(state.player_names.get(0, "?")))
	var anchor: Control = $Battle/PlayerBesaInfoLift/BadgeImage if mine else $Battle/PlayerBesaInfoRight/BadgeImage
	anim.float_text_raw(int(num), "refund", anchor.global_position + Vector2(0, 40))


# ============================================================
#  棋盘格（点击命中区，无视觉 —— 棋盘视觉由地图素材自带）
# ============================================================

func _build_cells() -> void:
	# 场景里**已烤好** 16 个格（Cell_x_y）→ 直接认领，避免重复
	for ch in _cells_root.get_children():
		if ch.get_script() != CELL_SCRIPT:
			ch.set_script(CELL_SCRIPT)
		if not ch.has_signal("cell_clicked"):
			continue
		if not ch.cell_clicked.is_connected(_on_cell_clicked):
			ch.cell_clicked.connect(_on_cell_clicked)
		_cells[ch.cell] = ch
	if _cells.size() == 16:
		return
	# 兜底：场景里缺失的格按需补建
	for x in 4:
		for y in 4:
			var c := Vector2i(x, y)
			if _cells.has(c):
				continue
			var node: Control = Control.new()
			node.set_script(CELL_SCRIPT)
			node.name = "Cell_%d_%d" % [x, y]
			node.position = _cell_pos_in_units(c)
			node.size = Vector2(PITCH, PITCH)
			node.cell = c
			node.cell_clicked.connect(_on_cell_clicked)
			_cells_root.add_child(node)
			_cells[c] = node


func _on_cell_clicked(cell: Vector2i) -> void:
	if state == null:
		return
	if state.sel_support != null:
		var tgt: UnitInstance = state.board.unit_at(cell)
		if tgt != null and state.confirm_support(tgt):
			state.cancel_selection()
		_refresh_highlights()
		return
	if state.sel_kind == state.SelKind.HAND:
		var idx: int = state.sel_hand_index
		var hand_cards: Array = state.hand[0]
		if idx < 0 or idx >= hand_cards.size():
			state.cancel_selection()
			return
		var card: CardData = hand_cards[idx]
		if card is UnitData:
			state.deploy_unit(0, idx, cell)
		else:
			var target: UnitInstance = state.board.unit_at(cell)
			if target != null and state.use_command(0, idx, target):
				state.cancel_selection()
		_refresh_highlights()
		return
	if state.sel_kind == state.SelKind.UNIT and state.sel_unit != null:
		var u: UnitInstance = state.sel_unit
		var occupant: UnitInstance = state.board.unit_at(cell)
		if occupant != null and occupant.side != u.side:
			state.attack(u, occupant)
		else:
			state.move_unit(u, cell)
		_refresh_highlights()
		return
	var here: UnitInstance = state.board.unit_at(cell)
	if here != null and here.side == 0:
		state.select_unit(here)
		show_card_detail(here.data)
		_refresh_highlights()


func _cell_pos_in_units(cell: Vector2i) -> Vector2:
	## ⚠️ 坐标约定（沿用项目既有口径）：cell.x = 行、cell.y = 列
	return Vector2(cell.y * PITCH, cell.x * PITCH)


# ============================================================
#  单位卡
# ============================================================

func _on_unit_spawned(inst: UnitInstance) -> void:
	_spawn_unit_node(inst)
	_refresh_highlights()


func _spawn_unit_node(inst: UnitInstance) -> void:
	if inst == null or _unit_nodes.has(inst.instance_id):
		_refresh_unit(inst)
		return
	# 运行时以**真实数据**为准：清掉场景里烤的预览单位，避免与真实单位重复
	if _units_root.get_child_count() > 0 and _unit_nodes.is_empty():
		for ch in _units_root.get_children():
			ch.queue_free()
	var node: Control = UNIT_CARD_SCENE.instantiate()
	node.name = "Unit_" + inst.instance_id.substr(0, 8)
	node.position = _cell_pos_in_units(inst.cell)
	_units_root.add_child(node)
	node.bind(unit_view_data(inst))
	if node.has_signal("unit_pressed"):
		node.unit_pressed.connect(_on_unit_clicked)
	elif node.has_signal("unit_clicked"):
		node.unit_clicked.connect(_on_unit_clicked)
	if node.has_signal("unit_long_pressed"):
		node.unit_long_pressed.connect(_on_unit_long_pressed)
	_unit_nodes[inst.instance_id] = node


## UnitInstance → 单位卡绑定字典（视觉层数据；静态走 data、运行态走实例）
func unit_view_data(inst: UnitInstance) -> Dictionary:
	if inst == null:
		return {}
	var kind := "unit"
	if inst.data != null:
		match inst.data.kind:
			CardData.CardKind.QUEEN: kind = "queen"
			CardData.CardKind.BUILDING: kind = "building"
			CardData.CardKind.COMMAND, CardData.CardKind.COMMAND_X: kind = "order"
	return {
		"id": inst.instance_id,
		"cost": inst.data.cost if inst.data != null else 0,
		"atk": inst.atk(),
		"hp": inst.current_hp,
		"move": inst.move_range(),
		"range": inst.attack_range(),
		"mine": inst.side == 0,
		"type": kind,
	}


func _on_unit_clicked(instance_id: String) -> void:
	unit_clicked.emit(instance_id)
	if state == null:
		return
	var inst := _find_unit(instance_id)
	if inst == null:
		return
	if inst.side == 0:
		state.select_unit(inst)
		show_card_detail(inst.data)
	else:
		var u: UnitInstance = state.sel_unit
		if u != null:
			state.attack(u, inst)
	_refresh_highlights()


func _on_unit_long_pressed(instance_id: String) -> void:
	unit_long_pressed.emit(instance_id)


func _on_unit_moved(inst: UnitInstance) -> void:
	_refresh_unit(inst)
	_refresh_highlights()


func _on_unit_removed(inst: UnitInstance) -> void:
	_fading[inst.instance_id] = true
	if not _unit_nodes.has(inst.instance_id):
		_fading.erase(inst.instance_id)


func _on_fade_out_done(instance_id: String) -> void:
	_fading.erase(instance_id)
	if _unit_nodes.has(instance_id) and is_instance_valid(_unit_nodes[instance_id]):
		_unit_nodes[instance_id].queue_free()
	_unit_nodes.erase(instance_id)


func _refresh_unit(inst: UnitInstance) -> void:
	if inst == null:
		return
	if not _unit_nodes.has(inst.instance_id):
		_spawn_unit_node(inst)
	if _unit_nodes.has(inst.instance_id):
		var n: Control = _unit_nodes[inst.instance_id]
		n.bind(unit_view_data(inst))
		n.position = _cell_pos_in_units(inst.cell)


func _find_unit(instance_id: String) -> UnitInstance:
	if state == null:
		return null
	for u in state.board.all_units():
		if u.instance_id == instance_id:
			return u
	return null


## 把全部单位节点吸附回**格子基准位置**（位移类动画的收位）
func _snap_units() -> void:
	if state == null:
		return
	for u in state.board.all_units():
		if _unit_nodes.has(u.instance_id) and is_instance_valid(_unit_nodes[u.instance_id]):
			_unit_nodes[u.instance_id].position = _cell_pos_in_units(u.cell)


# ============================================================
#  手牌（双方都渲染）
# ============================================================

func _refresh_hand() -> void:
	_render_hand_side(0, true)
	_render_hand_side(1, false)
	_refresh_hand_playable()


func _hand_parent(side: int) -> Control:
	var is_ally := side == 0
	if ally_hand_side == "right":
		return _hand_r if is_ally else _hand_l
	return _hand_l if is_ally else _hand_r


## 渲染一侧手牌（重建；我方那侧接信号可交互）
func _render_hand_side(side: int, interactive: bool) -> void:
	var parent := _hand_parent(side)
	if parent == null:
		return
	for c in parent.get_children():
		c.queue_free()
	if interactive:
		_hand_nodes.clear()
		_hand_order.clear()
	var cards: Array = state.hand[side]
	for i in cards.size():
		var data: CardData = cards[i]
		if data == null:
			continue
		var node: Control = HAND_CARD_SCENE.instantiate()
		var col := i % 2
		var row := i / 2
		node.position = Vector2(col * (HAND_SLOT.x + HAND_GAP.x), row * (HAND_SLOT.y + HAND_GAP.y))
		parent.add_child(node)
		if node.has_method("bind"):
			node.call("bind", data)
		if interactive:
			if node.has_signal("hand_clicked"):
				node.hand_clicked.connect(_on_hand_clicked)
			if node.has_signal("hand_long_pressed"):
				node.hand_long_pressed.connect(_on_hand_long_pressed)
			_hand_nodes[data.id] = node
			_hand_order.append(data.id)
		else:
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_hand_clicked(card_id: String) -> void:
	hand_card_clicked.emit(card_id)
	if state == null:
		return
	var idx := _hand_order.find(card_id)
	if idx >= 0:
		state.select_hand(idx)
		var cards: Array = state.hand[0]
		if idx < cards.size():
			show_card_detail(cards[idx])
	_refresh_highlights()


func _on_hand_long_pressed(card_id: String) -> void:
	hand_card_long_pressed.emit(card_id)


func _refresh_hand_playable() -> void:
	for i in _hand_order.size():
		var n: Control = _hand_nodes.get(_hand_order[i], null)
		if n == null:
			continue
		_call_opt(n, "set_playable", [state.active == 0 and state.can_play_hand(0, i)])
		_call_opt(n, "set_selected", [state.sel_kind == state.SelKind.HAND and state.sel_hand_index == i])


# ============================================================
#  高亮（把规则层的可操作集合翻译为表现）
# ============================================================

func _refresh_highlights() -> void:
	if state == null:
		return
	for c in _cells.keys():
		_cells[c].set_highlight("")
		_cells[c].set_selected(false)
	for id in _unit_nodes.keys():
		_call_opt(_unit_nodes[id], "set_selectable", [false])
		_call_opt(_unit_nodes[id], "set_selected", [false])
	if state.sel_support != null:
		for u in state.support_targets():
			if _cells.has(u.cell):
				_cells[u.cell].set_highlight("deploy")
		return
	if state.sel_kind == state.SelKind.HAND:
		var hand_cards: Array = state.hand[0]
		var idx: int = state.sel_hand_index
		if idx >= 0 and idx < hand_cards.size() and hand_cards[idx] is UnitData:
			for c in state.selected_deploy_cells():
				if _cells.has(c):
					_cells[c].set_highlight("deploy")
		else:
			for u in state.command_targets(idx):
				if _cells.has(u.cell):
					_cells[u.cell].set_highlight("attack")
		return
	if state.sel_kind == state.SelKind.UNIT and state.sel_unit != null:
		var u: UnitInstance = state.sel_unit
		for c in state.selected_move_cells():
			if _cells.has(c):
				_cells[c].set_highlight("move")
		for t in state.selected_attack_targets():
			if _cells.has(t.cell):
				_cells[t.cell].set_highlight("attack")
		if _unit_nodes.has(u.instance_id):
			_call_opt(_unit_nodes[u.instance_id], "set_selected", [true])
		return
	for u in state.board.units_of(state.active):
		if _unit_nodes.has(u.instance_id):
			var act: bool = state.can_unit_move(u) or state.can_unit_attack(u)
			_call_opt(_unit_nodes[u.instance_id], "set_selectable", [act])


func _call_opt(node: Object, method: String, args: Array) -> void:
	if node != null and node.has_method(method):
		node.callv(method, args)


func _refresh_all() -> void:
	if state == null:
		return
	_refresh_cost()
	_refresh_hand()
	for u in state.board.all_units():
		if not _unit_nodes.has(u.instance_id):
			_spawn_unit_node(u)
		else:
			_refresh_unit(u)
	for id in _unit_nodes.keys().duplicate():
		if _fading.has(id):
			continue
		if _find_unit(id) == null:
			_unit_nodes[id].queue_free()
			_unit_nodes.erase(id)
	_refresh_highlights()


# ============================================================
#  静态 UI 接口
# ============================================================

func show_card_detail(data: CardData) -> void:
	if data == null:
		return
	$HUD/InfoPanel/CardName.text = data.display_name
	var head := ""
	if data.glossary != "" or data.skill_name != "":
		head = "[%s] %s\n" % [data.glossary, data.skill_name]
	$HUD/InfoPanel/SkillDesc.text = head + data.description
	var u := data as UnitData
	if u != null:
		_set_attr_rows(str(u.atk), str(u.hp), str(u.move), str(u.attack_range))
		return
	var c := data as CommandData
	if c != null:
		_set_attr_rows(str(c.dmg), str(c.heal), str(c.target_range), "0")
	else:
		_set_attr_rows("-", "-", "-", "-")


func _set_attr_rows(a: String, b: String, c: String, d: String) -> void:
	var vals := [a, b, c, d]
	for i in 4:
		var row := $HUD/InfoPanel/Attributes.get_node_or_null("Row%d" % (i + 1))
		if row:
			var v: Label = row.get_node_or_null("Value")
			if v:
				v.text = vals[i]


func set_match_info(turn_text: String, map_name: String, site_effect: String) -> void:
	$HUD/MatchInfo/TurnInfo.text = turn_text
	$HUD/MatchInfo/MapName.text = map_name
	$HUD/MatchInfo/SiteEffect.text = site_effect


func set_cost(side: int, value: String) -> void:
	var node := $Battle/PlayerBesaInfoLift if side == 0 else $Battle/PlayerBesaInfoRight
	var lb: Label = node.get_node_or_null("BadgeImage/Value")
	if lb:
		lb.text = value


func set_player_names(ally: String, enemy: String) -> void:
	$Battle/PlayerBesaInfoLift/PlayerNamesLeft.text = ally
	$Battle/PlayerBesaInfoRight/PlayerNamesRight.text = enemy
	if state != null:
		state.player_names = {0: ally, 1: enemy}


func set_main_button(text: String, enabled: bool = true) -> void:
	var b: Button = $HUD/ActionBar/MainButton
	b.disabled = not enabled
	$HUD/ActionBar/Label.text = text


func load_map(map_data: MapData) -> void:
	if map_data == null:
		return
	var plate: TextureRect = $Battle/MapView/MapPlate/TextureRect
	if map_data.terrain_texture != null:
		plate.texture = map_data.terrain_texture
	$HUD/MatchInfo/MapName.text = map_data.display_name
	$HUD/MatchInfo/SiteEffect.text = map_data.description


func _on_main_pressed() -> void:
	if state != null:
		state.advance_phase()


func _on_func_pressed(which: String) -> void:
	match which:
		"Back":
			request_quit.emit()
		"Info":
			if state == null:
				return
			var u: UnitInstance = state.sel_unit
			if u != null and state.can_unit_support(u):
				var sk: Array = state.unit_support_skills(u)
				if not sk.is_empty():
					state.begin_support(u, sk[0])
					_refresh_highlights()
					return
			if state.can_rotate(state.active):
				state.rotate_hand(state.active)


func rotate_hand() -> bool:
	return state.rotate_hand(state.active) if state != null else false


func clear_all() -> void:
	for n in _units_root.get_children():
		n.queue_free()
	for p in [_hand_l, _hand_r]:
		for c in p.get_children():
			c.queue_free()
	_unit_nodes.clear()
	_hand_nodes.clear()
	_hand_order.clear()
