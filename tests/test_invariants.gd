extends GutTest
## **属性测试：规则不变量**（迭代161 · 第三轮 S3 / WS3）
##
## 人 2026-10-23 批准：6 条不变量起步（生命值 / 费用非负 / 格唯一 / 行动位 /
##   状态单向推进 / 同 seed 可复现），失败自动留存 seed（qc/out/pbt-fail-<seed>.json）。
##
## ⚠️ 两条"踩过的坑"写在这里，避免以后又写错：
##   ① 不变量不能写成"阶段变化必伴随行动方/回合变化"——同回合 DEPLOY→ACTION 就是合法推进；
##   ② 不能直接比 StateHash.sha：CardPool.build() 每次重建卡 id（跨引擎实例天然不同），
##      要比较**结构投影**（不含 id）。

const Fixture := preload("res://tests/support/battle_fixture.gd")
const StateHash := preload("res://src/net/state_hash.gd")

const STEPS := 40
const SEEDS := [1, 2, 3, 7, 11, 13, 17, 23, 42, 99]


## 结构投影（无 id）：同一 seed 的操作序列可复现的判定依据
func _projection(e) -> String:
	var head := "r%d/a%d/ph%d/c%d-%d" % [e.state.round_no, int(e.state.active),
		int(e.state.phase), e.state.cost(0), e.state.cost(1)]
	var rows: Array[String] = []
	for u in e.state.board.all_units():
		if u == null:
			continue
		rows.append("%d@%d,%d/hp%d/mv%d/ac%d" % [int(u.side), u.cell.x, u.cell.y,
			int(u.current_hp), 1 if u.has_moved else 0, 1 if u.has_acted else 0])
	rows.sort()
	return head + "|" + ",".join(rows)


## 返回违规描述；空串 = 6 条不变量全过（return 控制在 6 个以内，符合 max-returns）
func _violation(e, seen_flags: Dictionary, prev_key: Vector3i) -> String:
	## ① 生命值：0 ≤ current_hp ≤ max（data.hp）
	for u in e.state.board.all_units():
		if u == null:
			continue
		var max_hp: int = int(u.data.hp) if u.data != null else u.current_hp
		if u.current_hp < 0 or u.current_hp > max_hp:
			return "① 生命值越界：%s hp=%d max=%d" % [u.instance_id, u.current_hp, max_hp]
	## ② 费用非负
	for side in [0, 1]:
		if e.state.cost(side) < 0:
			return "② 费用为负：side=%d cost=%d" % [side, e.state.cost(side)]
	## ③ 每格至多一个单位 + ④ 同回合内行动位不得被清回
	var cells := {}
	for u in e.state.board.all_units():
		if u == null:
			continue
		if cells.has(u.cell):
			return "③ 同格两单位：%s" % str(u.cell)
		cells[u.cell] = true
		var key: String = String(u.instance_id)
		var now := Vector2i(1 if u.has_moved else 0, 1 if u.has_acted else 0)
		if seen_flags.has(key):
			var old: Vector2i = seen_flags[key]
			var same_turn: bool = (e.state.round_no == prev_key.x) and (int(e.state.active) == prev_key.y)
			if same_turn and (now.x < old.x or now.y < old.y):
				return "④ 行动位被清回：%s %s -> %s" % [key, str(old), str(now)]
		seen_flags[key] = now
	## ⑤ 状态单向推进：(round, active, phase) 字典序不得倒退
	var now_key := Vector3i(e.state.round_no, int(e.state.active), int(e.state.phase))
	if now_key < prev_key:
		return "⑤ 状态倒退：%s -> %s" % [str(prev_key), str(now_key)]
	return ""


func _run(seed: int, steps: int, plant_bug: bool = false) -> Dictionary:
	var e = Fixture.new_engine()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hashes: Array[String] = []
	var projections: Array[String] = []
	var seen_flags := {}
	if plant_bug:
		var q = Fixture.queen(e, 0)
		if q != null:
			q.current_hp = -3   ## 故意植入的坏状态（验证检查器本身能红）
	for i in steps:
		var prev_key := Vector3i(e.state.round_no, int(e.state.active), int(e.state.phase))
		var act: int = int(e.state.active)
		var phase: int = int(e.state.phase)
		if phase == 2:   ## DEPLOY
			e.request_deploy(act, int(rng.randi_range(0, 2)),
				Vector2i(rng.randi_range(0, 3), rng.randi_range(0, 3)))
		elif phase == 3:   ## ACTION
			var units: Array = e.state.board.units_of(act)
			var pick := int(rng.randi_range(0, 2))
			if units.size() > 0 and pick < 2:
				var u = units[int(rng.randi_range(0, units.size() - 1))]
				if pick == 0:
					var foes: Array = []
					for o in e.state.board.all_units():
						if o != null and int(o.side) != act and o.is_alive():
							foes.append(o)
					if foes.size() > 0:
						var f = foes[int(rng.randi_range(0, foes.size() - 1))]
						e.request_attack(act, u, f)
						e.request_attack(act, u, f)   ## 双步骤：第二次才结算
				else:
					var dst := Vector2i(rng.randi_range(0, 3), rng.randi_range(0, 3))
					e.request_move(act, u, dst)
					e.request_move(act, u, dst)   ## 双步骤
			else:
				e.request_end_phase(act)
		else:
			e.request_end_phase(act)
		var v := _violation(e, seen_flags, prev_key)
		if v != "":
			return {"ok": false, "msg": v, "seed": seed, "step": i}
		hashes.append(StateHash.sha(e.state))
		projections.append(_projection(e))
	return {"ok": true, "msg": "", "seed": seed, "hashes": hashes, "projections": projections}


func test_all_invariants_hold_across_random_games() -> void:
	var ran := 0
	for seed in SEEDS:
		var r := _run(int(seed), STEPS)
		ran += 1
		if not r["ok"]:
			var f := FileAccess.open("res://qc/out/pbt-fail-%d.json" % int(seed), FileAccess.WRITE)
			if f != null:
				f.store_string(JSON.stringify(r, "\t"))
				f.close()
			var msg := "不变量被破坏（seed=%d step=%s）：%s —— 复现：qc/out/pbt-fail-%d.json"
			assert_true(r["ok"], msg % [int(seed), str(r.get("step", -1)), r["msg"], int(seed)])
	## 断言"真的跑了"（否则全绿时本用例零断言 = 空测试）
	assert_eq(ran, SEEDS.size(), "应跑完所有 seed（%d 个）" % SEEDS.size())


func test_same_seed_yields_same_projection_sequence() -> void:
	var a := _run(1234, 25)
	var b := _run(1234, 25)
	assert_true(bool(a["ok"]), "第一轮应通过不变量：%s" % str(a.get("msg", "")))
	assert_true(bool(b["ok"]), "第二轮应通过不变量：%s" % str(b.get("msg", "")))
	if not (bool(a["ok"]) and bool(b["ok"])):
		return
	assert_eq(a["projections"], b["projections"], "同一 seed ⇒ 结构投影序列必须一致（卡 id 每引擎重建，不计入）")


func test_invariant_checker_itself_can_red() -> void:
	## 检查器自检：故意植入 hp=-3，必须被 ① 抓住（否则不变量是空的）
	var r := _run(7, 2, true)
	assert_false(bool(r["ok"]), "植入坏状态后检查器必须判红")
	assert_true(String(r["msg"]).begins_with("①"), "应命中生命值不变量：%s" % r["msg"])
