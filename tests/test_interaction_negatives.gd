extends GutTest
## **决策负路径**回归（迭代126 · 第二轮 P2 —— 《质控方案-补充-002》P2）
##
## 交互网此前只有"正半边"（能做的操作会成功）。本文件补负半边：
##   **无效操作必须"什么都不改"** —— 不改费用、不改手牌、不改棋盘、不改 hp，且决策层直接给 none。
## 判据都取**可读读数**（字段/数量/布尔返回），不看观感。

const Fixture := preload("res://tests/support/battle_fixture.gd")
const Dispatch := preload("res://scenes/ui/view_cell_dispatch.gd")

var e: BattleEngine = null


func before_each() -> void:
	e = Fixture.new_engine()


## 把整局状态压成可比较的读数（只取与"无效操作"相关的字段）
func _snap() -> Dictionary:
	var st = e.state
	var units: Array = []
	for side in [0, 1]:
		for u in st.units(side):
			units.append([u.instance_id, u.current_hp, u.cell])
	return {
		"active": int(st.active),
		"phase": int(st.phase),
		"round": int(st.round_no),
		"cost0": int(st.sides[0]["cost"]),
		"cost1": int(st.sides[1]["cost"]),
		"hand0": int(st.sides[0]["hand"].size()),
		"hand1": int(st.sides[1]["hand"].size()),
		"units": units,
	}


func test_non_my_turn_unit_click_is_noop() -> void:
	## 非己方回合点我方单位 ⇒ 决策层给 none，且**状态一字未动**
	e.state.active = 1                      # 对方回合
	var mine := Fixture.place_unit(e, 0, "泥蜂", Vector2i(2, 1))
	assert_not_null(mine, "前置：应有我方单位")
	var before := _snap()
	var d: Dictionary = Dispatch.decide_unit(e, 0, mine)
	assert_eq(String(d.get("type")), "none", "非己方回合应直接给 none")
	assert_eq(_snap(), before, "状态不得改变（费用/手牌/棋盘/hp）")


func test_deploy_when_not_enough_cost_is_rejected() -> void:
	## 费用不足时部署 ⇒ 请求返回 false，手牌与费用、棋盘全部不变
	var idx := Fixture.push_card(e, 0, "蜂巢")     # 建筑费用较高
	e.state.sides[0]["cost"] = 0                  # 强制费用不足（夹具的开局费用不保证为 0）
	assert_eq(int(e.state.sides[0]["cost"]), 0, "前置：应把费用压到 0")
	var cell := Fixture.empty_own_cell(e)
	var before := _snap()
	var ok: bool = e.request_deploy(0, idx, cell)
	assert_false(ok, "费用不足必须被拒（返回 false）")
	assert_eq(_snap(), before, "被拒后状态不得改变")


func test_attack_out_of_range_is_rejected() -> void:
	## 超射程攻击 ⇒ 请求返回 false，双方 hp 与位置都不变
	var atk := Fixture.place_unit(e, 0, "泥蜂", Vector2i(2, 0))
	var foe := Fixture.place_unit(e, 1, "泥蜂", Vector2i(0, 3))
	assert_not_null(atk, "前置：攻方")
	assert_not_null(foe, "前置：守方")
	assert_true(atk.cell != foe.cell, "前置：不同格")
	var far: bool = abs(atk.cell.x - foe.cell.x) + abs(atk.cell.y - foe.cell.y) > atk.attack_range()
	assert_true(far, "前置：距离应超出射程（实测 %d 格 / 射程 %d）" % [
		abs(atk.cell.x - foe.cell.x) + abs(atk.cell.y - foe.cell.y), atk.attack_range()])
	var before := _snap()
	var ok: bool = e.request_attack(0, atk, foe)
	assert_false(ok, "超射程必须被拒（返回 false）")
	assert_eq(_snap(), before, "被拒后状态不得改变")
