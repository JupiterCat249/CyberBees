class_name BattleDefs
extends RefCounted
## ============================================================
## 电子蜂 · 战斗场景「统一定义」——常量 / 坐标 / 图标索引 / 卡池
## 只放纯数据，不含逻辑；所有战斗节点共用本文件，避免常量散落各处。
## 规则依据: 电子蜂A5策划案/电子蜂a500规则.md（以 a500 为准）
## ============================================================

# ---------------- 设计坐标（与 battle_ui.gdshader 常量一致） ----------------
const MAP_ORIGIN := Vector2(460.0, 40.0)
const CELL := 250.0
const ROWS := 4
const COLS := 4
const PANEL_L := Vector2(32.0, 150.0)
const PANEL_R := Vector2(1488.0, 150.0)
const PANEL_SZ := 400.0
const HEX_L := Vector2(82.0, 90.0)
const HEX_R := Vector2(1538.0, 90.0)
const HEX_DIGIT_H := 44.0
const BTN_MAIN := Vector2(1488.0, 560.0)
const BTN_MAIN_SZ := Vector2(400.0, 100.0)
const DETAIL_POS := Vector2(32.0, 758.0)
const DETAIL_SCALE := 1.2
const STAT_X := 381.0
const STAT_Y0 := 800.0
const STAT_DY := 76.0
const SBTN0 := Vector2(1532.0, 1002.0)
const SBTN_DX := 104.0
const SBTN_HIT := 44.0

## 手牌卡：面板 400x400 内 2x2（卡设计尺寸 250 -> 0.76 = 190px）
const HAND_CARD_SCALE := 0.76
const HAND_CARD_STEP := 195.0
const HAND_CARD_PAD := 5.0

# ---------------- 框架资源（card-system 提供，禁止改动） ----------------
const ATLAS_PATH := "res://card-system/card_system/card_atlas.png"
const CARD_SCENE := "res://card-system/card_system/card_auto.tscn"
const UI_SCENE := "res://card-system/card_system/battle_ui.tscn"
const ART_DIR := "res://card-system/card_system/art/"
const ATLAS_CELL := 96.0
const DIGIT_Y := 4.0
const DIGIT_H := 88.0
const DIGW := [0.7021, 0.4239, 0.6522, 0.617, 0.7667, 0.6196, 0.6809, 0.7111, 0.6915, 0.6809]
const ATLAS_ICON_BASE := 10.0

# ---------------- 背景资源（card-system 未提供，属补充） ----------------
const MAP_TERRAIN_PATH := "res://assets/background/map_terrain.png"
const MAP_GRID_PATH := "res://assets/background/map_grid.png"
const BG_BLURRED_PATH := "res://assets/background/bg_blurred.png"

# ---------------- 背景特效：扫描线（叠加进"背景纹理"，不覆盖 UI） ----------------
const SCAN_TILE_PATH := "res://assets/background/bg_filter_tile.png"
const SCAN_TILE_PX := 100.0     ## 扫描线 tile 尺寸（设计像素）
const SCAN_MIX := 0.32          ## 叠加强度（0=无，1=全白线）
const SCAN_SPEED := 0.45        ## 每帧下移的设计像素（帧数计时，不用 delta）

# ---------------- 图标索引（card_auto / 图集） ----------------
const I_ATK := 0
const I_SPD := 1
const I_HP := 2
const I_RANGE := 3
const I_SOLDIER := 4
const I_BUILDING := 5
const I_COMMAND := 6
const I_QUEEN := 7
const I_TERRAIN := 5

# ---------------- 规则常量（a500） ----------------
const HAND_MAX := 4
const COST_MAX := 10
const ROUND_MAX := 12
const BASE_REFUND := 2
const ROUND7_EXTRA := 2
const SECOND_PLAYER_BONUS := 2

enum Phase { REFUND, FIELD, DEPLOY, ACTION }
const PHASE_NAME := ["回费", "场地", "部署", "行动"]
enum Mode { IDLE, DEPLOY_TARGET, CMD_TARGET }

