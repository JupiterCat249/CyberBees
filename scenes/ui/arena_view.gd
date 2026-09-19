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
const TerrainP := preload("res://scripts/data/terrain_params.gd")
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
## 地形格渲染参数（迭代059 步3：UI 资源化 —— 地形格视觉走本资源）
var terrain_params: Resource = TerrainP.new()

## 操作反馈：**人 2026-09-19 明确省略 HUD 橙色提示文本**（可省设计）
## 所有反馈走控制台输出（`_flash_msg` → print("[VIEW] ...")）
const FLASH_FRAMES := 180      ## 保留常量占位（若日后要恢复 HUD 提示可用）


func _ready() -> void:
	_connect_bus()
	_connect_static_ui()
	_adopt_cells()
	engine = EngLib.new()
	if auto_start and not engine.start(_config()):
		push_warning("BattleEngine 启动失败（看上面的配置错误日志）")
	## 引擎就绪后才下发：UI 参数（含地表）
	##   （手牌/费用的开局同步由 `_on_battle_started` → `_sync_all()` 负责）
	apply_params()
	_apply_terrain_to_cells()


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
	## 默认地图：**「丰饶」（无特殊地形格，符合"地图素材自带地形"的口径）**
	##   6 张图里 丰饶/寒潮/默认 均无地形格；要演示地形改用 load_map()
	if use_resources and ResourceLoader.exists("res://game_data/maps/丰饶.tres"):
		var md := load("res://game_data/maps/丰饶.tres") as MapData
		if md != null:
			c.map_data = md
	return c


func _connect_static_ui() -> void:
	var b: Button = $HUD/ActionBar/MainButton
	if b != null and not b.pressed.is_connected(_on_main_pressed):
		b.pressed.connect(_on_main_pressed)
	_fit_text_labels()
	_make_overlays_click_through()


## ⭐ 把所有扫描线特效层（`CrtFx`）设为**鼠标透明**
##
## 为什么必须做（迭代058 实测定案）：
##   `card_unit.tscn` / `card_hand.tscn` 的 `Artwork/ArtPlane/CrtFx` 是**扫描线叠加层**，
##   它在场景里被撑成 **1920×1080**（单位卡本身只有 250×250），且 `mouse_filter` 为默认 **STOP**。
##   于是它**盖住整个棋盘区**，把单位卡与格子的点击**全部吞掉** ——
##   这就是\"单位无法选中/移动\"的真正原因。
##
## 依据：D8「扫描线只作背景纹理，**不得覆盖 UI 节点**；战斗地图上不得出现扫描线」。
## 实证：`gui_get_hovered_control()` 在蜂王格中心返回的正是 `.../Artwork/ArtPlane/CrtFx`。
##
## 修法：递归找出所有名为 `CrtFx` 的 Control（含运行时新建的单位卡）→ 设 `MOUSE_FILTER_IGNORE`。
##   **只改鼠标穿透，不动视觉**（扫描线照常显示）。
func _make_overlays_click_through() -> void:
	_set_ignore_recursive(self)
	_make_card_children_click_through()


## ⭐ 让**卡片内部的所有子节点**鼠标透明（迭代059 实测 bug③ 根因）
##
## 现象：`gui_get_hovered_control()` 在单位格上返回的是
##   `Units/Unit_xxx/Artwork/ArtPlane/TextureRect` —— 单位卡**内部的立绘节点**。
##   这些内部节点默认 `mouse_filter = STOP`，会**吃掉点击**，事件到不了卡根节点的
##   `_gui_input` → 卡的 `unit_pressed` / `hand_pressed` 信号**永远不触发** →
##   选中指令卡后点单位目标走不到指令分支（控制台只说"要选中己方单位"）。
##
## 修法：对卡片实例（单位卡 + 手牌卡）**递归把子 Control 设为 IGNORE**，
##   只留卡根节点接收点击（卡根节点的 mouse_filter 在场景里已是 STOP）。
func _make_card_children_click_through() -> void:
	for node in _units_root.get_children():
		_ignore_descendants(node)
	_ignore_descendants(_hand_l)
	_ignore_descendants(_hand_r)


