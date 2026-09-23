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
## 飘字场景（迭代060 v4）
const FLOAT_TEXT_SCENE := preload("res://scenes/ui/float_text.tscn")
## 飘字字号：数值越大字体越大（《动画系统及流程》§二之2 line 51；线性映射，参数集中便于实机返工 T14/T15）
const FLOAT_FS_BASE := 40        ## 数值 0 → 该字号
const FLOAT_FS_MAX := 96         ## 参考数值 → 该字号
const FLOAT_FS_REF := 25         ## 字号映射的参考数值
## 数值文本颜色（《动画系统及流程》§二之2 line 48-50）
const COL_COST := Color("#FFA300")     ## 回费
const COL_DAMAGE := Color("#FF2000")   ## 受伤
const COL_HEAL := Color("#00DD00")     ## 回血
## 阶段枚举镜像（battle_state.gd: enum Phase { RECOVER, TERRAIN, DEPLOY, ACTION }）
##   仅用于 §二之3 的文本色表（回费/场地·等待行动 = 白 50%）
const PHASE_RECOVER := 0
const PHASE_TERRAIN := 1
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
## 联机（迭代062）：操作闸门 + 客户端；单机时 net_client 为 null（intent 等价直连引擎）
var intent: NetIntent = null
var net_client: RelayClient = null
var net_seat: int = 0
## 动画引擎（迭代060 v4）：Pattern→Unit→Clip **数据驱动**，数据在 `game_data/anims/*.tres`
##   帧数计时（T2）+ 确定性推进（回放一致）；实现见 `scripts/anim/anim_player.gd`
var anim: Node = null
## 飘字层（迭代060 v4）：`battle_scene.tscn` 的**最后子节点** + `z_index=100`（迭代021 教训：飘字必须后绘制）
var _fx_root: Control = null
## UI 锁定（§一之4 line 29）：`block_ui` 动画运行期间屏蔽交互
var _ui_locked: bool = false
## 待退场队列（instance_id → 幽灵节点）：等该单位身上动画播完再淡出（人 2026-09-21：致死也要看见抖动）
var _pending_exit: Dictionary = {}
## 抖动同帧去重（instance_id → 帧号）：event 信号 + unit_damaged 双来源只算一次
var _shake_frame: Dictionary = {}

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
	## T2 / 回放一致性（迭代060 检查点1）：**锁 60fps** —— 帧数基准的硬前提
	##   （`project.godot` 的 run/max_fps 在本机不生效；旧实现只在 `scenes/battle_flow.gd` 里显式设置）
	Engine.max_fps = 60
	## 动画引擎（迭代060 v4）：唯一动画宿主；帧数计时 + 确定性推进（回放一致）
	anim = preload("res://scripts/anim/anim_player.gd").new()
	anim.name = "AnimPlayer"
	add_child(anim)
	anim.instance_finished.connect(_on_anim_finished)
	anim.ui_lock_changed.connect(_on_ui_lock)
	## 飘字层：**运行时建**（不落盘），挂在 HUD 下（HUD 是最后绘制的一层）+ z_index 拉高
	##   ⚠️ 不再往 `battle_scene.tscn` 里加节点：编辑器持有旧内存副本，
	##      `node_create + scene_save` 会把整个场景回退（迭代060 实测：节点 56 → 29）
	_fx_root = Control.new()
	_fx_root.name = "EffectsTop"
	_fx_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_root.z_index = 100
	$HUD.add_child(_fx_root)
	_connect_bus()
	_connect_static_ui()
	_adopt_cells()
	## 联机开局（迭代062）：**先按服务器下发的 seed 播种**再建引擎 ——
	## 引擎唯一随机点＝牌库抽空重洗（dk.shuffle() 走全局 RNG），播种后两端重洗一致
	if NetSession.active:
		seed(NetSession.seed_value)
		net_seat = NetSession.seat
	engine = EngLib.new()
	if auto_start and not engine.start(_config()):
		push_warning("BattleEngine 启动失败（看上面的配置错误日志）")
	## 操作闸门：单机时等价直接调引擎；联机时同时上行 op
	intent = NetIntent.new(engine, null, net_seat)
	if NetSession.active:
		_setup_net()
	## 引擎就绪后才下发：UI 参数（含地表）
	##   （手牌/费用的开局同步由 `_on_battle_started` → `_sync_all()` 负责）
	apply_params()
	_apply_terrain_to_cells()


