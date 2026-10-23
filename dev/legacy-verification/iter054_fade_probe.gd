extends Node
## 【验证用 · 非生产】退场时序探针：定位"动画播完不回传"的真因
const AU := preload("res://scripts/game/action_unit.gd")
const Presets := preload("res://scripts/game/anim_presets.gd")
const Driver := preload("res://scripts/game/battle_anim_driver.gd")

func _ready() -> void:
	# ① 先直接测引擎：一个 20 帧的 pattern + trigger_on_stop_call 是否会回调
	var eng: Node = AU.new()
	add_child(eng)
	Presets.register_all(eng)
	var holder := Control.new()
	add_child(holder)
	eng.fx_parent = holder
	# 给引擎本身挂一个探针方法
	print("[探针] 引擎 pattern 数=", eng.pattern_names().size())
	print("[探针] 有 单位退场 =", eng.has_pattern("单位退场"))
	var def: Dictionary = eng._patterns.get("单位退场", {})
	print("[探针] 单位退场 定义 keys=", def.keys(), " cb=", def.get("trigger_on_stop_call", "（无）"))
	eng.action("单位退场", holder)
	print("[探针] action 后 running=", eng.running_names())
	var f := 0
	while eng.is_running("单位退场") and f < 120:
		await get_tree().process_frame
		f += 1
	print("[探针] 引擎直接播放 单位退场 用了 ", f, " 帧")

	# ② 再测 Driver
	var drv: Node = Driver.new()
	add_child(drv)
	await get_tree().process_frame
	print("[探针] Driver.engine =", drv.engine)
	print("[探针] Driver.engine pattern 数=", drv.engine.pattern_names().size() if drv.engine else -1)
	var got := {"n": 0, "id": ""}
	drv.unit_fade_out_done.connect(func(id: String) -> void: got["n"] += 1; got["id"] = id)
	var d := UnitData.new()
	d.id = Uuid.generate(); d.display_name = "探针单位"; d.kind = CardData.CardKind.SOLDIER
	d.hp = 5; d.atk = 1; d.move = 1; d.attack_range = 1
	var inst := UnitInstance.create(d, 0, Vector2i(1, 1))
	print("[探针] inst.instance_id =", inst.instance_id)
	drv.node_provider = func(_id: String) -> Node: return holder
	drv.on_unit_removed(inst)
	print("[探针] on_unit_removed 后 pending=", drv._pending_remove.keys())
	print("[探针] 引擎 running=", drv.engine.running_names())
	# 逐步追踪回调链
	var g := 0
	while got["n"] == 0 and g < 40:
		await get_tree().process_frame
		g += 1
		if g in [5, 15, 25]:
			print("[探针] 第%d帧：引擎running=%s pending=%s" % [g, str(drv.engine.running_names()), str(drv._pending_remove.keys())])
	# 手动直呼回调，验证方法本身可用
	print("[探针] 手动调用 on_unit_fade_out_done(holder) → 看是否 emit")
	drv.on_unit_fade_out_done(holder)
	await get_tree().process_frame
	print("[探针] 手动调用后 回调触发=", got["n"])
	print("[探针] 引擎 _patterns['单位退场'] cb=", str(drv.engine._patterns.get("单位退场", {}).get("trigger_on_stop_call", "无")))
	# 检查引擎能否找到该方法（跨脚本 preload 时 has_method 的对象是谁）
	var d2: Dictionary = drv.engine._patterns.get("单位退场", {})
	var cbname: String = str(d2.get("trigger_on_stop_call", ""))
	print("[探针] 引擎.has_method(%s) = %s" % [cbname, str(drv.engine.has_method(cbname))])
	print("[探针] drv.has_method(%s) = %s" % [cbname, str(drv.has_method(cbname))])
	print("[探针] Driver 回调触发=", got["n"], " 用了 ", g, " 帧；引擎 running=", drv.engine.running_names())
	get_tree().quit(0)
