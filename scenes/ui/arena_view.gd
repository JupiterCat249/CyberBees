extends Control
## ArenaView —— 战斗**视图适配器**（迭代057 C2/C3）
##
## 职责（单一）：订阅 `BattleSignalBus` 的信号 → 驱动 UI 节点；
##   把玩家点击 → 翻译成 `BattleEngine` 的**请求**。
##
## ⚠️ **本类是视图层**：只碰节点与信号，**不写规则**。
##   规则判定全部在 `scripts/battle/`（该目录 0 处节点/场景引用）——分层单向：
##     规则层 ──emit──▶ BattleSignalBus ──connect──▶ 本类 ──节点操作──▶ UI
##     玩家点击 ──请求──▶ BattleEngine ──（回到上面那条）
##
## 禁止（防规则漏回视图）：
##   · 不在本类里算射程/费用/胜负 —— 一律读引擎给的 `PreviewData` 与信号参数
##   · 不直接改引擎内部状态 —— 只调 `request_*` / `select_*`

const Bus := preload("res://scripts/battle/battle_signal_bus.gd")
const EngLib := preload("res://scripts/battle/battle_engine.gd")
const ConfigLib := preload("res://scripts/battle/battle_config.gd")
const K := preload("res://scripts/battle/preview_kind.gd")
const Pool := preload("res://scripts/data/card_pool.gd")
const DetailP := preload("res://scripts/data/detail_params.gd")
const HandP := preload("res://scripts/data/hand_card_params.gd")
const HAND_CARD_SCENE := preload("res://scenes/ui/card_hand.tscn")
const UNIT_CARD_SCENE := preload("res://scenes/ui/card_unit.tscn")
const CELL_SCRIPT := preload("res://scenes/ui/board_cell.gd")

const SIDE_ALLY := 0
const SIDE_ENEMY := 1
const PITCH := 250.0

@export var auto_start := true
@export var use_resources := true
@export var ally_name := "玩家·绿"
@export var enemy_name := "玩家·红"

var engine = null

# 节点引用
@onready var _cells_root: Control = $Battle/MapView/MapCells
@onready var _units_root: Control = $Battle/MapView/Units
@onready var _hand_l: Control = $Battle/HandPanelLeft/HandLeft
@onready var _hand_r: Control = $Battle/HandPanelRight/HandRight

# 运行时索引
var _cells := {}                      ## Vector2i -> BoardCell
var _unit_nodes := {}                 ## instance_id -> UnitCard
var _hand_nodes := {SIDE_ALLY: {}, SIDE_ENEMY: {}}   ## side -> {card_id: HandCard}
var _hand_order := {SIDE_ALLY: [], SIDE_ENEMY: []}
var _preview: Resource = null
var _preview_cleared := false

## 两套 UI 参数（**各自独立**，人要求：详情区 / 手牌卡不共用）
## 运行时可替换（如换皮肤/调参）——替换后调 apply_params() 重施即可
var detail_params: Resource = DetailP.new()
var hand_params: Resource = HandP.new()


func _ready() -> void:
	_connect_bus()
	_connect_static_ui()
	_adopt_cells()
	apply_params()                       ## 两套 UI 参数各施其位（详情区 / 手牌卡）
	engine = EngLib.new()
	if auto_start and not engine.start(_config()):
		push_warning("BattleEngine 启动失败（看上面的配置错误日志）")
	apply_params()                       ## 开局后手牌已渲染 → 再施一次手牌参数


func _exit_tree() -> void:
	## 避免视图重建后重复响应（总线是全局单例）
	var b := Bus.shared()
	if b != null and b.has_method("disconnect_all_of"):
		b.disconnect_all_of(self)


