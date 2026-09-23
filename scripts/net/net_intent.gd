class_name NetIntent
extends RefCounted
## 联机操作闸门（**唯一上行/下行转换点**）—— 迭代062
## ---------------------------------------------------------------------------
## 上行：视图调 `intent.request_*()`（与 `BattleEngine.request_*` **同名同签名**，便于整片替换）
##       → 先在本地引擎执行（失败不发）→ 成功则组 op 并经中继发出
## 下行：收到对端 op → `apply_remote(seat, payload)` → 映射回同样的引擎请求
## 铁律：**op 里绝不出现 `instance_id`**（随机 UUID，两端不同）→ 一律用**规范 cell** 反查单位
## 约定：**seat ↔ 引擎 side**（0=绿方 SIDE_ALLY · 1=红方 SIDE_ENEMY）
## ---------------------------------------------------------------------------
var engine = null                    ## BattleEngine
var client: RelayClient = null       ## null = 单机（纯本地）
var my_side: int = 0                 ## 本地玩家在引擎里的 side
var frame: int = 0                   ## 上行操作序号（递增，随 op 一起发出）
var sent_ops: int = 0
var applied_remote: int = 0
var rejected_remote: int = 0
var unsupported: int = 0             ## 收到但当前无法映射的 op
var sent_payloads: Array = []        ## 上行 op 留痕（供「只传操作 / 无 instance_id」举证）

## ⚠️ **仅供「单进程双引擎」自检**：两台引擎共用进程全局 RNG，而引擎唯一随机点是
##    牌库抽空重洗 `dk.shuffle()`（全局 RNG）→ 不重播会让两端重洗分叉（实测踩到）。
##    **生产不需要**：两进程各自 RNG，进程内全局 RNG 只被引擎使用 → 播种后自然同步
##    （已审计：运行时全局 RNG 消费者仅 battle_engine.gd:279；视图/动画的随机性已离线烤进 .tres）。
var reseed_each_op: bool = false
var reseed_value: int = 0
var _ops_by_sender := {0: 0, 1: 0}


func _init(p_engine = null, p_client: RelayClient = null, p_my_side: int = 0) -> void:
	engine = p_engine
	client = p_client
	my_side = p_my_side


func is_online() -> bool:
	return client != null and client.is_open()


## 自检用：每次引擎调用前套用**同一个重播值**（两端必须同步一致）
## ⚠️ 不能用「尝试次数」当索引：自检为找合法格会做大量**失败尝试**（不消耗 RNG，对端也看不到它）
func _reseed_now() -> void:
	if reseed_each_op:
		seed(reseed_value)


func _ch(cell: Vector2i) -> Array:
	return [cell.x, cell.y]


func _cell(v) -> Vector2i:
	if v is Array and v.size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i(-1, -1)


func _unit_at(v):
	var c := _cell(v)
	if c.x < 0 or engine == null or engine.state == null or engine.state.board == null:
		return null
	return engine.state.board.unit_at(c)


## 支援技能：优先用**引擎现成入口** `find_support_skill(unit)`
func _find_skill(unit, _skill_id: String):
	if unit == null or engine == null:
		return null
	if engine.has_method("find_support_skill"):
		var s = engine.find_support_skill(unit)
		if s != null:
			return s
	var holders: Array = [unit.get("data"), unit]
	for h in holders:
		if h == null:
			continue
		var sk = h.get("skills")
		if sk is Array:
			for s2 in sk:
				if s2 != null and String(s2.get("id")) == _skill_id:
					return s2
	return null


## 统一入口：本地执行（先确定性重播）→ 成功则上行
func _do(sender: int, method: String, args: Array, payload: Dictionary) -> bool:
	_reseed_now()
	var ok: bool = engine.callv(method, args)
	if ok:
		frame += 1
		sent_ops += 1
		sent_payloads.append(payload.duplicate(true))
		if is_online():
			client.send_op(frame, payload)
	return ok


# ============================ 上行（与引擎同名） ============================
func request_deploy(side: int, hand_index: int, cell: Vector2i) -> bool:
	return _do(my_side, "request_deploy", [side, hand_index, cell],
		{"k": "deploy", "hand_index": hand_index, "cell": _ch(cell)})


func request_move(side: int, unit, cell: Vector2i) -> bool:
	var from: Vector2i = unit.cell if unit != null else Vector2i(-1, -1)
	return _do(my_side, "request_move", [side, unit, cell],
		{"k": "move", "from": _ch(from), "to": _ch(cell)})


func request_attack(side: int, attacker, defender) -> bool:
	var a: Vector2i = attacker.cell if attacker != null else Vector2i(-1, -1)
	var d: Vector2i = defender.cell if defender != null else Vector2i(-1, -1)
	return _do(my_side, "request_attack", [side, attacker, defender],
		{"k": "attack", "from": _ch(a), "to": _ch(d)})


func request_use_command(side: int, hand_index: int, target) -> bool:
	var c: Vector2i = target.cell if target != null else Vector2i(-1, -1)
	return _do(my_side, "request_use_command", [side, hand_index, target],
		{"k": "command", "hand_index": hand_index, "target_cell": _ch(c)})


func request_support(side: int, unit, skill, target = null) -> bool:
	var from: Vector2i = unit.cell if unit != null else Vector2i(-1, -1)
	var sid := String(skill.id) if skill != null else ""
	return _do(my_side, "request_support", [side, unit, skill, target],
		{"k": "support", "from": _ch(from), "skill_id": sid,
		"target_cell": _ch(target.cell if target != null else from)})


func request_discard(side: int, hand_index: int) -> bool:
	return _do(my_side, "request_discard", [side, hand_index],
		{"k": "discard", "hand_index": hand_index})


func request_end_phase() -> bool:
	return _do(my_side, "request_end_phase", [], {"k": "end_phase"})


# ============================ 下行：应用对端 op ============================
func apply_remote(seat: int, payload) -> bool:
	if not (payload is Dictionary):
		return false
	var p: Dictionary = payload
	var side := int(seat)          ## 约定：seat ↔ 引擎 side
	_reseed_now()
	var ok := false
	match String(p.get("k", "")):
		"deploy":
			ok = engine.request_deploy(side, int(p.get("hand_index", -1)), _cell(p.get("cell")))
		"move":
			ok = engine.request_move(side, _unit_at(p.get("from")), _cell(p.get("to")))
		"attack":
			ok = engine.request_attack(side, _unit_at(p.get("from")), _unit_at(p.get("to")))
		"command":
			ok = engine.request_use_command(side, int(p.get("hand_index", -1)), _unit_at(p.get("target_cell")))
		"support":
			var u = _unit_at(p.get("from"))
			var sk = _find_skill(u, String(p.get("skill_id", "")))
			if sk == null:
				unsupported += 1
				return false
			ok = engine.request_support(side, u, sk, _unit_at(p.get("target_cell")))
		"discard":
			ok = engine.request_discard(side, int(p.get("hand_index", -1)))
		"end_phase":
			ok = engine.request_end_phase()
		_:
			unsupported += 1
			return false
	if ok:
		applied_remote += 1
	else:
		rejected_remote += 1
	return ok


func stats_text() -> String:
	return "上行 %d · 下行应用 %d · 拒绝 %d · 无法映射 %d" % [sent_ops, applied_remote, rejected_remote, unsupported]
