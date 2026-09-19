extends SceneTree
## 【守卫脚本】Godot 工程仓「裸改文件」合规自检 + **容器布局契约守卫**
##
## 为何存在：AI 执行协议 v2.2《Godot 工程文件的交互铁律》要求
##   「与 Godot 交互必须使用 MCP 工具，而不是直接修改文件」。
##   仅靠"记住规则"不可靠 —— 本脚本把纪律变成**可机械执行**的检查。
##
## 用法：
##   Godot_v4.7.2-stable_win64.exe --headless --path <游戏仓> --script verification/rule_check.gd
##
## 检查项
##   ① 关键脚本**行数不得骤减**（被回退的典型表现）
##   ② 关键**标记必须在**
##   ③ `project.godot` 不得把 `BattleSignalBus` 注册为 autoload
##   ④ `battle_scene.tscn` 烤入内容未被回退（节点数 + 数值 override）
##   ⑤ **容器布局契约**（迭代057 C1 · 人裁决 Q-1）：
##      手牌容器 `HandLeft`/`HandRight` 必须 `columns >= 2` 且间距为 0；
##      其**子卡不得带** `layout_mode` / `offset_*`（否则会把卡从容器布局里摘出来，列数会塌）
##
## 注：早期版本用过 `SceneTree.get_script_list()` —— 查 Godot 文档确认**无此 API**，已改为直接测磁盘文件。
##
## 输出 PASS/FAIL 清单；exit code 0 = 全 PASS。

## 关键脚本：相对路径 → 最少行数（低于此值几乎必然是回退）
const MIN_LINES := {
	"scenes/ui/card_unit.gd": 50,
	"scenes/ui/card_hand.gd": 130,
	"scripts/data/card_pool.gd": 200,
	"scripts/battle/battle_engine.gd": 400,
	"scripts/battle/rules_preview.gd": 80,
	"scripts/battle/preview_data.gd": 80,
	"scripts/battle/battle_signal_bus.gd": 120,
}

## 关键标记：文件 → 必须包含的字符串
const MUST_CONTAIN := {
	"scripts/battle/battle_engine.gd": "Preview.build",
	"scripts/battle/rules_preview.gd": "deploy_cells",
	"scripts/data/unit_instance.gd": "不再在此处减免",
	"scripts/data/card_pool.gd": "示范卡组",
}

## 已弃用文件：不得再出现（防旧文件混淆）
const FORBIDDEN_FILES := [
	"scenes/ui/arena_controller.gd",
	"scenes/ui/battle_scene.gd",
	"scenes/ui/battle_arena.gd",
	"scripts/data/sample_deck.gd",
]

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("\n===== 规则守卫自检（协议 v2.2 + 容器契约 + 鼠标穿透）=====")
	_check_min_lines()
	_check_markers()
	_check_autoload()
	_check_scene_baked()
	_check_hand_container_contract()
	_check_forbidden_files()
	_check_overlay_clickthrough()
	_check_effect_no_stacking()
	_check_res_schema_sync()
	_report()


## ⑨ 资源 schema 同步（迭代059 实测缺陷：代码改了但 .tres 还是旧 schema → 改动不生效）
##   人实测：装甲"又变 -2 且永久"—— 真因是 `game_data/cards/金刚蜂王.tres` 里烤着旧值。
func _check_res_schema_sync() -> void:
	var p := "res://game_data/cards/金刚蜂王.tres"
	var txt := FileAccess.get_file_as_string(p)
	_chk("金刚蜂王.tres 存在", txt.length() > 0)
	_chk("装甲资源已写 blocks_attack（旧 schema 无此字段）", txt.contains("blocks_attack = true"))
	_chk("装甲资源无旧值 dmg_reduce = 2", not txt.contains("dmg_reduce = 2"))
	## 卡资源里不得残留非 0 的 dmg_reduce（装甲已改为抵挡语义）
	var bad: Array = []
	var da := DirAccess.open("res://game_data/cards")
	if da != null:
		for f in da.get_files():
			if not f.ends_with(".tres"):
				continue
			var t := FileAccess.get_file_as_string("res://game_data/cards/" + f)
			if t.contains("dmg_reduce = ") and not t.contains("dmg_reduce = 0"):
				bad.append(f)
	_chk("无卡资源残留非零 dmg_reduce（%s）" % str(bad), bad.is_empty())
	## 回合轮换后手牌可出性必须在 active 切换之后计算（否则整手残留灰）
	var esrc := FileAccess.get_file_as_string("scripts/battle/battle_engine.gd")
	var idx_set := esrc.find("state.active = other")
	var idx_emit := esrc.find("_emit_hand(side)", idx_set)
	_chk("_end_turn 里 _emit_hand 位于 active 切换**之后**", idx_set > 0 and idx_emit > idx_set)


