extends GutTest
## 单位卡**数据装配**的纯回归（迭代112 —— 与 view_unit_model 同一批交付）
##
## 不起场景：装配只读 UnitInstance ⇒ 能精确断言"类型键 / 阵营色 / 效果徽标"三件事实。

const Fixture := preload("res://tests/support/battle_fixture.gd")
const Model := preload("res://scenes/ui/view_unit_model.gd")

var e: BattleEngine = null


func before_each() -> void:
	e = Fixture.new_engine()


func test_type_key_maps_card_kinds() -> void:
	var q = Fixture.queen(e, 0)
	assert_eq(Model.type_key(q), "queen", "蜂王 → queen")
	var soldier := Fixture.place_unit(e, 0, "泥蜂", Vector2i(2, 1))
	assert_eq(Model.type_key(soldier), "unit", "兵蜂 → unit")
	var building := Fixture.place_unit(e, 0, "蜂巢", Vector2i(2, 0))
	assert_eq(Model.type_key(building), "building", "建筑 → building")


func test_unit_view_mine_follows_seat() -> void:
	## 联机口径：每个玩家看到自己都是绿方 ⇒ mine = (inst.side == my_seat)
	var q = Fixture.queen(e, 0)
	assert_true(bool(Model.unit_view(q, 0)["mine"]), "seat0 看己方应为 mine")
	assert_false(bool(Model.unit_view(q, 1)["mine"]), "seat1 看同一单位应为非 mine")
	var v: Dictionary = Model.unit_view(q, 0)
	assert_eq(String(v["id"]), q.instance_id, "id 应取实例 id")
	assert_eq(int(v["hp"]), q.current_hp, "hp 应取当前生命（不是上限）")


func test_effect_badges_only_runtime_effects() -> void:
	## 只取 inst.effects（运行态）；卡牌自带被动在 UnitData.passives，绝不进徽标
	var q = Fixture.queen(e, 0)
	## 蜂王开局自带【部署】装甲 ⇒ 运行态效果可能非空；关键是**徽标与 inst.effects 一一对应**
	var badges: Array = Model.effect_badges(q, {})
	assert_eq(badges.size(), q.effects.size(), "徽标数应等于运行态效果数")
	for i in badges.size():
		assert_eq(String(badges[i]["name"]), String(q.effects[i].data.display_name), "徽标名应来自效果数据")