# ---------------- 卡池（含技能数据，供技能显示区使用） ----------------
const POOL := [
	{"art": "卡牌a-金刚蜂王", "name": "金刚蜂王", "kind": "queen", "cost": 8, "atk": 7, "spd": 1, "hp": 8, "range": 2,
		"sk": "【机场】蜂王巢口", "sdesc": "部署阶段可在自身相邻格部署兵蜂；蜂王免疫指令卡伤害与减益。",
		"stags": "被动 · 部署 · 蜂王"},
	{"art": "卡牌c1-叶蜂", "name": "叶蜂", "kind": "soldier", "cost": 2, "atk": 2, "spd": 1, "hp": 3, "range": 1,
		"support": {"id": "rally", "name": "鼓舞", "rng": 2, "buff": {"id": "atk_up", "name": "攻击提升", "atk_add": 1}},
		"sk": "【支援】鼓舞", "sdesc": "选择 2 格内的 1 个己方单位，赋予「攻击提升」：攻击力 +1。使用后结束该单位行动。",
		"stags": "支援 · 单位效果 · 增益"},
	{"art": "卡牌c1-泥蜂", "name": "泥蜂", "kind": "soldier", "cost": 2, "atk": 3, "spd": 1, "hp": 4, "range": 2,
		"sk": "（无技能）", "sdesc": "纯战斗兵蜂：攻击 3 / 速度 1 / 生命 4 / 射程 2。",
		"stags": "兵蜂"},
	{"art": "卡牌c2-熊蜂", "name": "熊蜂", "kind": "soldier", "cost": 5, "atk": 5, "spd": 1, "hp": 8, "range": 1,
		"support": {"id": "guard", "name": "护卫", "rng": 1, "buff": {"id": "def_up", "name": "护甲", "reduce": 1}},
		"sk": "【支援】护卫", "sdesc": "选择 1 格内的 1 个己方单位，赋予「护甲」：受到的每次伤害 -1。使用后结束该单位行动。",
		"stags": "支援 · 单位效果 · 增益"},
	{"art": "卡牌b1-蜂巢", "name": "蜂巢", "kind": "building", "cost": 4, "atk": 0, "spd": 0, "hp": 5, "range": 0, "refund": 1,
		"sk": "【回费】采集", "sdesc": "每个己方回费阶段，额外回复 1 点费用。部署在己方领地任意格。",
		"stags": "回费 · 资源建筑"},
	{"art": "卡牌b1-蜂巢III", "name": "蜂巢III", "kind": "building", "cost": 9, "atk": 0, "spd": 0, "hp": 12, "range": 0, "refund": 2,
		"sk": "【回费】集群采集", "sdesc": "每个己方回费阶段，额外回复 2 点费用。生命值 12，可作前场肉盾。",
		"stags": "回费 · 资源建筑"},
	{"art": "卡牌d1-电击", "name": "电击", "kind": "command", "cost": 3, "dmg": 4, "range": 2,
		"sk": "【指令】电击", "sdesc": "对射程 2 内的 1 个单位造成 4 点指令伤害。蜂王免疫。使用后返回墓地。",
		"stags": "指令 · 攻击指令"},
	{"art": "卡牌d2-治疗", "name": "治疗", "kind": "command", "cost": 3, "heal": 4, "range": 2,
		"sk": "【指令】治疗", "sdesc": "为射程 2 内的 1 个己方单位回复 4 点生命值（不超过上限）。使用后返回墓地。",
		"stags": "指令 · 辅助指令"},
	{"art": "卡牌d1-巡航导弹", "name": "巡航导弹", "kind": "command", "cost": 6, "dmg": 5, "range": 3, "debuff": {"id": "burn", "name": "灼烧", "dot": 1},
		"sk": "【指令】巡航导弹", "sdesc": "对射程 3 内的 1 个单位造成 5 点指令伤害，并赋予「灼烧」：其回合结束时 -1 生命。蜂王免疫。",
		"stags": "指令 · 攻击指令 · 减益"},
	{"art": "卡牌d1-电击III", "name": "X费·毁灭", "kind": "command_x", "cost": -1, "dmg": 0, "range": 3,
		"sk": "【指令】毁灭（X费）", "sdesc": "费用 = 目标单位的部署费用；对其造成「部署费用 ×2」的指令伤害。不可指定蜂王。",
		"stags": "指令 · 攻击指令 · X费"},
]

## 卡组：1 蜂王 + 8 常规卡（a500：同名不得超过 4 张）
const DECK_LIST := ["叶蜂", "叶蜂", "泥蜂", "泥蜂", "熊蜂", "蜂巢", "电击", "治疗"]


## 按名字取卡（找不到回退第一张兵蜂）
static func card(nm: String) -> Dictionary:
	for c in POOL:
		if c["name"] == nm:
			return c
	return POOL[1]


## 单元格 -> 设计坐标（左上角）
static func cell_pos(cell: Vector2i) -> Vector2:
	return MAP_ORIGIN + Vector2(cell.y * CELL, cell.x * CELL)