## 开局配置：优先读资源（game_data/decks/），不可用则回退代码构造
func _config() -> BattleConfig:
	var ally := Pool.build("示范卡组")
	var enemy := Pool.build("示范卡组·敌")
	var c := ConfigLib.make(ally, enemy, ally_name, enemy_name)
	if use_resources and ResourceLoader.exists("res://game_data/decks/示范卡组.tres"):
		var d := load("res://game_data/decks/示范卡组.tres") as DeckData
		if d != null and d.queen != null and d.cards.size() > 0:
			c.deck_ally = d
			c.deck_enemy = d.duplicate(true) as DeckData
	## 默认地图（让地图板/背景有内容可用）——6 张里的「默认」；换图调 engine.load_map()
	if use_resources and ResourceLoader.exists("res://game_data/maps/默认.tres"):
		var md := load("res://game_data/maps/默认.tres") as MapData
		if md != null:
			c.map_data = md
	return c


func _connect_static_ui() -> void:
	var b: Button = $HUD/ActionBar/MainButton
	if b != null and not b.pressed.is_connected(_on_main_pressed):
		b.pressed.connect(_on_main_pressed)


# ============================================================
#  信号订阅（规则 → 视图）
# ============================================================

func _connect_bus() -> void:
	var b := Bus.shared()
	b.connect(Bus.SIG_BATTLE_STARTED, _on_battle_started)
	b.connect(Bus.SIG_ROUND_STARTED, _on_round_started)
	b.connect(Bus.SIG_TURN_STARTED, _set_turn)
	b.connect(Bus.SIG_PHASE_STARTED, _on_phase_started)
	b.connect(Bus.SIG_COST_CHANGED, _on_cost_changed)
	b.connect(Bus.SIG_HAND_CHANGED, _on_hand_changed)
	b.connect(Bus.SIG_UNIT_SPAWNED, _on_unit_spawned)
	b.connect(Bus.SIG_UNIT_MOVED, _on_unit_moved)
	b.connect(Bus.SIG_UNIT_DAMAGED, _on_unit_damaged)
	b.connect(Bus.SIG_UNIT_HEALED, _on_unit_healed)
	b.connect(Bus.SIG_UNIT_REMOVED, _on_unit_removed)
	b.connect(Bus.SIG_SELECTION, _on_selection_changed)
	b.connect(Bus.SIG_MAIN_BUTTON, _on_main_button)
	b.connect(Bus.SIG_LOG, _on_log)
	b.connect(Bus.SIG_BATTLE_ENDED, _on_battle_ended)
	## 地图 / 背景：两个 TextureRect **各自独立**从同一条信号的参数取值（解耦）
	b.connect(Bus.SIG_MAP_ASSETS, _on_map_assets)


## 地图与背景资产变化
## ⚠️ 解耦：本方法只把 `assets` 的两个字段分别投给两个**互不引用**的节点；
##   换图时引擎重发同一信号，两个节点自动跟着变（人要求：信号 + 信号传参）
func _on_map_assets(assets: Resource) -> void:
	if assets == null:
		return
	var plate := $Battle/MapView/MapPlate/TextureRect as TextureRect
	if plate != null and assets.map_texture != null:
		plate.texture = assets.map_texture
	if plate != null:
		plate.visible = bool(assets.has_map)
	var bg := $Background/TextureRect as TextureRect
	if bg != null and assets.background_texture != null:
		bg.texture = assets.background_texture
	if assets.map_name != "":
		var nm := $HUD/MatchInfo/MapName
		if nm != null:
			nm.text = assets.map_name
	if assets.map_desc != "":
		var se := $HUD/MatchInfo/SiteEffect
		if se != null:
			se.text = assets.map_desc


## 应用两套 UI 参数（**分开应用**，不混用）
func apply_params() -> void:
	_apply_detail_params()
	_apply_hand_params()


