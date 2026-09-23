extends Node
## 迭代062 联机接入自检：**两客户端（同进程）+ 两台引擎**跑完整局
## ---------------------------------------------------------------------------
## ① 两客户端连中继 → 握手 welcome → 双方入队
## ② 服务器 matched + start（seed/first_side 由服务器定）
## ③ 各自 `seed(seed)` 后建引擎（对齐 061 确定性口径）→ NetIntent（client=各自客户端）
## ④ 按**确定性脚本**交替出招；每步后比对 StateHash（两端必须一致）
## ⑤ 收尾：终局 hash 一致 + op 统计 + payload 无 instance_id
## 运行：先起本地中继（`npm run start:test`，端口见 `net_config/net.test.json`），再 F6 本场景
## ⚠️ GDScript 闭包按值捕获 → 断言状态一律用**成员变量**
## ---------------------------------------------------------------------------
const EngineLib := preload("res://scripts/battle/battle_engine.gd")
const ConfigLib := preload("res://scripts/battle/battle_config.gd")
const DECK := "res://game_data/decks/示范卡组.tres"

var _pass := 0
var _fail := 0
var _a: RelayClient = null
var _b: RelayClient = null
var _e1 = null
var _e2 = null
var _i1: NetIntent = null
var _i2: NetIntent = null
var _wel_a := false
var _wel_b := false
var _started_a := false
var _started_b := false
var _code_a := ""
var _code_b := ""
var _seat_a := -9
var _seat_b := -9
var _seed := 0
var _first := 0
var _mismatch := 0
var _steps := 0
var _op_has_iid := false


func _ready() -> void:
	print("=== 迭代062 联机接入自检（两客户端 + 双引擎完整局）===")
	var prof := NetConfig.default_profile()
	var cfg := NetConfig.load_profile(prof)
	var url := NetConfig.resolve_url(cfg)
	_chk(url.begins_with("ws"), "① 目标 URL", url)
	_a = RelayClient.new()
	_b = RelayClient.new()
	_wire()
	_a.start(url, "flow-A")
	_b.start(url, "flow-B")

	await _wait_until(func() -> bool: return _wel_a and _wel_b, 12.0)
	_chk(_wel_a and _wel_b, "① 两端握手 welcome")
	if not (_wel_a and _wel_b):
		_chk(false, "① 中继未就绪 → 后续跳过（先 npm run start:test）", url)
		_finish()
		return
	_a.match_queue()
	_b.match_queue()
	await _wait_until(func() -> bool: return _seat_a >= 0 and _seat_b >= 0 and _started_a and _started_b, 15.0)
	_chk(_seat_a == 0 and _seat_b == 1, "② 配对座位 0 / 1", "%d/%d" % [_seat_a, _seat_b])
	_chk(_code_a != "" and _code_a == _code_b, "② 两端同房间码", _code_a)
	_chk(_started_a and _started_b and _seed > 0, "② 服务器下发 seed / first_side", "seed=%d 先手=%d" % [_seed, _first])

	var deck = load(DECK)
	if deck == null:
		_chk(false, "③ 卡组资源存在", DECK)
		_finish()
		return
	seed(_seed)
	_e1 = EngineLib.new()
	var ok1: bool = _e1.start(ConfigLib.make(deck, deck))
	seed(_seed)
	_e2 = EngineLib.new()
	var ok2: bool = _e2.start(ConfigLib.make(deck, deck))
	_chk(ok1 and ok2, "③ 两端引擎都开局", "%s/%s" % [ok1, ok2])
	_chk(StateHash.sha(_e1.state) == StateHash.sha(_e2.state), "③ 开局即同 hash", StateHash.sha(_e1.state).substr(0, 12))
	_i1 = NetIntent.new(_e1, _a, 0)
	_i2 = NetIntent.new(_e2, _b, 1)
	## ⚠️ 单进程双引擎**共用同一全局 RNG**，而引擎唯一随机点是重洗（dk.shuffle 走全局 RNG）
	##    → 自检开启确定性重播；**生产（两进程）不启用**（已审计：运行时全局 RNG 只被引擎使用）
	_i1.reseed_each_op = true
	_i2.reseed_each_op = true
	_i1.reseed_base = _seed
	_i2.reseed_base = _seed

	while _steps < 40 and not _e1.state.is_over():
		var side: int = int(_e1.state.active)
		if side == 0:
			_scripted(_i1, _e1, 0)
		else:
			_scripted(_i2, _e2, 1)
		_steps += 1
		await _barrier(side)
		var h1: String = StateHash.sha(_e1.state)
		var h2: String = StateHash.sha(_e2.state)
		if h1 != h2:
			_mismatch += 1
			print("    ! 第 %d 步分叉" % _steps)
			var seg1: Array = StateHash.of(_e1.state).split("|")
			var seg2: Array = StateHash.of(_e2.state).split("|")
			for i in range(maxi(seg1.size(), seg2.size())):
				var a: String = seg1[i] if i < seg1.size() else "-"
				var b: String = seg2[i] if i < seg2.size() else "-"
				if a != b:
					print("      [%d] e1=%s" % [i, a])
					print("      [%d] e2=%s" % [i, b])
			break
	_chk(_mismatch == 0, "④ 全程两端 hash 一致（%d 步）" % _steps)
	_chk(StateHash.sha(_e1.state) == StateHash.sha(_e2.state), "⑤ 终局两端 hash 一致", StateHash.sha(_e1.state).substr(0, 12))
	_chk(_steps > 0 and (_i1.sent_ops + _i2.sent_ops) > 0, "⑤ 确实发生了网络操作", "上行 %d + %d" % [_i1.sent_ops, _i2.sent_ops])
	_chk(_i1.unsupported == 0 and _i2.unsupported == 0, "⑤ 无无法映射的 op", "%d/%d" % [_i1.unsupported, _i2.unsupported])
	_chk(not _op_has_iid, "⑤ **payload 无 instance_id**（只传 side+cell）")
	print("  [状态] 回合=%d 阶段=%d 结果=%d" % [int(_e1.state.round_no), int(_e1.state.phase), int(_e1.state.result)])
	print("  [统计] %s | %s" % [_i1.stats_text(), _i2.stats_text()])
	_finish()