## 设计坐标 -> 单元格（越界返回 (-1,-1)）
static func pos_cell(p: Vector2) -> Vector2i:
	var b := p - MAP_ORIGIN
	if b.x < 0.0 or b.y < 0.0 or b.x >= COLS * CELL or b.y >= ROWS * CELL:
		return Vector2i(-1, -1)
	@warning_ignore("integer_division")
	var row := int(b.y / CELL)
	@warning_ignore("integer_division")
	var col := int(b.x / CELL)
	return Vector2i(row, col)


## 单元格是否在地图内
static func in_map(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < ROWS and cell.y >= 0 and cell.y < COLS


# ============================================================
# 资源工厂（手牌/场上/详情/徽章共用，避免各视图重复实现）
# ============================================================
const CARD_RES := preload("res://card-system/card_system/card_auto.tscn")
const ATLAS_RES := preload("res://card-system/card_system/card_atlas.png")


## 实例化一张框架卡牌（复用 card_auto.tscn）；按类型设置角标与四维属性
static func make_card(d: Dictionary, sc: float) -> Node2D:
	var node := CARD_RES.instantiate()
	node.scale = Vector2(sc, sc)
	node.set("art", load(ART_DIR + str(d["art"]) + ".png"))
	node.set("cost", int(d["cost"]))
	node.set("art_fit", 1)
	node.set("art_zoom", 1.05)
	match d["kind"]:
		"queen":
			node.set("icon_tag", I_QUEEN)
		"soldier":
			node.set("icon_tag", I_SOLDIER)
		"building":
			node.set("icon_tag", I_BUILDING)
		_:
			node.set("icon_tag", I_COMMAND)
	if d["kind"] == "command" or d["kind"] == "command_x":
		node.set("stat_l1", int(d["heal"]) if d.has("heal") else int(d.get("dmg", 0)))
		node.set("icon_l1", I_HP if d.has("heal") else I_ATK)
		node.set("stat_l2", -1)
		node.set("icon_l2", -1)
		node.set("stat_r1", -1)
		node.set("icon_r1", -1)
		node.set("stat_r2", int(d.get("range", 0)))
		node.set("icon_r2", I_RANGE)
	else:
		node.set("stat_l1", int(d.get("atk", -1)))
		node.set("icon_l1", I_ATK if int(d.get("atk", 0)) > 0 else -1)
		node.set("stat_l2", int(d.get("spd", -1)))
		node.set("icon_l2", I_SPD if int(d.get("spd", 0)) > 0 else -1)
		node.set("stat_r1", int(d.get("hp", -1)))
		node.set("icon_r1", I_HP)
		node.set("stat_r2", int(d.get("range", -1)))
		node.set("icon_r2", I_RANGE if int(d.get("range", 0)) > 0 else -1)
	return node


## 用框架图集的 0-9 字形拼出数字（与 card_auto.gdshader 同一套 DIGW/字形区映射）
static func digit_node(v: int, height: float, col: Color, center: Vector2) -> Node2D:
	var root := Node2D.new()
	root.position = center
	if v < 0:
		return root
	var ds: Array = []
	for ch in str(v):
		ds.append(int(ch))
	var sc := height / DIGIT_H
	var gap := 1.5 * sc
	var total := 0.0
	for dd in ds:
		total += float(DIGW[dd]) * DIGIT_H * sc
	if ds.size() > 1:
		total += gap * float(ds.size() - 1)
	var x := -total * 0.5
	for dd in ds:
		var pad := (1.0 - float(DIGW[dd])) * 0.5
		var at := AtlasTexture.new()
		at.atlas = ATLAS_RES
		at.region = Rect2((float(dd) + pad) * ATLAS_CELL, DIGIT_Y, float(DIGW[dd]) * ATLAS_CELL, DIGIT_H)
		var sp := Sprite2D.new()
		sp.texture = at
		sp.centered = false
		sp.scale = Vector2(sc, sc)
		sp.position = Vector2(x, -height * 0.5)
		sp.modulate = col
		root.add_child(sp)
		x += float(DIGW[dd]) * DIGIT_H * sc + gap
	return root


## 图集图标格（第 10+idx 格）做成精灵；sort=1 时按图标实心区居中留白
static func atlas_icon(idx: int, size: float, center: Vector2, col: Color) -> Sprite2D:
	var at := AtlasTexture.new()
	at.atlas = ATLAS_RES
	at.region = Rect2((ATLAS_ICON_BASE + float(idx)) * ATLAS_CELL, 0.0, ATLAS_CELL, ATLAS_CELL)
	var sp := Sprite2D.new()
	sp.texture = at
	sp.centered = true
	sp.position = center
	sp.scale = Vector2(size / ATLAS_CELL, size / ATLAS_CELL)
	sp.modulate = col
	return sp