## 联机接入（迭代062）：连中继 → 收 op 应用到本地引擎；套用座位视角（镜像 + 换色）
func _setup_net() -> void:
	set_my_seat(net_seat)
	net_client = RelayClient.new()
	intent.client = net_client
	net_client.op_received.connect(func(seat: int, _seq: int, _frame: int, payload, _sseq: int) -> void:
		if not intent.apply_remote(seat, payload):
			_flash_msg("收到无法应用的操作（%s）" % intent.stats_text()))
	net_client.peer_left.connect(func(_seat: int, reason: String, ended: bool) -> void:
		if ended:
			_flash_msg("对局结束：对手已离开（%s）" % reason))
	net_client.closed.connect(func(_code: int, _r: String) -> void:
		_flash_msg("与中继的连接已断开"))
	net_client.start(NetSession.url, "godot-battle")
	_flash_msg("联机中：%s" % NetSession.describe())


func _process(_dt: float) -> void:
	if net_client != null:
		net_client.poll()


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
	## 迭代060 v4 动画接线：地图抖动 / 回合色 / 阶段文本色
	b.connect(Bus.SIG_COMMAND_RESOLVED, _on_command_resolved)
	b.connect(Bus.SIG_ATTACK_RESOLVED, _on_attack_resolved)
	b.connect(Bus.SIG_PHASE_STARTED, _on_phase_text_color)


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
	## ⭐ 回合切换也刷新手牌亮/灰（人要求「轮换等情况下依然稳定显示是否可用」）
	##   与费用变化 / 手牌变化三条路径**互相幂等**（都只读当前 state），不会打架。
	refresh_hand_affordability()
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
	## ⭐ 阶段切换也刷新手牌亮/灰（幂等；保证任何时刻显示都跟当前费用一致）
	refresh_hand_affordability()


func _on_cost_changed(side: int, cost: int, delta: int) -> void:
	## ⚠️ 左右与阵营的对应（迭代059 小修补：原实现左右反了）
	##   左侧面板 `PlayerBesaInfoLift` = **敌方**（与 `HandPanelLeft`/`EnemyHand_*` 同侧）
	##   右侧面板 `PlayerBesaInfoRight` = **我方**（与 `HandPanelRight`/`AllyHand_*` 同侧）
	var node := $Battle/PlayerBesaInfoRight if side == SIDE_ALLY else $Battle/PlayerBesaInfoLift
	var lb: Label = node.get_node_or_null("BadgeImage/Value")
	if lb != null:
		lb.text = str(cost)
	## ⭐ 费用一变，双方手牌的亮/灰立刻按**费用口径**重算（幂等）
	refresh_hand_affordability()
	## 回费文本（§二之1 line 42「回费文本」；§二之2 line 48 回费 = #FFA300）
	if delta > 0:
		var badge: Control = node.get_node_or_null("BadgeImage")
		_float_at(badge, "+%d" % delta, COL_COST, delta)


func _on_hand_changed(side: int, hand: Array, playable: Array) -> void:
	_render_hand(side, hand, playable)


func _on_unit_spawned(inst: UnitInstance, cell: Vector2i) -> void:
	_spawn_unit(inst, cell)


func _on_unit_moved(inst: UnitInstance, _from: Vector2i, to: Vector2i) -> void:
	var n: Control = _unit_nodes.get(inst.instance_id, null)
	if n != null and is_instance_valid(n):
		n.position = _cell_pos(to)
		_play("移动落位", inst)


func _on_unit_damaged(inst: UnitInstance, dmg: int, hp_after: int, _src: String) -> void:
	_update_unit(inst, hp_after)
	_play("受伤闪红", inst)
	_shake(inst, dmg)
	_float_at(_unit_nodes.get(inst.instance_id, null), "-%d" % dmg, COL_DAMAGE, dmg)


