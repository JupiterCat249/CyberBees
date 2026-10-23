extends GutTest
## **攻击后果预览（双向）** 回归 —— 迭代143（人 2026-10-23 口径）
##
## 口径：目标卡显示"我打它多少"；我方卡显示"它反击我多少"（无反击 = 0，**仍然显示**）。
## 本文件只测数据层（不起场景）；视图浮字由 test_attack_preview_view 覆盖。

const Fixture := preload("res://tests/support/battle_fixture.gd")
const Combat := preload("res://scripts/battle/rules_combat.gd")
const Preview := preload("res://scripts/battle/rules_preview.gd")

var e: BattleEngine = null


func before_each() -> void:
	e = Fixture.new_engine()
	e.state.phase = e.state.Phase.ACTION
	e.state.active = 0


func test_preview_attack_is_bidirectional_and_pure() -> void:
	## 相邻双方都能互击 ⇒ 双向都有伤害；且**不消耗状态**（纯函数）
	var atk := Fixture.place_unit(e, 0, "泥蜂", Vector2i(1, 1))
	var foe := Fixture.place_unit(e, 1, "泥蜂", Vector2i(1, 2))
	var hp_a := atk.current_hp
	var hp_f := foe.current_hp
	var fx: Dictionary = Combat.preview_attack(atk, foe, e.state.board)
	assert_true(int(fx["damage_to_defender"]) > 0, "我打它应有伤害")
	assert_true(bool(fx["counter_valid"]), "相邻且在射程内 ⇒ 应有反击")
	assert_true(int(fx["damage_to_attacker"]) > 0, "它反击我也应有伤害")
	assert_eq(atk.current_hp, hp_a, "预览不得改攻方 hp")
	assert_eq(foe.current_hp, hp_f, "预览不得改守方 hp")


func test_counter_absent_when_out_of_range() -> void:
	## 反击条件：攻击方在反击者射程外 ⇒ counter_valid=false、反击伤害 0
	var atk := Fixture.place_unit(e, 0, "泥蜂", Vector2i(0, 0))
	var foe := Fixture.place_unit(e, 1, "泥蜂", Vector2i(3, 3))
	var fx: Dictionary = Combat.preview_attack(atk, foe, e.state.board)
	assert_false(bool(fx["counter_valid"]), "超射程 ⇒ 无反击")
	assert_eq(int(fx["damage_to_attacker"]), 0, "无反击 ⇒ 我方受伤 0")


func test_pending_target_preview_is_pair_scoped_and_bidirectional() -> void:
	## 已选目标（待确认）⇒ build 收缩到这一对，且 hints 同时含"目标"与"我方被反击"
	var atk := Fixture.place_unit(e, 0, "泥蜂", Vector2i(1, 1))
	var foe := Fixture.place_unit(e, 1, "泥蜂", Vector2i(1, 2))
	var pv: Resource = Preview.build(e.state, 2, -1, atk, null, true, foe.cell)
	assert_eq(int(pv.kind), 3, "待确认攻击应是 ATTACK 预览（PreviewKind.ATTACK=3）")
	assert_true(pv.hints.has(foe.instance_id), "目标卡应有后果数据")
	assert_true(pv.hints.has(atk.instance_id), "我方卡应有被反击数据")
	var mine: Dictionary = pv.hints[atk.instance_id]
	assert_true(mine.has("incoming"), "我方数据应含 incoming（无反击时为 0）")
	var their: Dictionary = pv.hints[foe.instance_id]
	assert_true(their.has("dmg"), "目标数据应含 dmg")
	assert_false(their.has("incoming"), "目标卡不显示被反击（那是给攻方的）")
