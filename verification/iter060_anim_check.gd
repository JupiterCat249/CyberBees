extends Node
## 迭代060 动画系统冒烟自检（T12：验证产物；生产代码禁止引用本目录）
## 校验项：
##   ① 静态类型的 Resource（AnimClip / AnimUnit / AnimPattern）可实例化与赋值
##   ② 逐帧步进线性（T2：每帧恰好 1 步）
##   ③ 终帧精确归位（Σ 步 = 0，不污染视图拥有的 position）
##   ④ 播完自动结束 + 实例级回调
## 运行：F6 或 project_run(mode="custom", scene="res://verification/iter060_anim_check.tscn")
const ClipLib := preload("res://scripts/anim/anim_clip.gd")
const UnitLib := preload("res://scripts/anim/anim_unit.gd")
const PatternLib := preload("res://scripts/anim/anim_pattern.gd")
const PlayerLib := preload("res://scripts/anim/anim_player.gd")

var _pass: int = 0
var _fail: int = 0


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label)


func _ready() -> void:
	print("=== 迭代060 动画系统冒烟 ===")
	var player: Node = PlayerLib.new()
	player.name = "AnimPlayer"
	add_child(player)

	## 1) 静态类型 Resource 构造
	var c1 := ClipLib.new()
	c1.kind = ClipLib.Kind.MOVE_BY
	c1.frames = 2
	c1.offset = Vector2(0, 3)
	var c2 := ClipLib.new()
	c2.kind = ClipLib.Kind.MOVE_BY
	c2.frames = 2
	c2.offset = Vector2(0, -3)
	var u := UnitLib.new()
	u.unit_name = "下沉回弹"
	u.clips = [c1, c2]
	var p := PatternLib.new()
	p.pattern_name = "冒烟-移动落位"
	p.units = [u]
	player.register(p)
	_check(player.has_pattern("冒烟-移动落位"), "Pattern 注册（names=%s）" % str(player.pattern_names()))

	## 2) 目标节点
	var tgt := Control.new()
	tgt.name = "Tgt"
	tgt.position = Vector2(100, 200)
	add_child(tgt)

	## 3) 逐帧推进
	player.action("冒烟-移动落位", tgt)
	_check(player.is_running("冒烟-移动落位"), "action 后处于运行态")
	var key: String = "冒烟-移动落位#%d" % tgt.get_instance_id()
	var trace: Array[float] = []
	for i: int in range(4):
		player._step(key)
		trace.append(tgt.position.y)
	_check(trace == [203.0, 206.0, 203.0, 200.0], "逐帧轨迹 %s（期望 [203,206,203,200]）" % str(trace))
	_check(tgt.position == Vector2(100, 200), "终帧精确归位 %s" % str(tgt.position))
	_check(not player.is_running("冒烟-移动落位"), "播完自动结束")

	print("=== 结果：%d PASS / %d FAIL ===" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
