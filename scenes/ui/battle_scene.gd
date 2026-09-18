extends Control
## BattleScene —— 战斗场景**接线控制器**（新战场：组合三个素材场景）
##
## 定位：本脚本**不是规则引擎**。它只做三件事，把"素材场景"与"游戏逻辑"接起来：
##   ① 把逻辑层的数据绑到节点（source_* / add_hand_card / add_unit …）
##   ② 把节点发出的交互信号**转发**给外层（emit 出去，绝不直接调逻辑对象的方法）
##   ③ 把逻辑层下发的"可操作态"翻译成视图表现（set_hand_playable / set_selectable …）
##
## 通信原则（D-1：尽量用信号互相通信而非直接互相引用）：
##   · 本控制器**不持有**规则状态对象，只持有数据（CardData / UnitInstance）
##   · 子组件（HandCard / UnitCard）**不引用**本控制器 —— 它们只 emit 自己的信号
##   本控制器监听子组件信号 → 转发为外层信号 → 外层（规则层）处理后回调本控制器
##
## 素材场景（勿改）：
##   res://scenes/ui/battle_ui_alpha.tscn   战斗 UI 骨架
##   res://scenes/ui/card_hand.tscn         手牌卡
##   res://scenes/ui/card_unit.tscn         地图单位卡

const HAND_CARD_SCENE := preload("res://scenes/ui/card_hand.tscn")
const UNIT_CARD_SCENE := preload("res://scenes/ui/card_unit.tscn")

const HAND_SLOT := Vector2(200.0, 200.0)      ## 手牌卡尺寸（与素材一致）
const HAND_GAP_X := 30.0
const HAND_GAP_Y := 30.0
const UNIT_PITCH := 250.0                     ## 地图格宽 = 单位卡尺寸

# ---------------- 对外信号（唯一的通信面） ----------------

## 手牌被点击/长按（转发自 HandCard）
signal hand_card_clicked(card_id: String)
signal hand_card_long_pressed(card_id: String)
## 单位被点击/长按（转发自 UnitCard）
signal unit_clicked(instance_id: String)
signal unit_long_pressed(instance_id: String)
## UI 自身引起的请求（由外层决定是否受理；本层不做规则判断）
signal main_button_pressed()
signal back_pressed()
signal func_button_pressed(which: String)

# ---------------- 对外入口（外层调用） ----------------

@export var side_ally: int = 0                ## 我方（绿，固定）——
@export var side_enemy: int = 1               ## 敌方（红）
@export var ally_hand_side: String = "right"  ## 我方手牌面板（右）

var _hand_nodes := {}                         ## instance_id/card_id → Node
var _unit_nodes := {}                         ## instance_id → UnitCard
var _hand_cards: Array[CardData] = []

@onready var _units: Control = $Battle/MapView/Units
@onready var _hand_l: Control = $Battle/HandPanelLeft/HandLeft
@onready var _hand_r: Control = $Battle/HandPanelRight/HandRight


func _ready() -> void:
	_connect_static_ui()

func _connect_static_ui() -> void:
	var main: Button = $HUD/ActionBar/MainButton
	if main and not main.pressed.is_connected(_on_main_pressed):
		main.pressed.connect(_on_main_pressed)
	for nm in ["Settings", "Emote", "Info", "Back"]:
		var b: Button = $HUD/FuncButtonGroup.get_node_or_null(nm + "/Button")
		if b and not b.pressed.is_connected(_on_func_pressed):
			b.pressed.connect(_on_func_pressed.bind(nm))


# ---------------- ① 数据绑定：手牌 ----------------

## 设置一侧手牌（重建该侧全部手牌卡节点）
func set_hand(cards: Array, ally: bool = true) -> void:
	var parent := _hand_parent(ally)
	for c in parent.get_children():
		c.queue_free()
	if ally:
		_hand_cards = []
	for i in cards.size():
		var data: CardData = cards[i]
		if data == null:
			continue
		var node: Control = HAND_CARD_SCENE.instantiate()
		var col := i % 2
		var row := i / 2          # 每行 2 张（整数除）
		node.position = Vector2(col * (HAND_SLOT.x + HAND_GAP_X), row * (HAND_SLOT.y + HAND_GAP_Y))
		node.bind(data)
		parent.add_child(node)
		# 子组件 → 本控制器（监听，不互相引用）
		node.hand_clicked.connect(_on_hand_clicked)
		node.hand_long_pressed.connect(_on_hand_long_pressed)
		if ally:
			_hand_cards.append(data)
			_hand_nodes[data.id] = node


func _hand_parent(ally: bool) -> Control:
	if ally:
		return _hand_r if ally_hand_side == "right" else _hand_l
	return _hand_l if ally_hand_side == "right" else _hand_r

func _on_hand_clicked(card_id: String) -> void:
	hand_card_clicked.emit(card_id)

func _on_hand_long_pressed(card_id: String) -> void:
	hand_card_long_pressed.emit(card_id)


# ---------------- ① 数据绑定：单位 ----------------

