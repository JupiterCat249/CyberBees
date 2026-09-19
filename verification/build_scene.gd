extends Node
## 【生产工具】重建 `res://scenes/ui/battle_scene.tscn` 的**烤入内容**
##
## 为什么需要它：场景里"烤好的"预览节点（16 格 + 双方单位 + 双方手牌 + 详情区立绘槽）
## 必须与权威数据一致 —— 卡池数值一变就要重烤，否则编辑器里显示的是旧数值。
##
## 用法：`project_run(mode="custom", scene="res://verification/build_scene.tscn")`
## 产出：覆盖写 `res://scenes/ui/battle_scene.tscn`
##
## ⚠️ **容器子节点不写布局（迭代057 C1 修正）**
##   手牌卡是 `GridContainer`（`HandLeft`/`HandRight`）的子节点 ——
##   对容器子节点写 `layout_mode = 0` + `offset_*` 等于把它们从容器布局里强行摘出来，
##   与容器排布**互相打架**（人反馈"列数总变成一列"的根因之一）。
##   容器的 `columns` / `separation` 契约由 `verification/apply_hand_container.gd` 写入。
##   非容器位置（`MapView/Units`、`MapView/MapCells`、`Artwork`）是普通 Control →
##   手动坐标**正确**，保留。
##
## 设计约定（勿破坏）：
##   · 根节点名 `BattleScene`，继承 `battle_ui_alpha.tscn`（**不挂脚本** —— 视图由新战斗系统接入）
##   · 格节点名必须是 `Cell_<行>_<列>`
##   · 手牌容器：`Battle/HandPanelLeft/HandLeft`（敌）· `Battle/HandPanelRight/HandRight`（我）
##   · 单位容器：`Battle/MapView/Units`（预览单位，运行时会清掉重建）
##   · 详情区立绘槽：`HUD/InfoPanel/DetailBlock/Artwork/Portrait`

const Pool := preload("res://scripts/data/card_pool.gd")
const OUT_PATH := "res://scenes/ui/battle_scene.tscn"

## 预览单位（双方蜂王）：我方在行3列1 / 敌方在行0列1
const PREVIEW_UNITS := [
	{"node": "Unit_ally", "name": "金刚蜂王", "cell": Vector2i(3, 1), "index": 0},
	{"node": "Unit_enemy", "name": "金刚蜂王", "cell": Vector2i(0, 1), "index": 1},
]
const PITCH := 250


## 收集本次要烤进去的立绘（卡名 → 资源 id）
var _art_ids := {}
var _art_paths := {}


func _collect_art() -> void:
	for pu in PREVIEW_UNITS:
		_art_of(String(pu["name"]))
	for i in mini(4, Pool.DECK_NAMES.size()):
		_art_of(String(Pool.DECK_NAMES[i]))


func _art_of(card_name: String) -> String:
	if _art_ids.has(card_name):
		return _art_ids[card_name]
	var path := "%s%s.png" % [Pool.ART_DIR, card_name]
	if not ResourceLoader.exists(path):
		_art_ids[card_name] = ""
		return ""
	var id := "art_%d" % _art_ids.size()
	_art_ids[card_name] = id
	_art_paths[id] = path
	return id