func _on_unit_healed(inst: UnitInstance, amt: int, hp_after: int) -> void:
	_update_unit(inst, hp_after)
	_float_at(_unit_nodes.get(inst.instance_id, null), "+%d" % amt, COL_HEAL, amt)


func _on_unit_removed(inst: UnitInstance, _reason: String) -> void:
	var n: Control = _unit_nodes.get(inst.instance_id, null)
	_unit_nodes.erase(inst.instance_id)
	if n == null or not is_instance_valid(n):
		return
	## 退场：**动画播完才真正释放**（幽灵节点）—— 基础动画 §一「播完立即退场」
	##   节点先立刻移出注册表 + 鼠标穿透（防吞点击），收尾在 `_on_anim_finished`
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## ⚠️ 人 2026-09-21：**致死也要看得见「受击抖动」** → 不再掐掉它身上还在跑的受击/闪红，
	##   而是**排队等它们播完再淡出**（否则抖动会在起播的同帧被退场掐掉，实测"看不到抖动"）
	if anim != null and anim.running_count_on(n) > 0:
		_pending_exit[n.get_instance_id()] = n
	else:
		_start_exit(n)


## 开始退场（淡出 20 帧）；没有该 Pattern 时直接释放
func _start_exit(n: Control) -> void:
	if n == null or not is_instance_valid(n):
		return
	if anim != null and anim.has_pattern("单位退场"):
		anim.action("单位退场", n)
	else:
		n.queue_free()


func _on_selection_changed(_kind: int, _id: String, preview: Resource, _units: Array) -> void:
	## ⚠️ 预览范围**由规则层算好装在 PreviewData 里** —— 视图只读不重算
	_preview = preview
	_render_preview()


func _on_main_button(text: String, enabled: bool, _hint: String = "") -> void:
	## 提示由 `_on_phase_started` 统一负责（避免两个信号争抢同一标签）
	var b: Button = $HUD/ActionBar/MainButton
	if b != null:
		b.disabled = not enabled
		## §二之3 line 60：结束部署 / 结束行动 = 文本白
		b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
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
	## ⚠️ 人 2026-09-21 缺陷：**蜂王被击杀时不飘字、不受击抖动** —— 根因＝此处原有的 `anim.stop_all()`
	##   在**同一帧**把刚起播的「受击抖动 / 受伤闪红 / 浮字上浮」全部清掉（`request_attack` 的顺序是
	##   `resolve_attack`(起播) → `unit_damaged`(飘字) → `_cleanup_dead` → `_declare_queen_killed`(本回调)）。
	##   只有**蜂王**死才触发对局结束，故只有它表现为"没有击杀反馈"。
	##   → **不需要 stop_all**：对局结束后不会再产生新动画，让击杀反馈自然播完
	##     （抖动 → `_pending_exit` 排队退场淡出 → 释放）


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


## 联机「棋盘镜像」（边界 T7）：seat≠0 的玩家把整块棋盘旋转 180° 呈现
## 做法＝**旋转容器**（MapView 绕棋盘中心）→ 底图 / 格 / 单位 / FX 一次性全部对齐；
## ⚠️ 数据仍是**规范 cell**（格节点保存规范 cell、点击回报规范 cell）→ 两端引擎状态天然一致
var my_seat: int = 0
const BOARD_PX := PITCH * 4.0


## 切换座位视角（联机握手/入房后调用；seat 0 = 绿方 = 规范视角）
func set_my_seat(seat: int) -> void:
	if seat == my_seat:
		return
	my_seat = seat
	var mv := get_node_or_null("Battle/MapView") as Control
	if mv != null:
		var mirror := BoardMirror.needs_mirror(my_seat)
		mv.pivot_offset = Vector2(BOARD_PX * 0.5, BOARD_PX * 0.5)   ## 绕棋盘中心
		mv.rotation = PI if mirror else 0.0
		## 单位卡自身反向旋转 → 位置随棋盘镜像，但**卡面文字保持正向可读**
		## ⚠️ 必须先把轴心设到卡片中心（默认轴心=左上角，反向自转会把自己转出格外 —— 实测踩到）
		## ⚠️ 同时**重涂阵营配色**：配色只在 spawn 时按 mine 上色，切座位必须补一次（实测踩到）
		for k in _unit_nodes:
			var un = _unit_nodes[k]
			if un != null and is_instance_valid(un):
				un.pivot_offset = Vector2(PITCH, PITCH) * 0.5
				un.rotation = PI if mirror else 0.0
				var inst_m = _find_unit(String(k))
				if inst_m != null and un.has_method("set_mine"):
					un.set_mine(int(inst_m.side) == my_seat)
	print("[NET] 棋盘镜像 seat=%d（需镜像=%s）" % [my_seat, str(BoardMirror.needs_mirror(my_seat))])