## 在指定格放置单位卡（数据来自 UnitInstance —— 运行态）
func add_unit(inst: UnitInstance) -> Control:
	if inst == null:
		return null
	var node: Control = UNIT_CARD_SCENE.instantiate()
	node.position = Vector2(inst.cell.x * UNIT_PITCH, inst.cell.y * UNIT_PITCH)
	_units.add_child(node)
	node.bind(inst)
	node.unit_clicked.connect(_on_unit_clicked)
	node.unit_long_pressed.connect(_on_unit_long_pressed)
	_unit_nodes[inst.instance_id] = node
	return node


func move_unit(instance_id: String, cell: Vector2i) -> void:
	if _unit_nodes.has(instance_id):
		_unit_nodes[instance_id].position = Vector2(cell.x * UNIT_PITCH, cell.y * UNIT_PITCH)


func remove_unit(instance_id: String) -> void:
	if _unit_nodes.has(instance_id):
		_unit_nodes[instance_id].queue_free()
		_unit_nodes.erase(instance_id)


func refresh_unit(instance_id: String) -> void:
	if _unit_nodes.has(instance_id):
		var n: Control = _unit_nodes[instance_id]
		n.bind(n.inst)            ## 重绑即刷新（含四维/血量）


func _on_unit_clicked(instance_id: String) -> void:
	unit_clicked.emit(instance_id)

func _on_unit_long_pressed(instance_id: String) -> void:
	unit_long_pressed.emit(instance_id)


# ---------------- ③ 逻辑下发 → 视图表现 ----------------

## 手牌可出牌态（x_cost = 当前费用，用于 X 费卡；缺省 -1 表示不判断）
func set_hand_playable(playable_ids: PackedStringArray) -> void:
	for id in _hand_nodes.keys():
		var n: Control = _hand_nodes[id]
		if is_instance_valid(n):
			n.set_playable(playable_ids.has(id))

func set_hand_selected(card_id: String) -> void:
	for id in _hand_nodes.keys():
		var n: Control = _hand_nodes[id]
		if is_instance_valid(n):
			n.set_selected(id == card_id)

## 地图单位可选中态
func set_units_selectable(selectable_ids: PackedStringArray) -> void:
	for id in _unit_nodes.keys():
		var n: Control = _unit_nodes[id]
		if is_instance_valid(n):
			n.set_selectable(selectable_ids.has(id))

func set_unit_selected(instance_id: String) -> void:
	for id in _unit_nodes.keys():
		var n: Control = _unit_nodes[id]
		if is_instance_valid(n):
			n.set_selected(id == instance_id)

## 详情区（左下：卡名 / 技能描述 / 四维）
func show_card_detail(data: CardData) -> void:
	if data == null:
		return
	$HUD/InfoPanel/CardName.text = data.display_name
	$HUD/InfoPanel/SkillDesc.text = data.description if data.skill_name == "" \
		else "[%s] %s\n%s" % [data.glossary, data.skill_name, data.description]
	var u := data as UnitData
	if u != null:
		_set_attr_rows(str(u.atk), str(u.hp), str(u.move), str(u.attack_range))
	else:
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

## 回合 / 地图 / 场地效果（HUD 右下）
func set_match_info(turn_text: String, map_name: String, site_effect: String) -> void:
	$HUD/MatchInfo/TurnInfo.text = turn_text
	$HUD/MatchInfo/MapName.text = map_name
	$HUD/MatchInfo/SiteEffect.text = site_effect

## 双方费用（蜂王回费量 / 当前费用由外层给）
func set_cost(side: int, value: String) -> void:
	var node := $Battle/PlayerBesaInfoLift if side == side_ally else $Battle/PlayerBesaInfoRight
	var lb: Label = node.get_node_or_null("BadgeImage/Value")
	if lb:
		lb.text = value

## 双方玩家名
func set_player_names(ally: String, enemy: String) -> void:
	$Battle/PlayerBesaInfoLift/PlayerNamesLeft.text = ally
	$Battle/PlayerBesaInfoRight/PlayerNamesRight.text = enemy

## 主按钮文案 / 是否可用
func set_main_button(text: String, enabled: bool = true) -> void:
	var b: Button = $HUD/ActionBar/MainButton
	b.text = ""
	b.disabled = not enabled
	$HUD/ActionBar/Label.text = text

## 换地图（改名字 + 贴图，不动结构）
func load_map(map_data: MapData) -> void:
	if map_data == null:
		return
	var plate := $Battle/MapView/MapPlate/TextureRect
	if map_data.terrain_texture != null:
		plate.texture = map_data.terrain_texture
	$HUD/MatchInfo/MapName.text = map_data.display_name
	$HUD/MatchInfo/SiteEffect.text = map_data.description


# ---------------- 静态 UI → 信号 ----------------

func _on_main_pressed() -> void:
	main_button_pressed.emit()

func _on_func_pressed(which: String) -> void:
	func_button_pressed.emit(which)
	if which == "Back":
		back_pressed.emit()


# ---------------- 清场（重开一局） ----------------

func clear_all() -> void:
	for n in _units.get_children():
		n.queue_free()
	for p in [_hand_l, _hand_r]:
		for c in p.get_children():
			c.queue_free()
	_unit_nodes.clear()
	_hand_nodes.clear()
	_hand_cards.clear()