func _apply_detail_params() -> void:
	var p = detail_params
	if p == null:
		return
	var nm := $HUD/InfoPanel/CardName as Label
	if nm != null:
		nm.add_theme_font_size_override("font_size", int(p.name_font_size))
		nm.add_theme_color_override("font_color", p.name_color)
	var ds := $HUD/InfoPanel/SkillDesc as Label
	if ds != null:
		ds.add_theme_font_size_override("font_size", int(p.desc_font_size))
		ds.add_theme_color_override("font_color", p.desc_color)
		ds.add_theme_constant_override("line_spacing", int(p.desc_line_spacing))
	var portrait := $HUD/InfoPanel/DetailBlock/Artwork/Portrait as TextureRect
	if portrait != null:
		portrait.size = p.art_size
	var attrs := $HUD/InfoPanel/Attributes
	if attrs != null:
		for i in int(p.attr_rows):
			var row := attrs.get_node_or_null("Row%d" % (i + 1))
			if row == null:
				continue
			var v: Label = row.get_node_or_null("Value")
			if v != null:
				v.add_theme_font_size_override("font_size", int(p.attr_value_font_size))
			var ic: TextureRect = row.get_node_or_null("Icon")
			if ic != null:
				ic.size = p.attr_icon_size


func _apply_hand_params() -> void:
	var p = hand_params
	if p == null:
		return
	## 手牌卡**只在需要时取参数**（容器决定尺寸；参数只用于卡内部元素）
	for side in [SIDE_ALLY, SIDE_ENEMY]:
		for id in _hand_nodes[side].keys():
			var node = _hand_nodes[side][id]
			if node != null and is_instance_valid(node):
				_apply_one_hand_params(node, p)


func _apply_one_hand_params(node, p) -> void:
	var badge: TextureRect = node.get_node_or_null("BadgeImage")
	if badge != null:
		badge.size = p.badge_size
		var bv: Label = badge.get_node_or_null("Value")
		if bv != null:
			bv.add_theme_font_size_override("font_size", int(p.badge_font_size))
			bv.add_theme_color_override("font_color", p.badge_color)
	var line: Panel = node.get_node_or_null("InnerLine")
	if line != null:
		line.size = p.inner_line_size
	var img: TextureRect = node.get_node_or_null("Artwork/ArtPlane/Image")
	if img != null and node.get("card_data") != null:
		var vis: CardVisual = (node.get("card_data") as CardData).visual
		var off: Vector2 = p.final_art_offset(vis)
		var base: Vector2 = p.art_base_offset
		## Image 基准尺寸为 400x454（源图量级）→ 用 offset 控制裁剪窗里显示哪一块
		var sz := Vector2(400, 454)
		img.offset_left = off.x
		img.offset_top = off.y
		img.offset_right = off.x + sz.x
		img.offset_bottom = off.y + sz.y
		img.scale = p.final_art_scale(vis)


func _on_battle_started(first_side: int, round_no: int, an: String, en: String) -> void:
	_set_names(an, en)
	_set_turn(first_side, round_no)
	## 开局后把双方手牌与费用同步一遗（引擎已在 start() 里发出过，
	## 但 _ready 里本视图可能尚未连上信号 → 主动拉一次，避免首帧空白）
	_sync_all()


func _on_round_started(round_no: int) -> void:
	if engine != null and engine.state != null:
		_set_turn(engine.state.active, round_no)


func _set_turn(side: int, round_no: int) -> void:
	$HUD/MatchInfo/TurnInfo.text = "回合%d--%s" % [round_no, "绿方" if side == SIDE_ALLY else "红方"]


func _on_phase_started(side: int, phase: int, _round_no: int) -> void:
	var names := {0: "回费", 1: "场地", 2: "部署", 3: "行动"}
	$HUD/MatchInfo/SiteEffect.text = "阶段：%s（%s）" % [
		str(names.get(phase, "?")), "绿" if side == SIDE_ALLY else "红"]


func _on_cost_changed(side: int, cost: int, _delta: int) -> void:
	var node := $Battle/PlayerBesaInfoLift if side == SIDE_ALLY else $Battle/PlayerBesaInfoRight
	var lb: Label = node.get_node_or_null("BadgeImage/Value")
	if lb != null:
		lb.text = str(cost)


