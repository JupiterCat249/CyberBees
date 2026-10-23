extends GutTest
## 攻击后果预览的**视图级**读数 —— 迭代143
##
## 人 2026-10-23 口径：双步骤确认的**第一步（选中目标、待确认）**就要看到两边后果：
##   目标卡 `-X`（或「抵挡」/「-X 击杀」）；我方卡 `反击 -Y`（无反击显示 `反击 0`）。
## 本文件用真实场景，直接数 `preview_hint` 浮字的**文本**。

const BattleScene := preload("res://scenes/ui/battle_scene.tscn")
const Fixture := preload("res://tests/support/battle_fixture.gd")

var _scene: Node = null


func before_all() -> void:
	_scene = BattleScene.instantiate()
	add_child(_scene)
	await wait_frames(3)


func after_all() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()


func _hint_texts() -> Array:
	var fx = _scene.get("_fx_root")
	var out: Array = []
	if fx == null:
		return out
	for ch in fx.get_children():
		if ch.has_meta("preview_hint"):
			var lb = ch.get_node_or_null("Text")
			if lb != null:
				out.append(String(lb.text))
	return out


func _first_empty_pair(e) -> Array:
	## 找一对相邻空格放"我"和"敌"（本文件共享场景 ⇒ 不写死坐标）
	for x in 3:
		for y in 3:
			var a := Vector2i(x, y)
			var b := Vector2i(x + 1, y)
			if e.state.board.is_empty(a) and e.state.board.is_empty(b):
				return [a, b]
	return []


func test_pending_attack_shows_both_sides() -> void:
	var e = _scene.get("engine")
	e.state.active = 0
	e.state.phase = e.state.Phase.ACTION
	var pair := _first_empty_pair(e)
	assert_eq(pair.size(), 2, "前置：应能找到一个相邻空格对")
	var atk := Fixture.place_unit(e, 0, "泥蜂", pair[0])
	var foe := Fixture.place_unit(e, 1, "泥蜂", pair[1])
	assert_not_null(atk, "前置：我方单位")
	assert_not_null(foe, "前置：敌方单位")
	_scene._on_unit_spawned(atk, atk.cell)
	_scene._on_unit_spawned(foe, foe.cell)
	await wait_frames(1)
	## 第一步：选我方单位（此时是"所有可打目标"预览）
	_scene._on_unit_clicked(atk.instance_id)
	await wait_frames(1)
	## 第二步：选目标（进入待确认）—— 这里必须同时出现"我打它"与"反击"
	_scene._on_unit_clicked(foe.instance_id)
	await wait_frames(1)
	var texts := _hint_texts()
	assert_eq(texts.size(), 2, "待确认时应有且仅有两条浮字（本对单位）：%s" % str(texts))
	var hit := false
	var counter := false
	for t in texts:
		var s := String(t)
		if s.begins_with("-") or s == "抵挡":
			hit = true
		if s.begins_with("反击"):
			counter = true
	assert_true(hit, "目标卡应显示我方的伤害/抵挡：%s" % str(texts))
	assert_true(counter, "我方卡应显示被反击数值（无反击也要显示 反击 0）：%s" % str(texts))


func test_no_counter_shows_zero() -> void:
	## 敌方无法反击（无攻击力）⇒ 我方卡仍显示「反击 0」（人 2026-10-23 口径）
	var e = _scene.get("engine")
	e.state.active = 0
	e.state.phase = e.state.Phase.ACTION
	var pair := _first_empty_pair(e)
	assert_eq(pair.size(), 2, "前置：应能找到一个相邻空格对")
	var atk := Fixture.place_unit(e, 0, "泥蜂", pair[0])
	var foe := Fixture.place_unit(e, 1, "蜂巢", pair[1])
	if foe == null:
		pass_test("本卡组无建筑卡，跳过")
		return
	_scene._on_unit_spawned(atk, atk.cell)
	_scene._on_unit_spawned(foe, foe.cell)
	await wait_frames(1)
	_scene._on_unit_clicked(atk.instance_id)
	await wait_frames(1)
	_scene._on_unit_clicked(foe.instance_id)
	await wait_frames(1)
	var texts := _hint_texts()
	var has_zero := false
	for t in texts:
		if String(t) == "反击 0":
			has_zero = true
	assert_true(has_zero, "无反击时应显示「反击 0」：%s" % str(texts))


func test_selecting_unit_alone_shows_no_consequence() -> void:
	## 人 2026-10-23：「一靠近对方就自动弹出攻击结果预览」= 错。
	##   **只选中我方单位（还没选目标）**时不得有任何后果浮字。
	var e = _scene.get("engine")
	e.state.active = 0
	e.state.phase = e.state.Phase.ACTION
	e.cancel_selection()
	await wait_frames(1)
	var pair := _first_empty_pair(e)
	assert_eq(pair.size(), 2, "前置：应能找到一个相邻空格对")
	var atk := Fixture.place_unit(e, 0, "泥蜂", pair[0])
	var foe := Fixture.place_unit(e, 1, "泥蜂", pair[1])
	_scene._on_unit_spawned(atk, atk.cell)
	_scene._on_unit_spawned(foe, foe.cell)
	await wait_frames(1)
	_scene._on_unit_clicked(atk.instance_id)
	await wait_frames(1)
	assert_eq(_hint_texts().size(), 0, "仅选中单位时不得出现后果浮字：%s" % str(_hint_texts()))


func test_cancel_clears_consequence_floats() -> void:
	## 人 2026-10-23：「执行或取消执行后浮字不自动消失」——取消后必须清空。
	var e = _scene.get("engine")
	e.state.active = 0
	e.state.phase = e.state.Phase.ACTION
	e.cancel_selection()
	await wait_frames(1)
	var pair := _first_empty_pair(e)
	assert_eq(pair.size(), 2, "前置：应能找到一个相邻空格对")
	var atk := Fixture.place_unit(e, 0, "泥蜂", pair[0])
	var foe := Fixture.place_unit(e, 1, "泥蜂", pair[1])
	_scene._on_unit_spawned(atk, atk.cell)
	_scene._on_unit_spawned(foe, foe.cell)
	await wait_frames(1)
	_scene._on_unit_clicked(atk.instance_id)
	await wait_frames(1)
	_scene._on_unit_clicked(foe.instance_id)
	await wait_frames(1)
	assert_eq(_hint_texts().size(), 2, "前置：待确认应有两条后果")
	e.cancel_selection()
	await wait_frames(1)
	assert_eq(_hint_texts().size(), 0, "取消后不得残留浮字：%s" % str(_hint_texts()))