func _cell_pos(cell: Vector2i) -> Vector2:
	## ⚠️ 沿用项目坐标约定：cell.x = 行、cell.y = 列（**规范坐标**，不随镜像变化）
	return Vector2(cell.y * PITCH, cell.x * PITCH)


## 点格 → 翻译成引擎请求（**不在视图里做规则判定**：种类看预览资源给的 kind）
func _on_cell_clicked(cell: Vector2i) -> void:
	if _ui_locked: return   ## 规则4：block_ui 动画期间禁交互
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
			if not intent.request_deploy(side, engine.sel_hand_index, cell):
				_flash_msg("该格不能部署（兵蜂需蜂王相邻空格；建筑需己方领地空格）")
		K.Kind.MOVE:
			if not intent.request_move(side, engine.sel_unit, cell):
				_flash_msg("该格不可到达")
		K.Kind.COMMAND, K.Kind.SUPPORT, K.Kind.ATTACK:
			var target: UnitInstance = engine.state.board.unit_at(cell)
			if target == null:
				_flash_msg("该格没有目标单位")
				return
			if kind == K.Kind.COMMAND:
				if not intent.request_use_command(side, engine.sel_hand_index, target):
					_flash_msg("指令目标不合法或费用不足")
			elif kind == K.Kind.SUPPORT:
				## 支援不针对特定单位（人澄清 Y-5）→ 点任意己方单位即进入待确认
				if not intent.request_support(side, engine.sel_unit, engine.sel_support):
					_flash_msg("再次点击（或点主按钮「确认」）才执行【支援】")
			else:
				if not intent.request_attack(side, engine.sel_unit, target):
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
			if not intent.request_deploy(side, engine.sel_hand_index, cell):
				_flash_msg("该格不能部署（兵蜂需蜂王相邻空格；建筑需己方领地空格）")
		int(EngLib.HandMode.TARGET):
			var u: UnitInstance = engine.state.board.unit_at(cell)
			if u == null or not intent.request_use_command(side, engine.sel_hand_index, u):
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
		## ⭐ 手牌亮/灰：**按当前状态自算**（费用口径），不依赖外部传入的瞬时 mask
		##   人明确：「只考虑部署费用，其他不用考虑」+ 要求「稳定显示」
		var aff: bool = engine.hand_affordable(side, i) if engine != null else false
		if i < playable.size():
			aff = bool(playable[i])
		if hand_params != null:
			_apply_one_hand_params(node, hand_params)
		_call_opt(node, "set_playable", [aff])
	## ⭐ 每次渲染后都把子卡内部节点设为鼠标透明（**保留卡根节点可点**）
	##   （`_ready` 里那次跑在首次渲染之前 → 容器还是空的，等于没跑）
	_ignore_descendants(parent)


## ⭐ 稳定刷新手牌亮/灰（费用口径）——人要求「轮换等情况下依然稳定显示是否可用」
##   调用时机：费用变化 / 阶段变化 / 回合切换 / 卡入牌库墓地 之后
##   它是**幂等**的：只读当前 state.cost 与手牌费用，因此不会与其它刷新互相打架。
func refresh_hand_affordability() -> void:
	if engine == null:
		return
	for side in [SIDE_ALLY, SIDE_ENEMY]:
		var hand: Array = engine.state.sides[side]["hand"]
		## 按渲染顺序（_hand_order）取节点，避免字典顺序错配
		for i in _hand_order[side].size():
			var cid: String = _hand_order[side][i]
			var node: Control = _hand_nodes[side].get(cid)
			if node == null or not is_instance_valid(node):
				continue
			_call_opt(node, "set_playable", [engine.hand_affordable(side, i)])