func _on_hand_changed(side: int, hand: Array, playable: Array) -> void:
	_render_hand(side, hand, playable)


func _on_unit_spawned(inst: UnitInstance, cell: Vector2i) -> void:
	_spawn_unit(inst, cell)


func _on_unit_moved(inst: UnitInstance, _from: Vector2i, to: Vector2i) -> void:
	var n: Control = _unit_nodes.get(inst.instance_id, null)
	if n != null and is_instance_valid(n):
		n.position = _cell_pos(to)


func _on_unit_damaged(inst: UnitInstance, _dmg: int, hp_after: int, _src: String) -> void:
	_update_unit(inst, hp_after)


func _on_unit_healed(inst: UnitInstance, _amt: int, hp_after: int) -> void:
	_update_unit(inst, hp_after)


func _on_unit_removed(inst: UnitInstance, _reason: String) -> void:
	var n: Control = _unit_nodes.get(inst.instance_id, null)
	if n != null and is_instance_valid(n):
		n.queue_free()
	_unit_nodes.erase(inst.instance_id)


func _on_selection_changed(_kind: int, _id: String, preview: Resource, _units: Array) -> void:
	## ⚠️ 预览范围**由规则层算好装在 PreviewData 里** —— 视图只读不重算
	_preview = preview
	_render_preview()


func _on_main_button(text: String, enabled: bool) -> void:
	var b: Button = $HUD/ActionBar/MainButton
	if b != null:
		b.disabled = not enabled
	$HUD/ActionBar/Label.text = text


func _on_log(text: String, level: int) -> void:
	print("[BATTLE]", "[WARN]" if level > 0 else "", " ", text)


func _on_battle_ended(result: int, reason: String) -> void:
	var who := {0: "", 1: "绿方胜", 2: "红方胜", 3: "平局"}
	$HUD/ActionBar/Label.text = "%s（%s）" % [str(who.get(result, "?")), reason]
	$HUD/ActionBar/MainButton.disabled = true


## 开局后主动同步一遗（信号可能早于本视图连线）
func _sync_all() -> void:
	if engine == null or engine.state == null:
		return
	var st = engine.state
	for side in [SIDE_ALLY, SIDE_ENEMY]:
		var hand: Array = st.sides[side]["hand"]
		var mask: Array = []
		for i in hand.size():
			mask.append(engine.can_play_hand(side, i))
		_render_hand(side, hand, mask)
		_on_cost_changed(side, st.cost(side), 0)
		for u in st.units(side):
			_spawn_unit(u, u.cell)


# ============================================================
#  棋盘格：认领 + 点击转发
# ============================================================

func _adopt_cells() -> void:
	for x in 4:
		for y in 4:
			var c := Vector2i(x, y)
			var node := _cells_root.get_node_or_null("Cell_%d_%d" % [x, y]) as Control
			if node == null:
				node = Control.new()
				node.name = "Cell_%d_%d" % [x, y]
				node.position = _cell_pos(c)
				node.size = Vector2(PITCH, PITCH)
				_cells_root.add_child(node)
			node.set_script(CELL_SCRIPT)
			node.set("cell", c)
			node.set("mouse_filter", Control.MOUSE_FILTER_STOP)
			if node.has_signal("cell_clicked") and not node.cell_clicked.is_connected(_on_cell_clicked):
				node.cell_clicked.connect(_on_cell_clicked)
			_cells[c] = node


func _cell_pos(cell: Vector2i) -> Vector2:
	## ⚠️ 沿用项目坐标约定：cell.x = 行、cell.y = 列
	return Vector2(cell.y * PITCH, cell.x * PITCH)