## 扫描**手牌容器**：把每张卡的**内部**节点设为穿透，但保留**卡根节点**可点。
##   ⚠️ 卡根节点的 `mouse_filter = STOP` 由 `card_hand.gd` 的 `_ready()` 设置；
##      若把根节点也设成 IGNORE，整张卡都点不到（迭代059 实测）。
##   故此处**跳过容器的直接子节点（= 卡根）**，只处理它们下面的层级。
func _ignore_descendants(container: Node) -> void:
	if container == null:
		return
	for card in container.get_children():
		_ignore_children(card)


## 递归把 n 的**所有子 Control** 设为鼠标透明
##   （用于**单位卡实例**：卡根由 `card_unit.gd` 的 `_ready()` 设 STOP，此处只清内部）
func _ignore_children(n: Node) -> void:
	if n == null:
		return
	for ch in n.get_children():
		if ch is Control:
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_children(ch)


func _set_ignore_recursive(n: Node) -> void:
	for ch in n.get_children():
		if ch is Control:
			var c := ch as Control
			## 扫描线特效层一律鼠标穿透（按节点名识别，含卡内叠加层）
			if String(c.name) == "CrtFx" or String(c.name).begins_with("CrtFx"):
				c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_ignore_recursive(ch)


## 适配长文案与地形提示
## ⚠️ **人 2026-09-19 明确要求：不要改字号。**
##   之前这里把主按钮 60→30、阶段提示 24→20，导致字号变小（尤其手牌/详情区属性区）。
##   现只保留**自动换行**（不改字号），字号一律沿用素材场景原值。
func _fit_text_labels() -> void:
	var se := $HUD/MatchInfo/SiteEffect as Label
	if se != null:
		se.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## ⚠️ 人 2026-09-19 明确：**橙色提示文本省略**（可省设计），需要时作为**控制台输出**存在。
## 故这里不再新建/维护任何 HUD 提示标签；所有操作反馈走 `print("[VIEW] ...")`。
func _flash_msg(text: String) -> void:
	print("[VIEW] ", text)


## （HUD 提示已按人要求省略 —— 反馈走控制台）



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
	## 换图后地形格视觉同步（地形效果随地图变化）
	_apply_terrain_to_cells()


## 把地形效果/参数下发给各格（格子自己不查地图 —— 单向分层）
func _apply_terrain_to_cells() -> void:
	var md: MapData = null
	if engine != null and engine.state != null:
		md = engine.state.map_data
	for c in _cells.keys():
		var cell: Control = _cells[c]
		if cell == null or not is_instance_valid(cell):
			continue
		var te = md.effect_at(c) if md != null else null
		if cell.has_method("set_terrain"):
			cell.set_terrain(te, terrain_params)


## 看该格是否地形格（供详情/提示用，视图只读）
func terrain_name_at(cell: Vector2i) -> String:
	if engine == null or engine.state == null or engine.state.map_data == null:
		return ""
	var te = engine.state.map_data.effect_at(cell)
	return te.display_name if te != null else ""


## 应用两套 UI 参数（**分开应用**，不混用）
func apply_params() -> void:
	_apply_detail_params()
	_apply_hand_params()
	_apply_terrain_to_cells()


func _apply_detail_params() -> void:
	var p = detail_params
	if p == null:
		return
	var nm := $HUD/InfoPanel/CardName as Label
	if nm != null and int(p.name_font_size) > 0:
		nm.add_theme_font_size_override("font_size", int(p.name_font_size))
	var ds := $HUD/InfoPanel/SkillDesc as Label
	if ds != null and int(p.desc_font_size) > 0:
		ds.add_theme_font_size_override("font_size", int(p.desc_font_size))
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
			## ⚠️ 只在**显式给了正数**时才覆盖字号（0/负数 = 沿用素材场景原值）
			##   人 2026-09-19：不要改字号 —— 之前这里把 42 覆盖成 24 导致属性区字号变小
			if v != null and int(p.attr_value_font_size) > 0:
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
		## ⚠️ 只在显式给正数时覆盖字号（人 2026-09-19：不要改字号）
		##    素材原值 48；之前这里覆盖成 26 → 变小
		if bv != null and int(p.badge_font_size) > 0:
			bv.add_theme_font_size_override("font_size", int(p.badge_font_size))
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
	## ⚠️ `_sync_all()` 必须**推迟一帧**：
	##   `engine.start()` 在「初始费用/后手加成/回费」**设好之前**就发出了本信号，
	##   此时立刻渲染手牌会因 `cost=0` 把所有牌判为不可出 → **手牌全灰**（迭代059 实测 bug）。
	##   改为 call_deferred → 引擎完全就绪后再同步。
	_sync_all.call_deferred()


