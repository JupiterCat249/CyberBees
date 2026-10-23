extends RefCounted
## 单位卡**数据装配**（自 arena_view._unit_view / _effect_badges / _effect_icon 切出 —— 迭代112）
##
## 判据：只把 UnitInstance 读成"卡面要绑的字典"，**不碰节点、不读视图状态**（除了 my_seat 与图标缓存）。
##   ⇒ 既是纯函数（可单测），也让视图那三个函数整体消失而不是变薄。
##
## ⚠️ 口径（与切分前逐字段一致）：
##   · type 映射：QUEEN→queen · BUILDING→building · COMMAND/COMMAND_X→order · 其余→unit；
##   · mine = (inst.side == my_seat)：联机下"每个玩家看到自己都是绿方"；
##   · effects **只取 inst.effects**（运行态）；卡牌自带被动在 UnitData.passives，绝不进徽标。

const CardKindLib := preload("res://src/data/card_kind.gd")
const STATUS_ICON_DIR := "res://assets/status_icons/"


## 单位卡类型键（供卡面切类型图标/底色）
static func type_key(inst: UnitInstance) -> String:
	if inst == null or inst.data == null:
		return "unit"
	match int(inst.data.kind):
		CardKindLib.Kind.QUEEN: return "queen"
		CardKindLib.Kind.BUILDING: return "building"
		CardKindLib.Kind.COMMAND, CardKindLib.Kind.COMMAND_X: return "order"
	return "unit"


## UnitInstance → 卡面绑定字典（**含立绘**，否则卡面永远是场景默认图）
static func unit_view(inst: UnitInstance, my_seat: int) -> Dictionary:
	if inst == null:
		return {}
	var art = null
	var nm := ""
	if inst.data != null:
		nm = inst.data.display_name
		if inst.data.visual != null:
			art = inst.data.visual.artwork
	return {
		"id": inst.instance_id,
		"name": nm,
		"cost": inst.data.cost if inst.data != null else 0,
		## 设计口径：蜂王左上角显示"每回合回费量"而非部署费用 ⇒ 一并下发
		"refund": inst.data.refund if inst.data != null else 0,
		"atk": inst.atk(),
		"hp": inst.current_hp,
		"move": inst.move_range(),
		"range": inst.attack_range(),
		"mine": int(inst.side) == int(my_seat),
		"type": type_key(inst),
		"art": art,
		## 持有效果（只含运行态；被动在 UnitData.passives）
		"effects": effect_badges(inst, {}),
	}


## 持有效果 → 徽标数据（供 card_unit 渲染卡面小图标条）
##   cache 由调用方持有（视图用 static 缓存；测试传 {} 即可）
static func effect_badges(inst: UnitInstance, cache: Dictionary) -> Array:
	var out: Array = []
	if inst == null:
		return out
	for e in inst.effects:
		if e == null or e.data == null:
			continue
		out.append({
			"name": String(e.data.display_name),
			"icon": effect_icon(e.data, cache),
			"debuff": bool(e.data.is_debuff),
			"turns": int(e.turns),
		})
	return out


## 效果图标解析（带缓存；null 也缓存，避免重复 ResourceLoader.exists）
##   优先级：① EffectData.icon ② 按**显示名**回退 assets/status_icons/<显示名>.png
static func effect_icon(d: EffectData, cache: Dictionary) -> Texture2D:
	if d == null:
		return null
	if d.icon != null:
		return d.icon
	var nm := String(d.display_name)
	if nm == "":
		return null
	if cache.has(nm):
		return cache[nm] as Texture2D
	var tex: Texture2D = null
	var p := STATUS_ICON_DIR + nm + ".png"
	if ResourceLoader.exists(p):
		tex = load(p) as Texture2D
	cache[nm] = tex
	return tex