## 点格 → 翻译成引擎请求（**不在视图里做规则判定**：种类看预览资源给的 kind）
func _on_cell_clicked(cell: Vector2i) -> void:
	if engine == null or engine.state == null:
		return
	var spec = engine.current_preview()
	var kind: int = int(spec.kind) if spec != null else 0
	var side: int = engine.state.active
	match kind:
		K.Kind.DEPLOY:
			engine.request_deploy(side, engine.sel_hand_index, cell)
		K.Kind.MOVE:
			engine.request_move(side, engine.sel_unit, cell)
		K.Kind.COMMAND, K.Kind.SUPPORT, K.Kind.ATTACK:
			var target: UnitInstance = engine.state.board.unit_at(cell)
			if target == null:
				return
			if kind == K.Kind.COMMAND:
				engine.request_use_command(side, engine.sel_hand_index, target)
			elif kind == K.Kind.SUPPORT:
				engine.request_support(side, engine.sel_unit, engine.sel_support, target)
			else:
				engine.request_attack(side, engine.sel_unit, target)
		_:
			## 无预览 → 尝试选中该格上的己方单位
			var here: UnitInstance = engine.state.board.unit_at(cell)
			if here != null and here.side == side:
				engine.select_unit(side, here)
				show_detail(here.data)


# ============================================================
#  手牌渲染（**容器负责排布**，视图只给数据）
# ============================================================

func _hand_parent(side: int) -> Control:
	return _hand_r if side == SIDE_ALLY else _hand_l


## ⚠️ 不写 position / size —— 手牌区是 GridContainer，布局完全由它负责
##   （迭代057 C1 修正：以前写 layout_mode/offset 会把卡从容器布局里摘出来）
func _render_hand(side: int, hand: Array, playable: Array) -> void:
	var parent := _hand_parent(side)
	for ch in parent.get_children():
		if not ch.is_queued_for_deletion():
			ch.queue_free()
	_hand_nodes[side].clear()
	_hand_order[side].clear()
	for i in hand.size():
		var data: CardData = hand[i]
		if data == null:
			continue
		var node: Control = HAND_CARD_SCENE.instantiate()
		parent.add_child(node)
		if node.has_method("bind"):
			node.call("bind", data)
		if node.has_signal("hand_clicked"):
			node.hand_clicked.connect(_on_hand_clicked.bind(side))
		_hand_nodes[side][data.id] = node
		_hand_order[side].append(data.id)
		if i < playable.size():
			_call_opt(node, "set_playable", [bool(playable[i])])
		## 手牌卡内部元素参数（**与详情区参数分开**）
		if hand_params != null:
			_apply_one_hand_params(node, hand_params)


func _on_hand_clicked(card_id: String, side: int) -> void:
	if engine == null:
		return
	var idx: int = _hand_order[side].find(card_id)
	if idx < 0:
		return
	engine.select_hand(side, idx)
	var hand: Array = engine.state.sides[side]["hand"]
	if idx < hand.size():
		show_detail(hand[idx])


# ============================================================
#  单位渲染
# ============================================================

func _spawn_unit(inst: UnitInstance, cell: Vector2i) -> void:
	if inst == null or _unit_nodes.has(inst.instance_id):
		return
	_clear_preview_units_once()
	var node: Control = UNIT_CARD_SCENE.instantiate()
	node.name = "Unit_" + inst.instance_id.substr(0, 8)
	node.position = _cell_pos(cell)
	_units_root.add_child(node)
	node.bind(_unit_view(inst, cell))
	if node.has_signal("unit_pressed"):
		node.unit_pressed.connect(_on_unit_clicked)
	_unit_nodes[inst.instance_id] = node


func _clear_preview_units_once() -> void:
	if _preview_cleared:
		return
	_preview_cleared = true
	for ch in _units_root.get_children():
		if not ch.is_queued_for_deletion():
			ch.queue_free()