func _finish() -> void:
	if _a != null:
		_a.close()
	if _b != null:
		_b.close()
	print("=== 结果：%d PASS / %d FAIL ===" % [_pass, _fail])
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(1 if _fail > 0 else 0)


func _chk(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  — " + detail) if detail != "" else ""])


func _wire() -> void:
	_a.welcomed.connect(func(_s: String, _p: int, _bld: String) -> void: _wel_a = true)
	_b.welcomed.connect(func(_s: String, _p: int, _bld: String) -> void: _wel_b = true)
	_a.matched.connect(func(code: String, seat: int, _pl: Array) -> void:
		_code_a = code
		_seat_a = seat)
	_b.matched.connect(func(code: String, seat: int, _pl: Array) -> void:
		_code_b = code
		_seat_b = seat)
	_a.match_started.connect(func(sv: int, fs: int) -> void:
		_seed = sv
		_first = fs
		_started_a = true)
	_b.match_started.connect(func(_sv: int, _fs: int) -> void: _started_b = true)
	## 下行：A 收到 B 的 op → 应用到 e1；B 收到 A 的 op → 应用到 e2
	_a.op_received.connect(func(seat: int, _s: int, _f: int, payload, _ss: int) -> void:
		_scan_payload(payload)
		_i1.apply_remote(seat, payload))
	_b.op_received.connect(func(seat: int, _s: int, _f: int, payload, _ss: int) -> void:
		_scan_payload(payload)
		_i2.apply_remote(seat, payload))


func _scan_payload(payload) -> void:
	if payload is Dictionary and (payload as Dictionary).has("instance_id"):
		_op_has_iid = true


## 确定性脚本：优先部署；其次攻击；否则结束阶段（两端同源 → 可逐位比对）
func _scripted(it: NetIntent, e, side: int) -> void:
	var phase: int = int(e.state.phase)
	if phase == 2:
		for i in range(e.state.hand(side).size()):
			for x in 4:
				for y in 4:
					var c := Vector2i(x, y)
					if e.state.board.is_empty(c) and e.state.board.is_own_territory(c, side):
						if it.request_deploy(side, i, c):
							return
	if phase == 3:
		for u in e.state.units(side):
			for v in e.state.units(1 - side):
				if it.request_attack(side, u, v):
					return
	it.request_end_phase()


## 精确屏障：等**对端把本轮发出的 op 应用完**再比对
## ⚠️ 不能用固定帧数 —— 实测因此产生过「最后一步还在路上」的**假分叉**
func _barrier(acted_side: int) -> void:
	var t := 0.0
	while t < 6.0:
		_a.poll()
		_b.poll()
		var done := false
		if acted_side == 0:
			done = (_i2.applied_remote + _i2.rejected_remote) >= _i1.sent_ops
		else:
			done = (_i1.applied_remote + _i1.rejected_remote) >= _i2.sent_ops
		if done:
			await get_tree().process_frame
			_a.poll()
			_b.poll()
			return
		await get_tree().process_frame
		t += get_process_delta_time()


func _settle() -> void:
	for _i in 16:
		if _a != null:
			_a.poll()
		if _b != null:
			_b.poll()
		await get_tree().process_frame


func _wait_until(pred: Callable, timeout: float) -> void:
	var t := 0.0
	while t < timeout:
		_a.poll()
		_b.poll()
		if pred.call():
			return
		await get_tree().process_frame
		t += get_process_delta_time()
