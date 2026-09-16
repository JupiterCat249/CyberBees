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
const HAND_CARD_SCALE := 0.76   # 手牌卡＝框架卡面（250×0.76=190px，card-system 原先的手牌规格）
const HAND_CARD_STEP := 195.0
const HAND_CARD_PAD := 5.0

# ---------------- 框架资源（card-system 提供，禁止改动） ----------------
const ATLAS_PATH := "res://card-system/card_system/card_atlas.png"
const CARD_SCENE := "res://card-system/card_system/card_auto.tscn"
const UI_SCENE := "res://card-system/card_system/battle_ui.tscn"
const ART_DIR := "res://card-system/card_system/art/"


# ---------------- 状态图标（迭代015）：A5 素材「状态图标/」10 张 80×80 ----------------
## 素材原目录：电子蜂A5策划案/素材/状态图标/  →  已迁移到本仓 assets/status_icons/
const STATUS_ICON_DIR := "res://assets/status_icons/"
## 效果 id → 图标文件（对应 A5《美术资源图鉴》里的状态关键词）
##   目前已实现的效果：burn 灼烧 · armor 装甲
##   其余 8 张（护盾/力场/冻结/暴击/拦截/诱饵/速攻/启动）为**已迁移待用**——对应规则尚未在代码中实现
const STATUS_ICON_MAP := {
	"burn": "灼烧.png",
	"armor": "装甲.png",
	"shield": "护盾.png",
	"force_field": "力场.png",
	"freeze": "冻结.png",
	"crit": "暴击.png",
	"intercept": "拦截.png",
	"decoy": "诱饵.png",
	"haste": "速攻.png",
	"startup": "启动.png",
}


## 取效果对应的状态图标路径；无对应/素材缺失 → 返回 ""（调用方回退到纯色角标）
static func status_icon_path(effect_id: String) -> String:
	var f := str(STATUS_ICON_MAP.get(effect_id, ""))
	if f == "":
		return ""
	var p := STATUS_ICON_DIR + f
	return p if ResourceLoader.exists(p) else ""
const ATLAS_CELL := 96.0
const DIGIT_Y := 4.0
const DIGIT_H := 88.0
const DIGW := [0.7021, 0.4239, 0.6522, 0.617, 0.7667, 0.6196, 0.6809, 0.7111, 0.6915, 0.6809]
const ATLAS_ICON_BASE := 10.0

# ---------------- 背景资源（card-system 未提供，属补充） ----------------
const MAP_TERRAIN_PATH := "res://assets/background/map_terrain.png"
const MAP_GRID_PATH := "res://assets/background/map_grid.png"
const BG_BLURRED_PATH := "res://assets/background/bg_blurred.png"

# ---------------- 框架 UI 素材（A5 策划案 zip原图，用于待确认/选中指示；非新建像素文件） ----------------
const CELL_PENDING_PATH := "res://assets/ui/cell_pending.png"   ## 战斗UI-地图格选中250x250（白色六边形选中框）
const CARD_SELECTED_PATH := "res://assets/ui/card_selected.png" ## 卡牌x-选中266x266（白色卡牌选中边框）

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

## 长按阈值（帧数，T2：不使用 delta）；60fps 下 30 帧 ≈ 0.5 秒
const LONG_PRESS_FRAMES := 30

# ---------------- 规则常量（a500） ----------------
const HAND_MAX := 4
const COST_MAX := 10
const ROUND_MAX := 12
const BASE_REFUND := 2
const ROUND7_EXTRA := 2
const SECOND_PLAYER_BONUS := 2

enum Phase { REFUND, FIELD, DEPLOY, ACTION, PREPARE }
const PHASE_NAME := ["回费", "场地", "部署", "行动", "准备"]
## 迭代005.1：换牌（原 EXCHANGE_MAX / 对战准备 5 的初始手牌调整）已整体移除 —— 开局前无换牌机会
enum Mode { IDLE, DEPLOY_TARGET, CMD_TARGET, SUPPORT_TARGET }

