extends Node
## 迭代063 ②: **op 覆盖面专项自检**
## ---------------------------------------------------------------------------
## 目标（IDEA-024）：
##  ① 7 种 op 各至少一例：deploy · move · attack · command · support · discard · end_phase
##  ② payload 契约：键集合与 扩展-001 §三 一致 · 全谱无 instance_id · **未知 k 被拒且不改状态**
##  ③ 每步两端 StateHash 一致 · rejected/unsupported 均为 0
## 运行：先起本地中继（npm run start:test），再 F6 本场景
## ⚠️ GDScript 闭包按值捕获 → 断言/计数一律用**成员变量**
## ⚠️ 支援是**二次点击确认**（第一次返回 false）→ 脚本里连调两次
## ---------------------------------------------------------------------------
const EngineLib := preload("res://scripts/battle/battle_engine.gd")
const ConfigLib := preload("res://scripts/battle/battle_config.gd")
const DECK := "res://game_data/decks/示范卡组.tres"
const MAX_STEPS := 160

## payload 契约表（与 系统维护/网络联机/扩展-001 §三 同源）
const EXPECT := {
	"deploy": ["k", "hand_index", "cell"],
	"move": ["k", "from", "to"],
	"attack": ["k", "from", "to"],
	"command": ["k", "hand_index", "target_cell"],
	"support": ["k", "from", "skill_id", "target_cell"],
	"discard": ["k", "hand_index"],
	"end_phase": ["k"],
}

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
var _mismatch := 0
var _steps := 0
var _kinds := {}
var _bad_keys := 0
var _has_iid := false
var _unknown_before := 0
var _hash_before_unknown := ""
## 每阶段动作预算：贪心脚本会无限刷 move、回合永不交替（实测踩到）→ 少量动作后主动结束阶段
var _phase_key := ""
var _phase_actions := 0


