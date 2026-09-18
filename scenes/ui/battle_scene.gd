extends Control
## BattleScene —— 战斗场景**接线控制器**（组合素材场景 + 驱动 GameState）
##
## 分层（严格单向依赖，避免循环引用）：
##   GameState / Board / BattleAction （规则层，不引用任何 UI）
##        ↑ 只通过 signal 上报                 ↓ 只通过公开方法下语义操作
##   BattleScene（本类：接线 + 翻译 + 绑定）
##        ↑ 只 signal 上报                     ↓ 只调用 bind()/set_* 等方法
##   HandCard / UnitCard / BoardCell（组件，不认识 GameState，也不认识本类）
##
## 通信原则（D-1）：组件只 emit 自己的信号；本类监听并**翻译**为规则调用；
## 规则层只 emit 状态信号；本类监听并**翻译**为视图表现。
##
## 素材场景（勿改结构）：
##   res://scenes/ui/battle_ui_alpha.tscn   战斗 UI 骨架（本场景继承它）
##   res://scenes/ui/card_hand.tscn         手牌卡
##   res://scenes/ui/card_unit.tscn         地图单位卡

const HAND_CARD_SCENE := preload("res://scenes/ui/card_hand.tscn")
const UNIT_CARD_SCENE := preload("res://scenes/ui/card_unit.tscn")
const CELL_SCRIPT := preload("res://scenes/ui/board_cell.gd")
const GameStateScript := preload("res://scripts/game/game_state.gd")

const PITCH := 250.0                        ## 格宽 = 单位卡尺寸
const MAP_ORIGIN := Vector2(459.0, 40.0)    ## 棋盘左上角（与地图板对齐）
const HAND_SLOT := Vector2(200.0, 200.0)
const HAND_GAP := Vector2(30.0, 30.0)

# ---------------- 对外信号（供更外层接入菜单/联网/存档） ----------------
signal battle_ended(result: int, reason: String)
signal request_quit()

# ---------------- 内部引用 ----------------
var state: Node = null               ## GameState（规则层）
var _cells := {}                     ## Vector2i → BoardCell
var _unit_nodes := {}                ## instance_id → UnitCard
var _hand_nodes := {}                ## card_id → HandCard
var _hand_order: Array = []          ## 手牌顺序（保 index 对齐）

@onready var _cells_root: Control = $Battle/MapView/MapCells
@onready var _units_root: Control = $Battle/MapView/Units
@onready var _hand_r: Control = $Battle/HandPanelRight/HandRight


func _ready() -> void:
	state = GameStateScript.new()
	state.name = "GameState"
	add_child(state)
	_connect_rules()
	_connect_static_ui()
	_build_cells()


## 开局：传入双方卡组（DeckData）与先手方
func start_battle(decks: Dictionary, first_player: int = 0, names: Dictionary = {}) -> void:
	state.setup(decks, first_player, names)
	_refresh_all()


# ============================================================
#  规则层 → 视图（信号翻译）
# ============================================================

func _connect_rules() -> void:
	state.state_changed.connect(_refresh_all)
	state.hand_changed.connect(func(_s: int) -> void: _refresh_hand())
	state.cost_changed.connect(_on_cost_changed)
	state.unit_spawned.connect(_on_unit_spawned)
	state.unit_moved.connect(_on_unit_moved)
	state.unit_removed.connect(_on_unit_removed)
	state.effect_changed.connect(_on_effect_changed)
	state.selection_changed.connect(_on_selection_changed)
	state.phase_changed.connect(_on_phase_changed)
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


func _on_phase_changed(_active: int, _phase: int, _round_no: int) -> void:
	_refresh_hand_playable()
	_refresh_highlights()


func _on_turn_started(active: int, round_no: int) -> void:
	$HUD/MatchInfo/TurnInfo.text = "回合%d--%s" % [round_no, "先手" if active == 0 else "后手"]
	_refresh_cost()


func _on_cost_changed(_side: int, _value: int) -> void:
	_refresh_cost()


func _on_log(text: String) -> void:
	print("[BATTLE] ", text)


func _refresh_cost() -> void:
	for side in [0, 1]:
		var node := $Battle/PlayerBesaInfoLift if side == 0 else $Battle/PlayerBesaInfoRight
		var lb: Label = node.get_node_or_null("BadgeImage/Value")
		if lb:
			lb.text = str(int(state.cost[side]))


func _on_effect_changed(inst: UnitInstance) -> void:
	_refresh_unit(inst)