func _on_hand_clicked(card_id: String, side: int) -> void:
	if _ui_locked: return   ## 规则4：block_ui 动画期间禁交互
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
	if BoardMirror.needs_mirror(my_seat):
		## 镜像视角下反向自转：位置随棋盘翻转、卡面保持正向；轴心必须=卡片中心
		node.pivot_offset = Vector2(PITCH, PITCH) * 0.5
		node.rotation = PI
	_units_root.add_child(node)
	## ⭐ 运行时新建的单位卡也会带 CrtFx 叠加层 → 必须单独设鼠标穿透，
	##    否则新部署的单位会**盖住整块棋盘**、吞掉所有点击（迭代058 实测教训）
	_set_ignore_recursive(node)
	_ignore_children(node)          ## ⭐ 单位卡内部子节点鼠标透明（否则点击被立绘吃掉，bug③）
	node.bind(_unit_view(inst, cell))
	if node.has_signal("unit_pressed"):
		node.unit_pressed.connect(_on_unit_clicked)
	_unit_nodes[inst.instance_id] = node
	_play("卡牌登场", inst)


# ============================================================
#  迭代060 v4 接线：飘字 / 地图抖动 / 回合色 / UI 锁定
# ============================================================

## 规则4（§一之4 line 29）：`block_ui` 动画运行期间屏蔽交互
func _on_ui_lock(locked: bool) -> void:
	_ui_locked = locked


## 飘字（§二之1 line 42-43「回费文本 / 数值buff变化 / 战斗结算文本」
##       + §二之2 line 47-51：三色 + **数值越大字体越大**）
func _float_at(anchor: Control, text: String, color: Color, value: int) -> void:
	if _fx_root == null or anchor == null or not is_instance_valid(anchor):
		return
	var ft: Control = FLOAT_TEXT_SCENE.instantiate()
	## ⚠️ 颜色/字号放**子节点**：`浮字上浮` 的淡出是 TINT（绝对 modulate），
	##   若把颜色放在动画目标本身会被白色冲掉（实测踩坑）→ 外层只吃 alpha，内层保留颜色
	var lb: Label = ft.get_node("Text")
	lb.text = text
	lb.modulate = color
	var t: float = clampf(float(value) / float(FLOAT_FS_REF), 0.0, 1.0)
	lb.add_theme_font_size_override("font_size", int(round(lerpf(float(FLOAT_FS_BASE), float(FLOAT_FS_MAX), t))))
	_fx_root.add_child(ft)
	## 坐标空间：飘字挂 EffectsTop（与视图根同原点的整屏 Control）→ 用 global 差值换算
	ft.position = anchor.global_position + Vector2(anchor.size.x * 0.5 - 100.0, -20.0) - _fx_root.global_position
	anim.action("浮字上浮", ft)


## 地图抖动（§二之2 line 54「释放攻击 AOE 时整个地图/镜头抖动」；§六「指令技能命中 ≥2 处」）
func _on_command_resolved(_side: int, _card, targets: Array, damage: int, _healed: int) -> void:
	## ① **每个被命中单位都要抖**（无条件：被抵挡、致死都算"受到攻击"——人 2026-09-21）
	##    指令伤害只给"总伤害"，按命中数均摊作为抖动强度
	var per: int = maxi(1, int(damage / maxi(1, targets.size())))
	for t in targets:
		if t is UnitInstance:
			_shake(t, per)
	## ② 命中 ≥2 处 → 整图抖动（§六「指令技能命中 ≥2 处」；§二之2 line 54）
	if anim != null and targets.size() >= 2:
		anim.action("地图抖动", $Battle/MapView)


## 攻击结算 —— `attack_resolved` 是**无条件广播**（rules_combat.gd:111），
##   抖动量要挂在这里才能覆盖"被完全抵挡（dmg=0，不发 unit_damaged）"的攻击
func _on_attack_resolved(attacker: UnitInstance, defender: UnitInstance,
		dmg_def: int, dmg_atk: int, counter_valid: bool) -> void:
	_shake(defender, dmg_def)
	if counter_valid:
		_shake(attacker, dmg_atk)


