extends Node
## 迭代061 检查点2 自检：中继客户端层 + 确定性（**全部可在本地验证**）
## ---------------------------------------------------------------------------
## 覆盖：
##   ① profile 加载与 URL 组装（test/prod 只换参数；生产档为 wss）
##   ② 确定性：同一 seed → 初始状态 hash 相同；不同 seed → 不同（防假阳性）
##   ③ 确定性：同一操作序列重放 → hash 仍相同
##   ④ 棋盘镜像自检（对合 / 180° / 领地对调）
##   ⑤ 网络（需本地中继在跑）：版本不匹配拒绝 · 握手/建房/加入/开局 · op 往返深等 ·
##      消息白名单（无状态下发）· 只传操作计数 · 掉线 peer_left{ended}
## 运行：先 `npm run start:test`（端口见 `net_config/net.test.json`），再 F6 本场景
## ⚠️ GDScript 闭包**按值捕获** → 所有断言状态用**成员变量**，不能在 lambda 里写局部变量
## ---------------------------------------------------------------------------
const EngineLib := preload("res://scripts/battle/battle_engine.gd")
const ConfigLib := preload("res://scripts/battle/battle_config.gd")
const DECK := "res://game_data/decks/示范卡组.tres"

var _pass := 0
var _fail := 0
var _url := ""
var _seed := 20260921

# 网络断言状态（成员变量，供 lambda 写入）
var _a: RelayClient = null
var _b: RelayClient = null
var _bad: RelayClient = null
var _a_wel := false
var _b_wel := false
var _bad_code := ""
var _room_code := ""
var _a_seat := -9
var _b_seat := -9
var _a_joined := false
var _seed_a := -1
var _seed_b := -1
var _op_got = null
var _op_frame := -1
var _op_seat := -9
var _op_acked := false
var _left_ended := false
var _left_seat := -9


func _ready() -> void:
	print("=== 迭代061 检查点2 自检（客户端联机层 + 确定性）===")
	_env()
	_mirror()
	_determinism()
	await _network()
	print("=== 结果：%d PASS / %d FAIL ===" % [_pass, _fail])
	await get_tree().create_timer(0.4).timeout
	get_tree().quit(1 if _fail > 0 else 0)