func _on_round_started(round_no: int) -> void:
	if engine != null and engine.state != null:
		_set_turn(engine.state.active, round_no)


func _set_turn(side: int, round_no: int) -> void:
	$HUD/MatchInfo/TurnInfo.text = "回合%d--%s" % [round_no, "绿方" if side == SIDE_ALLY else "红方"]


func _on_phase_started(side: int, phase: int, _round_no: int) -> void:
	## 阶段文本 + 操作提示（迭代058：可发现性 —— 告诉玩家\"现在能做什么\"）
	var names := {0: "回费", 1: "场地", 2: "部署", 3: "行动"}
	var tips := {
		0: "自动结算：己方单位回费 + 行动机会重置",
		1: "自动结算：场地效果作用于格子上的单位",
		2: "部署阶段：点手牌部署单位/使用指令，准备好后点右侧按钮进入行动阶段",
		3: "行动阶段：点自己的单位可移动/攻击/支援（每单位每回合 1 次行动）",
	}
	$HUD/MatchInfo/SiteEffect.text = "%s阶段（%s）｜%s" % [
		str(names.get(phase, "?")), "绿" if side == SIDE_ALLY else "红",
		str(tips.get(phase, ""))]


func _on_cost_changed(side: int, cost: int, _delta: int) -> void:
	## ⚠️ 左右与阵营的对应（迭代059 小修补：原实现左右反了）
	##   左侧面板 `PlayerBesaInfoLift` = **敌方**（与 `HandPanelLeft`/`EnemyHand_*` 同侧）
	##   右侧面板 `PlayerBesaInfoRight` = **我方**（与 `HandPanelRight`/`AllyHand_*` 同侧）
	var node := $Battle/PlayerBesaInfoRight if side == SIDE_ALLY else $Battle/PlayerBesaInfoLift
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


func _on_main_button(text: String, enabled: bool, _hint: String = "") -> void:
	## 提示由 `_on_phase_started` 统一负责（避免两个信号争抢同一标签）
	var b: Button = $HUD/ActionBar/MainButton
	if b != null:
		b.disabled = not enabled
	$HUD/ActionBar/Label.text = text