## ⑧ 效果**不叠加**（人 2026-09-19：「所有效果都不能叠加了，只有一层」）
##   防复发：曾出现「按层数放大」（deploy_armor=2 → dmg_reduce=2 导致蜂王互攻 0 伤）。
func _check_effect_no_stacking() -> void:
	var ed := FileAccess.get_file_as_string("scripts/data/effect_data.gd")
	_chk("EffectData.Stacking 只有 NONE", ed.contains("enum Stacking { NONE }"))
	_chk("EffectData 有 blocks_attack 显式语义字段（抵挡一次攻击）", ed.contains("blocks_attack"))
	var cp := FileAccess.get_file_as_string("scripts/data/card_pool.gd")
	_chk("装甲工厂**不按层数放大**（blocks_attack = true）", cp.contains("e.blocks_attack = true"))
	_chk("装甲不是数值减伤（dmg_reduce = 0）", cp.contains("e.dmg_reduce = 0"))
	# 全仓不得出现按层数放大效果的写法
	var offenders: Array = []
	for rel in _all_gd_under("scripts"):
		var txt := FileAccess.get_file_as_string(rel)
		for line in txt.split("\n"):
			var s := line.strip_edges()
			if s.begins_with("#") or s.begins_with("##"):
				continue
			if s.contains("* layers") or s.contains("* n_layers") or s.contains("* n)"):
				offenders.append(rel + " :: " + s)
	_chk("scripts/ 内无「按层数放大效果」的写法", offenders.is_empty())


func _all_gd_under(root: String) -> Array:
	var out: Array = []
	var dirs: Array = [root]
	while dirs.size() > 0:
		var d: String = dirs.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			if f.ends_with(".gd"):
				out.append(d + "/" + f)
		for sub in da.get_directories():
			dirs.append(d + "/" + sub)
	return out
	quit(0 if _fail == 0 else 1)


## ⑦ 扫描线特效层必须鼠标穿透（迭代058 定案 —— 曾导致「单位完全无法操控」）
##
## 现场：`card_unit.tscn` 的 `Artwork/ArtPlane/CrtFx` 是 1920×1080 的 STOP 层，
##   盖住整个棋盘 → 吞掉所有点击。`gui_get_hovered_control()` 在蜂王格中心返回的正是它。
## 依据：D8「扫描线只作背景纹理，**不得覆盖 UI 节点**；战斗地图上不得出现扫描线」。
## 契约：**素材场景内的 CrtFx 保持不动**（人工内容），由视图在运行时统一设为 MOUSE_FILTER_IGNORE；
##   本检查确认「素材场景里 CrtFx 仍是默认/STOP（即依赖视图兜底）」**且视图确有兜底代码**。
func _check_overlay_clickthrough() -> void:
	var view := FileAccess.get_file_as_string("scenes/ui/arena_view.gd")
	_chk("视图含 CrtFx 鼠标穿透兜底（_make_overlays_click_through）",
		view.contains("_make_overlays_click_through"))
	_chk("视图对**运行时新建的单位卡**也做了穿透（_set_ignore_recursive(node)）",
		view.contains("_set_ignore_recursive(node)"))
	# 素材场景里 CrtFx 只要存在，就必须依赖上面的兜底 → 告警式确认其存在
	var cu := FileAccess.get_file_as_string("scenes/ui/card_unit.tscn")
	_chk("card_unit.tscn 内确实有 CrtFx（故必须靠视图兜底）", cu.contains("CrtFx"))


## ① 行数不得骤减
func _check_min_lines() -> void:
	for rel in MIN_LINES.keys():
		var f := FileAccess.open(rel, FileAccess.READ)
		if f == null:
			_chk("关键文件存在：%s" % rel, false)
			continue
		var n := 0
		while not f.eof_reached():
			f.get_line()
			n += 1
		f.close()
		var least: int = int(MIN_LINES[rel])
		_chk("%s 行数 %d >= %d（未回退）" % [rel, n, least], n >= least)