# ---------------- 效果图鉴（迭代016）：源自 A5《电子蜂A5策划案》「效果图鉴」（计算优先级从上到下） ----------------
## 已实现：burn 灼烧 · armor 装甲 · force_field 力场 · shield 护盾
##   力场：地域效果，**每层减少 2 点非指令伤害**（作用于目标格上的单位）
##   护盾：兵蜂效果，**抵挡一次攻击**；参与防御计算或己方回费阶段消失
##   装甲：单位效果，抵挡一次攻击，参与防御计算则消失
const EFFECT_FORCE_FIELD_REDUCE := 2   ## 力场每层减伤（A5 效果图鉴）
const EFFECT_BURN_DAMAGE := 2         ## 灼烧每层追加的指令伤害（A5 效果图鉴）
const EFFECT_AURA_FORCE_FIELD := 1    ## 「力场」地域效果授予相邻己方单位的层数（A5：相邻己方单位获得 1 层力场）
## 迭代018（人明确）：**buff 不能叠加**（a500「相同效果最多一个」）—— 光环不累加层数，
##   手动赋予与光环授予也互不叠加；同名效果恒为 1 层。
const EFFECT_DEFS := {
	"burn": {"name": "灼烧", "icon": "灼烧.png", "kind": "debuff"},
	"armor": {"name": "装甲", "icon": "装甲.png", "kind": "buff_def"},
	"shield": {"name": "护盾", "icon": "护盾.png", "kind": "buff_def"},   # 迭代018（人明确）：护盾**同样抵挡指令伤害**
	"force_field": {"name": "力场", "icon": "力场.png", "kind": "buff_def_area"},
	"freeze": {"name": "冻结", "icon": "冻结.png", "kind": "debuff"},
	"intercept": {"name": "拦截", "icon": "拦截.png", "kind": "buff_def_area"},
	"crit": {"name": "暴击", "icon": "暴击.png", "kind": "buff_area"},
	"haste": {"name": "速攻", "icon": "速攻.png", "kind": "buff"},
	"startup": {"name": "启动", "icon": "启动.png", "kind": "buff"},
	"decoy": {"name": "诱饵", "icon": "诱饵.png", "kind": "debuff"},
}
## 己方回费阶段会**消失**的效果（A5 各类效果的消失时机）
const EFFECT_EXPIRE_ON_REFUND := ["shield", "freeze", "burn", "haste", "decoy"]


## 构造一个效果对象（键 = 效果 id，与 status_icon_path() 的映射一致）
static func make_effect(eid: String, layers := 1, aura := false) -> Dictionary:
	var e := {"id": eid, "layers": layers}
	var meta: Dictionary = EFFECT_DEFS.get(eid, {})
	if not meta.is_empty():
		e["name"] = str(meta.get("name", eid))
	match eid:
		"burn":
			# 迭代017（G-35 修正）：A5 效果图鉴 —— 「受攻击时每层效果追加 2 点**指令伤害**，己方回费阶段消失」
			#   旧实现为"回合结束扣血"（dot），与 A5 不符，已改为受攻击时追加指令伤害
			e["burn_dmg"] = EFFECT_BURN_DAMAGE * layers
		"armor":
			e["reduce"] = 1
		"force_field":
			e["ff_reduce"] = EFFECT_FORCE_FIELD_REDUCE * layers
			# 迭代017（G-37）：`aura=true` 标记该力场由**地域效果**（相邻授予）产生，
			#   每个回费阶段按场上光环重新计算（光环消失/单位离场时随之移除）
			if aura:
				e["aura"] = true
	return e