func _on_log(text: String, level: int) -> void:
	print("[BATTLE]", "[WARN]" if level > 0 else "", " ", text)
	## 失败/拦截原因**直接回显到 HUD**（迭代058 G4）—— 引擎已写好原因文案
	if level > 0:
		_flash_msg("⚠ " + text)


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
	## 预览也拉一次（开局选中态清零）
	_render_preview()


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
	## ⭐ 手牌状态机（人 2026-09-19）：
	##   在交互范围内 → 执行该卡的交互（部署 / 指定指令目标）
	##   脱离交互范围 → **自动切换状态**（退出选中），再按普通流程处理本次点击
	##   ⚠️ 不能无条件取消：否则点部署格时选中被清掉 → **手牌选中后无法部署**（曾引入的回归）
	if engine.sel_kind == 1:
		if engine.hand_range_has_cell(cell):
			_execute_hand_on_cell(cell)
			return
		engine.hand_range_leave()
	var spec = engine.current_preview()
	var kind: int = int(spec.kind) if spec != null else 0
	var side: int = engine.state.active
	match kind:
		K.Kind.DEPLOY:
			if not engine.request_deploy(side, engine.sel_hand_index, cell):
				_flash_msg("该格不能部署（兵蜂需蜂王相邻空格；建筑需己方领地空格）")
		K.Kind.MOVE:
			if not engine.request_move(side, engine.sel_unit, cell):
				_flash_msg("该格不可到达")
		K.Kind.COMMAND, K.Kind.SUPPORT, K.Kind.ATTACK:
			var target: UnitInstance = engine.state.board.unit_at(cell)
			if target == null:
				_flash_msg("该格没有目标单位")
				return
			if kind == K.Kind.COMMAND:
				if not engine.request_use_command(side, engine.sel_hand_index, target):
					_flash_msg("指令目标不合法或费用不足")
			elif kind == K.Kind.SUPPORT:
				## 支援不针对特定单位（人澄清 Y-5）→ 点任意己方单位即进入待确认
				if not engine.request_support(side, engine.sel_unit, engine.sel_support):
					_flash_msg("再次点击（或点主按钮「确认」）才执行【支援】")
			else:
				if not engine.request_attack(side, engine.sel_unit, target):
					_flash_msg("不能攻击该目标（射程外 / 已行动过 / 非行动阶段）")
		_:
			## 无预览 → 尝试选中该格上的己方单位（并说明"为什么不能操作"）
			var here: UnitInstance = engine.state.board.unit_at(cell)
			if here == null:
				## 空且无预览：最常见的原因是阶段不对
				if engine.state.phase == 2:
					_flash_msg("部署阶段：点手牌选卡后点高亮格部署；要操作单位请先点右侧「完成部署 → 进入行动」")
				elif engine.state.phase == 3 and engine.sel_unit == null:
					_flash_msg("点是自己的单位来选中它（选中后才能移动/攻击/支援）")
				return
			if here.side != side:
				_flash_msg("这是对方的单位（要攻击请先选中自己的单位）")
				return
			engine.select_unit(side, here)
			show_detail(here.data)
			_explain_actions(here)


## 手牌状态机：在交互范围内点击格 → 按卡种执行
func _execute_hand_on_cell(cell: Vector2i) -> void:
	var side: int = engine.state.active
	match int(engine.hand_mode):
		int(EngLib.HandMode.DEPLOY):
			if not engine.request_deploy(side, engine.sel_hand_index, cell):
				_flash_msg("该格不能部署（兵蜂需蜂王相邻空格；建筑需己方领地空格）")
		int(EngLib.HandMode.TARGET):
			var u: UnitInstance = engine.state.board.unit_at(cell)
			if u == null or not engine.request_use_command(side, engine.sel_hand_index, u):
				_flash_msg("该单位不是该指令的合法目标")
		_:
			pass


## 选中单位后，把"现在能做什么 / 为什么不能做"说清楚（迭代058 G3/G7）
func _explain_actions(inst: UnitInstance) -> void:
	if inst == null:
		return
	if inst.has_acted:
		_flash_msg("%s 本回合已行动过（每个单位每回合 1 次行动）" % inst.card_name())
		return
	if inst.side == SIDE_ALLY and inst.cell.x == 3 and inst.has_moved and inst.has_acted:
		pass
	var pv = engine.current_preview()
	var n_move := 0
	var n_atk := 0
	if pv != null:
		n_move = K.cells_from(pv, K.Kind.MOVE).size()
		n_atk = pv.units.size()
	# a500 行动机会 3：部署当回合无行动机会（视图据此解释，不自己判定规则）
	if n_move == 0 and n_atk == 0 and not inst.has_acted:
		_flash_msg("%s 本回合无可行动作（刚部署的单位当回合无行动机会；下个己方回合即可行动）" % inst.card_name())
	else:
		_flash_msg("%s：可移动 %d 格 · 可攻击 %d 个目标" % [inst.card_name(), n_move, n_atk])


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
	## ⭐ 每次渲染后都把子卡内部节点设为鼠标透明（**保留卡根节点可点**）
	##   （`_ready` 里那次跑在首次渲染之前 → 容器还是空的，等于没跑）
	_ignore_descendants(parent)


func _on_hand_clicked(card_id: String, side: int) -> void:
	if engine == null:
		return
	var idx: int = _hand_order[side].find(card_id)
	if idx < 0:
		return
	## 非行动方的手牌不可操作（本地双人热座：只有轮到的一方能动）
	if side != engine.state.active:
		_flash_msg("现在不是%s的回合" % ("绿方" if side == SIDE_ALLY else "红方"))
		return
	engine.select_hand(side, idx)
	var hand: Array = engine.state.sides[side]["hand"]
	if idx < hand.size():
		var card: CardData = hand[idx]
		show_detail(card)
		_explain_hand(card, side)


