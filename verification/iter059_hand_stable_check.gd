extends Node
## 【验证用 · 非生产】迭代059：手牌亮/灰**稳定性**专项
## 人要求：「确保手牌在轮换等情况下依然能**稳定**显示是否可用（**只考虑部署费用**，其他不用考虑）」
##
## 不变式（任意状态下都必须成立）：
##   对每张手牌： modulate == 亮  ⟺  cost ≤ 该方当前费用  （X 费卡视为可负担）
##
## 用法：project_run(mode="custom", scene="res://verification/iter059_hand_stable_check.tscn")

const StateLib := preload("res://scripts/battle/battle_state.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _scene: Control = null


func _ready() -> void:
	print("\n===== 手牌亮/灰稳定性专项（只考虑部署费用）=====")
	_scene = (load("res://scenes/ui/battle_scene.tscn") as PackedScene).instantiate() as Control
	add_child(_scene)
	for _i in 12:
		await get_tree().process_frame
	var eng = _scene.get("engine")

	await _verify(eng, "开局（第1回合）")

	## 多次阶段推进 + 回合轮换，每一步都查不变式
	var guard := 0
	while guard < 10:
		guard += 1
		if eng.state.phase == StateLib.Phase.DEPLOY or eng.state.phase == StateLib.Phase.ACTION:
			eng.request_end_phase()
		await _tick(3)
		await _verify(eng, "推进#%d（active=%d phase=%d）" % [guard, eng.state.active, eng.state.phase])
		if guard >= 6:
			break

	## 幂等校验：连羽刷新 5 次，结果必须与只刷一次完全一致
	print("\n--- 幂等校验（连续刷新 5 次）---")
	var before := _snapshot(eng)
	for _k in 5:
		_scene.refresh_hand_affordability()
		await _tick(1)
	var after := _snapshot(eng)
	_chk("连续刷新 5 次后亮/灰完全不变（幂等）", before == after)
	print("    before = %s" % str(before))
	print("    after  = %s" % str(after))

	_report()
	get_tree().quit(0 if _fail == 0 else 1)


## 每个状态的完整断言：亮/灰 必须等于「费用口径」
func _verify(eng, tag: String) -> void:
	var st = eng.state
	print("\n--- %s ---" % tag)
	var hr := _scene.get_node("Battle/HandPanelRight/HandRight")
	var hl := _scene.get_node("Battle/HandPanelLeft/HandLeft")
	for pair in [[0, hr, "我方绿(右)"], [1, hl, "敌方红(左)"]]:
		var side: int = pair[0]
		var host: Control = pair[1]
		var hand: Array = st.hand(side)
		var cost: int = st.cost(side)
		var line: Array = []
		var ok_all := true
		for i in hand.size():
			var c: CardData = hand[i]
			var expect: bool = (c.cost < 0) or (c.cost <= cost)   ## 费用口径（唯一判据）
			var node: Control = host.get_child(i) if i < host.get_child_count() else null
			var bright: bool = node != null and absf(node.modulate.r - 1.0) < 0.01
			var mark: String = "亮" if bright else "灰"
			var want: String = "亮" if expect else "灰"
			if bright != expect:
				ok_all = false
			line.append("%s(费%d)=%s" % [c.display_name, c.cost, mark])
		print("    %s cost=%d : %s" % [pair[2], cost, ", ".join(line)])
		_chk("%s 亮/灰 == 费用口径" % pair[2], ok_all)


func _snapshot(eng) -> Array:
	var out: Array = []
	var hr := _scene.get_node("Battle/HandPanelRight/HandRight")
	var hl := _scene.get_node("Battle/HandPanelLeft/HandLeft")
	for pair in [[0, hr], [1, hl]]:
		for ch in (pair[1] as Control).get_children():
			if ch is Control:
				out.append(snappedf((ch as Control).modulate.r, 0.01))
	return out


func _section(t: String) -> void:
	print("\n--- %s ---" % t)


func _chk(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  [PASS] ", label)
	else:
		_fail += 1
		_failures.append(label)
		print("  [FAIL] ", label)


func _report() -> void:
	print("\n===== 手牌稳定性结果 =====")
	print("  通过 %d / 失败 %d" % [_pass, _fail])
	for f in _failures:
		print("   X ", f)
	print("==========================")


func _tick(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