# ---------------- 卡池（含技能数据，供技能显示区使用） ----------------
const POOL := [
	# refund = 每回合回费量（A5：蜂王左上角显示「每回合回复费用」而非部署费用；金刚蜂王 = 回费 4）
	# refund = 每回合回费量（A5：蜂王左上角显示「每回合回复费用」而非部署费用；金刚蜂王 = 回费 4）
	{"art": "卡牌a-金刚蜂王", "name": "金刚蜂王", "kind": "queen", "cost": 8, "atk": 7, "spd": 1, "hp": 8, "range": 2, "refund": 4,
		"sk": "【机场】蜂王巢口", "sdesc": "部署阶段可在自身相邻格部署兵蜂；蜂王免疫指令卡伤害与减益。",
		"stags": "被动 · 部署 · 蜂王"},
	{"art": "卡牌c1-叶蜂", "name": "叶蜂", "kind": "soldier", "cost": 2, "atk": 2, "spd": 1, "hp": 3, "range": 1,
		"support": {"id": "rally", "name": "鼓舞", "rng": 2, "buff": {"id": "atk_up", "name": "攻击提升", "atk_add": 1}},
		"sk": "【支援】鼓舞", "sdesc": "选择 2 格内的 1 个己方单位，赋予「攻击提升」：攻击力 +1。使用后结束该单位行动。",
		"stags": "支援 · 单位效果 · 增益"},
	{"art": "卡牌c1-泥蜂", "name": "泥蜂", "kind": "soldier", "cost": 2, "atk": 3, "spd": 1, "hp": 4, "range": 2,
		"sk": "（无技能）", "sdesc": "纯战斗兵蜂：攻击 3 / 速度 1 / 生命 4 / 射程 2。",
		"stags": "兵蜂"},
	# A5《美术资源图鉴》「力场蜂巢」「力场炮台」：被动 —— 相邻己方单位获得 1 层力场
	{"art": "卡牌b1-蜂巢", "name": "力场蜂巢", "kind": "building", "cost": 3, "atk": 0, "spd": 0, "hp": 3, "range": 0, "refund": 1,
		"sk": "【被动】力场", "sdesc": "相邻己方单位获得 1 层「力场」：每层减少 2 点非指令伤害。",
		"stags": "被动 · 地域效果 · 增益 · 力场"},
	{"art": "卡牌b1-蜂巢III", "name": "力场炮台", "kind": "building", "cost": 2, "atk": 4, "spd": 0, "hp": 2, "range": 2,
		"sk": "【被动】力场", "sdesc": "相邻己方单位获得 1 层「力场」：每层减少 2 点非指令伤害。",
		"stags": "被动 · 地域效果 · 增益 · 力场"},
	# A5《美术资源图鉴》「护盾单元」：回费 1 / 套盾（支援：赋予射程内 1 个友方兵蜂护盾）
	{"art": "卡牌d2-治疗", "name": "护盾单元", "kind": "building", "cost": 2, "atk": 0, "spd": 0, "hp": 2, "range": 0, "refund": 1,
		"support": {"id": "shield_grant", "name": "护盾", "rng": 2, "buff": {"id": "shield", "name": "护盾", "layers": 1}},
		"sk": "【支援】护盾", "sdesc": "选择 2 格内的 1 个己方兵蜂，赋予「护盾」：抵挡一次攻击（参与防御计算或己方回费阶段消失）。",
		"stags": "支援 · 单位效果 · 增益 · 套盾"},
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
	{"art": "卡牌d1-电击III", "name": "X费·毁灭", "kind": "command_x", "cost": -1, "range": 3,
		"sk": "【指令】毁灭（X费）", "sdesc": "费用 = 目标单位的部署费用；对其造成「部署费用 ×2」的指令伤害。不可指定蜂王。",
		"stags": "指令 · 攻击指令 · X费"},
	{"art": "卡牌d2-治疗", "name": "回收", "kind": "command", "cost": 2, "range": 1,
		"sk": "【指令】回收", "sdesc": "使射程 1 内的 1 个己方兵蜂退场，并返还 2 点费用。",
		"stags": "指令 · 辅助指令 · 回收"},
	{"art": "卡牌d2-治疗", "name": "补给", "kind": "command", "cost": 1, "range": 0,
		"sk": "【指令】补给", "sdesc": "若当前回合 ≥3，则本回合费用 +3（不超过上限 10）。",
		"stags": "指令 · 辅助指令 · 资源"},
	{"art": "卡牌d2-治疗", "name": "轮换", "kind": "command", "cost": 1, "range": 0,
		"sk": "【指令】轮换", "sdesc": "抽取 1 张手牌（手牌上限 4 张）。",
		"stags": "指令 · 辅助指令 · 手牌"},
	{"art": "卡牌d1-电击", "name": "蜂群突袭", "kind": "command", "cost": 4, "dmg": 4, "range": 3,
		"sk": "【指令】蜂群突袭", "sdesc": "第 3 回合起且手牌 ≥2 时可用；对射程 3 内 1 个敌方单位造成 4×1.5 点伤害。",
		"stags": "指令 · 攻击指令 · 条件 · 倍率"},
	{"art": "卡牌d1-巡航导弹", "name": "扩散毒雾", "kind": "command", "cost": 4, "dmg": 2, "range": 2,
		"sk": "【指令】扩散毒雾", "sdesc": "对目标单位造成 2 点伤害，并链式传播给其上下左右相邻单位各 2 点。",
		"stags": "指令 · 攻击指令 · 链式传播"},
	{"art": "卡牌d1-电击III", "name": "精确打击", "kind": "command", "cost": 5, "dmg": 5, "range": 3,
		"sk": "【指令】精确打击", "sdesc": "仅对敌方兵蜂造成 5 点伤害（1 格溅射），不会误伤己方。",
		"stags": "指令 · 攻击指令 · 过滤"},
	{"art": "卡牌d2-治疗", "name": "蜂粮储备", "kind": "command", "cost": 1, "range": 0,
		"sk": "【指令】蜂粮储备", "sdesc": "当前费用 ≤5 时可用；本回合费用 +2。",
		"stags": "指令 · 辅助指令 · 资源"},
]

