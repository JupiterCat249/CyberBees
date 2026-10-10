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
## 状态图标目录：10 张图标**按中文效果名命名**（灼烧/装甲/护盾/力场/冻结/暴击/拦截/诱饵/速攻/启动）
## → 视图按 `EffectData.display_name` 回退取图，规则实现即自动有图标（无需改渲染层）
const STATUS_ICON_DIR := "res://assets/status_icons/"
## 效果图标缓存（显示名 → Texture2D；值为 null 表示"已查过但没有"，避免每次刷新重试）
static var _icon_cache: Dictionary = {}
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
## 结算浮层（迭代063）：代码构建，不落场景（避开编辑器回退坑）
const RESULT_PANEL := preload("res://scenes/ui/result_panel.gd")
var _result_panel: Control = null
var _leaving := false
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
## ⭐ ② 修正（人 2026-10-05）：当前 `_preview` 是否来自**对端**（远端预览）——
##   远端预览**只渲染范围格，绝不给单位打 attack 标记** ✗（实测：选指令卡时对手单位套红框）
var _preview_is_remote := false
## ⭐ 迭代064 遗留③（人 2026-10-05）：**远端预览当前挂在谁/哪一格上** —— 远端预览有两个来源：
##   · `_remote_preview_id`：对端选中的**单位**（`_on_remote_select`）—— 它死亡/被移除时必须作废；
##   · `_remote_command_cell`：对端**指令卡**的待确认中心格（`_on_remote_action`）—— 对端清掉待确认时必须作废；
##   · `_remote_sel_cell`：对端当前选中的格（白框通道），用于识别"对端换了目标"。
##   三者一起构成远端预览的**生命周期登记**（此前的缺口：预览会被无限期持有 ⇒ 幽灵范围）。
var _remote_preview_id := ""
var _remote_command_cell := Vector2i(-1, -1)
var _remote_sel_cell := Vector2i(-1, -1)
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
	## 🧪 诊断信号接线（跨尺寸扫查用；见 `diag_request` / `_on_diag_request`）
	if not diag_request.is_connected(_on_diag_request):
		diag_request.connect(_on_diag_request)
	## ⭐ 主按钮描边覆盖层（见函数注释：绘制在按钮内容之上，而不是嵌套一圈）
	_install_main_button_stroke()
	## ⭐ 自适应窗口（2026-10-10，**异机实测驱动**）：保证**渲染区 ≥ 设计分辨率**
	##   实测（另一台机器，1920×1080 屏）：窗口被 OS 压到 **1920×1055**（比设计矮 25px）
	##   ⇒ `canvas_items + expand` 把视口撑成 **1965×1080**（宽 45px）⇒ 靠下的 UI 被推出屏幕。
	##   本机 2560×1600 屏没有这个约束，所以"本机不复现"。此处按**实际可用区**自动兜住。
	_fit_window_to_design()
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
	## ⚠️ 必须铺满：否则子节点（结算浮层）用 FULL_RECT 锚点会解析成 0×0、挤在左上角（实测踩到，同大厅那次）
	_fx_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	## ⚠️ `$HUD` 是 CanvasLayer（无尺寸）→ 仅靠锚点仍是 0×0，必须**显式**给视口尺寸（实测踩到）
	_fx_root.size = get_viewport_rect().size
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
	NetSession.detect_auto()
	if NetSession.auto:
		_auto_start()
	## 引擎就绪后才下发：UI 参数（含地表）
	##   （手牌/费用的开局同步由 `_on_battle_started` → `_sync_all()` 负责）
	apply_params()
	_apply_terrain_to_cells()


## 联机接入（迭代062）：连中继 → 收 op 应用到本地引擎；套用座位视角（镜像 + 换色）
func _setup_net() -> void:
	set_my_seat(net_seat)
	## 复用大厅建立的**同一条连接**（房间/座位在连接上；重建会丢房间归属 —— 双实例实测教训）
	if NetSession.client != null and NetSession.client.is_open():
		net_client = NetSession.client
		_flash_msg("复用大厅连接（%s）" % NetSession.describe())
	else:
		net_client = RelayClient.new()
		net_client.start(NetSession.url, "godot-battle")
		_flash_msg("重新连接中继（%s）" % NetSession.url)
	intent.client = net_client
	net_client.op_received.connect(func(seat: int, _seq: int, _frame: int, payload, _sseq: int) -> void:
		if not intent.apply_remote(seat, payload):
			_flash_msg("收到无法应用的操作（%s）" % intent.stats_text()))
	net_client.peer_left.connect(func(_seat: int, reason: String, ended: bool) -> void:
		if ended:
			_flash_msg("对局结束：对手已离开（%s）" % reason)
			_show_result(0, "对手已离开（%s）" % reason))   ## 人裁定：结算保留到手动返回
	net_client.closed.connect(func(_code: int, _r: String) -> void:
		_flash_msg("与中继的连接已断开"))
	net_client.start(NetSession.url, "godot-battle")
	_flash_msg("联机中：%s" % NetSession.describe())


func _process(_dt: float) -> void:
	if net_client != null:
		net_client.poll()
	if NetSession.auto:
		_auto_tick()


## ============================================================================
##  dev / 双实例验收：自动出招（**确定性脚本**，两端同源；仅 --net-auto / SB_NET_AUTO / auto.flag 启用）
##  只在自己行动侧出招（引擎 active 侧天然串行化 → 与另一实例互不抢）
##  收尾：到达回合上限后**双方一致地停手**，静默 1.5s 排空在途 op，再各自打印终局 hash
## ============================================================================
const AUTO_ROUND_CAP := 12

var _auto_timer := 0
var _auto_stopped := false
var _auto_recorded := false
var _auto_quiet := 0.0
var _auto_last_applied := 0


func _auto_start() -> void:
	print("[AUTO] 自动出招已开启 · seat=%d · url=%s" % [net_seat, NetSession.url])


func _auto_tick() -> void:
	if net_client == null or engine == null or engine.state == null:
		return
	if _auto_stopped:
		_auto_quiet += get_process_delta_time()
		if intent != null and intent.applied_remote != _auto_last_applied:
			_auto_last_applied = intent.applied_remote
			_auto_quiet = 0.0
		if _auto_quiet > 1.5:
			_auto_finish()
		return
	if int(engine.state.round_no) >= AUTO_ROUND_CAP:
		_auto_stopped = true
		_auto_quiet = 0.0
		_auto_last_applied = intent.applied_remote if intent != null else 0
		return
	_auto_timer += 1
	if _auto_timer < 12:
		return
	_auto_timer = 0
	if int(engine.state.active) != net_seat:
		return
	if _auto_step():
		NetSession.auto_steps += 1


## 与自检脚本同源：部署优先 → 攻击次之 → 否则结束阶段（失败尝试不发 op、不消耗 RNG）
func _auto_step() -> bool:
	var side := net_seat
	var phase: int = int(engine.state.phase)
	if phase == 2:
		for i in range(engine.state.hand(side).size()):
			for x in 4:
				for y in 4:
					var c := Vector2i(x, y)
					if engine.state.board.is_empty(c) and engine.state.board.is_own_territory(c, side):
						if intent.request_deploy(side, i, c):
							return true
	if phase == 3:
		for u in engine.state.units(side):
			for v in engine.state.units(1 - side):
				if intent.request_attack(side, u, v):
					return true
	return intent.request_end_phase()


func _auto_finish() -> void:
	if _auto_recorded:
		return
	_auto_recorded = true
	_auto_stopped = true
	NetSession.final_hash = StateHash.sha(engine.state)
	NetSession.games += 1
	print("[AUTO] GAME %d FINAL round=%d result=%d seat=%d steps=%d hash=%s" % [
		NetSession.games, int(engine.state.round_no), int(engine.state.result),
		net_seat, NetSession.auto_steps, NetSession.final_hash])
	var p := "user://auto_result_seat%d_g%d.txt" % [net_seat, NetSession.games]
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		f.store_line(NetSession.final_hash)
		f.close()
		print("[AUTO] 已写入 " + ProjectSettings.globalize_path(p))
	if NetSession.games < 2:
		## 连打第二局：走**正式收尾流程**（leave → 回大厅 → 自动重新入队）—— 顺带验证收尾闭环 ✓
		_leave_and_go(true)
	else:
		await get_tree().create_timer(0.6).timeout
		get_tree().quit(0)


## ============================================================================
##  结算浮层与收尾去向（迭代063 · 人裁定：浮层保留战场画面 · 再来一局＝回大厅后再匹配 · 掉线随时可手动返回）
## ============================================================================
func _show_result(result: int, reason: String) -> void:
	if _result_panel != null:
		return
	var title := "对局结束"
	match int(result):
		1: title = "绿方胜"
		2: title = "红方胜"
		3: title = "平局"
	if int(result) == 1 or int(result) == 2:
		var my_win: bool = (int(result) == 1 and net_seat == 0) or (int(result) == 2 and net_seat == 1)
		title = ("胜利" if my_win else "失败") + "（" + title + "）"
	var lines: Array[String] = []
	lines.append("我的座位：%d（%s）" % [net_seat, "绿方" if net_seat == 0 else "红方"])
	if engine != null and engine.state != null:
		lines.append("回合数：%d" % int(engine.state.round_no))
		lines.append("状态指纹：%s" % StateHash.sha(engine.state).substr(0, 12))
	if NetSession.active:
		lines.append("房间：%s" % NetSession.room_code)
	_result_panel = Control.new()
	_result_panel.set_script(RESULT_PANEL)
	_result_panel.setup(title, reason, lines)      ## ⚠️ 必须在 add_child 之前（_ready 里要用这些字段建 UI）
	_result_panel.rematch_pressed.connect(func() -> void: _leave_and_go(true))
	_result_panel.lobby_pressed.connect(func() -> void: _leave_and_go(false))
	_fx_root.add_child(_result_panel)