func _ready() -> void:
	print("=== 迭代063 op 覆盖面专项自检（7 种 op + payload 契约）===")
	var prof := NetConfig.default_profile()
	var cfg := NetConfig.load_profile(prof)
	var url := NetConfig.resolve_url(cfg)
	_chk(url.begins_with("ws"), "① 目标 URL", url)
	_a = RelayClient.new()
	_b = RelayClient.new()
	_wire()
	_a.start(url, "ops-A")
	_b.start(url, "ops-B")
	await _wait_until(func() -> bool: return _wel_a and _wel_b, 12.0)
	_chk(_wel_a and _wel_b, "① 两端握手 welcome")
	if not (_wel_a and _wel_b):
		_chk(false, "① 中继未就绪 → 先 npm run start:test", url)
		_finish()
		return
	_a.match_queue()
	_b.match_queue()
	await _wait_until(func() -> bool: return _seat_a >= 0 and _seat_b >= 0 and _started_a and _started_b, 15.0)
	_chk(_seat_a == 0 and _seat_b == 1 and _code_a != "" and _code_a == _code_b, "① 配对与同房码", "%s seat %d/%d" % [_code_a, _seat_a, _seat_b])

	var deck = load(DECK)
	if deck == null:
		_chk(false, "① 卡组资源存在", DECK)
		_finish()
		return
	seed(_seed)
	_e1 = EngineLib.new()
	var ok1: bool = _e1.start(ConfigLib.make(deck, deck))
	seed(_seed)
	_e2 = EngineLib.new()
	var ok2: bool = _e2.start(ConfigLib.make(deck, deck))
	_chk(ok1 and ok2, "① 两端引擎都开局")
	_i1 = NetIntent.new(_e1, _a, 0)
	_i2 = NetIntent.new(_e2, _b, 1)
	_i1.reseed_each_op = true
	_i2.reseed_each_op = true
	_i1.reseed_value = _seed
	_i2.reseed_value = _seed

	while _steps < MAX_STEPS and not _e1.state.is_over():
		_i1.reseed_value = _seed + _steps
		_i2.reseed_value = _seed + _steps
		var side: int = int(_e1.state.active)
		var kind := ""
		if side == 0:
			kind = _step(_i1, _e1, 0)
		else:
			kind = _step(_i2, _e2, 1)
		if kind != "":
			_kinds[kind] = int(_kinds.get(kind, 0)) + 1
		_steps += 1
		await _barrier(side)
		if StateHash.sha(_e1.state) != StateHash.sha(_e2.state):
			_mismatch += 1
			print("    ! 第 %d 步分叉（kind=%s）" % [_steps, kind])
			break
	_chk(_mismatch == 0, "② 全程两端 hash 一致（%d 步）" % _steps)

	var missing: Array[String] = []
	for k in EXPECT.keys():
		if int(_kinds.get(k, 0)) == 0:
			missing.append(String(k))
	_chk(missing.is_empty(), "③ **7 种 op 全覆盖**", "%s%s" % [_kinds, " 缺：" + str(missing) if not missing.is_empty() else ""])

	for it in [_i1, _i2]:
		for p in it.sent_payloads:
			_check_payload(p)
	_chk(_bad_keys == 0, "④ 每种 op 的键集合与协议表一致", "不匹配 %d 条" % _bad_keys)
	_chk(not _has_iid, "④ **全谱 payload 无 instance_id**")
	_chk(_i1.rejected_remote == 0 and _i2.rejected_remote == 0, "④ 对端应用无拒绝", "%d/%d" % [_i1.rejected_remote, _i2.rejected_remote])

	_unknown_before = _i2.unsupported
	_hash_before_unknown = StateHash.sha(_e2.state)
	_a.send_op(9999, {"k": "definitely_not_an_op"})
	await _settle()
	_chk(_i2.unsupported == _unknown_before + 1, "⑤ 未知 op 被拒（计入 unsupported）", "%d → %d" % [_unknown_before, _i2.unsupported])
	_chk(StateHash.sha(_e2.state) == _hash_before_unknown, "⑤ 未知 op **未改动状态**")
	print("  [诊断] 手牌支援卡 / 单位支援技能：")
	for sd in [0, 1]:
		var h: Array = _e1.state.hand(sd)
		var names: Array = []
		for c in h:
			names.append("%s%s" % [String(c.display_name) if c != null else "?", "(支援)" if _has_support_skill(c) else ""])
		var usk: Array = []
		for u in _e1.state.units(sd):
			var s2 = _e1.find_support_skill(u) if _e1.has_method("find_support_skill") else null
			usk.append("%s→%s" % [u.card_name(), String(s2.display_name) if s2 != null else "无"])
		print("    side%d 手牌 %s · 单位支援 %s" % [sd, str(names), str(usk)])
	print("  [统计] 覆盖面 %s" % _kinds)
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
	_a.match_started.connect(func(sv: int, _fs: int) -> void:
		_seed = sv
		_started_a = true)
	_b.match_started.connect(func(_sv: int, _fs: int) -> void: _started_b = true)
	_a.op_received.connect(func(seat: int, _s: int, _f: int, payload, _ss: int) -> void:
		_scan(payload)
		_i1.apply_remote(seat, payload))
	_b.op_received.connect(func(seat: int, _s: int, _f: int, payload, _ss: int) -> void:
		_scan(payload)
		_i2.apply_remote(seat, payload))


func _scan(payload) -> void:
	if payload is Dictionary and (payload as Dictionary).has("instance_id"):
		_has_iid = true


func _check_payload(p) -> void:
	if not (p is Dictionary):
		_bad_keys += 1
		return
	var d: Dictionary = p
	var k := String(d.get("k", ""))
	if not EXPECT.has(k):
		_bad_keys += 1
		return
	var w: Array = (EXPECT[k] as Array).duplicate()
	var got: Array = d.keys()
	got.sort()
	w.sort()
	if got != w:
		_bad_keys += 1
		print("    ! 键集合不符 %s：期望 %s 实得 %s" % [k, str(w), str(got)])
	if d.has("instance_id"):
		_has_iid = true