## ============================================================
## 结构化技能表（依据《技能结构.md》；术语以 a500 为准）
## 结构：{id, name, source, conditions{all/any/not/multiplier}, targets{}, effects[], sk, sdesc, stags}
##   source    : command 指令 / support 支援 / passive 被动
##   targets   : {mode: self|single|cell, kind, side, range, splash, chain}
##   effects[] : {type: damage|modify|resource|deploy|recycle|move|hand, value, ...}
##   conditions: 7 维度叶子 {dim, key, op, value}；含 multiplier 时按「基础值 × 倍率」结算
## ============================================================
const SKILLS := {
	"鼓舞": {
		"id": "rally", "name": "鼓舞", "source": "support",
		"sk": "【支援】鼓舞", "stags": "支援 · 单位效果 · 增益",
		"sdesc": "选择 2 格内的 1 个己方单位，赋予「攻击提升」：攻击力 +1。使用后结束该单位行动。",
		"conditions": {"all": [{"dim": "unit_pos", "key": "in_map", "op": "==", "value": true}]},
		"targets": {"mode": "single", "kind": "any", "side": "ally", "range": 2},
		"effects": [{"type": "modify", "id": "atk_up", "value": 1,
			"effect": {"id": "atk_up", "name": "攻击提升", "atk_add": 1}}],
	},
	"护卫": {
		"id": "guard", "name": "护卫", "source": "support",
		"sk": "【支援】护卫", "stags": "支援 · 单位效果 · 增益",
		"sdesc": "选择 1 格内的 1 个己方单位，赋予「护甲」：抵挡一次攻击，参与防御计算则消失（A5 效果图鉴）。使用后结束该单位行动。",
		"conditions": {"all": [{"dim": "unit_pos", "key": "in_map", "op": "==", "value": true}]},
		"targets": {"mode": "single", "kind": "any", "side": "ally", "range": 1},
		"effects": [{"type": "modify", "id": "armor", "value": 1,
			"effect": {"id": "armor", "name": "护甲", "reduce": 1}}],
	},
	"护盾": {
		"id": "shield_grant", "name": "护盾", "source": "support",
		"sk": "【支援】护盾", "stags": "支援 · 单位效果 · 增益",
		"sdesc": "选择 2 格内的 1 个己方兵蜂，赋予「护盾」：抵挡一次攻击（参与防御计算或己方回费阶段消失）。使用后结束该单位行动。",
		"conditions": {"all": [{"dim": "unit_pos", "key": "in_map", "op": "==", "value": true}]},
		"targets": {"mode": "single", "kind": "soldier", "side": "ally", "range": 2},
		"effects": [{"type": "modify", "id": "shield", "value": 1,
			"effect": {"id": "shield", "name": "护盾", "layers": 1}}],
	},
	"力场": {
		"id": "force_field_aura", "name": "力场", "source": "passive",
		"sk": "【被动】力场", "stags": "被动 · 地域效果 · 增益",
		"sdesc": "相邻己方单位获得 1 层「力场」：每层减少 2 点非指令伤害（A5 效果图鉴）。",
		"conditions": {},
		"targets": {"mode": "self", "aura": "force_field", "aura_layers": 1},
		"effects": [],
	},
	"机场": {
		"id": "airfield", "name": "机场", "source": "passive",
		"sk": "【机场】蜂王巢口", "stags": "被动 · 部署 · 蜂王",
		"sdesc": "部署阶段可在自身相邻格部署兵蜂；蜂王免疫指令卡伤害与减益。",
		"conditions": {},
		"targets": {"mode": "self"},
		"effects": [{"type": "deploy", "value": 1}],
	},
	"电击": {
		"id": "shock", "name": "电击", "source": "command",
		"sk": "【指令】电击", "stags": "指令 · 攻击指令 · 单体",
		"sdesc": "对射程 2 内的 1 个单位造成 4 点指令伤害，蜂王免疫。",
		"conditions": {},
		"targets": {"mode": "single", "kind": "any", "side": "any", "range": 2},
		"effects": [{"type": "damage", "value": 4}],
	},
	"治疗": {
		"id": "heal", "name": "治疗", "source": "command",
		"sk": "【指令】治疗", "stags": "指令 · 辅助指令 · 单体",
		"sdesc": "为射程 2 内的 1 个己方单位恢复 4 点生命值。",
		"conditions": {},
		"targets": {"mode": "single", "kind": "any", "side": "ally", "range": 2},
		"effects": [{"type": "modify", "id": "heal_up", "value": 4,
			"effect": {"id": "regen", "name": "治疗", "heal": 4, "instant_heal": true}}],
	},
	"巡航导弹": {
		"id": "cruise", "name": "巡航导弹", "source": "command",
		"sk": "【指令】巡航导弹", "stags": "指令 · 攻击指令 · 溅射",
		"sdesc": "对目标格及其 1 格溅射范围内的所有单位造成 4 点指令伤害。",
		"conditions": {},
		"targets": {"mode": "cell", "splash": 1},
		"effects": [{"type": "damage", "value": 4}],
	},
	"蜂群共鸣": {
		"id": "swarm", "name": "蜂群共鸣", "source": "passive",
		"sk": "【蜂群共鸣】被动", "stags": "被动 · 单位效果 · 增益 · 倍率",
		"sdesc": "若己方单位数 ≥3，则为 2 格内的己方单位赋予「蜂群」：攻击力 +1（倍率随己方单位数提升）。",
		"conditions": {"all": [{"dim": "unit_pos", "key": "in_map", "op": "==", "value": true}],
			"multiplier": 1.0},
		"targets": {"mode": "single", "kind": "any", "side": "ally", "range": 2, "chain": false},
		"effects": [{"type": "modify", "id": "swarm", "value": 1,
			"effect": {"id": "swarm", "name": "蜂群", "atk_add": 1}}],
	},
	"回收": {
		"id": "salvage", "name": "回收", "source": "command",
		"sk": "【指令】回收", "stags": "指令 · 辅助指令 · 回收",
		"sdesc": "使射程 1 内的 1 个己方兵蜂退场，并返还 2 点费用。",
		"conditions": {},
		"targets": {"mode": "single", "kind": "soldier", "side": "ally", "range": 1},
		"effects": [{"type": "recycle", "value": 1},
			{"type": "resource", "value": 2, "gain": true}],
	},
	"补给": {
		"id": "supply", "name": "补给", "source": "command",
		"sk": "【指令】补给", "stags": "指令 · 辅助指令 · 资源",
		"sdesc": "若当前回合 ≥3，则本回合费用 +3（无法超过上限 10）。",
		"conditions": {"all": [{"dim": "round", "key": "now", "op": ">=", "value": 3}], "multiplier": 1.0},
		"targets": {"mode": "self"},
		"effects": [{"type": "resource", "value": 3, "gain": true}],
	},
	"轮换": {
		"id": "rotate", "name": "轮换", "source": "command",
		"sk": "【指令】轮换", "stags": "指令 · 辅助指令 · 手牌",
		"sdesc": "抽取 1 张手牌（手牌上限 4 张）。",
		"conditions": {"all": [{"dim": "hand", "key": "count", "op": "<", "value": 4}]},
		"targets": {"mode": "self"},
		"effects": [{"type": "hand", "value": 1}],
	},
	"X费·毁灭": {
		"id": "ruin_x", "name": "X费·毁灭", "source": "command",
		"sk": "【指令】毁灭（X费）", "stags": "指令 · 攻击指令 · X费",
		"sdesc": "费用 = 目标单位的部署费用；对其造成「部署费用 × 2」的指令伤害，不可指定蜂王。",
		"conditions": {},
		"targets": {"mode": "single", "kind": "any", "side": "any"},
		"effects": [{"type": "damage", "value": 0, "by_target_cost": true}],
	},

	# ---------------- 检查点3/4 样例：覆盖「位移类」与「链式传播」 ----------------
	"蜂群转移": {
		"id": "swarm_move", "name": "蜂群转移", "source": "support",
		"sk": "【支援】蜂群转移", "stags": "支援 · 位移类 · 单位效果",
		"sdesc": "支援射程 2 内的 1 个己方单位，使其获得「疾行」（移动力 +1）。使用后结束该单位行动。",
		"conditions": {},
		"targets": {"mode": "single", "kind": "any", "side": "ally", "range": 2},
		"effects": [{"type": "modify", "id": "haste", "value": 1,
			"effect": {"id": "haste", "name": "疾行", "spd_add": 1}}],
	},
	"扩散毒雾": {
		"id": "toxic_chain", "name": "扩散毒雾", "source": "command",
		"sk": "【指令】扩散毒雾", "stags": "指令 · 攻击指令 · 链式传播",
		"sdesc": "对目标格单位造成 2 点指令伤害，并链式传播给其上下左右相邻单位各 2 点（蜂王免疫）。",
		"conditions": {},
		"targets": {"mode": "single", "kind": "any", "side": "any", "chain": true},
		"effects": [{"type": "damage", "value": 2, "chainable": true}],
	},

	# ---------------- 检查点6 样例：**启用单位过滤**（与「不过滤」的巡航导弹形成对照） ----------------
	"精确打击": {
		"id": "precision", "name": "精确打击", "source": "command",
		"sk": "【指令】精确打击", "stags": "指令 · 攻击指令 · 过滤",
		"sdesc": "（描述由数据自动生成）",
		"conditions": {},
		# 过滤能力启用：side=enemy + kind=soldier；filter 里还可加血量阈值 / 已有效果 / 排除自身等
		"targets": {"mode": "cell", "splash": 1,
			"filter": {"side": "enemy", "kind": "soldier", "exclude_source": true}},
		"effects": [{"type": "damage", "value": 5}],
	},

	# ---------------- 检查点8 样例：**纯数据新增**（不改任何逻辑代码即可生效） ----------------
	"蜂群突袭": {
		"id": "assault", "name": "蜂群突袭", "source": "command",
		"sk": "【指令】蜂群突袭", "stags": "指令 · 攻击指令 · 条件 · 倍率",
		"sdesc": "（描述由数据自动生成）",
		"conditions": {"all": [
			{"dim": "round", "key": "now", "op": ">=", "value": 3},
			{"dim": "hand", "key": "count", "op": ">=", "value": 2},
		], "multiplier": 1.5},
		"targets": {"mode": "single", "kind": "any", "side": "enemy", "range": 3},
		"effects": [{"type": "damage", "value": 4}],
	},
	"工蜂修筑": {
		"id": "fortify", "name": "工蜂修筑", "source": "support",
		"sk": "【支援】工蜂修筑", "stags": "支援 · 单位效果 · 上限提升",
		"sdesc": "（描述由数据自动生成）",
		"conditions": {},
		"targets": {"mode": "single", "kind": "any", "side": "ally", "range": 1},
		"effects": [{"type": "modify", "id": "tough", "value": 1,
			"effect": {"id": "tough", "name": "坚固", "hp_add": 2}}],
	},
	"蜂粮储备": {
		"id": "granary", "name": "蜂粮储备", "source": "command",
		"sk": "【指令】蜂粮储备", "stags": "指令 · 辅助指令 · 资源",
		"sdesc": "（描述由数据自动生成）",
		"conditions": {"all": [{"dim": "cost", "key": "now", "op": "<=", "value": 5}]},
		"targets": {"mode": "self"},
		"effects": [{"type": "resource", "value": 2, "gain": true}],
	},
}


