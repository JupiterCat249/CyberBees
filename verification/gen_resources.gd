extends Node
## 【验证用 · 生产工具（一次性）】从 `scripts/data/card_pool.gd` 生成 `.tres` 资源文件
##
## 为什么用脚本生成而不是手写 .tres：手写极易出错（sub_resource 引用、uid、format 版本），
## 交给 Godot 的 `ResourceSaver.save()` 生成才是权威格式。
##
## 输出目录（**新增的统一资源目录**）：
##   res://game_data/cards/     卡牌（UnitData / CommandData）
##   res://game_data/effects/   效果
##   res://game_data/skills/    技能
##   res://game_data/decks/     卡组
##   res://game_data/maps/      地图
##
## 生成后立刻**回读校验**：逐个 load 回来，核对字段与源数据一致。

const CardPoolLib := preload("res://scripts/data/card_pool.gd")
const ROOT := "res://game_data"
const DIRS := ["cards", "effects", "skills", "decks", "maps"]

var _saved := 0
var _errors: Array[String] = []


func _ready() -> void:
	_make_dirs()
	_generate_cards()
	_generate_deck()
	_generate_maps()
	_verify()
	print("\n===== 资源生成报告 =====")
	print("  生成文件数：%d" % _saved)
	print("  错误数：%d" % _errors.size())
	for e in _errors:
		print("   ✗ ", e)
	print("========================")
	print("  目录：", ROOT)
	get_tree().quit(0 if _errors.is_empty() else 1)


func _make_dirs() -> void:
	for d in DIRS:
		DirAccess.make_dir_recursive_absolute(ROOT + "/" + d)


func _generate_cards() -> void:
	## ⚠️ 迭代055：**先清空旧卡资源**（人指示：删除旧资源并创建新资源）
	_clear_dir("%s/cards" % ROOT)
	for spec in CardPoolLib.CARDS:
		var card: CardData = CardPoolLib.make(spec)
		var sub := "cards"
		var path := "%s/%s/%s.tres" % [ROOT, sub, _safe(card.display_name)]
		_save(card, path)


func _generate_deck() -> void:
	# 卡组：引用上面生成出来的卡牌资源（而不是代码对象）—— 这才叫"数据驱动资源"
	var dd := DeckData.new()
	dd.id = Uuid.generate()
	dd.display_name = "示范卡组"
	var by_name := {}
	var specs_by_name := {}
	for spec in CardPoolLib.CARDS:
		specs_by_name[spec["name"]] = spec
	# 先把卡牌资源按名字加载进来
	for spec in CardPoolLib.CARDS:
		var p := "%s/cards/%s.tres" % [ROOT, _safe(spec["name"])]
		if ResourceLoader.exists(p):
			by_name[spec["name"]] = load(p)
	for nm in CardPoolLib.DECK_NAMES:
		if by_name.has(nm):
			dd.cards.append(by_name[nm])
	dd.queen = by_name.get("金刚蜂王", null)
	_save(dd, "%s/decks/示范卡组.tres" % ROOT)


## 生成 6 张地图资源 —— 名字与场地效果**逐条对照《电子蜂A5策划案.md》§场地效果表**
##   · 默认 = 无特殊效果
##   · 铁锈 = 位于特殊地形的单位获得 [1] 层 [力场]
##   · 寒潮 = 第 3、6、9、12 回合场地阶段，所有己方单位 -2 生命（蜂王除外）
##   · 禁区 = 障碍地形无法部署单位（但**不阻挡移动与攻击**）
##   · 丰饶 = 第 3、9 回合额外回复 4 点费用
##   · 水没 = 位于特殊地形的单位减少 2 点指令伤害（拦截效果）
##
## ⚠️ `terrain_cells`（特殊地形格坐标）：策划案 §一 明确「地形由地图**素材**自带」——
##    坐标在制作地图时直接画好，故此处留空，**素材到位后回填**（与旧实现口径一致）。
var MAP_SPECS := [
	{
		"name": "默认",
		"desc": "场地效果：无特殊效果。",
		"rounds": [], "refund": 0, "dmg": 0, "field": false,
	},
	{
		"name": "铁锈",
		"desc": "场地效果：位于特殊地形的单位获得 1 层[力场]效果。",
		"rounds": [], "refund": 0, "dmg": 0, "field": true,
	},
	{
		"name": "寒潮",
		"desc": "场地效果：第 3、6、9、12 回合的场地阶段，所有己方单位减少 2 点生命值（蜂王除外）。",
		"rounds": [3, 6, 9, 12], "refund": 0, "dmg": 2, "field": false,
	},
	{
		"name": "禁区",
		"desc": "场地效果：障碍地形无法部署单位，但不会阻挡移动与攻击。",
		"rounds": [], "refund": 0, "dmg": 0, "field": false,
	},
	{
		"name": "丰饶",
		"desc": "场地效果：第 3、9 回合玩家额外回复 4 点费用。",
		"rounds": [3, 9], "refund": 4, "dmg": 0, "field": false,
	},
	{
		"name": "水没",
		"desc": "场地效果：位于特殊地形的单位减少 2 点指令伤害（拦截效果）。",
		"rounds": [], "refund": 0, "dmg": 0, "field": false,
	},
]


