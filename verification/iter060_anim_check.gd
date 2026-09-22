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
	## 0) 数据驱动装载：`game_data/anims/*.tres` → Pattern 库
	var names: Array[StringName] = player.pattern_names()
	_check(names.size() == 12, "库装载 12 条 Pattern（实际 %d：%s）" % [names.size(), str(names)])

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

	## 4) 规则3（§一之4 line 28）：终止**级联**到子 Pattern
	var cb := ClipLib.new()
	cb.kind = ClipLib.Kind.TINT
	cb.frames = 30
	var ub := UnitLib.new()
	ub.unit_name = "子"
	ub.clips = [cb]
	var pb := PatternLib.new()
	pb.pattern_name = "冒烟-子"
	pb.units = [ub]
	player.register(pb)
	var ca := ClipLib.new()
	ca.kind = ClipLib.Kind.TINT
	ca.frames = 30
	var ua := UnitLib.new()
	ua.unit_name = "父"
	ua.clips = [ca]
	var pa := PatternLib.new()
	pa.pattern_name = "冒烟-父"
	pa.trigger_on_start = "冒烟-子"
	pa.units = [ua]
	player.register(pa)
	player.action("冒烟-父", tgt)
	_check(player.is_running("冒烟-父") and player.is_running("冒烟-子"), "规则2：A 开始时触发 B（两者并行在跑）")
	player.stop("冒烟-父")
	_check(not player.is_running("冒烟-父") and not player.is_running("冒烟-子"), "规则3：停 A → 级联停 B")

	## 5) 规则2 的条件判断：value 门控
	var cc := ClipLib.new()
	cc.kind = ClipLib.Kind.TINT
	cc.frames = 2
	cc.condition = ClipLib.Cond.VALUE_GTE
	cc.cond_value = 7
	cc.on_start_trigger = "冒烟-子"
	var uc := UnitLib.new()
	uc.unit_name = "带条件"
	uc.clips = [cc]
	var pc := PatternLib.new()
	pc.pattern_name = "冒烟-条件"
	pc.units = [uc]
	player.register(pc)
	player.action("冒烟-条件", tgt, 3)
	player._step("冒烟-条件#%d" % tgt.get_instance_id())
	_check(not player.is_running("冒烟-子"), "规则2：value=3 < 7 → 条件不成立、不触发")
	player.stop_all()
	player.action("冒烟-条件", tgt, 9)
	player._step("冒烟-条件#%d" % tgt.get_instance_id())
	_check(player.is_running("冒烟-子"), "规则2：value=9 ≥ 7 → 条件成立、触发 B")
	player.stop_all()

	print("=== 结果：%d PASS / %d FAIL ===" % [_pass, _fail])
	await get_tree().create_timer(0.6).timeout
	get_tree().quit(1 if _fail > 0 else 0)
