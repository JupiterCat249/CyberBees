extends GutTest
## 远端呈现**纯查询**的回归（迭代110 —— 与 view_remote_flow 同一批交付）
##
## 不起场景：查询只读引擎状态 ⇒ 毫秒级，且能精确覆盖"该不该给预览"的判定。

const Fixture := preload("res://tests/support/battle_fixture.gd")
const Flow := preload("res://src/view/view_remote_flow.gd")

var e: BattleEngine = null


func before_each() -> void:
	e = Fixture.new_engine()


func test_unit_preview_only_for_opponent_selected_opponent_unit() -> void:
	var foe := Fixture.place_unit(e, 1, "泥蜂", Vector2i(1, 2))
	var hit: Dictionary = Flow.remote_unit_preview(e, 0, 1, foe.cell)     # 对端(1) 选中自己的单位
	assert_not_null(hit.get("unit"), "应带回该单位")
	assert_not_null(hit.get("preview"), "应算出它的可作用范围")


func test_unit_preview_skipped_when_selector_is_me() -> void:
	var foe := Fixture.place_unit(e, 1, "泥蜂", Vector2i(1, 2))
	var hit: Dictionary = Flow.remote_unit_preview(e, 0, 0, foe.cell)     # 发送方是我 ⇒ 不是远端
	assert_null(hit.get("unit"), "本地选中不该走远端通道")
	assert_null(hit.get("preview"), "也不该产出远端预览")


func test_command_preview_matches_card_name_only() -> void:
	Fixture.push_card(e, 1, "电击")
	var cell := Vector2i(2, 2)
	var ok: Resource = Flow.remote_command_preview(e, 1, "选中手牌 电击", cell)
	assert_not_null(ok, "名字对得上应给出效果范围")
	var bad: Resource = Flow.remote_command_preview(e, 1, "选中手牌 不存在的卡", cell)
	assert_null(bad, "名字对不上应为空（保持原行为：既不登记也不清登记）")