## UnitInstance → 单位卡绑定字典（含**立绘**，否则卡面永远是场景默认图）
func _unit_view(inst: UnitInstance, cell: Vector2i) -> Dictionary:
	var kind := "unit"
	var art = null
	var nm := ""
	if inst.data != null:
		nm = inst.data.display_name
		match inst.data.kind:
			CardData.CardKind.QUEEN: kind = "queen"
			CardData.CardKind.BUILDING: kind = "building"
			CardData.CardKind.COMMAND, CardData.CardKind.COMMAND_X: kind = "order"
		if inst.data.visual != null:
			art = inst.data.visual.artwork
	return {
		"id": inst.instance_id,
		"name": nm,
		"cost": inst.data.cost if inst.data != null else 0,
		"atk": inst.atk(),
		"hp": inst.current_hp,
		"move": inst.move_range(),
		"range": inst.attack_range(),
		"mine": inst.side == SIDE_ALLY,
		"type": kind,
		"art": art,
	}


func _update_unit(inst: UnitInstance, hp_after: int) -> void:
	var n: Control = _unit_nodes.get(inst.instance_id, null)
	if n == null or not is_instance_valid(n):
		return
	var d := _unit_view(inst, inst.cell)
	d["hp"] = hp_after
	n.bind(d)


func _on_unit_clicked(instance_id: String) -> void:
	if engine == null or engine.state == null:
		return
	var inst := _find_unit(instance_id)
	if inst == null:
		return
	var side: int = engine.state.active
	if inst.side == side:
		engine.select_unit(side, inst)
		show_detail(inst.data)
	else:
		engine.request_attack(side, engine.sel_unit, inst)


func _find_unit(instance_id: String) -> UnitInstance:
	for u in engine.state.board.all_units():
		if u.instance_id == instance_id:
			return u
	return null


# ============================================================
#  预览渲染（读 PreviewData 资源，**不重算规则**）
# ============================================================

func _render_preview() -> void:
	for c in _cells.keys():
		_cells[c].set_highlight("")
		_cells[c].set_selected(false)
	if _preview == null:
		return
	var style := {
		K.Kind.DEPLOY: "deploy",
		K.Kind.MOVE: "move",
		K.Kind.ATTACK: "attack",
		K.Kind.COMMAND: "attack",
		K.Kind.SUPPORT: "deploy",
	}
	for pc in _preview.cells:
		if _cells.has(pc.cell):
			_cells[pc.cell].set_highlight(String(style.get(pc.kind, "")))


# ============================================================
#  详情区 + 工具
# ============================================================

func show_detail(data: CardData) -> void:
	if data == null:
		return
	$HUD/InfoPanel/CardName.text = data.display_name
	var head := ""
	if data.glossary != "" or data.skill_name != "":
		head = "[%s] %s\n" % [data.glossary, data.skill_name]
	$HUD/InfoPanel/SkillDesc.text = head + data.description
	var portrait := $HUD/InfoPanel/DetailBlock/Artwork/Portrait as TextureRect
	if portrait != null:
		portrait.texture = data.visual.artwork if data.visual != null else null
	var u := data as UnitData
	if u != null:
		_rows(str(u.atk), str(u.hp), str(u.move), str(u.attack_range))
		return
	var c := data as CommandData
	if c != null:
		_rows(str(c.dmg), str(c.heal), str(c.target_range), "0")


func _rows(a: String, b: String, c: String, d: String) -> void:
	var vals := [a, b, c, d]
	for i in 4:
		var row := $HUD/InfoPanel/Attributes.get_node_or_null("Row%d" % (i + 1))
		if row != null:
			var v: Label = row.get_node_or_null("Value")
			if v != null:
				v.text = vals[i]


func _set_names(ally: String, enemy: String) -> void:
	var l := $Battle/PlayerBesaInfoLift.get_node_or_null("PlayerNamesLeft")
	if l != null:
		l.text = ally
	var r := $Battle/PlayerBesaInfoRight.get_node_or_null("PlayerNamesRight")
	if r != null:
		r.text = enemy


func _call_opt(node: Object, method: String, args: Array) -> void:
	if node != null and is_instance_valid(node) and node.has_method(method):
		node.callv(method, args)


## 主按钮 → 推进阶段（引擎自行判定回费/场地不可手动推）
func _on_main_pressed() -> void:
	if engine != null:
		engine.request_end_phase()