func _has_support_skill(card) -> bool:
	if card == null:
		return false
	var sk = card.get("skills")
	if not (sk is Array):
		return false
	for s in sk:
		if s != null and int(s.kind) == int(SkillData.Kind.SUPPORT):
			return true
	return false


## 确定性脚本：优先**稀有 op**（指令/支援/弃牌）→ 部署（优选带支援技能的卡）→ 移动/攻击 → 结束阶段
func _step(it: NetIntent, e, side: int) -> String:
	var ph: int = int(e.state.phase)
	var key := "%d/%d/%d" % [int(e.state.round_no), ph, side]
	if key != _phase_key:
		_phase_key = key
		_phase_actions = 0
	if ph == 2:
		## 部署阶段：最多 2 次部署
		if _phase_actions < 2:
			var hand: Array = e.state.hand(side)
			var order: Array = []
			for i in range(hand.size()):
				if _has_support_skill(hand[i]):
					order.append(i)
			for i in range(hand.size()):
				if not order.has(i):
					order.append(i)
			for i in order:
				for x in 4:
					for y in 4:
						var c := Vector2i(x, y)
						if e.state.board.is_empty(c) and e.state.board.is_own_territory(c, side):
							if it.request_deploy(side, i, c):
								_phase_actions += 1
								return "deploy"
		it.request_end_phase()
		_phase_actions = 0
		return "end_phase"
	if ph == 3:
		## 行动阶段：最多 3 个动作
		if _phase_actions < 3:
			var hand2: Array = e.state.hand(side)
			for i in range(hand2.size()):
				if hand2[i] is CommandData:
					for v in e.state.units(1 - side):
						if it.request_use_command(side, i, v):
							_phase_actions += 1
							return "command"
			for u in e.state.units(side):
				var sk = e.find_support_skill(u) if e.has_method("find_support_skill") else null
				if sk != null:
					for f in e.state.units(side):
						it.request_support(side, u, sk, f)
						if it.request_support(side, u, sk, f):
							_phase_actions += 1
							return "support"
			for i2 in range(hand2.size()):
				if it.request_discard(side, i2):
					_phase_actions += 1
					return "discard"
			## ⚠️ 攻击放到最后，且**支援/弃牌覆盖到之前不打** —— 否则蜂王被打死、对局提前结束
			##    （实测：贪心攻击让对局 27 步就结束，support/discard 再无机会）
			var may_attack: bool = (int(_kinds.get("support", 0)) > 0 and int(_kinds.get("discard", 0)) > 0) or _steps > 100
			if may_attack:
				for u3 in e.state.units(side):
					for v2 in e.state.units(1 - side):
						if it.request_attack(side, u3, v2):
							_phase_actions += 1
							return "attack"
			for u2 in e.state.units(side):
				for x2 in 4:
					for y2 in 4:
						if it.request_move(side, u2, Vector2i(x2, y2)):
							_phase_actions += 1
							return "move"
		it.request_end_phase()
		_phase_actions = 0
		return "end_phase"
	it.request_end_phase()
	_phase_actions = 0
	return "end_phase"


func _barrier(acted_side: int) -> void:
	var t := 0.0
	while t < 6.0:
		_a.poll()
		_b.poll()
		var done := false
		if acted_side == 0:
			done = (_i2.applied_remote + _i2.rejected_remote + _i2.unsupported) >= _i1.sent_ops
		else:
			done = (_i1.applied_remote + _i1.rejected_remote + _i1.unsupported) >= _i2.sent_ops
		if done:
			await get_tree().process_frame
			_a.poll()
			_b.poll()
			return
		await get_tree().process_frame
		t += get_process_delta_time()


func _settle() -> void:
	for _i in 20:
		_a.poll()
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