func _generate_maps() -> void:
	## 地图板贴图（terrain）：棋盘底图 1000×1000
	var tex: Texture2D = null
	if ResourceLoader.exists("res://assets/background/map_terrain.png"):
		tex = load("res://assets/background/map_terrain.png")
	## 全屏背景（background）：1920×1080 —— 迭代057 新增
	##   人已建好 `Background/TextureRect` 并要求「解耦调用」，故资源里必须真有这张图，
	##   否则该节点永远为空。当前 6 张图共用同一张模糊底（分地图素材到位后逐张换）。
	var bg: Texture2D = null
	if ResourceLoader.exists("res://assets/background/bg_blurred.png"):
		bg = load("res://assets/background/bg_blurred.png")
	for spec in MAP_SPECS:
		var md := MapData.new()
		md.id = Uuid.generate()
		md.display_name = String(spec["name"])
		md.description = String(spec["desc"])
		md.effect_rounds = PackedInt32Array(spec["rounds"])
		md.refund_bonus = int(spec["refund"])
		md.damage_per_round = int(spec["dmg"])
		md.grant_field_on_terrain = bool(spec["field"])
		if tex != null:
			md.terrain_texture = tex
		if bg != null:
			md.background_texture = bg
		_save(md, "%s/maps/%s.tres" % [ROOT, _safe(String(spec["name"]))])


## 删除目录下的旧资源（含 .import/.uid 边车）
func _clear_dir(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	var removed := 0
	for f in d.get_files():
		if d.remove(f) == OK:
			removed += 1
	print("  已清空旧资源：%s（%d 个文件）" % [dir_path, removed])


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err == OK:
		_saved += 1
	else:
		_errors.append("保存失败(%d)：%s" % [err, path])


func _safe(nm: String) -> String:
	# 文件名去掉路径不友好字符
	var out := nm.replace("/", "_").replace("\\", "_").replace(":", "_")
	return out


# ---------------- 回读校验 ----------------

func _verify() -> void:
	print("===== 回读校验 =====")
	var n_cards := 0
	for spec in CardPoolLib.CARDS:
		var path := "%s/cards/%s.tres" % [ROOT, _safe(spec["name"])]
		if not ResourceLoader.exists(path):
			_errors.append("回读缺失：" + path)
			continue
		var r: Resource = load(path)
		if r == null:
			_errors.append("回读为 null：" + path)
			continue
		n_cards += 1
		# 逐字段核对
		var src: CardData = CardPoolLib.make(spec)
		if r.display_name != src.display_name:
			_errors.append("%s 卡名不符" % path)
		if int(r.get("cost")) != int(src.get("cost")):
			_errors.append("%s cost 不符：%s vs %s" % [path, r.get("cost"), src.get("cost")])
		if r.kind != src.kind:
			_errors.append("%s kind 不符" % path)
		var us := src as UnitData
		var ur := r as UnitData
		if us != null and ur != null:
			if ur.atk != us.atk or ur.hp != us.hp or ur.attack_range != us.attack_range or ur.refund != us.refund:
				_errors.append("%s 四维不符" % path)
		var cs := src as CommandData
		var cr := r as CommandData
		if cs != null and cr != null:
			if cr.dmg != cs.dmg or cr.heal != cs.heal or cr.target_range != cs.target_range:
				_errors.append("%s 指令数值不符" % path)
	print("  卡牌回读：%d / %d" % [n_cards, CardPoolLib.CARDS.size()])
	# 卡组
	var dp := "%s/decks/示范卡组.tres" % ROOT
	if ResourceLoader.exists(dp):
		var dd: DeckData = load(dp)
		var ok: bool = dd != null and dd.cards.size() == 8 and dd.queen != null
		print("  卡组回读：%d 张，蜂王=%s → %s" % [
			dd.cards.size() if dd != null else -1,
			dd.queen.display_name if (dd != null and dd.queen != null) else "null",
			"OK" if ok else "不符"])
		if not ok:
			_errors.append("卡组回读不符")
		# 校验卡组里引用的确实是**资源**（有 resource_path）而不是代码对象
		if dd != null and dd.queen != null:
			print("  蜂王资源路径：", dd.queen.resource_path)
			if dd.queen.resource_path == "":
				_errors.append("卡组引用的蜂王不是磁盘资源")
	else:
		_errors.append("卡组资源缺失")
	# 地图（6 张）
	var n_maps := 0
	for spec in MAP_SPECS:
		var mp := "%s/maps/%s.tres" % [ROOT, _safe(String(spec["name"]))]
		if not ResourceLoader.exists(mp):
			_errors.append("地图资源缺失：" + mp)
			continue
		var md: MapData = load(mp)
		if md == null:
			_errors.append("地图回读为 null：" + mp)
			continue
		n_maps += 1
		if md.display_name != String(spec["name"]):
			_errors.append("%s 地图名不符" % mp)
		if md.effect_rounds != PackedInt32Array(spec["rounds"]) or md.refund_bonus != int(spec["refund"]) 				or md.damage_per_round != int(spec["dmg"]) 				or md.grant_field_on_terrain != bool(spec["field"]):
			_errors.append("%s 场地效果字段不符" % mp)
		print("  地图回读：%-4s 回费+%d 每回合伤害%d 力场=%s 回合=%s" % [
			md.display_name, md.refund_bonus, md.damage_per_round,
			str(md.grant_field_on_terrain), str(md.effect_rounds)])
	print("  地图回读：%d / %d" % [n_maps, MAP_SPECS.size()])
