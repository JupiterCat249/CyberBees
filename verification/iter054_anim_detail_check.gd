extends Node
## 【验证用 · 非生产】迭代054 动画系统 + 详情区 专项自检
##
## 目的：按"接通前先两两对照"的要求，逐条验证
##   ① 详情区：节点存在性（脚本期望 vs 场景实际）+ 真实绑定效果
##   ② Action Unit：帧数计时（T2）、围绕原位对称、高伤害延长、退场时序、UI 锁
##   ③ 资源：.tres 与代码数据逐字段一致（生成侧已校，此处再抽查）

const AU := preload("res://scripts/game/action_unit.gd")
const Presets := preload("res://scripts/game/anim_presets.gd")
const Driver := preload("res://scripts/game/battle_anim_driver.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []

var _scene: Control = null


func _ready() -> void:
	_test_detail_node_paths()
	_scene = (load("res://scenes/ui/battle_scene.tscn") as PackedScene).instantiate()
	add_child(_scene)
	for i in 30:
		await get_tree().process_frame
	await _test_detail_binding()
	await _test_action_unit_engine()
	await _test_shake_symmetry()
	await _test_fade_out_sequence()
	_test_resource_sampling()
	_report()
	get_tree().quit(0 if _fail == 0 else 1)


# ================= ① 详情区 =================

func _test_detail_node_paths() -> void:
	## 脚本期望的路径 vs 场景实际 —— 逐条核对（"接通前先对照"）
	var base: Node = (load("res://scenes/ui/battle_ui_alpha.tscn") as PackedScene).instantiate()
	add_child(base)
	var need := [
		"HUD/InfoPanel/CardName",
		"HUD/InfoPanel/SkillDesc",
		"HUD/InfoPanel/Attributes/Row1/Value",
		"HUD/InfoPanel/Attributes/Row2/Value",
		"HUD/InfoPanel/Attributes/Row3/Value",
		"HUD/InfoPanel/Attributes/Row4/Value",
	]
	for p in need:
		_chk("详情区节点存在：" + p, base.get_node_or_null(p) != null)
	# 四行图标也在（用于核对四维语义）
	for i in 4:
		_chk("详情区第%d行有 Icon" % (i + 1),
			base.get_node_or_null("HUD/InfoPanel/Attributes/Row%d/Icon" % (i + 1)) != null)
	base.queue_free()


func _test_detail_binding() -> void:
	var st = _scene.state
	# 造一张兵蜂卡（走 GameState 的手牌），点它 → 详情区应显示真实数据
	var d := UnitData.new()
	d.id = Uuid.generate()
	d.display_name = "详情测试蜂"
	d.kind = CardData.CardKind.SOLDIER
	d.cost = 3
	d.atk = 6
	d.hp = 7
	d.move = 1
	d.attack_range = 2
	d.description = "详情区绑定测试用描述"
	d.skill_name = "测试技能"
	d.glossary = "支援"
	st.hand[0].insert(0, d)
	_scene._refresh_hand()
	await get_tree().process_frame
	# 模拟点击第一张手牌
	_scene._on_hand_clicked(d.id)
	await get_tree().process_frame
	var name_lb: Label = _scene.get_node("HUD/InfoPanel/CardName")
	var desc_lb: Label = _scene.get_node("HUD/InfoPanel/SkillDesc")
	var r1: Label = _scene.get_node("HUD/InfoPanel/Attributes/Row1/Value")
	var r2: Label = _scene.get_node("HUD/InfoPanel/Attributes/Row2/Value")
	var r3: Label = _scene.get_node("HUD/InfoPanel/Attributes/Row3/Value")
	var r4: Label = _scene.get_node("HUD/InfoPanel/Attributes/Row4/Value")
	_chk("详情区：卡名已绑定", name_lb.text == "详情测试蜂")
	_chk("详情区：描述含技能名与正文", desc_lb.text.contains("测试技能") and desc_lb.text.contains("详情区绑定测试用描述"))
	_chk("详情区：Row1=攻击 6", r1.text == "6")
	_chk("详情区：Row2=生命 7", r2.text == "7")
	_chk("详情区：Row3=移动 1", r3.text == "1")
	_chk("详情区：Row4=射程 2", r4.text == "2")
	# 指令卡 → 走指令分支（dmg/heal/range）
	var c := CommandData.new()
	c.id = Uuid.generate()
	c.display_name = "详情指令"
	c.kind = CardData.CardKind.COMMAND
	c.cost = 2
	c.dmg = 4
	c.heal = 0
	c.target_range = 3
	_scene.show_card_detail(c)
	await get_tree().process_frame
	_chk("详情区：指令卡 Row1=伤害 4", r1.text == "4")
	_chk("详情区：指令卡 Row3=射程 3", r3.text == "3")
	# 还原（避免影响后续）
	_scene.show_card_detail(d)


# ================= ② Action Unit =================

func _test_action_unit_engine() -> void:
	var eng: Node = AU.new()
	add_child(eng)
	Presets.register_all(eng)
	_chk("引擎注册了默认 Pattern", eng.pattern_names().size() >= 10)
	_chk("含「受击抖动」", eng.has_pattern("受击抖动"))
	_chk("含「单位退场」", eng.has_pattern("单位退场"))
	_chk("含「浮字上浮」", eng.has_pattern("浮字上浮"))

	# 帧数计时（T2）：一个 10 帧的 TINT pattern 应恰好跑 10 帧
	var host := Control.new()
	add_child(host)
	host.modulate = Color.WHITE
	eng.register("_测试10帧", {"units": [
		{"type": AU.U.TINT, "clips": [{"frames": 10, "color": Color(1, 1, 1, 0.5)}]}]})
	var t0 := host.modulate
	eng.action("_测试10帧", host)
	var frames_taken := 0
	while eng.is_running("_测试10帧") and frames_taken < 300:
		await get_tree().process_frame
		frames_taken += 1
	_chk("帧数计时：10 帧动画恰好 %d 帧（≤ 12 帧）" % frames_taken, frames_taken <= 12)
	_chk("动画确实改了表现（modulate 变化）", host.modulate != t0)
	host.queue_free()

	# UI 锁（block_ui）
	var host2 := Control.new()
	add_child(host2)
	eng.register("_测试锁", {"units": [
		{"type": AU.U.TINT, "clips": [{"frames": 30, "color": Color.WHITE}]}], "block_ui": true})
	eng.action("_测试锁", host2)
	_chk("block_ui：播放中 UI 被锁", eng.ui_locked)
	eng.stop("_测试锁")
	_chk("block_ui：终止后解锁", not eng.ui_locked)
	host2.queue_free()
	eng.queue_free()


func _test_shake_symmetry() -> void:
	## 围绕原位对称：抖动结束时位移应回到 0（旧实现有过 +7.3px 的基准漂移）
	var built: Dictionary = Presets.build_shake("受击抖动", 3, 12345)
	var step_sum := Vector2.ZERO
	for c in built["units"][0]["clips"]:
		step_sum += c["step"] as Vector2
	_chk("抖动位移总和归零（围绕原位对称，无漂移）%.3f" % step_sum.length(), step_sum.length() < 0.01)
	# 高伤害延长时长
	var lo: Dictionary = Presets.build_shake("受击抖动", 2, 1)
	var hi: Dictionary = Presets.build_shake("受击抖动", 9, 1)
	_chk("高伤害延长时长（%d 帧 → %d 帧）" % [int(lo["frames"]), int(hi["frames"])],
		int(hi["frames"]) > int(lo["frames"]))
	# 可复现（同种子同结果）
	var a: Dictionary = Presets.build_shake("受击抖动", 5, 777)
	var b: Dictionary = Presets.build_shake("受击抖动", 5, 777)
	_chk("同种子可复现", str(a["units"][0]["clips"]) == str(b["units"][0]["clips"]))
	# 幅度随伤害上升
	var c1: Dictionary = Presets.build_shake("受击抖动", 1, 5)
	var c2: Dictionary = Presets.build_shake("受击抖动", 6, 5)
	var m1: float = (c1["units"][0]["clips"][0]["step"] as Vector2).length()
	var m2: float = (c2["units"][0]["clips"][0]["step"] as Vector2).length()
	_chk("幅度随伤害上升（%.2f → %.2f）" % [m1, m2], m2 > m1)


func _test_fade_out_sequence() -> void:
	## 退场时序：先播淡出、播完才通知移除（迭代030/031 的时序要求）
	var drv: Node = Driver.new()
	add_child(drv)
	var holder := Control.new()
	add_child(holder)
	drv.node_provider = func(_id: String) -> Node: return holder
	drv.set_fx_parent(holder)
	# 等引擎就绪
	await get_tree().process_frame

	var inst := UnitInstance.create(_mk_unit("退场测试"), 0, Vector2i(2, 2))
	var got := {"done": 0}
	drv.unit_fade_out_done.connect(func(_id: String) -> void: got["done"] += 1)
	drv.on_unit_removed(inst)
	_chk("退场：立即开始播动画（未立刻通知移除）", got["done"] == 0)
	var guard := 0
	while got["done"] == 0 and guard < 300:
		await get_tree().process_frame
		guard += 1
	_chk("退场：动画播完后才通知移除（%d 帧）" % guard, got["done"] == 1 and guard > 10)
	drv.queue_free()
	holder.queue_free()


func _mk_unit(nm: String) -> UnitData:
	var d := UnitData.new()
	d.id = Uuid.generate()
	d.display_name = nm
	d.kind = CardData.CardKind.SOLDIER
	d.cost = 1
	d.atk = 1
	d.hp = 5
	d.move = 1
	d.attack_range = 1
	return d


# ================= ③ 资源抽查 =================

func _test_resource_sampling() -> void:
	var p := "res://game_data/cards/熊蜂.tres"
	_chk("资源存在：" + p, ResourceLoader.exists(p))
	if not ResourceLoader.exists(p):
		return
	var r: UnitData = load(p)
	_chk("资源加载为 UnitData", r != null)
	_chk("资源 have UUID id", r.id != "" and Uuid.is_valid(r.id))
	_chk("熊蜂 数值 5/8/1/1", r.atk == 5 and r.hp == 8 and r.attack_range == 1 and r.cost == 5)
	_chk("资源带视觉（立绘已引用）", r.visual != null and r.visual.artwork != null)
	var dp := "res://game_data/decks/样例卡组.tres"
	_chk("卡组资源存在", ResourceLoader.exists(dp))


# ================= 报告 =================

func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  [PASS] ", label)
	else:
		_fail += 1
		_failures.append(label)
		print("  [FAIL] ", label)


func _report() -> void:
	print("\n===== 迭代054 动画 + 详情区 自检 =====")
	print("  通过 %d / 失败 %d" % [_pass, _fail])
	for f in _failures:
		print("   ✗ ", f)
	print("====================================")