## 取技能定义（无该技能返回 {}）
static func skill(nm: String) -> Dictionary:
	return SKILLS.get(nm, {})
## 出战中涉及的卡（迭代006：补入 蜂巢III —— 它在卡池内且**有图标素材**，但此前两个卡组表都没用到它）
const DECK_LIST := ["叶蜂", "叶蜂", "泥蜂", "泥蜂", "熊蜂", "蜂巢", "蜂巢III", "电击", "治疗", "护盾单元", "力场蜂巢", "力场炮台"]

## 对战地图池（a500 对战准备 4：抽取对战地图）
## ⚠️ 迭代005.1（人明确）：地图上的特殊地形**由地图素材自带**（制作地图时直接画好），
##   游戏内**不再额外绘制地形标签/图标**；地形格坐标等**地图素材到位后**再填 `terrain_cells`。
## 地图名取自《电子蜂A5策划案》场地效果表（6 张）；其**场地效果细则同样待素材/细则到位后落地**
##   （A5策划案：默认=无 · 铁锈=地形格获得 1 层力场 · 寒潮=第3/6/9/12回合扣 2 血(蜂王除外)
##     · 禁区=障碍地形不可部署 · 丰饶=第3/9回合额外回费 4 · 水没=地形格减 2 指令伤害）。
##   现状：全部 `terrain_cells` 为空 → 不影响数值；效果字段留空以免自造规则。
const MAP_POOL := [
	{"name": "默认", "terrain_cells": []},
	{"name": "铁锈", "terrain_cells": []},
	{"name": "寒潮", "terrain_cells": []},
	{"name": "禁区", "terrain_cells": []},
	{"name": "丰饶", "terrain_cells": []},
	{"name": "水没", "terrain_cells": []},
]


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