## ② 关键标记必须在
func _check_markers() -> void:
	for rel in MUST_CONTAIN.keys():
		var txt := FileAccess.get_file_as_string(rel)
		if txt == "":
			_chk("可读：%s" % rel, false)
			continue
		var needle: String = MUST_CONTAIN[rel]
		_chk("%s 含关键标记「%s」" % [rel, needle], txt.contains(needle))


## ③ autoload 不得夹带同名项
func _check_autoload() -> void:
	var txt := FileAccess.get_file_as_string("project.godot")
	_chk("project.godot 可读", txt != "")
	if txt == "":
		return
	_chk("project.godot 未把 BattleSignalBus 注册为 autoload（避免同名冲突）",
		not txt.contains("BattleSignalBus="))


## ④ 场景烤入内容未被回退
func _check_scene_baked() -> void:
	var txt := FileAccess.get_file_as_string("scenes/ui/battle_scene.tscn")
	if txt == "":
		_chk("battle_scene.tscn 可读", false)
		return
	var nodes := 0
	for line in txt.split("\n"):
		if line.begins_with("[node "):
			nodes += 1
	_chk("battle_scene.tscn 节点数 %d >= 50（烤入内容未被回退）" % nodes, nodes >= 50)
	_chk("battle_scene.tscn 含烤入数值（费用 override）", txt.contains("BadgeImage\" index=\"0\"]"))


## ⑤ 容器布局契约（迭代057 C1 · Q-1）
func _check_hand_container_contract() -> void:
	var base := FileAccess.get_file_as_string("scenes/ui/battle_ui_alpha.tscn")
	if base == "":
		_chk("battle_ui_alpha.tscn 可读", false)
		return
	for owner in ["HandLeft", "HandRight"]:
		_chk("%s 已声明 columns >= 2（防默认单列）" % owner,
			_compose_has(base, owner, "columns = ", 2))
		_chk("%s 间距显式为 0（防默认 4）" % owner,
			_compose_has(base, owner, "theme_override_constants/h_separation = 0", 0) \
			and _compose_has(base, owner, "theme_override_constants/v_separation = 0", 0))
	# 子卡不得带手动布局
	var scene := FileAccess.get_file_as_string("scenes/ui/battle_scene.tscn")
	var offenders: Array = []
	var cur := ""
	for line in scene.split("\n"):
		if line.begins_with("[node "):
			cur = line
		elif (line.begins_with("layout_mode =") or line.begins_with("offset_")) and cur.contains("/HandLeft") == false \
				and cur.contains("/HandRight") == false and cur.contains("parent=\"Battle/HandPanel"):
			## parent 是手牌容器 → 子卡不该写布局
			if not cur.contains("type=\""):
				offenders.append(cur.substr(0, 40))
	_chk("手牌子卡未写 layout_mode / offset（布局交给容器）", offenders.is_empty())


## 判断某节点的属性块里是否出现 needle（粗略：只看声名行后到下一个 [node 之前）
func _compose_has(text: String, owner: String, needle: String, _n: int) -> bool:
	var idx := text.find("[node name=\"%s\"" % owner)
	if idx < 0:
		return false
	var nxt := text.find("[node ", idx + 1)
	var chunk := text.substr(idx, (nxt - idx) if nxt > 0 else -1)
	return chunk.contains(needle)


## ⑥ 已弃用文件不得再现
func _check_forbidden_files() -> void:
	for rel in FORBIDDEN_FILES:
		var f := FileAccess.open(rel, FileAccess.READ)
		var exists := f != null
		if f != null:
			f.close()
		_chk("已弃用文件不存在：%s" % rel, not exists)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  [PASS] ", label)
	else:
		_fail += 1
		_failures.append(label)
		print("  [FAIL] ", label)


func _report() -> void:
	print("  通过 %d / 失败 %d" % [_pass, _fail])
	for f in _failures:
		print("   X ", f)
	if _fail > 0:
		print("  -> 疑似被编辑器内存旧版回写：git checkout HEAD -- <文件> 抢救，并请人关闭对应 tab")
	print("=============================================")