func _ready() -> void:
	_collect_art()
	var lines: PackedStringArray = []
	# ① 头部（不再引用旧控制器：迭代057 Q-3 已移除，避免文件混淆）
	lines.append("[gd_scene load_steps=%d format=3]" % (4 + _art_paths.size()))
	lines.append("")
	lines.append('[ext_resource type="PackedScene" path="res://scenes/ui/battle_ui_alpha.tscn" id="1_base"]')
	lines.append('[ext_resource type="PackedScene" path="res://scenes/ui/card_unit.tscn" id="3_unit"]')
	lines.append('[ext_resource type="PackedScene" path="res://scenes/ui/card_hand.tscn" id="4_hand"]')
	for id in _art_paths.keys():
		lines.append('[ext_resource type="Texture2D" path="%s" id="%s"]' % [_art_paths[id], id])
	lines.append("")
	lines.append('[node name="BattleScene" instance=ExtResource("1_base")]')

	# ② 16 个格点击区（`MapCells` 是**普通 Control** → 手动坐标正确）
	for x in 4:
		for y in 4:
			lines.append("")
			lines.append('[node name="Cell_%d_%d" type="Control" parent="Battle/MapView/MapCells" index="%d"]'
				% [x, y, x * 4 + y])
			lines.append("layout_mode = 0")
			lines.append("offset_left = %d.0" % (y * PITCH))
			lines.append("offset_top = %d.0" % (x * PITCH))
			lines.append("offset_right = %d.0" % (y * PITCH + PITCH))
			lines.append("offset_bottom = %d.0" % (x * PITCH + PITCH))
			lines.append("mouse_filter = 2")

	# ③ 预览单位（`Units` 是**普通 Control** → 手动坐标正确；数值与立绘都烤进去）
	for pu in PREVIEW_UNITS:
		_append_unit(lines, pu)

	# ④ 手牌（左右各 4 张；**只烤数据与立绘，不烤布局** —— 布局归 GridContainer）
	var demo: Array = Pool.DECK_NAMES
	for side in ["Enemy", "Ally"]:
		var parent := "Battle/HandPanelLeft/HandLeft" if side == "Enemy" \
			else "Battle/HandPanelRight/HandRight"
		for i in mini(4, demo.size()):
			_append_hand(lines, "%sHand_%d" % [side, i], parent, i, String(demo[i]))

	# ⑤ 详情区立绘槽（`Artwork` 是**普通 Panel** → 手动坐标正确）
	lines.append("")
	lines.append('[node name="Portrait" type="TextureRect" parent="HUD/InfoPanel/DetailBlock/Artwork" index="0"]')
	lines.append("layout_mode = 0")
	lines.append("offset_right = 300.0")
	lines.append("offset_bottom = 300.0")
	lines.append("mouse_filter = 2")
	lines.append("expand_mode = 1")
	lines.append("stretch_mode = 5")

	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("无法写入 ", OUT_PATH)
		get_tree().quit(1)
		return
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("[build_scene] 已重建 %s（%d 行）" % [OUT_PATH, lines.size() + 1])
	get_tree().quit(0)


func _append_unit(lines: PackedStringArray, pu: Dictionary) -> void:
	var c: CardData = Pool.card(String(pu["name"]))
	if c == null or not (c is UnitData):
		printerr("预览单位卡不存在：", pu["name"])
		return
	var u := c as UnitData
	var cell: Vector2i = pu["cell"]
	lines.append("")
	lines.append('[node name="%s" parent="Battle/MapView/Units" index="%d" instance=ExtResource("3_unit")]'
		% [pu["node"], pu["index"]])
	lines.append("layout_mode = 0")
	lines.append("offset_left = %d.0" % (cell.y * PITCH))
	lines.append("offset_top = %d.0" % (cell.x * PITCH))
	lines.append("offset_right = %d.0" % (cell.y * PITCH + PITCH))
	lines.append("offset_bottom = %d.0" % (cell.x * PITCH + PITCH))
	lines.append("mouse_filter = 2")
	var base := "Battle/MapView/Units/%s" % pu["node"]
	lines.append("")
	lines.append('[node name="Cost" parent="%s/CostPlate" index="0"]' % base)
	lines.append('text = "%d"' % u.refund)          ## 蜂王左上角显示**回费**（策划案）
	_append_attr(lines, base, "Attr_Attack", u.atk)
	_append_attr(lines, base, "Attr_Health", u.hp)
	_append_attr(lines, base, "Attr_Speed", u.move)
	_append_attr(lines, base, "Attr_Range", u.attack_range)
	var art_id := _art_of(String(pu["name"]))
	if art_id != "":
		lines.append('[node name="TextureRect" parent="%s/Artwork/ArtPlane" index="0"]' % base)
		lines.append('texture = ExtResource("%s")' % art_id)


func _append_attr(lines: PackedStringArray, base: String, node: String, v: int) -> void:
	lines.append('[node name="Value" parent="%s/%s" index="1"]' % [base, node])
	lines.append('text = "%d"' % v)


## 手牌：**只写数据与立绘**，不写任何布局（`layout_mode` / `offset_*`）——
## 布局完全交给 `GridContainer`（`columns` / `separation`）与卡自身的 `size_flags`。
func _append_hand(lines: PackedStringArray, node: String, parent: String, idx: int, card_name: String) -> void:
	var c: CardData = Pool.card(card_name)
	if c == null:
		printerr("预览手牌卡不存在：", card_name)
		return
	lines.append("")
	lines.append('[node name="%s" parent="%s" index="%d" instance=ExtResource("4_hand")]'
		% [node, parent, idx])
	lines.append("mouse_filter = 2")
	lines.append("")
	lines.append('[node name="Value" parent="%s/%s/BadgeImage" index="0"]' % [parent, node])
	lines.append('text = "%d"' % c.cost)
	var art_id := _art_of(card_name)
	if art_id != "":
		lines.append('[node name="Image" parent="%s/%s/Artwork/ArtPlane" index="0"]' % [parent, node])
		lines.append('texture = ExtResource("%s")' % art_id)
