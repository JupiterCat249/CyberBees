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


## ⭐ 迭代064 UI-15：**选中存在性广播**（**不是操作** —— 不改引擎状态、无需对端引擎执行）
##   op 铁律：**不带 instance_id** ⇒ 用**规范 cell** 传递；`cell == null` = 取消选中（空 cell）
##   与 `request_*` 的区别：不调引擎、不校验成败，只发一个"我在看哪一格"的存在性消息。
func send_selection(cell, hand_index: int = -1, card_name: String = "") -> void:
	if not is_online():
		return
	var p: Dictionary = {"k": "sel", "cell": [] if cell == null else _ch(cell)}
	## ⭐ 新目标 ①（对手"选中了哪张手牌"）：**可选字段** —— 旧端忽略未知键 ⇒ 协议向前兼容 ✓
	if hand_index >= 0:
		p["hi"] = hand_index
	if card_name != "":
		p["nm"] = card_name
	frame += 1
	sent_ops += 1
	sent_payloads.append(p.duplicate(true))
	client.send_op(frame, p)


## ⭐ 迭代064 P-19：**以格为中心的指令**（空地 AOE）—— 复用同一个 `k: "command"`，
##   只是把 `target_cell` 换成显式格（**不加协议字段**，对端据此复原中心）。
##   阶段1（挂待确认）返回 false ⇒ **不发 op**；阶段2（确认）返回 true ⇒ 发出 ✓
func request_use_command_at(side: int, hand_index: int, cell: Vector2i) -> bool:
	if engine == null:
		return false
	_reseed_now()
	var ok: bool = engine.request_use_command_at(side, hand_index, cell)
	if ok:
		frame += 1
		sent_ops += 1
		var payload: Dictionary = {"k": "command", "hand_index": hand_index, "target_cell": _ch(cell)}
		sent_payloads.append(payload.duplicate(true))
		if is_online():
			client.send_op(frame, payload)
	return ok