## 迭代013（G-30）：该卡是否「借用」他人立绘 —— 判定：art 名里不含卡名本身
##   （如「补给」用 卡牌d2-治疗.png → 借用；「叶蜂」用 卡牌c1-叶蜂.png → 非借用）
static func is_borrowed_art(d: Dictionary) -> bool:
	var nm := str(d.get("name", ""))
	var art := str(d.get("art", ""))
	if nm == "" or art == "":
		return false
	return not art.contains(nm)


## 实例化一张框架卡牌（复用 card_auto.tscn）
## icon_tex_path 非空 → 用「图标」素材作中央立绘（迭代006）
## bare=true → **精简卡面（迭代006 修正，人明确）**：只显示左上角费用，隐藏左右两侧信息栏
##   （触发点/数值/类别角标全部 -1；空白格底调成与卡底同色，观感上"两侧栏消失"）
## name_pos.y >= 0 → 卡面加一行卡名文字（**本轮已按要求停用，改由技能框显示卡名**）
static func make_card(d: Dictionary, sc: float, icon_tex_path := "", name_pos := Vector2(-1, -1), bare := false) -> Node2D:
	var node := CARD_RES.instantiate()
	node.scale = Vector2(sc, sc)
	var tex: Texture2D = null
	var use_icon := str(icon_tex_path) != ""
	if use_icon:
		tex = load(str(icon_tex_path)) as Texture2D
	if tex == null:
		tex = load(ART_DIR + str(d["art"]) + ".png") as Texture2D      # 无图标素材 → 回退旧卡面立绘
		use_icon = false
	node.set("art", tex)
	# 迭代013（G-07）：蜂王卡面角落显示**每回合回费量**（A5：蜂王不显示部署费用）；其余卡显示部署费用
	node.set("cost", int(d.get("refund", d["cost"])))
	node.set("art_fit", 1)
	# 图标是"画好留白"的方形素材：用 zoom 1.0 保留全部内容；旧卡面沿用 1.05 的裁边观感
	node.set("art_zoom", 1.0 if use_icon else 1.05)
	if bare:
		# 精简卡面：四角数值/图标全部隐藏（渲染以 -1 为"不显示"），并抹掉空白格底避免出现方格
		node.set("stat_l1", -1)
		node.set("stat_l2", -1)
		node.set("stat_r1", -1)
		node.set("stat_r2", -1)
		node.set("icon_l1", -1)
		node.set("icon_l2", -1)
		node.set("icon_r1", -1)
		node.set("icon_r2", -1)
		node.set("icon_tag", -1)                     # 类别角标也不显示
		node.set("col_cell", Color(1, 1, 1, 1))      # 空白格底 → 与卡底同色（视觉上两侧栏消失）
		node.set("col_band", Color(1, 1, 1, 1))      # 横带/分隔条同样抹平
		return node
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
	if name_pos.y >= 0.0:
		node.add_child(make_name_label(str(d["name"]), name_pos))
	return node