## 收尾去向：**先 leave 再切场景**（保证房间不残留）；连接不断，回大厅直接复用
func _leave_and_go(rematch_next: bool) -> void:
	if _leaving:
		return
	_leaving = true
	NetSession.rematch = rematch_next
	if net_client != null and net_client.is_open():
		net_client.leave()
		_flash_msg("已退出房间，返回大厅…" if not rematch_next else "已退出房间，返回大厅并重新匹配…")
		for _i in 30:                       ## ≈0.5s：给服务器处理 leave / 释放房间
			net_client.poll()
			await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/ui/net_lobby.tscn")


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
	## ⭐ 迭代064 遗留修复（人 2026-10-05「左侧单位技能详细信息栏存在文本超出边框来到战斗地图而没有自动换行」）：
	##   **实测根因**：`HUD/InfoPanel/SkillDesc` 的框宽 **300px**，而技能描述**单行文本宽 444px**、
	##   `autowrap_mode = 0`（无换行）且 `clip_text = false` ⇒ 文字**直接画出框外**、
	##   越过面板右缘（面板右缘 430）压到战斗地图上 ✗。
	##   修法：与右下面板 `SiteEffect` **同一口径** —— 只开**自动换行**，**不改字号**（守 2026-09-19 硬约束）。
	##   `CardName` 同理补上（当前卡名未溢出，但卡名长度由数据决定，属同类隐患；换行只对更长的卡名生效）。
	for dp in ["HUD/InfoPanel/SkillDesc", "HUD/InfoPanel/CardName"]:
		var dl := get_node_or_null(dp) as Label
		if dl != null:
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	## ⭐ 迭代064 B7（修 P-11 = 清单 UI-7「主按钮存在文本不对齐问题（在一些情况下如添加额外的文字）」）
	## 根因（**实测**，不是猜）：主按钮 `Label` 的框只有 **240px**，而 **Control 会按"最小尺寸"把自己撑大** ——
	##   文案一长（实测 `绿方胜（蜂王被击杀）` = **420px**）框就长到 420，但它的 `position` **固定 x=80 不动**
	##   ⇒ 文字从框左边缘起排、直接冲出屏幕右缘。所以**改 `horizontal_alignment` 无效**（它本来就是居中 1）。
	## 修法：监听 Label 的 `resized`，每次按**按钮实际宽度重新水平居中** —— 不动字号、不动按钮尺寸。
	var lb := $HUD/ActionBar/Label as Control
	if lb != null and not lb.resized.is_connected(_center_main_button_label):
		lb.resized.connect(_center_main_button_label)
		_center_main_button_label()
	## ⭐ 迭代064 B7（修 P-06 = 清单 UI-12「文本达到两位数时没居中」/ UI-19「费用为 10 时 UI 文本溢出」）
	## 根因与主按钮**完全同源**（实测）：费用 `Label` 的框只有 **38px**，而 **`Control` 会按最小尺寸
	##   被文案撑大** —— "10" 实测 **77px** ⇒ 框长到 77，但 `position` 不动 ⇒ 文字**中心偏离徽章约 20px**、
	##   右端**溢出徽章**（截图实测那个 "0" 探出徽章右缘）。
	## 修法：按**徽章实际宽度**重新水平居中；**绝不动字号**（人 2026-09-19 硬约束：不得覆写素材字号 ——
	##   历史上正是"手牌费用徽章 48→26"这类覆写被否）。
	for bp in ["Battle/PlayerBesaInfoRight/BadgeImage", "Battle/PlayerBesaInfoLift/BadgeImage"]:
		var badge := get_node_or_null(bp) as Control
		if badge == null or badge.has_meta("b7_badge_centered"):
			continue
		badge.set_meta("b7_badge_centered", true)
		var v := badge.get_node_or_null("Value") as Control
		if v != null:
			v.resized.connect(_center_badge_value.bind(badge))
			_center_badge_value(badge)


## 把费用数字**水平居中到徽章宽度内**（供 `Value.resized` 回调；幂等）
## ⚠️ 与 `_center_main_button_label()` 同一套思路：**只挪位置、不动字号/尺寸**
func _center_badge_value(badge: Control) -> void:
	## ⚠️ **修正（人 2026-10-05 实测：费用数字普遍**向右偏移**、而模板场景本身是正确居中的）**：
	##   原实现 `lb.position.x = (badge.size.x - lb.size.x) * 0.5` **是错的** ——
	##   模板里 `Value` 本来就是居中的 38px 文本框（`offset 30.9..68.9`，锚点在父左上），
	##   我又按"父左上角 + 当前框宽"重算了一遍 `position` ⇒ **叠加了一次偏移** ⇒ 整体右移。
	##   正确做法（**与模板单数字时的视觉完全等价**，且两位数也永远居中）：
	##   让文本框**覆盖整个徽章** + 文本水平/垂直居中 ⇒ 任意位数都居中、也不会因最小尺寸被撑大而偏移。
	##   （对齐中心 (30.9+68.9)/2 = 49.9 ≈ 徽章中心 ⇒ 单数字结果与模板一致 ✓）
	if badge == null:
		return
	var lb := badge.get_node_or_null("Value") as Control
	if lb == null:
		return
	## ⭐ 迭代067（人 2026-10-10：「费用数字过度靠下…可能需要做自适应」）：
	##   见 `_center_badge_value_geometry()` —— 两处（信息栏 / 手牌卡）**共用同一实现**，杜绝分叉。
	_center_badge_value_geometry(badge)


## 把徽章里的数字**几何居中**到徽章正中（幂等；供信息栏与手牌卡**两处共用**）
## ⭐ 为什么两处要共用一个实现：人 2026-10-10 反馈"联机对端**费用数字过度靠下**" ——
##   两边原来各写一套（信息栏走 `_center_badge_value`、手牌走 `_apply_one_hand_params`），
##   任何一处漏掉就会出现"本机正常、对端偏下"的机器相关差异。统一到一个函数，杜绝分叉。
## ⚠️ 保持 `Value` 仍是徽章的**直接子节点**（路径 `BadgeImage/Value` 被多处按路径取用）。
func _center_badge_value_geometry(badge: Control) -> void:
	if badge == null:
		return
	## ⚠️ **幂等/防重入**（实测踩到栈溢出）：本函数会改 `Value` 的尺寸，而 `_center_badge_value`
	##   又把该节点的 `resized` 接到这里 ⇒ 不加守卫会**无限递归**（Stack overflow）。
	##   徽章的父框尺寸不变时无需重算 ⇒ 用"上次算过的父框尺寸"做记忆即可。
	var stamp := badge.size
	if badge.has_meta("vcenter_stamp") and badge.get_meta("vcenter_stamp") == stamp:
		return
	badge.set_meta("vcenter_stamp", stamp)
	var lb := badge.get_node_or_null("Value") as Control
	if lb == null:
		return
	lb.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	if lb is Label:
		var l := lb as Label
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		## ⚠️ **单行文本不要显式设尺寸**：字体最小尺寸会把高度撑成"行盒高"（实测 38×78，
		##   远大于徽章可用空间 ⇒ 位置算成负值、反而偏离中心）。
		##   只把它铺满父框、把居中交给对齐标记 ⇒ 与字体度量无关，任意位数都居中。
		lb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	## 非 Label 兜底：按最小尺寸几何居中
	var need := lb.get_combined_minimum_size()
	if need.x < 1.0 or need.y < 1.0:
		need = badge.size
	lb.size = need
	lb.position = ((badge.size - need) * 0.5).floor()


## 把主按钮文案**水平居中**到 ActionBar 宽度内（供 `resized` 回调；幂等）
## ⭐ 迭代067（人 2026-10-10：「主按钮的描边是**叠加在底部图像之上**的，不是在外面嵌套一圈」）：
##   做法：在 `ActionBar` 下**运行时新建一层描边覆盖层**（`z_index` 高于按钮、`MOUSE_FILTER_IGNORE` 不挡点击），
##   由它把设计稿的内描边画在**按钮内容之上**；同时把按钮自身 `StyleBoxFlat` 的边框清掉，
##   避免"两圈描边"。设计稿 §2.7：主按钮 400×100 圆角 10 · **内描边 (1492,572) 396×96 圆角 8 `#FFFFFF-10%` 4px**。
##   ⚠️ 只动绘制层次，不改尺寸/字号/文案（守 2026-09-19 硬约束）。
func _install_main_button_stroke() -> void:
	var bar := get_node_or_null("HUD/ActionBar") as Control
	if bar == null:
		return
	## 按钮自身不再画边框（描边改由覆盖层负责）
	var mb := bar.get_node_or_null("MainButton") as Button
	if mb != null:
		for sname in ["normal", "hover", "pressed", "focus", "disabled"]:
			var sb := mb.get_theme_stylebox(sname)
			if sb is StyleBoxFlat:
				var s2: StyleBoxFlat = (sb as StyleBoxFlat).duplicate()
				s2.border_width_left = 0
				s2.border_width_top = 0
				s2.border_width_right = 0
				s2.border_width_bottom = 0
				mb.add_theme_stylebox_override(sname, s2)
	## 覆盖层（幂等）
	var stroke := bar.get_node_or_null("MainButtonStroke") as Panel
	if stroke == null:
		stroke = Panel.new()
		stroke.name = "MainButtonStroke"
		stroke.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stroke.z_index = 2
		bar.add_child(stroke)
	## 位置与尺寸：**与手牌描边同口径 —— 贴边、同宽 4px**
	## ⚠️ 2026-10-10 修正（人：「主按钮的描边**太粗了**，要和手牌描边的粗细程度统一」）：
	##   实测两条描边**宽度都是 4px**（手牌 `1490..1494`、按钮 `1492..1496`）⇒ 差异**不在粗细**，在**位置**：
	##     · 手牌 `InnerLine`（4px/圆角8）**贴卡边**铺满 200×200
	##     · 我上一版把覆盖层放在 `(2,2) 396×96`（照搬设计稿的"内缩 2px"）⇒ 描边**浮在里侧 2px**
	##       ⇒ 视觉上"多出来一圈白边"，看着更粗 ✗
	##   ⇒ 改为**覆盖层 = 按钮矩形**（贴边），仍 4px / 圆角 8 / `#FFFFFF-10%` ⇒ 与手牌一致。
	const STROKE_W := 4
	const STROKE_R := 8
	stroke.position = Vector2.ZERO
	stroke.size = Vector2(400, 100)
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(0, 0, 0, 0)
	sb2.border_color = Color(1, 1, 1, 0.1)
	sb2.set_border_width_all(STROKE_W)
	sb2.set_corner_radius_all(STROKE_R)
	stroke.add_theme_stylebox_override("panel", sb2)
	## 按钮尺寸变了也跟着贴边（不影响手牌链路）
	if not bar.resized.is_connected(_fit_main_button_stroke):
		bar.resized.connect(_fit_main_button_stroke)
	_fit_main_button_stroke()


## 让描边覆盖层始终**贴住**按钮矩形（幂等；供 `ActionBar.resized` 回调）
func _fit_main_button_stroke() -> void:
	var bar := get_node_or_null("HUD/ActionBar") as Control
	if bar == null:
		return
	var stroke := bar.get_node_or_null("MainButtonStroke") as Control
	if stroke == null:
		return
	stroke.position = Vector2.ZERO
	stroke.size = bar.size


## 把主按钮文案**水平居中**到 ActionBar 宽度内（供 `resized` 回调；幂等）
func _center_main_button_label() -> void:
	var lb := $HUD/ActionBar/Label as Control
	var bar := $HUD/ActionBar as Control
	if lb == null or bar == null:
		return
	## 不夹到 0：文案比按钮还宽时，宁可两侧各溢出一点也要**保持居中**
	lb.position.x = (bar.size.x - lb.size.x) * 0.5


## ⚠️ 人 2026-09-19 明确：**橙色提示文本省略**（可省设计），需要时作为**控制台输出**存在。
## 故这里不再新建/维护任何 HUD 提示标签；所有操作反馈走 `print("[VIEW] ...")`。
func _flash_msg(text: String) -> void:
	print("[VIEW] ", text)


## （HUD 提示已按人要求省略 —— 反馈走控制台）

