extends SceneTree
## 【守卫脚本】Godot 工程仓「裸改文件」合规自检
##
## 为何存在：AI 执行协议 v2.2《Godot 工程文件的交互铁律》要求
##   「与 Godot 交互必须使用 MCP 工具，而不是直接修改文件」。
##   仅靠"记住规则"不可靠 —— 本脚本把纪律变成**可机械执行**的检查。
##
## 用法：
##   Godot_v4.7.2-stable_win64.exe --headless --path <游戏仓> --script verification/rule_check.gd
##
## 检查项（均为高置信的回退信号）
##   ① 关键脚本**行数不得骤减**（被回退的典型表现：736 行完整版 → 256 行旧版）
##   ② 关键**标记必须在**（如 card_pool 引用、Preview 接入）
##   ③ `project.godot` 不得把 `BattleSignalBus` 注册为 autoload
##      （与同名 class_name 冲突，且 check-only 下不可见；已改为 preload 单例）
##
## 注：早期版本想用 `SceneTree.get_script_list()` 检查载入脚本 ——
##     经查 Godot 文档**无此 API**，故改为“直接测磁盘文件”的可靠做法。
##
## 输出 PASS/FAIL 清单；exit code 0 = 全 PASS。

## 关键脚本：相对路径 → 最少行数（低于此值几乎必然是回退）
const MIN_LINES := {
	"scenes/ui/arena_controller.gd": 600,
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
	"scenes/ui/arena_controller.gd": "card_pool.gd",
	"scripts/battle/battle_engine.gd": "Preview.build",
	"scripts/battle/rules_preview.gd": "deploy_cells",
	"scripts/data/unit_instance.gd": "不再在此处减免",
	"scripts/data/card_pool.gd": "示范卡组",
}

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("\n===== 规则守卫自检（协议 v2.2 · Godot 工程文件的交互铁律）=====")
	_check_min_lines()
	_check_markers()
	_check_autoload()
	_check_no_clobber_marker()
	_report()
	quit(0 if _fail == 0 else 1)


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


## ④ 场景不得被回退：烤入内容必须还在
func _check_no_clobber_marker() -> void:
	var txt := FileAccess.get_file_as_string("scenes/ui/battle_scene.tscn")
	if txt == "":
		_chk("battle_scene.tscn 可读", false)
		return
	var nodes := 0
	for line in txt.split("\n"):
		if line.begins_with("[node "):
			nodes += 1
	## 烤入内容存在时节点数 >= 50（被回退后典型为 30）
	_chk("battle_scene.tscn 节点数 %d >= 50（烤入内容未被回退）" % nodes, nodes >= 50)
	_chk("battle_scene.tscn 含烤入数值（手牌费用 override）",
		txt.contains("BadgeImage\" index=\"0\"]") or txt.contains("text = \"2\""))


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
	print("=====================================================")