## ⭐ 迭代064 UI-15/联机-1：**取消选中**（本地 + 广播）。选中态是**视图/引擎的本地态**，
##   故清空后照常经 `SIG_SELECTION` 走一遍 → 视图的广播逻辑会自动把"空选中"发给对端。
func request_clear_selection() -> void:
	if engine != null:
		engine.request_clear_selection()


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
	## ⭐ 迭代064 联机-2：把 `my_side` 一并传出 ⇒ 引擎据此拒绝"不是我回合的结束阶段"
	return _do(my_side, "request_end_phase", [my_side], {"k": "end_phase"})


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
			## ⭐ 迭代064 ④（目标轮10）：**对手行动可视化** —— 在应用对端部署的同时播一条可读提示。
			##   ⚠️ 卡名必须在 `request_deploy` **之前**取：部署成功会把该牌移出手牌（下标即失效）✗
			var dcell := _cell(p.get("cell"))
			var dhi := int(p.get("hand_index", -1))
			var dname := "?"
			var dhand: Array = engine.state.sides[side]["hand"]
			if dhi >= 0 and dhi < dhand.size():
				dname = String(dhand[dhi].display_name)
			ok = engine.request_deploy(side, dhi, dcell)
			if ok:
				var dbus = engine.bus()
				dbus.emit_signal(dbus.SIG_REMOTE_ACTION, side, "部署 %s" % dname, dcell)
		"move":
			## ⭐ 新目标 ②：对手**移动**播报（复用 ④ 的 SIG_REMOTE_ACTION 通道 ⇒ 面板描边 + 目标格标记 ✓）
			var mv_u = _unit_at(p.get("from"))
			var mv_to := _cell(p.get("to"))
			var mv_nm := String(mv_u.card_name()) if mv_u != null else "单位"
			ok = engine.request_move(side, mv_u, mv_to)
			if ok:
				var mb = engine.bus()
				mb.emit_signal(mb.SIG_REMOTE_ACTION, side, "移动 %s" % mv_nm, mv_to)
		"attack":
			## ⭐ 新目标 ②：对手**攻击**播报（含攻击者名与目标格 ⇒ 视觉提示"谁打谁、打哪里"）
			var at_u = _unit_at(p.get("from"))
			var at_to := _cell(p.get("to"))
			var at_nm := String(at_u.card_name()) if at_u != null else "单位"
			ok = engine.request_attack(side, at_u, _unit_at(p.get("to")))
			if ok:
				var ab = engine.bus()
				ab.emit_signal(ab.SIG_REMOTE_ACTION, side, "攻击 %s" % at_nm, at_to)
		"command":
			## ⭐ 迭代064 P-19：**AOE（aoe_span > 0）走"以格为中心"入口，且必须连调两次** ——
			##   阶段1 只挂待确认并返回 false、阶段2 才执行（与支援同理；否则联机下 AOE 恒失败）。
			var hi := int(p.get("hand_index", -1))
			var u0 = _unit_at(p.get("target_cell"))
			var is_aoe := false
			if engine.state != null:
				var hh: Array = engine.state.sides[side]["hand"]
				if hi >= 0 and hi < hh.size() and hh[hi] is CommandData:
					is_aoe = (hh[hi] as CommandData).aoe_span > 0
			if is_aoe:
				var cc := _cell(p.get("target_cell"))
				engine.request_use_command_at(side, hi, cc)
				ok = engine.request_use_command_at(side, hi, cc)
			else:
				ok = engine.request_use_command(side, hi, u0)
		"support":
			var u = _unit_at(p.get("from"))
			var sk = _find_skill(u, String(p.get("skill_id", "")))
			if sk == null:
				unsupported += 1
				return false
			## ⚠️ 引擎支援是**二次点击确认**：第一次只挂 pending 并返回 false（battle_engine.gd:486）
			##    → 对端只收到最终 op、本地没有 pending → 必须**连调两次**才能执行
			##      （否则支援在联机下恒失败 —— 迭代063 全谱自检实测发现）
			engine.request_support(side, u, sk, _unit_at(p.get("target_cell")))
			ok = engine.request_support(side, u, sk, _unit_at(p.get("target_cell")))
			if ok:
				## ⭐ 新目标 ②：对手**支援/技能**播报（单位名 + 技能名 + 目标格 ⇒ 视觉提示 ✓）
				var sb = engine.bus()
				var sk_nm := String(sk.display_name) if sk != null else "技能"
				var su_nm := String(u.card_name()) if u != null else "单位"
				sb.emit_signal(sb.SIG_REMOTE_ACTION, side,
					"支援 %s·%s" % [su_nm, sk_nm], _cell(p.get("target_cell")))
		"discard":
			ok = engine.request_discard(side, int(p.get("hand_index", -1)))
		"end_phase":
			## ⭐ 迭代064 联机-2：把**发送方 seat** 传进去 ⇒ 引擎校验"结束阶段的到底是不是当前行动方"
			ok = engine.request_end_phase(side)
		"sel":
			## ⭐ 迭代064 UI-15：对端**选中存在性** —— **纯呈现**（不改引擎状态、不参与规则）
			##   经总线转给视图渲染"对手选中"标记；空 cell（`_cell([])` → (-1,-1)）表示对端已取消选中。
			##   ⚠️ 不参与 ok/拒绝 计数，直接返回（它没有"执行失败"这回事）。
			##   ⭐ 新目标 ①：若带 `nm`（对端**选中的是哪张手牌**）⇒ 再播一条动作提示（复用 ④ 的常驻条 ✓）
			var b = engine.bus()
			var scell := _cell(p.get("cell", []))
			b.emit_signal(b.SIG_REMOTE_SELECT, side, scell)
			var snm := String(p.get("nm", ""))
			## ⭐ ① 修正（人 2026-10-05）：**总是**播报 —— 无卡名（snm==""）＝对端**已取消选中手牌**
			##   ⇒ 视图据此**清除**那个常驻标记 ✓（否则标记会永远留着 ✗）
			b.emit_signal(b.SIG_REMOTE_ACTION, side, ("选中手牌 %s" % snm) if snm != "" else "", scell)
			applied_remote += 1
			return true
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