## 卡名文字（迭代006）：深底浅字
## ⚠️ 坐标契约：`pos` 是 **overlay 坐标系下的屏幕坐标（1920×1080 设计空间）**。
##   必须挂在 Overlay 上（其父链无缩放）；**不要挂到 Holder/卡节点下** ——
##   那里叠了 Holder 0.6 × 卡节点 0.76 两层缩放，位置与字号都会被再缩一次（本轮已踩此坑）。
static func make_name_label(nm: String, pos: Vector2, box_w := 190.0, fs := 22, bg_a := 0.74) -> Node2D:
	var root := Node2D.new()
	root.name = "NamePlate"
	root.position = pos
	var bg := ColorRect.new()
	bg.name = "NameBg"
	bg.color = Color(0.08, 0.08, 0.08, bg_a)
	bg.size = Vector2(box_w, float(fs) + 10.0)
	bg.position = Vector2(-box_w * 0.5, -(float(fs) + 10.0) * 0.5)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE          # 绝不拦截点击
	if bg_a > 0.0:
		root.add_child(bg)
	# 无底色时（详情卡名压在卡面名称带上）加字影，保证在灰底上也读得清
	if bg_a <= 0.0:
		var sh := Label.new()
		sh.name = "NameShadow"
		sh.text = nm
		sh.size = Vector2(box_w, float(fs) + 10.0)
		sh.position = Vector2(-box_w * 0.5 + 2.0, -(float(fs) + 10.0) * 0.5 + 2.0)
		sh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sh.add_theme_font_size_override("font_size", fs)
		sh.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 0.85))
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(sh)
	var l := Label.new()
	l.name = "NameText"
	l.text = nm
	l.size = Vector2(box_w, float(fs) + 10.0)
	l.position = Vector2(-box_w * 0.5, -(float(fs) + 10.0) * 0.5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return root


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
