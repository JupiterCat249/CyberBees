extends Node
## 【验证用 · 生产工具（一次性）】从 `scripts/data/sample_deck.gd` 生成 `.tres` 资源文件
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

const SampleDeckLib := preload("res://scripts/data/sample_deck.gd")
const ROOT := "res://game_data"
const DIRS := ["cards", "effects", "skills", "decks", "maps"]

var _saved := 0
var _errors: Array[String] = []


func _ready() -> void:
	_make_dirs()
	_generate_cards()
	_generate_deck()
	_generate_map_stub()
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
	for spec in SampleDeckLib.CARD_SPECS:
		var card: CardData = SampleDeckLib._make(spec)
		var sub := "cards"
		var path := "%s/%s/%s.tres" % [ROOT, sub, _safe(card.display_name)]
		_save(card, path)


func _generate_deck() -> void:
	# 卡组：引用上面生成出来的卡牌资源（而不是代码对象）—— 这才叫"数据驱动资源"
	var dd := DeckData.new()
	dd.id = Uuid.generate()
	dd.display_name = "样例卡组"
	var by_name := {}
	var specs_by_name := {}
	for spec in SampleDeckLib.CARD_SPECS:
		specs_by_name[spec["name"]] = spec
	# 先把卡牌资源按名字加载进来
	for spec in SampleDeckLib.CARD_SPECS:
		var p := "%s/cards/%s.tres" % [ROOT, _safe(spec["name"])]
		if ResourceLoader.exists(p):
			by_name[spec["name"]] = load(p)
	for nm in SampleDeckLib.DECK_NAMES:
		if by_name.has(nm):
			dd.cards.append(by_name[nm])
	dd.queen = by_name.get("金刚蜂王", null)
	_save(dd, "%s/decks/样例卡组.tres" % ROOT)


func _generate_map_stub() -> void:
	# 地图：本轮只落 schema（场地效果细则仍缺 G-26）
	var md := MapData.new()
	md.id = Uuid.generate()
	md.display_name = "丰饶"
	md.description = "场地效果：第3、9回合玩家额外回复4点费用（细则待策划确认 · G-26）"
	md.effect_rounds = PackedInt32Array([3, 9])
	md.refund_bonus = 4
	if ResourceLoader.exists("res://assets/background/map_terrain.png"):
		md.terrain_texture = load("res://assets/background/map_terrain.png")
	_save(md, "%s/maps/丰饶.tres" % ROOT)


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
	for spec in SampleDeckLib.CARD_SPECS:
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
		var src: CardData = SampleDeckLib._make(spec)
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
	print("  卡牌回读：%d / %d" % [n_cards, SampleDeckLib.CARD_SPECS.size()])
	# 卡组
	var dp := "%s/decks/样例卡组.tres" % ROOT
	if ResourceLoader.exists(dp):
		var dd: DeckData = load(dp)
		var ok: bool = dd != null and dd.cards.size() == 12 and dd.queen != null
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
	# 地图
	var mp := "%s/maps/丰饶.tres" % ROOT
	if ResourceLoader.exists(mp):
		var md: MapData = load(mp)
		print("  地图回读：%s（回费 +%d @ 第 %s 回合）" % [
			md.display_name, md.refund_bonus, str(md.effect_rounds)])
	else:
		_errors.append("地图资源缺失")