## 选卡后的可发现性说明（迭代058 G3）
func _explain_hand(card: CardData, side: int) -> void:
	if card == null:
		return
	if not engine.can_play_hand(side, engine.sel_hand_index):
		if card.cost > engine.state.cost(side):
			_flash_msg("%s 费用 %d，当前只有 %d" % [card.display_name, card.cost, engine.state.cost(side)])
		else:
			_flash_msg("%s 现在不能使用（仅部署/行动阶段可用）" % card.display_name)
		return
	if card is UnitData:
		_flash_msg("已选「%s」：点高亮格部署（兵蜂需蜂王相邻，建筑需己方领地）" % card.display_name)
	elif card is CommandData:
		_flash_msg("已选指令「%s」：点高亮的合法目标使用" % card.display_name)


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
	## ⭐ 运行时新建的单位卡也会带 CrtFx 叠加层 → 必须单独设鼠标穿透，
	##    否则新部署的单位会**盖住整块棋盘**、吞掉所有点击（迭代058 实测教训）
	_set_ignore_recursive(node)
	_ignore_children(node)          ## ⭐ 单位卡内部子节点鼠标透明（否则点击被立绘吃掉，bug③）
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
	## ⭐ 手牌状态机：若该单位是当前指令卡的合法目标 → 就地执行指令
	if engine.sel_kind == 1:
		if engine.hand_range_has_cell(inst.cell):
			_execute_hand_on_cell(inst.cell)
			return
		engine.hand_range_leave()
	if inst.side == side:
		# ── 支援双击确认（原设计）：已选中带支援技能的单位时，点友方 → 待确认 → 再点执行 ──
		if int(engine.sel_kind) == 3 and engine.sel_unit != null and engine.sel_support != null \
				and engine.sel_unit.instance_id != inst.instance_id:
			## 支援不针对特定单位（Y-5）→ 点己方单位即确认/进入待确认
			engine.request_support(side, engine.sel_unit, engine.sel_support)
			return
		engine.select_unit(side, inst)
		show_detail(inst.data)
		_explain_actions(inst)
	else:
		if not engine.request_attack(side, engine.sel_unit, inst):
			_flash_msg("不能攻击 %s（需先选中自己的单位，且目标在射程内）" % inst.card_name())


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
	## ⚠️ 左侧 = 敌方（与敌方手牌 `HandPanelLeft` 同侧）；右侧 = 我方（迭代059 小修补）
	var l := $Battle/PlayerBesaInfoLift.get_node_or_null("PlayerNamesLeft")
	if l != null:
		l.text = enemy
	var r := $Battle/PlayerBesaInfoRight.get_node_or_null("PlayerNamesRight")
	if r != null:
		r.text = ally


func _call_opt(node: Object, method: String, args: Array) -> void:
	if node != null and is_instance_valid(node) and node.has_method(method):
		node.callv(method, args)


## 主按钮 → 按当前选中分流（G-6 Q-3：选中手牌时按钮兼顾弃牌）
func _on_main_pressed() -> void:
	if engine == null or engine.state == null:
		return
	## 待确认支援 → 按钮「确认」执行（迭代059 步3：恢复原设计）
	if engine.support_pending != null:
		engine.confirm_pending()
		return
	## 选中了手牌 → 弃牌
	if int(engine.sel_kind) == 1 and int(engine.sel_hand_index) >= 0:
		var card: CardData = null
		var hand: Array = engine.state.sides[engine.state.active]["hand"]
		if int(engine.sel_hand_index) < hand.size():
			card = hand[engine.sel_hand_index]
		var dc: int = engine.discard_cost_of(card) if card != null else 0
		if not engine.request_discard(engine.state.active, engine.sel_hand_index):
			_flash_msg("弃牌失败：需 %d 费，当前 %d" % [dc, engine.state.cost(engine.state.active)])
		return
	## 否则推进阶段
	print("[VIEW] 主按钮被点击 → request_end_phase()；phase=", engine.state.phase)
	engine.request_end_phase()