func _chk(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  — " + detail) if detail != "" else ""])


# ---------------------------------------------------------------- ① 配置
func _env() -> void:
	var pname := NetConfig.default_profile()
	var cfg := NetConfig.load_profile(pname)
	_url = NetConfig.resolve_url(cfg)
	_chk(not cfg.is_empty(), "① profile 加载", "%s → %s" % [pname, _url])
	_chk(_url.begins_with("ws://") or _url.begins_with("wss://"), "① URL 组装", _url)
	var pc := NetConfig.load_profile("prod")
	var purl := NetConfig.resolve_url(pc)
	_chk(not pc.is_empty() and purl.begins_with("wss://"), "① 生产档可读且为 wss（参数切换演练的半）", purl)
	_chk(NetConfig.profiles().size() >= 2, "① 枚举到多套配置", str(NetConfig.profiles()))


# ---------------------------------------------------------------- ④ 镜像
func _mirror() -> void:
	var errs: Array[String] = BoardMirror.self_test()
	_chk(errs.is_empty(), "④ 棋盘镜像自检（对合/180°/领地对调）", "" if errs.is_empty() else str(errs))
	_chk(BoardMirror.to_view(Vector2i(0, 0), 0) == Vector2i(0, 0), "④ seat0 不镜像")
	_chk(BoardMirror.to_view(Vector2i(0, 0), 1) == Vector2i(3, 3), "④ seat1 镜像到对角")


# ---------------------------------------------------------------- ②③ 确定性
func _determinism() -> void:
	var deck = load(DECK)
	if deck == null:
		_chk(false, "② 卡组资源存在", DECK)
		return
	seed(_seed)
	var e1 = EngineLib.new()
	var ok1: bool = e1.start(ConfigLib.make(deck, deck))
	seed(_seed)
	var e2 = EngineLib.new()
	var ok2: bool = e2.start(ConfigLib.make(deck, deck))
	_chk(ok1 and ok2, "② 引擎能开局（同 seed 两次）", "start=%s/%s" % [ok1, ok2])
	var h1: String = StateHash.sha(e1.state)
	var h2: String = StateHash.sha(e2.state)
	_chk(h1 == h2, "② **同 seed → 初始状态 hash 相同**", h1.substr(0, 16))
	## 引擎**唯一的随机点＝牌库抽空时的 dk.shuffle()**（battle_engine.gd:279；**开局不洗牌**，牌序来自 .tres）
	## → 必须证明「洗牌受 seed 控制」，否则两端抽空牌库重洗后会发散（这正是服务器下发 seed 的用途）
	var s1: Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	var s2: Array = s1.duplicate()
	seed(_seed)
	s1.shuffle()
	seed(_seed)
	s2.shuffle()
	_chk(s1 == s2, "② 同 seed → 洗牌结果相同（两端重洗可控）", str(s1))
	var s3: Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	seed(_seed + 777)
	s3.shuffle()
	_chk(s3 != s1, "② 不同 seed → 洗牌不同（防假阳性）")
	## ③ 同一操作序列重放（先推进到部署阶段，再部署第一张手牌到己方领地空格）
	var guard := 0
	while e1.state.phase != BattleState.Phase.DEPLOY and guard < 4:
		e1.request_end_phase()
		e2.request_end_phase()
		guard += 1
	_chk(e1.state.phase == BattleState.Phase.DEPLOY and e2.state.phase == BattleState.Phase.DEPLOY,
		"③ 已推进到部署阶段", "phase=%d/%d" % [e1.state.phase, e2.state.phase])
	## 找一对 (手牌序号, 格) 让部署合法：**直接问引擎**（返回 false 无副作用；一旦成功该操作已执行）
	var picked := -1
	var picked_cell := Vector2i(-1, -1)
	var hand: Array = e1.state.hand(0)
	for i in range(hand.size()):
		for c in _own_cells(e1):
			if e1.request_deploy(0, i, c):
				picked = i
				picked_cell = c
				break
		if picked >= 0:
			break
	_chk(picked >= 0, "③ 找到合法部署（手牌序号 + 格）", "idx=%d cell=%s" % [picked, str(picked_cell)])
	if picked < 0:
		return
	var d2: bool = e2.request_deploy(0, picked, picked_cell)
	_chk(d2, "③ 同一部署在第二份引擎上也接受", str(d2))
	var h3: String = StateHash.sha(e1.state)
	var h4: String = StateHash.sha(e2.state)
	_chk(h3 == h4, "③ **同操作序列重放 → hash 仍相同**", h3.substr(0, 16))
	_chk(h3 != h1, "③ 操作确实改变了状态（防假阳性）")


func _first_own_cell(e) -> Vector2i:
	var cs: Array[Vector2i] = _own_cells(e)
	return cs[0] if cs.size() > 0 else Vector2i(-1, -1)


func _own_cells(e) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in 4:
		for y in 4:
			var c := Vector2i(x, y)
			if e.state.board.is_empty(c) and e.state.board.is_own_territory(c, 0):
				out.append(c)
	return out


# ---------------------------------------------------------------- ⑤ 网络
func _network() -> void:
	_a = RelayClient.new()
	_b = RelayClient.new()
	_bad = RelayClient.new()
	_bad.proto = NetCodec.PROTO + 98

	_bad.server_error.connect(func(code: String, _m: String) -> void: _bad_code = code)
	_a.welcomed.connect(func(_s: String, _p: int, _bd: String) -> void: _a_wel = true)
	_b.welcomed.connect(func(_s: String, _p: int, _bd: String) -> void: _b_wel = true)
	_a.room_state.connect(func(code: String, seat: int, _pl: Array) -> void:
		_room_code = code
		_a_seat = seat)
	_b.room_state.connect(func(_c: String, seat: int, _pl: Array) -> void: _b_seat = seat)
	_a.peer_joined.connect(func(_s: int, _n: String) -> void: _a_joined = true)
	_a.match_started.connect(func(sev: int, _f: int) -> void: _seed_a = sev)
	_b.match_started.connect(func(sev: int, _f: int) -> void: _seed_b = sev)
	_b.op_received.connect(func(seat: int, _s: int, frame: int, pl, _ss: int) -> void:
		_op_seat = seat
		_op_frame = frame
		_op_got = pl)
	_a.op_acked.connect(func(_s: int, _ss: int) -> void: _op_acked = true)
	_b.peer_left.connect(func(seat: int, _r: String, ended: bool) -> void:
		_left_seat = seat
		_left_ended = ended)

	_bad.start(_url, "godot-mismatch")
	_a.start(_url, "godot-A")
	_b.start(_url, "godot-B")
	await _wait(func() -> bool: return _a_wel and _b_wel and _bad_code != "", 8.0)
	_chk(_a_wel and _b_wel, "⑤ A/B 握手收到了 welcome")
	_chk(_bad_code == "VERSION_MISMATCH", "⑤ 版本不匹配被服务器拒绝", _bad_code)
	if not (_a_wel and _b_wel):
		_chk(false, "⑤ 中继未就绪，网络部分跳过（请先 npm run start:test）", _url)
		return

	_a.create_room()
	await _wait(func() -> bool: return _room_code != "", 5.0)
	_chk(_room_code.length() == 6 and _a_seat == 0, "⑤ 建房（6 位码 + seat=0）", "%s seat=%d" % [_room_code, _a_seat])

	_b.join_room(_room_code)
	await _wait(func() -> bool: return _b_seat == 1 and _a_joined, 5.0)
	_chk(_b_seat == 1 and _a_joined, "⑤ 加入（seat=1，房主收到 peer_joined）")

	_a.start_match()
	await _wait(func() -> bool: return _seed_a > 0 and _seed_b > 0, 5.0)
	_chk(_seed_a > 0 and _seed_a == _seed_b, "⑤ 双端收到同一 seed", "seed=%d" % _seed_a)

	var payload := {"k": "deploy", "card": "蜂巢", "cell": [2, 0], "n": {"深": [1, 2, {"x": true}]}}
	_a.send_op(1, payload)
	await _wait(func() -> bool: return _op_got != null and _op_acked, 5.0)
	_chk(_op_got != null and _deep_eq(_op_got, payload), "⑤ **op 往返深等**（编解码无损）")
	_chk(_op_frame == 1 and _op_seat == 0, "⑤ 帧号/座位透传", "frame=%d seat=%d" % [_op_frame, _op_seat])
	_chk(_a.unknown_msgs == 0 and _b.unknown_msgs == 0, "⑤ 无状态下发（消息类型全在协议白名单）",
		"unknown=%d/%d" % [_a.unknown_msgs, _b.unknown_msgs])
	_chk(_a.sent_ops == 1 and _b.recv_ops == 1, "⑤ 只传操作（op 计数 1/1）")

	_a.close()
	await _wait(func() -> bool: return _left_ended, 6.0)
	_chk(_left_ended and _left_seat == 0, "⑤ A 掉线 → B 收 peer_left{ended:true}（T7 掉线即结束）")
	_b.close()
	bad_close()
	print("  [统计] A: sent_ops=%d bytes=%d · B: recv_ops=%d bytes=%d" % [
		_a.sent_ops, _a.sent_bytes, _b.recv_ops, _b.recv_bytes])


func bad_close() -> void:
	if _bad != null and _bad.is_open():
		_bad.close()


func _wait(pred: Callable, timeout: float) -> void:
	var t := 0.0
	while t < timeout:
		if _a != null:
			_a.poll()
		if _b != null:
			_b.poll()
		if _bad != null:
			_bad.poll()
		if pred.call():
			return
		await get_tree().process_frame
		t += get_process_delta_time()


## 递归深等（忽略字典键顺序；**数值类型宽松** —— JSON 数字在 Godot 统一解码为 float）
func _deep_eq(x, y) -> bool:
	var nx: bool = typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT
	var ny: bool = typeof(y) == TYPE_INT or typeof(y) == TYPE_FLOAT
	if nx and ny:
		return float(x) == float(y)
	if typeof(x) != typeof(y):
		return false
	if x is Dictionary:
		var dx: Dictionary = x
		var dy: Dictionary = y
		if dx.size() != dy.size():
			return false
		for k in dx:
			if not dy.has(k) or not _deep_eq(dx[k], dy[k]):
				return false
		return true
	if x is Array:
		var ax: Array = x
		var ay: Array = y
		if ax.size() != ay.size():
			return false
		for i in ax.size():
			if not _deep_eq(ax[i], ay[i]):
				return false
		return true
	return x == y