func _on_selection_changed(_kind: String, _id: String) -> void:
	_refresh_highlights()


# ============================================================
#  棋盘格（点击命中区，无视觉 —— 棋盘视觉由地图素材自带）
# ============================================================

func _build_cells() -> void:
	for x in 4:
		for y in 4:
			var c := Vector2i(x, y)
			var node: Control = Control.new()
			node.set_script(CELL_SCRIPT)
			node.name = "Cell_%d_%d" % [x, y]
			node.position = Vector2(c.y * PITCH, c.x * PITCH)
			node.size = Vector2(PITCH, PITCH)
			node.cell = c
			node.cell_clicked.connect(_on_cell_clicked)
			_cells_root.add_child(node)
			_cells[c] = node


func _on_cell_clicked(cell: Vector2i) -> void:
	# ① 正在选卡 → 部署 / 用指令
	if state.sel_kind == state.SelKind.HAND:
		var idx: int = state.sel_hand_index
		var hand_cards: Array = state.current_hand()
		if idx < 0 or idx >= hand_cards.size():
			state.cancel_selection()
			return
		var card: CardData = hand_cards[idx]
		if card is UnitData:
			# 指令/建筑/兵蜂的合法性由 GameState 判断（视图不判规则）
			if not state.deploy_unit(state.active, idx, cell):
				print("[BATTLE] 该格不可部署")
			return
		_use_command_at(idx, cell)
		return
	# ② 正在选单位 → 移动 / 攻击
	if state.sel_kind == state.SelKind.UNIT and state.sel_unit != null:
		var u: UnitInstance = state.sel_unit
		var occupant: UnitInstance = state.board.unit_at(cell)
		if occupant != null and occupant.side != u.side:
			state.attack(u, occupant)
			return
		state.move_unit(u, cell)
		return
	# ③ 点到自己单位 → 选中
	var here: UnitInstance = state.board.unit_at(cell)
	if here != null and here.side == state.active:
		state.select_unit(here)


## 指令卡：对格子上的单位使用（各类指令的细分效果属后续检查点）
func _use_command_at(idx: int, cell: Vector2i) -> void:
	var target: UnitInstance = state.board.unit_at(cell)
	if target == null:
		print("[BATTLE] 指令卡需要选择目标单位")
		return
	print("[BATTLE] 指令卡结算尚未接线（待后续检查点）：目标 %s" % target.card_name())


# ============================================================
#  单位卡
# ============================================================

func _cell_pos_in_units(cell: Vector2i) -> Vector2:
	## Units 容器就在 MapView 空间下，与 MapCells 同空间 → 直接用格坐标×格宽
	return Vector2(cell.y * PITCH, cell.x * PITCH)


func _on_unit_spawned(inst: UnitInstance) -> void:
	_spawn_unit_node(inst)
	_refresh_highlights()


## 建一个单位卡节点（幂等：已存在则只刷新）
func _spawn_unit_node(inst: UnitInstance) -> void:
	if inst == null or _unit_nodes.has(inst.instance_id):
		_refresh_unit(inst)
		return
	var node: Control = UNIT_CARD_SCENE.instantiate()
	node.position = _cell_pos_in_units(inst.cell)
	_units_root.add_child(node)
	node.bind(inst)
	node.unit_clicked.connect(_on_unit_card_clicked)
	_unit_nodes[inst.instance_id] = node


func _on_unit_card_clicked(instance_id: String) -> void:
	var inst := _find_unit(instance_id)
	if inst == null:
		return
	if inst.side == state.active:
		state.select_unit(inst)
		state.show_card_detail(inst.data)
	else:
		var u: UnitInstance = state.sel_unit
		if u != null:
			state.attack(u, inst)


func _on_unit_moved(inst: UnitInstance) -> void:
	_refresh_unit(inst)
	_refresh_highlights()


func _on_unit_removed(inst: UnitInstance) -> void:
	if _unit_nodes.has(inst.instance_id):
		_unit_nodes[inst.instance_id].queue_free()
		_unit_nodes.erase(inst.instance_id)


func _refresh_unit(inst: UnitInstance) -> void:
	if not _unit_nodes.has(inst.instance_id):
		return
	var n: Control = _unit_nodes[inst.instance_id]
	n.bind(inst)
	n.position = _cell_pos_in_units(inst.cell)


func _find_unit(instance_id: String) -> UnitInstance:
	for u in state.board.all_units():
		if u.instance_id == instance_id:
			return u
	return null


# ============================================================
#  手牌（我方在右）
# ============================================================