# ============================================================
#  🖥️ 自适应窗口（保证渲染区 ≥ 设计分辨率 —— **不假设两台机器一致**）
# ============================================================
## 问题（2026-10-10 异机实测定位）：
##   项目设计分辨率 **1920×1080**，而 UI 坐标全是设计分辨率下的绝对像素。
##   在 **1920×1080 的屏幕上**，一个 1080 高的窗口放不下（标题栏/任务栏吃掉约 25–60px）⇒
##   OS 把窗口压到 **1055** ⇒ `canvas_items + expand` 把视口撑成 **1965×1080**
##   ⇒ 横向多出 45px、**纵向少 25px** ⇒ 靠下的 UI（手牌/费用数字/按钮）被推出屏幕。
##   本机是 2560×1600 屏，根本不会触发 ⇒ "本机正常、异机出问题"。
##
## 修法（按能力从强到弱，全部在 **运行时实测** 后决策）：
##   ① 可用高度 **放得下**设计高 → 不动（本机走这条）
##   ② 窗口**已经矮于**设计高（已被 OS 压缩）但**屏幕放得下** → 把窗口改回设计尺寸
##   ③ 屏幕都放不下（或可用区高度不足） → **无边框全屏**（屏幕高 = 设计高时 1:1，不缩放、不裁切）
##   ④ 仍不行 → 只告警并打印实测数据（不硬改），由采集报告带出去
## ⚠️ 只动**窗口/显示**，不动任何游戏数据与联机协议（两端各自适配自己的屏幕，互不影响）。
func _fit_window_to_design() -> void:
	var dw := int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920))
	var dh := int(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	if dw <= 0 or dh <= 0:
		return
	var win := get_window()
	if win == null:
		return
	## 全屏（真全屏/无边框全屏）下不需要适配
	if win.mode != Window.MODE_WINDOWED:
		print("[VIEW][WIN] 非窗口模式（mode=%d），跳过自适应" % int(win.mode))
		return
	var scr := DisplayServer.screen_get_size(win.current_screen)
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	var cur := win.size
	print("[VIEW][WIN] 适配前：窗口=%s · 屏幕=%s · 可用=%s · 设计=%dx%d" % [
		str(cur), str(scr), str(usable), dw, dh])
	## ① 已经达标：窗口不低于设计分辨率
	if cur.x >= dw and cur.y >= dh:
		print("[VIEW][WIN] ✓ 窗口已放得下设计分辨率，无需调整")
		return
	## ② 屏幕（可用区）放得下设计尺寸 ⇒ 把窗口改回设计尺寸（修正被 OS 压掉的高）
	if usable.size.x >= dw and usable.size.y >= dh:
		win.size = Vector2i(dw, dh)
		print("[VIEW][WIN] ✓ 已把窗口恢复到设计尺寸 %dx%d（原 %s 低于设计）" % [dw, dh, str(cur)])
		return
	## ③ 屏幕放不下 ⇒ 无边框全屏（无标题栏/任务栏干涉；屏幕高 = 设计高时 1:1）
	win.mode = Window.MODE_FULLSCREEN
	print("[VIEW][WIN] ✓ 屏幕可用区(%s)放不下设计尺寸 ⇒ 已切无边框全屏（屏幕=%s）" % [
		str(usable.size), str(scr)])

# ============================================================
#  🧪 运行环境自测（2026-10-08 新增 · 为"异机不一致"提供可取证手段）
# ============================================================
## 为什么需要：本项目的 UI 坐标是**设计分辨率 1920×1080 下的绝对像素**，
##   而 `canvas_items + expand` 在不同窗口/屏幕/缩放下会给到**不同的实际渲染区** ⇒
##   "本机正常、别的机器下移/越界"。**不能靠假设两边一致，必须在运行时实测**。
## 用法（任意机器、任意窗口大小）：
##   · 游戏运行中按 **F8** → 控制台打印「实际视口 / Canvas 变换 / 各关键节点的全局矩形」，
##     并存一张整屏 PNG 到 `user://diag_YYYYmmdd_HHMMSS.png`（可直接发回来核对）。
##   · 想换尺寸复测：F11 全屏 / 拖动窗口 / 改 `[display] window/size` 后重跑，再按 F8。
## 口径：`get_global_rect()` 是**渲染后的真实屏幕坐标**（含 canvas 变换）⇒ 可直接与视口比较判越界。
const DIAG_NODES := [
	"Battle/MapView", "Battle/MapView/MapPlate", "Battle/MapView/MapCells", "Battle/MapView/Units",
	"Battle/MapView/MapFrame",
	"Battle/HandPanelLeft", "Battle/HandPanelLeft/HandLeft",
	"Battle/HandPanelRight", "Battle/HandPanelRight/HandRight",
	"Battle/PlayerBesaInfoRight", "Battle/PlayerBesaInfoRight/BadgeImage",
	"Battle/PlayerBesaInfoRight/BadgeImage/Value",
	"Battle/PlayerBesaInfoLift", "Battle/PlayerBesaInfoLift/BadgeImage",
	"Battle/PlayerBesaInfoLift/BadgeImage/Value",
	"HUD/InfoPanel", "HUD/ActionBar", "HUD/ActionBar/MainButton", "HUD/ActionBar/Label",
	"HUD/MatchInfo", "HUD/FuncButtonGroup",
]


func _unhandled_key_input(event: InputEvent) -> void:
	## F8 = 运行环境自测（不影响其他输入：只接管这一个键）
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_F8:
		dump_runtime_geometry(true)
		get_viewport().set_input_as_handled()


## 🧪 诊断专用信号（供 MCP `game_eval` **跨尺寸扫查**用）
## ⚠️ 为什么用信号而不是直接 `await dump_runtime_geometry()`：
##   在 `game_eval` 里 await 会**冻住 eval 通道本身**（实测 EVAL_GAME_NOT_READY）⇒
##   正确用法＝**只从 eval 触发信号**，动作在**帧边界之后**由本节点执行：
##     `get_tree().current_scene.diag_request.emit(Vector2i(1280,720))`   # 改窗口后再 dump
##     `get_tree().current_scene.diag_request.emit(Vector2i.ZERO)`        # 只 dump 当前
signal diag_request(window_size: Vector2i)


## 诊断请求处理：可先改窗口尺寸、等两帧让布局重算，再 dump（全在帧边界后执行）
func _on_diag_request(window_size: Vector2i) -> void:
	if window_size != Vector2i.ZERO:
		get_window().size = window_size
		print("[DIAG] 窗口已改为 %s（等待布局重算）" % str(window_size))
	await get_tree().process_frame
	await get_tree().process_frame
	dump_runtime_geometry(true)


## 打印并（可选）截图：**实测**运行期几何，供异机比对
func dump_runtime_geometry(save_shot: bool = true) -> Dictionary:
	var vp := get_viewport()
	var win := get_window()
	var info := {
		"viewport_size": vp.get_visible_rect().size,
		"canvas_transform": vp.canvas_transform,
		"window_size": Vector2(win.size),
		"window_content_scale": win.content_scale_size,
		## ⚠️ 屏幕类 API 在 Godot 4 属于 **DisplayServer**（`Window.get_screen_get_*()` 不存在 —— 实测踩到
		##   `Invalid call. Nonexistent function 'get_screen_get_scale'`，直接把游戏停进了断点）
		"screen_scale": DisplayServer.screen_get_scale(),
		"screen_size": Vector2(DisplayServer.screen_get_size()),
		"screen_dpi": DisplayServer.screen_get_dpi(),
		"screen_count": DisplayServer.get_screen_count(),
		"window_screen": win.current_screen,
		"window_mode": win.mode,
		"stretch_mode": ProjectSettings.get_setting("display/window/stretch/mode", "<unset>"),
		"stretch_aspect": ProjectSettings.get_setting("display/window/stretch/aspect", "<unset>"),
		"design_size": Vector2(
			float(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
			float(ProjectSettings.get_setting("display/window/size/viewport_height", 0))),
	}
	print("========== 🧪 RUNTIME GEOMETRY ==========")
	print("  设计分辨率 : %s" % str(info["design_size"]))
	print("  视口(渲染区): %s" % str(info["viewport_size"]))
	print("  窗口       : %s · content_scale=%s" % [
		str(info["window_size"]), str(info["window_content_scale"])])
	print("  屏幕       : %s · scale=%.2f · dpi=%d · 屏数=%d · 本窗口屏=%d · 窗口模式=%d" % [
		str(info["screen_size"]), float(info["screen_scale"]), int(info["screen_dpi"]),
		int(info["screen_count"]), int(info["window_screen"]), int(info["window_mode"])])
	print("  Canvas变换 : 位移=%s 缩放=%s" % [
		str(info["canvas_transform"].origin), str(info["canvas_transform"].get_scale())])
	print("  stretch    : %s / %s" % [str(info["stretch_mode"]), str(info["stretch_aspect"])])
	var vw := float(info["viewport_size"].x)
	var vh := float(info["viewport_size"].y)
	var bad := 0
	for path in DIAG_NODES:
		var n := get_node_or_null(String(path)) as Control
		if n == null:
			print("  ⚠ %s : <缺失>" % String(path))
			continue
		var gr := n.get_global_rect()
		## 越界判定：**渲染后的全局矩形**是否超出实际渲染区（含 1px 容差）
		var flags := ""
		if gr.position.x < -1.0:
			flags += " ←左越界"
		if gr.position.y < -1.0:
			flags += " ←上越界"
		if gr.end.x > vw + 1.0:
			flags += " →右越界"
		if gr.end.y > vh + 1.0:
			flags += " ↓下越界"
			bad += 1
		print("  %-46s rect=(%.0f,%.0f) size=(%.0f×%.0f) end=(%.0f,%.0f)%s" % [
			String(path), gr.position.x, gr.position.y, gr.size.x, gr.size.y,
			gr.end.x, gr.end.y, flags])
	## 手牌卡逐张（费用徽章"下移"要看卡内节点相对卡的实际偏移）
	var hn = get("_hand_nodes")
	if hn != null:
		for sidek in hn.keys():
			for k in hn[sidek].keys():
				var c = hn[sidek][k]
				if c == null or not is_instance_valid(c):
					continue
				var badge := c.get_node_or_null("BadgeImage") as Control
				var val := c.get_node_or_null("BadgeImage/Value") as Control
				if badge != null and val != null:
					var cb := badge.get_global_rect()
					var cv := val.get_global_rect()
					print("  手牌(side=%s) 卡=%s 徽章=(%.0f,%.0f %.0fx%.0f) 数字=(%.0f,%.0f %.0fx%.0f) Δy=%.1f" % [
						str(sidek), String(k).substr(0, 6),
						cb.position.x, cb.position.y, cb.size.x, cb.size.y,
						cv.position.x, cv.position.y, cv.size.x, cv.size.y,
						cv.position.y - cb.position.y])
					break
			break
	print("  下越界节点数：%d" % bad)
	if save_shot:
		var dir := "user://diag"
		DirAccess.make_dir_recursive_absolute(dir)
		var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
		var path := "%s/diag_%s.png" % [dir, stamp]
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var err := img.save_png(path)
		var abs_path := ProjectSettings.globalize_path(path)
		print("  📸 截图：%s（err=%d）" % [abs_path, err])
		info["shot"] = abs_path
	print("========================================")
	return info



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
	## ⭐ 迭代064 B1（修 P-21）：**效果类信号此前全仓无人订阅**，而规则层一直在发 ——
	##    `rules_effects.gd:67` 发 effect_granted · `:39/:155` 与 `rules_combat.gd:137` 发 effect_expired
	##    （装甲抵挡后即在此消失）· `rules_effects.gd:64/68` 与 `rules_combat.gd:139` 发 unit_stats_changed。
	##    视图不接 → 效果被消耗/移除后**卡面从不重绑**，徽标残存（人 2026-09-27 问题清单 联机-3）。
	##    ⚠️ 旁证：总线那批 `UNUSED_SIGNAL` 警告不是噪音，正是"未接线信号"的清单。
	b.connect(Bus.SIG_EFFECT_GRANTED, _on_effect_granted)
	b.connect(Bus.SIG_EFFECT_EXPIRED, _on_effect_expired)
	b.connect(Bus.SIG_UNIT_STATS, _on_unit_stats_changed)
	## ⭐ 迭代064 B7（清单 UI-20）：**单位回费**单独一条 → 飘字落在那只回费的单位身上
	b.connect(Bus.SIG_REFUND, _on_refund_gained)
	## ⭐ 迭代064 UI-15（对手选中同步）：订阅对端**选中存在性**（纯呈现，不改引擎状态）
	b.connect(Bus.SIG_REMOTE_SELECT, _on_remote_select)
	b.connect(Bus.SIG_REMOTE_ACTION, _on_remote_action)   ## ⭐ 迭代064 ④：对手动作提示


## ⭐ 迭代064 UI-15：**对端选中**的呈现 —— 不改规则、不进引擎状态
##   · 复用 `board_cell.set_selected()`（白框通道**此前未被使用**，正好归"对端选中"）
##   · `_render_preview()` 会清掉所有格子的 selected ⇒ 本标记由那边**记下并重打**（不新增变量）
func _on_remote_select(side: int, cell: Vector2i) -> void:
	## ⭐ 迭代064 遗留③（人 2026-10-05）：每次对端选中变化都**先作废上一条远端预览的登记**。
	##   （下面若确实是对端单位选中，会在同一函数内重新登记 ✓）
	_remote_preview_id = ""
	_remote_command_cell = Vector2i(-1, -1)
	_remote_sel_cell = cell
	for c in _cells.keys():
		if _cells[c].selected:
			_cells[c].set_selected(false)
	if cell.x >= 0 and _cells.has(cell):
		_cells[cell].set_selected(true)
	## ⭐ ③ 新目标：若对端选中的格上有**对端单位** ⇒ 本地**纯计算**它的可作用范围，
	##   并用**既有范围样式**渲染 ✓（"事前提醒"的核心视觉：对手在看哪、能打到哪）
	##   ⚠️ 只读计算、不改本地选中态；`side` 是**发送方**的 side（故 `side != my_seat` 即对端 ✓）
	var rp: Resource = null
	var ru: UnitInstance = null
	if side != my_seat and engine != null and cell.x >= 0:
		ru = engine.state.board.unit_at(cell)
		if ru != null and ru.side != my_seat:
			rp = engine.remote_preview_of(ru)
	if rp != null:
		_preview = rp
		## ⭐ 迭代064 遗留③（人 2026-10-05）：登记这条远端预览**挂在谁身上** ——
		##   该单位一旦死亡/被移除，必须由 `_on_unit_removed()` 立即作废（否则幽灵范围残留）。
		_remote_preview_id = ru.instance_id
		## ⭐ 迭代064 遗留①（**人 2026-10-05 口径澄清：这一条是「应该」**）：
		##   「敌方**应该**能够看到我方选中单位在进入攻击状态后的**攻击范围**以及**选择的攻击目标**，
		##     而不是单纯的静态设计」—— 这是**联机信息完全透明的主动设计** ⇒ 对端视图必须把
		##   远端预览当作**与本地同一份预览**来渲染：范围格 ✓ **单位卡上的攻击目标标框也要 ✓**。
		##   （旧注释「远端只渲染范围格、绝不给单位打 attack 标记」据人口径**作废**；
		##     那条修正真正要挡的是「选指令卡时对手单位被套红框」，已由 `_render_preview()` 里的
		##     **AOE 跳过单位打标** 覆盖，不再靠"远端一律不打标"这种一刀切。）
		_preview_is_remote = true
	else:
		_remote_preview_id = ""
		_preview_is_remote = false
	_render_preview()


## ⭐ 迭代064 ④（目标轮10）：**对手行动可视化** —— 对手用了什么、落在哪。
##   提示条：主按钮左上的浮动提示（`_flash_msg`），让玩家一眼看到"对手在干什么"；
##   落点标记：复用 ③ 的 remote 选中通道（格高亮 + 该格单位卡标框）✓
## ⚠️ 人 2026-10-05（硬口径）：**文本提示条是错误做法** —— 占用额外 UI 空间、破坏原有布局 ✗。
##   ⇒ 一律改用**视觉方案**（复用既有渲染通道，**不新增任何 UI 空间** ✓）：
##     ① 对手**信息面板描边**（"对手正在操作"，由 side 决定哪块面板）
##     ② 目标**格高亮** ③ 目标**单位卡标框**（复用既有 set_selected / set_mark 通道）
##   文本仍 print 到控制台（便于诊断与验收），但**不占界面** ✓。
func _remote_panel(side: int) -> Control:
	if side == SIDE_ALLY:
		return get_node_or_null("Battle/PlayerBesaInfoRight") as Control
	return get_node_or_null("Battle/PlayerBesaInfoLift") as Control


func _flash_remote_panel(side: int) -> void:
	var panel := _remote_panel(side)
	if panel == null:
		return
	var mark := panel.get_node_or_null("RemoteMark") as Panel
	if mark == null:
		mark = Panel.new()
		mark.name = "RemoteMark"
		## ⚠️ 实测根因：`PlayerBesaInfo*` 是 **HBoxContainer** ⇒ 子节点会被容器重排（宽度归零 [0,99] ✗）。
		##   ⇒ 用 `top_level = true` 让描边**脱离父级布局**，再按面板的**全局矩形**显式定位 ✓（容器免疫 ✓）
		mark.top_level = true
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.z_index = 2
		panel.add_child(mark)
	var gr := panel.get_global_rect()
	mark.global_position = gr.position
	mark.size = gr.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(5)
	sb.border_color = Color(1, 0.72, 0.26, 1.0)   ## 暖橙：与本地选中（紫）/攻击（红）区分
	sb.set_corner_radius_all(14)
	mark.add_theme_stylebox_override("panel", sb)
	mark.modulate.a = 1.0
	mark.visible = true
	## 淡出（纯视觉、不常驻、不占位 ✓）
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(mark, "modulate:a", 0.0, 0.7)


## ⭐ ① 的视觉表达（人授权"都想办法提示" + 明确**禁用文本** ✗）：
##   对手**选中手牌**（无目标）⇒ 描**对手手牌区**（HandPanelLeft=敌方 / HandPanelRight=我方）
##   —— **零新增 UI 空间** ✓，且**无需改协议/信号**（复用现有 SIG_REMOTE_ACTION 的 cell 语义：
##   有目标/落点时 cell ≥ 0，纯选牌时 cell 为 (-1,-1) ✓）
func _flash_opponent_hand(side: int) -> void:
	var path := "Battle/HandPanelRight" if side == SIDE_ALLY else "Battle/HandPanelLeft"
	var panel := get_node_or_null(path) as Control
	if panel == null:
		return
	var mark := panel.get_node_or_null("RemoteHandMark") as Panel
	if mark == null:
		mark = Panel.new()
		mark.name = "RemoteHandMark"
		mark.top_level = true
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.z_index = 2
		panel.add_child(mark)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(4)
	sb.border_color = Color(0.55, 0.85, 1.0, 1.0)   ## 冷蓝：与"出牌/行动"的暖橙区分
	sb.set_corner_radius_all(12)
	mark.add_theme_stylebox_override("panel", sb)
	var gr := panel.get_global_rect()
	mark.global_position = gr.position
	mark.size = gr.size
	mark.modulate.a = 1.0
	mark.visible = true
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(mark, "modulate:a", 0.0, 0.6)


## ⭐ ① 修正（人 2026-10-05）：在**对手手牌区里标记具体那张卡**（不再描整片 HandPanel ✗），
##   且**常驻**（不做 Tween 淡出 ✗）。定位方式＝按**卡名**在对手手牌里找下标
##   （接收端持有对手手牌 ✓ ⇒ 无需改协议 ✓）。清除时机：text 无卡名（对端取消选中）✓
func _mark_opponent_hand(side: int, text: String) -> void:
	var container: Control = _hand_r if side == SIDE_ALLY else _hand_l
	if container == null:
		return
	for ch in container.get_children():
		var old := ch.get_node_or_null("RemoteHandMark") as Panel
		if old != null:
			## ⚠️ 人 2026-10-05 反馈"两个甚至三个以上手牌被同时选中"：根因是这里用了 `queue_free()`
			##   （**延迟释放** ✗）⇒ 连续多个 `sel` 到达时旧标记仍挂在树上 ⇒ 多个同时可见 ⟹ 改 `free()` 立即释放 ✓
			old.free()
	if text == "" or engine == null or engine.state == null:
		return
	var nm := text.replace("选中手牌 ", "")
	var hand: Array = engine.state.sides[side]["hand"]
	var idx := -1
	for i in hand.size():
		if String(hand[i].display_name) == nm:
			idx = i
			break
	if idx < 0 or idx >= container.get_child_count():
		return
	var card := container.get_child(idx) as Control
	if card == null:
		return
	var mk := Panel.new()
	mk.name = "RemoteHandMark"
	mk.top_level = true
	mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mk.z_index = 3
	card.add_child(mk)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(4)
	sb.border_color = Color(0.55, 0.85, 1.0, 1.0)   ## 冷蓝：与"出牌/行动"的暖橙区分
	sb.set_corner_radius_all(10)
	mk.add_theme_stylebox_override("panel", sb)
	var gr := card.get_global_rect()
	mk.global_position = gr.position
	mk.size = gr.size


## 对手动作：**视觉方案**（描边 + 目标标记）—— 不做文本条 ✗
##   ⭐ 按 cell 语义分流：cell.x < 0 ⇒ **具体手牌**（①：标那张牌、常驻）；cell ≥ 0 ⇒ 行动+落点（标具体对象 ✓）
func _on_remote_action(side: int, text: String, cell: Vector2i) -> void:
	print("[REMOTE] ", text)
	if cell.x < 0:
		_mark_opponent_hand(side, text)
	else:
		## ⭐ 人 2026-10-05 反馈修复：**选的是单位/移动/攻击/指令等"非选牌"目标时，必须清掉手牌选中标记**
		##   —— 否则此前的手牌标记会一直残留（多个同时选中 ✗，正是"选中其他目标了对手却看到多个手牌被选中"）
		_mark_opponent_hand(side, "")
		## ⭐ ⑤ 修正（人 2026-10-05）：**不得围绕"玩家基本信息框"** ✗ ⇒ 只标具体对象 ✓
		_on_remote_select(side, cell)
		## ⭐ ③ 修正（人 2026-10-05）：对端**指令卡**（文本＝"选中手牌 <卡名>"）带**待确认格** ⇒
		##   本地**纯算出该卡在该中心格上的效果范围**并用既有样式渲染 ✓
		##   （此前只显示落点、不显示范围 ✗）；放在 _on_remote_select 之后 ⇒ 范围优先生效 ✓
		if text.begins_with("选中手牌 ") and engine != null and engine.state != null:
			var nm := text.replace("选中手牌 ", "")
			var hh: Array = engine.state.sides[side]["hand"]
			for i in hh.size():
				if String(hh[i].display_name) == nm:
					var rp: Resource = engine.remote_command_preview(i, cell)
					if rp != null:
						_preview = rp
						_preview_is_remote = true
						## ⭐ 迭代064 遗留③（人 2026-10-05）：登记这条**对端指令卡效果范围**挂在哪一格 ——
						##   对端一旦清掉待确认（`sel` 不带 cell / 换目标），`_on_remote_select` 会作废登记；
						##   这里补上"以格为键"的记忆，避免效果范围以幽灵形式留在对手屏幕上 ✗。
						_remote_command_cell = cell
						_render_preview()
					break
		else:
			## ⭐ 迭代064 遗留③（人 2026-10-05）：对端的"非选牌"动作（移动/攻击/支援…）不携带待确认格 ⇒
			##   作废上一条指令效果范围，否则它会在对手操作已推进后仍留在屏幕上 ✗。
			_remote_command_cell = Vector2i(-1, -1)


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
	## 地图机制文本（`MapData.description`）——⭐ 迭代064 B7（清单 UI-6）：**始终写入**
	##   （无文案则清空，避免换图后残留上一张的说明；此前只在非空时写）
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
		## ⭐ 迭代067（人 2026-10-10：详情区尺寸调整后立绘要跟着修）：
		##   原实现 `portrait.size = p.art_size`（**写死 300×300**）—— 而详情区重排后
		##   `DetailBlock` = 284×284、内框 `Artwork` = **274×274** ⇒ 立绘**溢出 26px 且贴左上角** ✗
		##   （实测：`Portrait size=(300,300)` / `Artwork (274,274)`）
		##   修法：**以父框实测尺寸为准铺满**（不写死），并保持宽高比居中 —— 区再改也不用回来改这里。
		## ⚠️ 2026-10-10 **二次修正**（人：「立绘还是偏右而不是居中」—— 实测定位到残留问题）：
		##   ① 定位要**相对父框原点**：`Portrait` 的父 `Artwork` 自身在 `(4,4)`，
		##      `Portrait.position=(0,0)` 是**相对 Artwork** 的 ⇒ 观感**偏左上 4px**
		##      （实测：框心 `(141,141)` / 立绘心 `(137,137)`）✗
		##   ② 场景里 `stretch_mode = 5` 是 **KEEP_ASPECT_COVERED（会裁切）** ⇒
		##      构图偏右的立绘右侧被切掉 ⇒ 观感"偏右"；改为 **KEEP_ASPECT_CENTERED（按比例居中、不裁）** ✓
		var frame := portrait.get_parent() as Control
		var fit: Vector2 = frame.size if frame != null else p.art_size
		portrait.size = fit if (fit.x > 1.0 and fit.y > 1.0) else p.art_size
		portrait.position = Vector2.ZERO
		## 垂直微调：**优先读 `Portrait` 节点上的 `metadata/art_offset_y`**（编辑器可改、可观察），
		## 回退 `DetailParams.art_offset_y`（默认 0）。⚠️ 不动比例、不改字号。
		var off_y: float = p.art_offset_y
		if portrait.has_meta("art_offset_y"):
			off_y = float(portrait.get_meta("art_offset_y"))
		portrait.position.y = off_y
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		## ⚠️ 不设 `label`/`clip`：立绘源图与框同量级时按比例居中即可
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
		## ⚠️ 人 2026-10-05：费用图标"疑似横向被压缩" —— 与立绘窗**同一类问题**：
		##   徽章贴图被硬拉进固定 `60×65` 矩形 ⇒ 宽高比被破坏 ✗。
		##   修法同立绘：宽取参数值，**高按贴图自身宽高比推导** ✓（参数仍是被尊重的"宽"基准）。
		## ⭐ 迭代067 追加（人 2026-10-10：「费用数字相对父节点过度靠下」）：
		##   实测徽章贴图 **91×101**（纵向比 **1.110**）⇒ 按上一行推导会把节点撑成 **60×66.6**，
		##   而节点自身是 **60×60** ⇒ 贴图被**纵向拉长**、六边形比设计稿更"高"
		##   ⇒ 数字虽在**节点内**居中（实测 ΔY=+1.0px），却相对这个**被拉长的六边形**显得靠下 ✗
		##   依据：策划案 §2.4「费用徽章标注区域 **100×100**」+ §2.7「费用/徽章**内描边 4px**」
		##   ⇒ 徽章本体是**正方形**，贴图应按比例**居中**而不是撑满。
		##   修法：节点保持参数给的**正方形**尺寸，贴图 `KEEP_ASPECT_CENTERED`（不再拉伸、不再改变节点高）。
		badge.size = p.badge_size
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var bv: Label = badge.get_node_or_null("Value")
		## ⚠️ 只在显式给正数时覆盖字号（人 2026-09-19：不要改字号）
		##    素材原值 48；之前这里覆盖成 26 → 变小
		if bv != null and int(p.badge_font_size) > 0:
			bv.add_theme_font_size_override("font_size", int(p.badge_font_size))
		## ⭐ 迭代067：与信息栏**共用同一套几何居中**（人反馈"对端数字过度靠下" ⇒ 两处统一，杜绝分叉）
		_center_badge_value_geometry(badge)
	var line: Panel = node.get_node_or_null("InnerLine")
	if line != null:
		line.size = p.inner_line_size
	var img: TextureRect = node.get_node_or_null("Artwork/ArtPlane/Image")
	if img != null and node.get("card_data") != null:
		var cd: CardData = node.get("card_data") as CardData
		var vis: CardVisual = cd.visual
		## ⭐ 迭代064 **回归修复 v2**（人 2026-10-05 指出"回退后的效果和按问题清单修改前不同…可能没有回到原始正确版本"）：
		##   以下逐字恢复**原始正确版本**（`254d42a~1`）：
		##     · 基准窗**固定 `Vector2(400, 454)`**（源图量级），**不是**贴图实际尺寸 —— UI-8 与 Stage1 都错在这里
		##     · 裁剪靠 **`ArtPlane.clip_contents = true`（UI 控件自带裁剪）**，不靠整图缩放
		##     · 偏移 = `p.final_art_offset(vis)`（兵蜂即"头部居中、多出部分裁掉"的原始构图）
		##   仅在此基础上加**清单要求的那一条**修正：蜂王/建筑/指令按参数表 `kind_art_scale` 缩到 **50%**
		##   并在裁剪窗内**居中**（原方案直接套用兵蜂参数 ⇒ 水平居中但垂直偏上、缩放系数过大 ✗）。
		var key := _hand_kind_key(cd)
		## ⚠️ 人 2026-10-05 实测"指令卡等部分卡：横向纵向压缩程度不同、整体偏瘦"的**真因**：
		##   `Image` 是 `TextureRect` 且**未设 `stretch_mode`**（默认＝拉伸填满控件）——
		##   贴图实际 **250×258** 被硬拉进 **400×454** 的窗：横向 400/250=1.60×、纵向 454/258=1.76×
		##   ⇒ **宽高比被破坏**，卡片内容看起来被压瘦 ✗。
		##   修法：窗高按**贴图自身宽高比**推导（基准宽仍取原始版本的 400，保持偏移语义不变）。
		var tsz: Vector2 = img.texture.get_size() if img.texture != null else Vector2(400, 454)
		var sz := Vector2(400, 400.0 * tsz.y / maxf(tsz.x, 1.0))
		var sc: Vector2 = p.art_scale_for_key(key, vis)
		var off: Vector2 = p.final_art_offset(vis)
		if p.should_center_key(key):
			var plane: Control = img.get_parent()
			var pw: Vector2 = Vector2(194, 196)
			if plane != null and plane.size.x > 4.0 and plane.size.y > 4.0:
				pw = plane.size
			var draw: Vector2 = Vector2(sz.x * sc.x, sz.y * sc.y)
			off = (pw - draw) * 0.5
		img.offset_left = off.x
		img.offset_top = off.y
		img.offset_right = off.x + sz.x
		img.offset_bottom = off.y + sz.y
		img.scale = sc


## 手牌卡种键（供 UI 参数查表）—— 参数类不得引用 `CardData`，故转换放在视图侧
func _hand_kind_key(cd: CardData) -> String:
	if cd == null:
		return ""
	match cd.kind:
		CardData.CardKind.QUEEN:
			return "queen"
		CardData.CardKind.BUILDING:
			return "building"
		CardData.CardKind.COMMAND, CardData.CardKind.COMMAND_X:
			return "order"
		CardData.CardKind.SOLDIER:
			return "unit"
		_:
			return ""


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


## 玩家信息面板的压暗口径（清单 21）：**我方** → 轮到自己正常 / 否则灰；**敌方** → 一律**变黑**
## ⚠️ 2026-10-10 **还原**（人明确：这条"不对称"是**联机两端变化规律不一致**，不是配色口径问题；
##   本机变化规律**正确**，对端"异常变暗后再叠加已有的规律"）。
##   我曾按"两侧应对称"改成统一 `INFO_DIM` —— **方向错了**，已在此逐字还原为原三态口径。
##   ⇒ 这条的正确动作是：**先保原规律，再查"为什么两端规律不一致"**（见 `浏览器/采集报告 §F 回合态`）。
func _info_tint(side: int) -> Color:
	if int(side) != my_seat:
		return Color(0.22, 0.22, 0.22, 1)
	if engine != null and engine.state != null and int(engine.state.active) == my_seat:
		return Color(1, 1, 1, 1)
	return Color(0.65, 0.65, 0.65, 1)


func _set_turn(side: int, round_no: int) -> void:
	## ⭐ 回合切换也刷新手牌亮/灰（人要求「轮换等情况下依然稳定显示是否可用」）
	##   与费用变化 / 手牌变化三条路径**互相幂等**（都只读当前 state），不会打架。
	refresh_hand_affordability()
	_refresh_zone_info(side, round_no)
	## ⭐ 迭代064 UI-21（清单 21 的后半：「玩家基本信息」同样分灰/黑）：
	## ⚠️ **修正（人 2026-10-05 实测：自己回合变灰、敌方不变黑 ⟹ 左右写反了）**：
	##   以本文件 `_on_cost_changed()` 的**既有正确口径**为准（迭代059 小修补已定）——
	##     `PlayerBesaInfoRight` = **我方 `SIDE_ALLY`**（与 `HandPanelRight`/`AllyHand_*` 同侧）
	##     `PlayerBesaInfoLift`  = **敌方 `SIDE_ENEMY`**（与 `HandPanelLeft`/`EnemyHand_*` 同侧）
	##   B2 的镜像只交换两者**位置**、不改变各自代表的阵营 ⇒ 压暗必须**按名字映射到阵营**。
	var lift := get_node_or_null("Battle/PlayerBesaInfoLift") as Control
	if lift != null:
		lift.modulate = _info_tint(SIDE_ENEMY)
	var right := get_node_or_null("Battle/PlayerBesaInfoRight") as Control
	if right != null:
		right.modulate = _info_tint(SIDE_ALLY)
	## 🧪 结构化时序日志（人 2026-10-10：「对端**异常变暗后再叠加**已有的规律」⇒ 需要时序证据）
	##   每行给出：用于计算的 `side`（事件带的行动方）· `my_seat` · 两侧最终 modulate。
	##   ⇒ 两端各发一份报告，比 §F 与这些 `[TURN]` 行即可看出"从哪一步开始不一致"。
	print("[TURN] set_turn(side=%d) · my_seat=%d · active=%s · 左(敌)=%s · 右(我)=%s" % [
		int(side), int(my_seat),
		str(engine.state.active) if (engine != null and engine.state != null) else "?",
		str(lift.modulate) if lift != null else "?",
		str(right.modulate) if right != null else "?"])


## ⭐ 迭代064 P-15（清单 **机制-7**「没有做完善的 手牌-备卡-墓地 轮换机制」）：
##   轮换规则本身按 a500 已完整（见 `修复记录` 逐条对照：使用→墓地 / 回合末补到 4 /
##   牌库空→墓地前 4 张洗回 / 丢弃按部署费 / 单位阵亡**直接删除**不入墓地），
##   但**玩家看不见「备卡」与「墓地」两个区** ⇒ 轮换成了黑箱。
##   故把三个区的数量并进回合信息行（**不改场景结构、不动字号**，纯文本口径）。
func _refresh_zone_info(side: int, round_no: int) -> void:
	var ti := $HUD/MatchInfo/TurnInfo as Label
	if ti == null or engine == null or engine.state == null:
		return
	var s: int = side
	var hand: Array = engine.state.sides[s]["hand"]
	var dk: Array = engine.state.sides[s]["deck"]
	var dis: Array = engine.state.sides[s]["discard"]
##   ⚠️ **三区计数暂不并入该行**（R17 曾尝试，已实测回退）：该面板宽约 230px，而
##   `"回合1--绿方 ｜ 手牌4 · 备卡4 · 墓地0"` 实测文本宽 **721px** —— 压缩成
##   `"回合1--绿方 ｜ 手4 备4 墓0"` **仍被面板截断**（截图两次实测）；而人 2026-09-19
##   硬约束「**不要改字号**」⇒ 既不能缩字号、也不宜硬撑面板。故**只保留原文案**，
##   函数与调用点仍在（一旦有布局位可直接启用）。详见 迭代064 P-15 修复记录。
	ti.text = "回合%d--%s" % [round_no, "绿方" if s == SIDE_ALLY else "红方"]


func _on_phase_started(side: int, phase: int, _round_no: int) -> void:
	## 阶段文本 + 操作提示（迭代058：可发现性 —— 告诉玩家\"现在能做什么\"）
	var names := {0: "回费", 1: "场地", 2: "部署", 3: "行动"}
	var tips := {
		0: "自动结算：己方单位回费 + 行动机会重置",
		1: "自动结算：场地效果作用于格子上的单位",
		2: "部署阶段：点手牌部署单位/使用指令，准备好后点右侧按钮进入行动阶段",
		3: "行动阶段：点自己的单位可移动/攻击/支援（每单位每回合 1 次行动）",
	}
	## ⚠️ 迭代064 B7（人 2026-09-27 清单 **UI-6**「UI 面板右下角的**信息显示面板显示的应该是地图机制信息**，
	##   而不是其他如回合阶段解释信息」）：此处**不再覆写** `SiteEffect` ——
	##   该标签已由 `_on_map_assets()` 填入 `ArenaAssets.map_desc`（＝ `MapData.description`，
	##   即地图机制；实测 6 张地图**都有**该文案，如「场地效果：第 3、9 回合玩家额外回复 4 点费用。」）。
	##   阶段提示按 **2026-09-19 既定裁决**（「橙色提示文本省略 → 需要时作为控制台输出存在」）走 `_flash_msg()`。
	_flash_msg("%s阶段（%s）｜%s" % [
		str(names.get(phase, "?")), "绿" if side == SIDE_ALLY else "红",
		str(tips.get(phase, ""))])
	## ⭐ 阶段切换也刷新手牌亮/灰（幂等；保证任何时刻显示都跟当前费用一致）
	refresh_hand_affordability()


func _on_cost_changed(side: int, cost: int, _delta: int) -> void:
	## ⚠️ 左右与阵营的对应（迭代059 小修补：原实现左右反了）
	##   左侧面板 `PlayerBesaInfoLift` = **敌方**（与 `HandPanelLeft`/`EnemyHand_*` 同侧）
	##   右侧面板 `PlayerBesaInfoRight` = **我方**（与 `HandPanelRight`/`AllyHand_*` 同侧）
	var node := $Battle/PlayerBesaInfoRight if side == SIDE_ALLY else $Battle/PlayerBesaInfoLift
	var lb: Label = node.get_node_or_null("BadgeImage/Value")
	if lb != null:
		lb.text = str(cost)
	## ⭐ 费用一变，双方手牌的亮/灰立刻按**费用口径**重算（幂等）
	refresh_hand_affordability()
	## ⚠️ 迭代064 B7（人 2026-09-27 清单 UI-20）：
	##   **回费飘字不再挂费用图标** —— 人明确「回费文本特效发生在费用图标上是错的（正确做法是
	##   **一个回费的单位就一个回费文本特效**，而且手牌等地方不该出现回费特效）」。
	##   本处原实现把飘字挂在**玩家信息面板的 `BadgeImage`** 上 → 属错位，**先移除**。
	##   ⏳ 正位（挂在**真正回费的那个单位**上）需引擎把单位一并传出：
	##      · 发射点 `battle_engine.gd:503`（`_resolve_support(side, unit, skill)` 里**确实持有 `unit`**）
	##      · 发射点 `:222`（`_do_recover` 是**侧级合计** `recover_gain(side)`，无单一单位）
	##      ⇒ 需规则层加参数或新信号（**T10，待授权**）—— 详见迭代064 修复记录 B7。
	##   ✅ **已解决（迭代064 B7 二批 · 人已授权动规则层）**：规则层新增 `SIG_REFUND`
	##      （只由"**持有施法单位的回费**"发出，发射点 `battle_engine.gd:503` `_resolve_support`）
	##      → 见下方 `_on_refund_gained()`：飘字落在**那只回费的单位**身上。
	##      ⚠️ **侧级回费不飘字** —— 回合回费（`_do_recover`）与丰饶场地效果（`rules_effects.gd`）
	##      都没有"某一个单位"，正是人说的"**一个回费的单位就一个回费文本特效**"。


## ⭐ 迭代064 B7（清单 UI-20）：**单位回费飘字** —— 落在真正回费的那只单位上
##   · 一次单位回费 = **一个**飘字（人明确"一个回费的单位就一个回费文本特效"）
##   · **手牌与费用图标处都不出现**回费特效（前者从未有过；后者已在上一批移除）
func _on_refund_gained(_side: int, unit: UnitInstance, amount: int) -> void:
	if unit == null or amount <= 0:
		return
	var card: Control = _unit_nodes.get(unit.instance_id, null)
	if card == null or not is_instance_valid(card):
		return
	_float_at(card, "+%d" % amount, COL_COST, amount)


func _on_hand_changed(side: int, hand: Array, playable: Array) -> void:
	_render_hand(side, hand, playable)


func _on_unit_spawned(inst: UnitInstance, cell: Vector2i) -> void:
	_spawn_unit(inst, cell)


func _on_unit_moved(inst: UnitInstance, _from: Vector2i, to: Vector2i) -> void:
	var n: Control = _unit_nodes.get(inst.instance_id, null)
	if n != null and is_instance_valid(n):
		n.position = _cell_pos(to)
		_play("移动落位", inst)


## ============================================================
##  迭代064 B1：效果 / 数值变化 → **只重绑该单位卡**（修 P-21 徽标残存）
##  人 2026-09-27 反馈「持有效果实际状态不实时更新，典型如金刚蜂王的装甲明明触发并消失了图标还残存」。
##  根因＝效果类信号无人订阅（见 `_connect_bus()` 尾部注释），三条信号都改由这里落地。
## ============================================================

## 重绑单个单位卡：现取 `_unit_view()` 现绑 → **与 `_update_unit()` 同源**，避免两处数据口径漂移；
## 缺节点（未出场/已移除）则跳过，不崩、也不整盘重绘。
func _rebind_unit(inst: UnitInstance) -> void:
	if inst == null:
		return
	var n: Control = _unit_nodes.get(inst.instance_id, null)
	if n == null or not is_instance_valid(n):
		return
	n.bind(_unit_view(inst, inst.cell))


## 效果被授予（发射点：`rules_effects.gd:67`）
func _on_effect_granted(inst: UnitInstance, _effect: EffectData, _source: String) -> void:
	_rebind_unit(inst)


## 效果到期 / 被消耗（发射点：`rules_effects.gd:39` / `:155` / `rules_combat.gd:137`
## —— **装甲抵挡一次攻击后正是从这里消失**，即人反馈的那条）
func _on_effect_expired(inst: UnitInstance, _effect: EffectData) -> void:
	_rebind_unit(inst)


## 单位数值/状态变化（发射点：`rules_effects.gd:64` / `:68` / `rules_combat.gd:139`）
func _on_unit_stats_changed(inst: UnitInstance) -> void:
	_rebind_unit(inst)


func _on_unit_damaged(inst: UnitInstance, dmg: int, hp_after: int, _src: String) -> void:
	_update_unit(inst, hp_after)
	_play("受伤闪红", inst)
	_shake(inst, dmg)
	_float_at(_unit_nodes.get(inst.instance_id, null), "-%d" % dmg, COL_DAMAGE, dmg)


func _on_unit_healed(inst: UnitInstance, amt: int, hp_after: int) -> void:
	_update_unit(inst, hp_after)
	_float_at(_unit_nodes.get(inst.instance_id, null), "+%d" % amt, COL_HEAL, amt)


func _on_unit_removed(inst: UnitInstance, _reason: String) -> void:
	## ⭐ 迭代064 遗留③（人 2026-10-05）：**这条单位正是当前远端预览的持有者 ⇒ 立即作废该预览**。
	##   根因：`_preview` 还挂着这条 PreviewData，而它下面 6 行就会因"取不到节点"而 `return` ⇒
	##   预览/高亮**永不重算** ⇒ 对手视角下"我方被选中单位的范围"在该单位死后一直残留（人反馈）。
	##   放在 `return` **之前**是有意的：被杀死的单位的卡节点可能已经不在了，但这道清理必须执行 ✓。
	if _remote_preview_id != "" and inst != null and _remote_preview_id == inst.instance_id:
		_remote_preview_id = ""
		_remote_command_cell = Vector2i(-1, -1)
		## ⚠️ 实测补漏（本探针 ③ 第一次跑出来）：光清 `_preview` 还不够 ——
		##   对端选中留在格上的**白框**是另一条通道（`board_cell.set_selected`），
		##   它由 `_render_preview()` 依据"该格仍被选中"重打 ⇒ 不一起清就会留下一个孤零零的选中框 ✗。
		if _remote_sel_cell.x >= 0 and _cells.has(_remote_sel_cell):
			_cells[_remote_sel_cell].set_selected(false)
		_remote_sel_cell = Vector2i(-1, -1)
		_preview = null
		_preview_is_remote = false
		_render_preview()
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


## ⭐ 迭代064 联机-1：**右键任意棋盘格 = 取消选中**（本地清 + 经 `sel` op 广播）
func _on_cell_right_clicked(_cell: Vector2i) -> void:
	if _ui_locked: return
	if intent != null:
		intent.request_clear_selection()


## ⭐ 迭代064 联机-1：**点地图外（未被任何控件消费的左键）= 取消选中**
##   依赖 `_unhandled_input` 的语义：HUD 与棋格的点击都被各自的 Control 吃掉 ⇒
##   只有真正"点在空处/地图外"的事件才会落到这里 —— 正合人说的"点地图外取消选中"。
func _unhandled_input(event: InputEvent) -> void:
	## ⚠️ 人 2026-10-05（实机定位）：「点地图外取消选中」此前**完全收不到事件** ——
	##   根因＝**全屏焦点控件在 GUI 阶段就把左键吃掉了**（实测该点 `gui_get_hovered_control()` 命中的是
	##   `Battle/Background/TextureRect`，而它只是背景美术 ✗）⇒ 事件根本到不了 `_unhandled_input`。
	##   修法见 `battle_ui_alpha.tscn`：全屏非交互层统一 `mouse_filter = 2`（IGNORE）。
	##   本函数保留为"真正点空处"的唯一语义入口（HUD/棋格的点击仍被各自 Control 消费 ✓）。
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if engine == null or engine.state == null or intent == null:
		return
	if int(engine.sel_kind) == 0:
		return                     ## 本来就没选中 ⇒ 不做无谓广播
	intent.request_clear_selection()


func _on_selection_changed(_kind: int, _id: String, preview: Resource, _units: Array) -> void:
	## ⚠️ 预览范围**由规则层算好装在 PreviewData 里** —— 视图只读不重算
	_preview = preview
	## ⭐ 迭代064 遗留③（人 2026-10-05）：**本地选中变化 ⇒ 这条预览归本地** ——
	##   显式清掉远端登记，否则「先看过对端选中、再选自己的单位」时残留的 `_preview_is_remote=true`
	##   会继续影响渲染分支（历史踩坑：`_render_preview` 曾用它一刀切跳过单位打标）。
	_preview_is_remote = false
	_remote_preview_id = ""
	_remote_command_cell = Vector2i(-1, -1)
	_render_preview()
	## ⭐ ③ 迭代064 遗留修复（目标轮8）：**把"本地选中"广播给对端**（`sel` op）。
	##   实测根因（双端真机定位）：`NetIntent.send_selection()` **全项目 0 处调用**（死代码 ✗）——
	##   接收侧（`apply_remote` → `SIG_REMOTE_SELECT` → `_on_remote_select`）完整，但**永远收不到东西** ⟹
	##   实机观感即"看不到对手选了什么" ✗。
	##   ⇒ 在此处（**本地**选中变化信号）发送：选中的是单位则发其格；否则发 null（= 取消广播）。
	##   ⚠️ 不会回环：对端收到的是 `SIG_REMOTE_SELECT`（另一条信号），**不会**再触发本函数 ✓
	##   ⚠️ 离线时 `send_selection` 内部已用 `is_online()` 直接返回 ⇒ 单机无副作用 ✓
	if intent != null:
		var sc := Vector2i(-1, -1)
		var hi := -1
		var nm := ""
		if engine != null:
			## ⭐ 人 2026-10-05：**事前提醒**（而非事后解释）—— 双步确认的**阶段1「待确认」**就要把目标格
			##   广播出去，让对手在"确认之前"就看到落点/范围 ✓（`command_cell` 即阶段1 挂上的中心格；
			##   支援的 `support_pending` 同理，走 `sel_unit` 分支）
			if engine.command_cell.x >= 0:
				sc = engine.command_cell
			elif engine.sel_unit != null:
				sc = engine.sel_unit.cell
			## ⭐ 新目标 ①：选中的是**手牌**时，把卡号与卡名一并广播
			##   （对手据此在提示中看到"选中手牌 <卡名>"；旧端忽略未知键 ⇒ 兼容 ✓）
			if int(engine.sel_kind) == 1 and int(engine.sel_hand_index) >= 0:
				var h: Array = engine.state.sides[engine.state.active]["hand"]
				if int(engine.sel_hand_index) < h.size():
					hi = int(engine.sel_hand_index)
					nm = String(h[hi].display_name)
		intent.send_selection(sc if sc.x >= 0 else null, hi, nm)


func _on_main_button(text: String, enabled: bool, _hint: String = "") -> void:
	## 提示由 `_on_phase_started` 统一负责（避免两个信号争抢同一标签）
	var b: Button = $HUD/ActionBar/MainButton
	if b != null:
		b.disabled = not enabled
		## §二之3 line 60：结束部署 / 结束行动 = 文本白
		b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	## ⭐ 人 2026-10-05：「非己方回合内主按钮的文本改为等待，来到自己的回合时重新变回常态」——
	##   ⚠️ 实测：**主按钮本体 caption 为空（""）**，玩家看到的"完成部署/结束回合"是它右侧的 **Label** ✓
	##   ⇒ 换文案要换 Label：非我方回合显示「等待」，轮到我方时用引擎给的常态文案（text 参数）✓
	var lbl := $HUD/ActionBar/Label as Label
	if lbl != null:
		var my_turn: bool = engine != null and engine.state != null and int(engine.state.active) == my_seat
		lbl.text = text if my_turn else "等待"


func _on_log(text: String, level: int) -> void:
	print("[BATTLE]", "[WARN]" if level > 0 else "", " ", text)
	## 失败/拦截原因**直接回显到 HUD**（迭代058 G4）—— 引擎已写好原因文案
	if level > 0:
		_flash_msg("⚠ " + text)


func _on_battle_ended(result: int, reason: String) -> void:
	var who := {0: "", 1: "绿方胜", 2: "红方胜", 3: "平局"}
	$HUD/ActionBar/Label.text = "%s（%s）" % [str(who.get(result, "?")), reason]
	$HUD/ActionBar/MainButton.disabled = true
	_show_result(result, reason)
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
			## ⭐ 迭代064 联机-1（清单「点地图外取消选中在联机下无反应」）：**右键 = 取消选中**
			##   走 `intent.request_clear_selection()` ⇒ 本地清 + 引擎发 `SIG_SELECTION`
			##   ⇒ 视图据此经 `sel` op 广播 ⇒ 对端的"对手选中"紫框同步清除（两端一致）。
			if node.has_signal("cell_right_clicked") \
					and not node.cell_right_clicked.is_connected(_on_cell_right_clicked):
				node.cell_right_clicked.connect(_on_cell_right_clicked)
			_cells[c] = node


## 联机「棋盘镜像」（边界 T7）：seat≠0 的玩家把整块棋盘旋转 180° 呈现
## 做法＝**旋转容器**（MapView 绕棋盘中心）→ 底图 / 格 / 单位 / FX 一次性全部对齐；
## ⚠️ 数据仍是**规范 cell**（格节点保存规范 cell、点击回报规范 cell）→ 两端引擎状态天然一致
var my_seat: int = 0
## ⭐ 人 2026-10-05：「非己方回合内主按钮文本改为等待，来到自己的回合时重新变回常态」
##   —— 记下"常态文案"（完成部署/结束回合），非我方回合显示「等待」，轮到我方时还原 ✓
var _btn_text_normal := ""
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
	_place_hud(BoardMirror.needs_mirror(my_seat))
	print("[NET] 棋盘镜像 seat=%d（需镜像=%s）" % [my_seat, str(BoardMirror.needs_mirror(my_seat))])


## ⭐ 迭代064 B2：**HUD 也要跟着座位换边**（人 2026-09-27 清单 **UI-13**「自己的手牌无论如何都应该默认在玩家视图的右边」
##   与 **UI-14**「手牌区域、玩家信息等基本 UI 在联机中都应该对齐默认绿方/玩家自己的视角」）
##
## 现状与根因：面板的**静态映射**是 `HandPanelRight`/`PlayerBesaInfoRight` = 我方 `SIDE_ALLY`（绿），
##   `HandPanelLeft`/`PlayerBesaInfoLift` = 敌方 `SIDE_ENEMY`（红）—— **与 `my_seat` 无关**。
##   可联机里 seat=1 的玩家在引擎中就是 `SIDE_ENEMY` ⇒ 他的"自己"其实画在**左边**，
##   "自己的手牌在右手边"于是不成立（实测截图：seat=1 时红方手牌与信息仍钉在左侧）。
##   而 `set_my_seat()` 此前**只动 `Battle/MapView`**，完全没碰 HUD。
##
## 做法：**只把左右两组面板的 x 坐标对调**，内容映射一律不动 —— 最小改动、不必改任何索引语义。
##   ⚠️ 原始 x 用 `set_meta("home_x")` 缓存**一次** → 反复调用幂等，且 seat 切回 0 时能精确还原。
func _place_hud(mirror: bool) -> void:
	var pairs := [
		["Battle/HandPanelLeft", "Battle/HandPanelRight"],
		["Battle/PlayerBesaInfoLift", "Battle/PlayerBesaInfoRight"],
	]
	for p in pairs:
		var a := get_node_or_null(String(p[0])) as Control
		var b := get_node_or_null(String(p[1])) as Control
		if a == null or b == null:
			continue
		if not a.has_meta("home_x"):
			a.set_meta("home_x", a.position.x)
			b.set_meta("home_x", b.position.x)
		var ax := float(a.get_meta("home_x"))
		var bx := float(b.get_meta("home_x"))
		a.position.x = bx if mirror else ax
		b.position.x = ax if mirror else bx


func _cell_pos(cell: Vector2i) -> Vector2:
	## ⚠️ 沿用项目坐标约定：cell.x = 行、cell.y = 列（**规范坐标**，不随镜像变化）
	return Vector2(cell.y * PITCH, cell.x * PITCH)


## 点格 → 翻译成引擎请求（**不在视图里做规则判定**：种类看预览资源给的 kind）
func _on_cell_clicked(cell: Vector2i) -> void:
	if _ui_locked: return   ## 规则4：block_ui 动画期间禁交互
	if engine == null or engine.state == null:
		return
	## ⭐ 迭代064 联机-2（清单「可以操控对方的回合」）：**不是自己回合就不接受棋盘操作**
	##   （落子 / 移动 / 攻击 / 指令目标）。引擎的 `_can_act_with()` 最终也会拒，但视图先别"邀请"
	##   —— 否则玩家会看到范围高亮、点下去却毫无反应，观感即"能操控对方回合"。
	if int(engine.state.active) != my_seat:
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
			## ⭐ 迭代064 P-19（清单 机制-4）：**AOE 卡改走"以格为中心"** —— 空地也能放；
			##   阶段1 只挂待确认（引擎返回 false ⇒ 不发 op），预览随即显示**效果范围**，按钮变「确认」。
			var hcard: CardData = null
			var hh: Array = engine.state.sides[side]["hand"]
			if engine.sel_hand_index >= 0 and engine.sel_hand_index < hh.size():
				hcard = hh[engine.sel_hand_index]
			if hcard is CommandData:
				intent.request_use_command_at(side, engine.sel_hand_index, cell)
			elif u == null or not intent.request_use_command(side, engine.sel_hand_index, u):
				_flash_msg("该单位不是该指令的合法目标")
		int(EngLib.HandMode.DISCARD):
			## ⭐ 弃牌 BUG 修复：弃牌态点"手牌区以外任意处" ⇒ **执行弃牌** ✓
			##   （此前 `_execute_hand_on_cell` 无 DISCARD 分支、且 `hand_range_has_cell` 先把它挡掉 ✗）
			var dc: int = engine.discard_cost_of(engine.sel_hand_card) if engine.sel_hand_card != null else 0
			if not intent.request_discard(side, engine.sel_hand_index):
				_flash_msg("弃牌失败：需 %d 费，当前 %d" % [dc, engine.state.cost(side)])
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
		## ⭐ 迭代064 UI-21（清单 21「敌人回合自己的手牌和玩家基本信息是默认灰色不可选中…
		##   敌人手牌与基本信息直接变黑而不是变灰」）—— **以清单为准**（覆盖 2026-09-19
		##   「亮/灰只看费用、不看阶段、不看是否当前行动方」的旧裁决）。
		var my_turn0: bool = engine != null and int(engine.state.active) == my_seat
		if not my_turn0 or int(side) != my_seat:
			aff = false
		if hand_params != null:
			_apply_one_hand_params(node, hand_params)
		_call_opt(node, "set_playable", [aff, int(side) != my_seat])
	## ⭐ 每次渲染后都把子卡内部节点设为鼠标透明（**保留卡根节点可点**）
	##   （`_ready` 里那次跑在首次渲染之前 → 容器还是空的，等于没跑）
	_ignore_descendants(parent)
	## ⭐ 迭代064 P-15：**手牌变化也是三区数量的刷新时机** ——
	##   ⚠️ 不能只靠费用信号：部署代码是「先扣费并发 `SIG_COST_CHANGED`、**之后**才 `hand.remove_at`
	##   + 进墓地」⇒ 费用信号那一刻手牌还是旧数量（实测文本停在「手牌4·墓地0」）。
	##   手牌变化（`_emit_hand` → 本函数）才是"三区已定"的汇聚点。
	if engine != null and engine.state != null:
		_refresh_zone_info(int(engine.state.active), int(engine.state.round_no))


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
			## ⭐ 迭代064 UI-21（与 `_render_hand` 同一口径，**以清单为准**）：
			##   非本回合 / 非本方 → 一律不可用；**敌方手牌走 `dim_black`（变黑）**，本方不可用走灰。
			var my_turn1: bool = int(engine.state.active) == my_seat
			var aff1: bool = engine.hand_affordable(side, i) and my_turn1 and (int(side) == my_seat)
			_call_opt(node, "set_playable", [aff1, int(side) != my_seat])
	## ⭐ 迭代064 P-15：轮换三区数量一并刷新（**幂等**；与上面的亮/灰共用同一批刷新时机 ——
	##   费用变化 / 阶段变化 / 回合切换 / 卡入牌库墓地，四条路径都会到）
	if engine.state != null:
		_refresh_zone_info(int(engine.state.active), int(engine.state.round_no))


func _on_hand_clicked(card_id: String, side: int) -> void:
	if _ui_locked: return   ## 规则4：block_ui 动画期间禁交互
	if engine == null:
		return
	## ⭐ 迭代064 联机-2（清单 **联机-2**「可以操控对方的回合和手牌」）：**对手的手牌不可点**。
	##   HUD 同时显示双方手牌（左＝敌方 / 右＝我方）⇒ 不做这道门，玩家能直接点对手的牌去选中/部署
	##   （引擎最终会拒，但 UI 先"邀请"了 —— 正是人反馈的"操控对方手牌"）。
	## ⭐ 迭代064 遗留②（人 2026-10-05）：「选中手牌后**不能靠点击战斗地图之外的敌方手牌取消选中**」
	##   根因＝这道"对手手牌不可点"的权限门**直接 `return`、连"取消选中"都不做** ⇒ 手牌选中态卡死，
	##   只能靠点别的己方/敌方手牌或场地单位脱身 ✗。
	##   修法：对手手牌**仍然不可操作**（权限门不变），但这一下点击在语义上属于
	##   **「点击非交互区域」= 取消当前选中**（设计稿 §5.1「进入对象选择状态 → 点击不可交互区域取消选中」）✓。
	if side != my_seat:
		if int(engine.sel_kind) != 0:
			intent.request_clear_selection()
		return
	var idx: int = _hand_order[side].find(card_id)
	if idx < 0:
		return
	## 非行动方的手牌不可操作（本地双人热座：只有轮到的一方能动）
	if side != engine.state.active:
		_flash_msg("现在不是%s的回合" % ("绿方" if side == SIDE_ALLY else "红方"))
		return
	## ⭐ 弃牌 BUG 修复（人 2026-10-05）：处于**弃牌态**时，**点另一张手牌 = 对当前选中的那张执行弃牌** ✓
	##   （此前这里只会 `select_hand(idx)` ⇒ 只是换了个选中，永远弃不掉 ✗）；随后仍选中被点的这张 ✓
	if int(engine.hand_mode) == int(EngLib.HandMode.DISCARD) and int(engine.sel_hand_index) >= 0 \
			and int(engine.sel_hand_index) != idx:
		intent.request_discard(side, engine.sel_hand_index)
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
		## ⭐ 迭代064 UI-11：设计口径要求**蜂王左上角显示"每回合回费量"而非部署费用** ⇒ 一并下发
		"refund": inst.data.refund if inst.data != null else 0,
		## ⭐ 迭代064 UI-16：**是否已行动**（a500：使用主动攻击/支援后行动结束）—— 卡面据此做视觉差分。
		##   联机下两侧单位都读同一份引擎状态（对局经 op 回放保持同步）⇒ 对手单位的"行动过"同样看得出。
		"acted": inst.has_acted,
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
		## 持有效果（**只含运行态效果列表**；卡牌自带被动在 `UnitData.passives`，不在其中）
		"effects": _effect_badges(inst),
	}


## ============================================================
##  单位卡「持有效果徽标」数据装配（2026-09-24 · 迭代063 收尾）
## ============================================================

## 持有效果 → 徽标数据（供 `card_unit.gd` 渲染卡面小图标条）
## ⚠️ 数据源**只取 `inst.effects`**（运行态效果，经 `UnitInstance.apply_effect()` 进入）。
##    卡牌自带被动在 `UnitData.passives`（`unit_data.gd` 明确"不占用 T14 的效果槽、不入效果列表"），
##    **故不会**在卡面刷出一排"固有被动"徽标 —— 这里正是两者分界的落点。
## 图标来源优先级：① `EffectData.icon`（数据层显式设了就用它）
##                ② 按**显示名**回退 `assets/status_icons/<显示名>.png`（那 10 张图标正是按中文效果名命名）
##    ⇒ 规则实现即自动有图标，渲染层不必随效果种类增长而改（沿用迭代015 的 id→图标映射约定）。
func _effect_badges(inst: UnitInstance) -> Array:
	var out: Array = []
	if inst == null:
		return out
	for e in inst.effects:
		if e == null or e.data == null:
			continue
		out.append({
			"name": String(e.data.display_name),
			"icon": _effect_icon(e.data),
			"debuff": bool(e.data.is_debuff),
			"turns": int(e.turns),
		})
	return out


## 效果图标解析（带缓存；`null` 也缓存，避免每帧重复 `ResourceLoader.exists`）
func _effect_icon(d: EffectData) -> Texture2D:
	if d == null:
		return null
	if d.icon != null:
		return d.icon
	var nm := String(d.display_name)
	if nm == "":
		return null
	if _icon_cache.has(nm):
		return _icon_cache[nm] as Texture2D
	var tex: Texture2D = null
	var p := STATUS_ICON_DIR + nm + ".png"
	if ResourceLoader.exists(p):
		tex = load(p) as Texture2D
	_icon_cache[nm] = tex
	return tex


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
	## ⭐ 迭代064 联机-2：**不是自己回合就不接受单位操作**（同上 —— 别先邀请）
	if int(engine.state.active) != my_seat:
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
	## ⭐ 迭代064 UI-15：先把**对端选中**的格子记下来 —— 下面会清空所有格子的 selected，
	##   而对端选中**不属于预览**、不能被预览清掉（否则对手选中会一帧就被自己的预览刷没）。
	var rsel := Vector2i(-1, -1)
	for c in _cells.keys():
		if _cells[c].selected:
			rsel = c
			break
	for c in _cells.keys():
		_cells[c].set_highlight("")
		_cells[c].set_selected(false)
	## ⚠️ 卡上"标框"必须**每次先清**再按新预览重打 —— 否则预览消失（取消选中/操作结束）后标框残留。
	##   （迭代064 B4 实测踩到：只在 `_preview != null` 分支里打标、却没在开头清 → 清空后红框不退。）
	for k in _unit_nodes.keys():
		var un = _unit_nodes[k]
		if un != null and is_instance_valid(un) and un.has_method("set_mark"):
			## ⭐ 迭代064 UI-15：清标框时**顺带**把"对端选中"打在对应卡上。
			##   为什么必须打在卡上：单位卡正好 250×250（＝`PITCH`）会把**格子填充整片盖住** ——
			##   实测截图中"对手选中"在有单位的格上完全看不见（与 P-13 同一类坑）。
			##   为什么在**这里**打：放函数末尾会被上面的 `_preview == null: return` 跳过；
			##   放在预览打标之前则会被 preview 覆盖 —— 本循环是唯一"既清又打、且不会被跳过"的位置。
			##   （若该单位同时是我方预览的可攻击目标，预览的红橙标框会覆盖它 —— 可接受：攻击提示优先）
			var mark_kind := ""
			if rsel.x >= 0:
				var iu = _find_unit(String(k))
				if iu != null and iu.cell == rsel:
					mark_kind = "remote"
			un.set_mark(mark_kind)
	## ⭐ 迭代064 UI-15：重打对端选中标记（与本地预览互不干扰）
	if rsel.x >= 0 and _cells.has(rsel):
		_cells[rsel].set_selected(true)
	var style := {
		K.Kind.DEPLOY: "deploy",
		K.Kind.MOVE: "move",
		K.Kind.ATTACK: "attack",
		K.Kind.COMMAND: "attack",
		K.Kind.SUPPORT: "deploy",
	}
	## ⭐ 迭代064 B4（修 P-13 = 清单 UI-17）：**被占格的标记改画在"卡上"**
	##   原因：`PITCH = 250` 而单位卡正好 250×250 → 卡把自己那格**整片盖住**，
	##   格上的高亮在"有单位"的格上根本看不见，而攻击/支援目标恰恰都是有单位的格。
	##   这里按 `PreviewData.units`（受影响单位，见 `preview_data.gd:38`）给对应卡片打标；
	##   `kind → 样式` 复用下面同一张 `style` 映射表，**视图不额外判断规则**。
	if _preview == null:
		return
	var mark_kind := String(style.get(_preview.kind, ""))
	for pc in _preview.cells:
		if _cells.has(pc.cell):
			_cells[pc.cell].set_highlight(String(style.get(pc.kind, "")))
	## ⚠️ 人 2026-10-05：「在敌方单位上套红框（这个不需要额外显示）」 ✗
	##   AOE 指令卡要的是**效果范围**（格高亮），不是逐单位红框 ⇒ 选中的是 AOE 卡时**跳过单位打标**。
	var skip_unit_marks := false
	if engine != null and int(engine.sel_kind) == 1:
		var hc: CardData = null
		var hh: Array = engine.state.sides[engine.state.active]["hand"]
		if engine.sel_hand_index >= 0 and engine.sel_hand_index < hh.size():
			hc = hh[engine.sel_hand_index]
		if hc is CommandData and (hc as CommandData).aoe_span > 0:
			skip_unit_marks = true
	## ⭐ 迭代064 遗留①（**人 2026-10-05 口径：这一条是「应该」**）：远端预览**不再跳过单位打标** ——
	##   「敌方**应该**能够看到我方选中单位进入攻击状态后的攻击范围以及**选择的攻击目标**」——
	##   联机信息完全透明的主动设计 ⇒ 对端视图与本地视图渲染同一份 PreviewData（含目标标框）。
	##   旧条件里的 `not _preview_is_remote` 据人口径作废；"选指令卡时给对手单位套红框"仍由上面的
	##   AOE 跳过覆盖（那才是当时真正要挡的现象）。
	if not skip_unit_marks:
		for u in _preview.units:
			var un = _unit_nodes.get(u.instance_id, null)
			if un != null and is_instance_valid(un) and un.has_method("set_mark"):
				un.set_mark(mark_kind)


# ============================================================
#  详情区 + 工具
# ============================================================

func show_detail(data: CardData) -> void:
	if data == null:
		return
	$HUD/InfoPanel/CardName.text = data.display_name
	## ⚠️ 迭代064 B7（人 2026-09-27 清单 UI-5「**任何技能都不需要名字描述**」）：
	##   此处原先会把 `[glossary] skill_name` 拼成描述头（即"卡名下再挂一行技能名"）——**已移除**。
	##   理由：**描述正文自带类型前缀**（如「[被动]在敌方领地时，攻击造成[2]倍伤害」），
	##   再挂一行技能名纯属冗余。保留 `CardName` + `description` 两项即可。
	$HUD/InfoPanel/SkillDesc.text = data.description
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
	## ⭐ 迭代064 P-19（清单 机制-4「还应该有一个确定环节」）：待确认的**空地 AOE** →
	##   按钮「确认」= 再调一次同一入口 ⇒ 执行（`ok=true` ⇒ op 随 `command` 的 `target_cell` 发出）
	if engine.command_cell.x >= 0:
		## ⭐ ④ 修正（人 2026-10-05）：待确认的**单位行动**（移动/攻击）也要能从这里「确认」执行 ——
		##   与指令卡共用"待确认格"，按 `pending_action` 分流 ✓
		var pa := String(engine.pending_action)
		if pa == "move" and engine.sel_unit != null:
			intent.request_move(engine.state.active, engine.sel_unit, engine.command_cell)
		elif pa == "attack" and engine.sel_unit != null:
			var tgt: UnitInstance = engine.state.board.unit_at(engine.command_cell)
			if tgt != null:
				intent.request_attack(engine.state.active, engine.sel_unit, tgt)
		else:
			intent.request_use_command_at(engine.state.active, engine.sel_hand_index, engine.command_cell)
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