## 文本色表（§二之3 line 60-62）：结束部署/行动 = 白；回费阶段·等待行动 = 白 50%
func _on_phase_text_color(_side: int, phase: int, _round_no: int) -> void:
	var lb: Label = $HUD/ActionBar/Label
	if lb == null:
		return
	lb.modulate = Color(1, 1, 1, 0.5) if (phase == PHASE_RECOVER or phase == PHASE_TERRAIN) else Color(1, 1, 1, 1)


## 受击抖动（§二之2 line 54「单位受到攻击时抖动」+ line 55「数值越大越剧烈」）
##   ⚠️ 触发条件是**"受到攻击/伤害的事件"**，不是"血量是否变化"（人 2026-09-21）：
##     · 抵挡型效果（装甲/护盾/力场）**完全抵挡** → 引擎不发 `unit_damaged` → 仍要抖
##     · **致死伤害** → 仍要抖（退场会排队等它播完，见 `_pending_exit`）
##   同一帧多个来源（event 信号 + `unit_damaged`）只算一次 → 按帧号去重
func _shake(inst: UnitInstance, value: int) -> void:
	if anim == null or inst == null:
		return
	var fid: int = Engine.get_process_frames()
	if int(_shake_frame.get(inst.instance_id, -1)) == fid:
		return
	_shake_frame[inst.instance_id] = fid
	_play("受击抖动", inst, maxi(1, value))


## 播动画（迭代060 v4）—— 目标节点由 `instance_id` 解析；不在册则跳过（不报错、不吞）
func _play(pname: String, inst: UnitInstance, value: int = 0) -> void:
	if anim == null or inst == null:
		return
	var n: Control = _unit_nodes.get(inst.instance_id, null)
	if n != null and is_instance_valid(n):
		anim.action(pname, n, value)


## 动画自然播完的收尾（基础动画 §一：**播完立即退场**，不额外等帧）
##   仅 "单位退场" 需要释放节点；其余动画的收尾已由引擎自身回位
## 动画自然播完的收尾（基础动画 §一：**播完立即退场**，不额外等帧）
##   · `单位退场` → 释放幽灵节点
##   · `浮字上浮` → 释放飘字（否则淡到 α=0 后永远留在浮字层＝泄漏）
func _on_anim_finished(pname: StringName, target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	var n := String(pname)
	if n == "单位退场" or n == "浮字上浮":
		target.queue_free()
		return
	## 待退场排队：该单位身上动画**全部播完**后才开始淡出（人 2026-09-21）
	var tid: int = target.get_instance_id()
	if _pending_exit.has(tid) and anim != null and anim.running_count_on(target) == 0:
		_pending_exit.erase(tid)
		_start_exit(target)


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
		## 联机换色（人 2026-09-23 澄清）：**每个玩家看到自己都是绿方**
		##   局部约定：seat 0 ↔ 引擎 SIDE_ALLY（绿）· seat 1 ↔ SIDE_ENEMY（红）
		##   故 mine = (inst.side == my_seat)：seat1 玩家看到自己的红方单位被着成绿
		"mine": int(inst.side) == int(my_seat),
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
	if _ui_locked: return   ## 规则4：block_ui 动画期间禁交互
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
			intent.request_support(side, engine.sel_unit, engine.sel_support)
			return
		engine.select_unit(side, inst)
		show_detail(inst.data)
		_explain_actions(inst)
	else:
		if not intent.request_attack(side, engine.sel_unit, inst):
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
	if _ui_locked: return   ## 规则4：block_ui 动画期间禁交互
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
		if not intent.request_discard(engine.state.active, engine.sel_hand_index):
			_flash_msg("弃牌失败：需 %d 费，当前 %d" % [dc, engine.state.cost(engine.state.active)])
		return
	## 否则推进阶段
	print("[VIEW] 主按钮被点击 → request_end_phase()；phase=", engine.state.phase)
	intent.request_end_phase()