func _refresh_hand() -> void:
	for c in _hand_r.get_children():
		c.queue_free()
	_hand_nodes.clear()
	_hand_order.clear()
	var cards: Array = state.current_hand()
	for i in cards.size():
		var data: CardData = cards[i]
		if data == null:
			continue
		var node: Control = HAND_CARD_SCENE.instantiate()
		var col := i % 2
		var row := i / 2
		node.position = Vector2(col * (HAND_SLOT.x + HAND_GAP.x), row * (HAND_SLOT.y + HAND_GAP.y))
		_hand_r.add_child(node)
		node.bind(data)
		node.hand_clicked.connect(_on_hand_clicked)
		_hand_nodes[data.id] = node
		_hand_order.append(data.id)
	_refresh_hand_playable()


func _on_hand_clicked(card_id: String) -> void:
	var idx := _hand_order.find(card_id)
	if idx < 0:
		return
	state.select_hand(idx)
	var cards: Array = state.current_hand()
	if idx < cards.size():
		show_card_detail(cards[idx])


func _refresh_hand_playable() -> void:
	for i in _hand_order.size():
		var id: String = _hand_order[i]
		var n: Control = _hand_nodes.get(id, null)
		if n == null:
			continue
		n.set_playable(state.can_play_hand(state.active, i))
		n.set_selected(state.sel_kind == state.SelKind.HAND and state.sel_hand_index == i)


# ============================================================
#  高亮（把规则层的可操作集合翻译为格子/单位表现）
# ============================================================

func _refresh_highlights() -> void:
	for c in _cells.keys():
		_cells[c].set_highlight("")
		_cells[c].set_selected(false)
	for id in _unit_nodes.keys():
		_unit_nodes[id].set_selectable(false)
		_unit_nodes[id].set_selected(false)

	if state.sel_kind == state.SelKind.HAND:
		for c in state.selected_deploy_cells():
			if _cells.has(c):
				_cells[c].set_highlight("deploy")
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
			_unit_nodes[u.instance_id].set_selected(true)
		return

	for u in state.board.units_of(state.active):
		if _unit_nodes.has(u.instance_id):
			var act: bool = state.can_unit_move(u) or state.can_unit_attack(u)
			_unit_nodes[u.instance_id].set_selectable(act)


# ============================================================
#  静态 UI
# ============================================================

func _connect_static_ui() -> void:
	var main: Button = $HUD/ActionBar/MainButton
	if main and not main.pressed.is_connected(_on_main_pressed):
		main.pressed.connect(_on_main_pressed)
	for nm in ["Settings", "Emote", "Info", "Back"]:
		var b: Button = $HUD/FuncButtonGroup.get_node_or_null(nm + "/Button")
		if b and not b.pressed.is_connected(_on_func_pressed):
			b.pressed.connect(_on_func_pressed.bind(nm))


func _on_main_pressed() -> void:
	state.advance_phase()


func _on_func_pressed(which: String) -> void:
	if which == "Back":
		request_quit.emit()


# ============================================================
#  详情区 / 地图 / 全量刷新
# ============================================================

func _refresh_all() -> void:
	_refresh_cost()
	_refresh_hand()
	# ⚠️ **幂等补建**：`GameState.setup()` 在控制器连信号**之前**就会 place 蜂王并 emit
	#    `unit_spawned` → 那次信号我们收不到；故此处在全量刷新时把"棋盘上有、但视图缺"的
	#    单位补建出来（比依赖信号时序更稳，也顺带覆盖任何漏发的增删）。
	_sync_unit_nodes()
	_refresh_highlights()
	for u in state.board.all_units():
		_refresh_unit(u)


## 让单位节点集合与棋盘一致（补建缺失 / 移除多余）
func _sync_unit_nodes() -> void:
	for u in state.board.all_units():
		if not _unit_nodes.has(u.instance_id):
			_spawn_unit_node(u)
	# 棋盘上已不存在的 → 销毁节点
	for id in _unit_nodes.keys().duplicate():
		var alive := false
		for u in state.board.all_units():
			if u.instance_id == id:
				alive = true
				break
		if not alive:
			_unit_nodes[id].queue_free()
			_unit_nodes.erase(id)


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


func set_player_names(ally: String, enemy: String) -> void:
	$Battle/PlayerBesaInfoLift/PlayerNamesLeft.text = ally
	$Battle/PlayerBesaInfoRight/PlayerNamesRight.text = enemy
	state.player_names = {0: ally, 1: enemy}
