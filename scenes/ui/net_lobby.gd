extends Control
## 联机大厅（迭代062 · 人 2026-09-23 裁定：**只需「在线/对局人数 + 匹配按钮」**）
## 流程：连中继 → 显示 lobby 人数 → 点「开始匹配」入队 → 配对成功（matched + start）
##       → 写入 NetSession → 点「进入对局」切战斗场景
## 口径：本场景**不涉及规则**；人数统计来自服务器 lobby 广播（只含存在性，不含对局状态）
const SCENE_BATTLE := "res://scenes/ui/battle_scene.tscn"

var _client: RelayClient = null
var _url := ""
var _in_queue := false

@onready var _stats: Label = $VBox/Stats
@onready var _status: Label = $VBox/Status
@onready var _btn_match: Button = $VBox/MatchButton
@onready var _btn_enter: Button = $VBox/EnterButton
@onready var _addr: Label = $VBox/Addr


func _ready() -> void:
	var prof := NetConfig.default_profile()
	var cfg := NetConfig.load_profile(prof)
	_url = NetConfig.resolve_url(cfg)
	_addr.text = "%s（档位 %s）" % [_url, prof]
	_btn_enter.visible = false
	_btn_match.pressed.connect(_on_match_pressed)
	_btn_enter.pressed.connect(_on_enter_pressed)

	_client = RelayClient.new()
	_client.opened.connect(func() -> void: _set_state("已连接中继，等待握手…"))
	_client.welcomed.connect(func(_sid: String, _p: int, b: String) -> void: _set_state("已连接（服务器 build=%s）" % b))
	_client.lobby_stats.connect(func(online: int, waiting: int, playing: int) -> void:
		_stats.text = "在线 %d 人 · 匹配中 %d 人 · 对局中 %d 人" % [online, waiting, playing])
	_client.queued.connect(func(pos: int) -> void:
		_in_queue = true
		_btn_match.text = "取消匹配"
		_set_state("匹配中…（队列第 %d 位）" % pos))
	_client.unqueued.connect(func() -> void:
		_in_queue = false
		_btn_match.text = "开始匹配"
		_set_state("已取消匹配"))
	_client.matched.connect(func(code: String, seat: int, players: Array) -> void:
		_set_state("已匹配：房间 %s · 座位 %d · %d 人" % [code, seat, players.size()]))
	_client.match_started.connect(func(seed_value: int, first_side: int) -> void:
		NetSession.set_match(_url, _client.room_code, _client.seat, seed_value, first_side)
		_btn_enter.visible = true
		_set_state("对局已就绪（%s）→ 点「进入对局」" % NetSession.describe()))
	_client.server_error.connect(func(code: String, msg: String) -> void: _set_state("错误：%s %s" % [code, msg]))
	_client.closed.connect(func(c: int, r: String) -> void: _set_state("连接已关闭（%d %s）" % [c, r]))
	_client.start(_url, "godot-lobby")
	_set_state("正在连接 %s …" % _url)


func _process(_dt: float) -> void:
	if _client != null:
		_client.poll()


func _on_match_pressed() -> void:
	if _client == null or not _client.is_open():
		_set_state("尚未连接：%s" % _url)
		return
	if _in_queue:
		_client.cancel_queue()
	else:
		_client.match_queue()
		_set_state("正在入队…")


func _on_enter_pressed() -> void:
	get_tree().change_scene_to_file(SCENE_BATTLE)


func _set_state(s: String) -> void:
	if _status != null:
		_status.text = s
	print("[LOBBY] " + s)
