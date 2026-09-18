class_name ActionUnit
extends Node
## ActionUnit —— **自写 Action Unit 动画引擎**（T3 红线：禁用引擎动画系统）
##
## 依据：`电子蜂A5策划案/动画系统及流程.md`
## 边界：**T3** 自写 Action Unit（不用 AnimationPlayer / Tween / AnimationTree）
##       **T2** 帧数计时（逐帧推进，不用 delta 当计时基准）
##
## 层级：`Pattern（动画）` → `Unit（单元）` → `Clip（动作）`
##   · 一个 Pattern 由若干 Unit 并行组成；一个 Unit 由若干 Clip **顺序**组成
##
## 5 类 Unit（策划案「3. ActionUnit 类型」）：
##   MOVE_BY   移动/旋转**指定数值**（可叠加）
##   MOVE_TO   移动/旋转**到指定数值**（不可重复：到位即完成）
##   ROT_TRACK 旋转**追踪目标**（不可重复）
##   TINT      变色
##   SPAWN_FX  生成特效
##
## 生命周期（策划案「2. 初始化与生命周期控制」）：
##   reset_unit(名, 目标)   重置（action 时按 pattern.inited 自动初始化）
##   action(名, 目标)       开始（可触发 on_start）
##   stop(名)              终止 —— **级联终止子单元、且不自动复位**
##
## ⚠️ 本引擎**只管表现**：不读写任何规则状态，也不认识 GameState。
##    调用方（接线层）负责在「规则事件」发生时调 action()。

@warning_ignore_start("shadowed_variable_base_class")

enum U { MOVE_BY, MOVE_TO, ROT_TRACK, TINT, SPAWN_FX }

const FPS := 60                     ## 帧率基准（T2：帧数计时）

var _patterns := {}                 ## Pattern 名 → 定义
var _running := {}                  ## 运行键 `pattern#实例ID` → 运行态

var ui_locked := false              ## 动画期间是否锁 UI（pattern.block_ui）
var anim_paused := false            ## 全局暂停（调试/结算用）
var debug_hold := false             ## 调试冻结（截图取证用）
var debug_log_timing := false       ## 打印实际帧数 vs 配置帧数

## 一次性特效（飘字等）的宿主节点；由接线层注入（一般挂在最上层，避免被遮挡）
var fx_parent: Node = null

## 节点解析：外部可注入「单位实例 id → 节点」的映射函数，便于按 id 播放
var node_provider: Callable = Callable()

## 结束回调的**兜底宿主**：pattern 的 `trigger_on_stop_call` 若本引擎没有该方法，
##   就转发给本节点（通常是接线层）。⚠️ 旧实现用 `_state` 做这层兜底，移植时曾漏掉 →
##   表现为"退场动画播完了但回调从不触发、单位永不消失"（本迭代实测）。
var owner_node: Node = null


# ============================================================
# 注册与查询
# ============================================================

func register(pname: String, spec: Dictionary) -> void:
	_patterns[pname] = spec


func has_pattern(pname: String) -> bool:
	return _patterns.has(pname)


func pattern_names() -> Array:
	return _patterns.keys()


## 正在播放的 pattern 名（去重）
func running_names() -> Array:
	var out: Array = []
	for k in _running.keys():
		var nm := str(_running[k].get("name", _key_pattern(str(k))))
		if not out.has(nm):
			out.append(nm)
	return out


func is_running(pname: String) -> bool:
	for k in _running.keys():
		if _key_pattern(str(k)) == pname:
			return true
	return false


func any_running_blocking() -> bool:
	for k in _running.keys():
		var nm := str(_running[k].get("name", _key_pattern(str(k))))
		if bool(_patterns.get(nm, {}).get("block_ui", false)):
			return true
	return false


# ============================================================
# 生命周期
# ============================================================

## 开始播放（携带目标节点）
func action(pname: String, target: Node = null) -> void:
	if not _patterns.has(pname):
		return
	_apply_initial(pname, target)
	# ⚠️ 只存**弱引用**：节点被 free 后若还持强引用，取出赋值时会报
	#    "Trying to assign invalid previously freed instance"（旧实现 V-004-17 实测）
	var key := _run_key(pname, target)
	if _running.has(key):
		stop(key)                    # 同一目标重播：先收尾上一段（含一次性特效释放）
	var n_units: int = (_patterns[pname].get("units", []) as Array).size()
	var zeros: Array = []
	for _k in n_units:
		zeros.append(0)              # i=当前 clip 下标 → 用数组**按单元下标**存（支持多单元并行）
	_running[key] = {
		"name": pname, "c": zeros.duplicate(), "f": zeros.duplicate(),
		"tref": weakref(target), "t0": Time.get_ticks_msec(), "frames": 0,
	}
	var p: Dictionary = _patterns[pname]
	var on_start := str(p.get("trigger_on_start", ""))
	if on_start != "" and _patterns.has(on_start):
		action(on_start, target)
	if bool(p.get("block_ui", false)):
		ui_locked = true


func reset_unit(pname: String, target: Node = null) -> void:
	_apply_initial(pname, target)


## 终止：**级联终止本 pattern 的全部单元**、**不复位**（策划案 规则3）
## 入参可为「实例键」或「pattern 名」（后者停该 pattern 的所有实例）
func stop(pname: String) -> void:
	var keys: Array = []
	if _running.has(pname):
		keys.append(pname)
	else:
		for k in _running.keys():
			if _key_pattern(str(k)) == pname:
				keys.append(k)
	for k0 in keys:
		_stop_instance(str(k0))


func stop_all() -> void:
	_running.clear()
	ui_locked = false


func _stop_instance(key: String) -> void:
	if not _running.has(key):
		return
	var st0: Dictionary = _running[key]
	var tgt: Node = null
	if st0.has("tref"):
		var wr0 = st0["tref"]
		tgt = wr0.get_ref() if wr0 != null else null
	var pname := str(st0.get("name", _key_pattern(key)))
	if debug_log_timing:
		var cfgf := _inst_frames(pname)
		var gotf := int(st0.get("frames", 0))
		var ms := Time.get_ticks_msec() - int(st0.get("t0", 0))
		print("[ActionUnit] %s 结束：实际帧=%d 配置帧=%d 耗时=%dms %s" % [
			pname, gotf, cfgf, ms, ("OK" if absf(float(gotf - cfgf)) <= 2.0 else "不符")])
	_running.erase(key)
	# 一次性特效（飘字等）：播完自释放
	if tgt != null and is_instance_valid(tgt) and tgt.has_meta("fx_once"):
		tgt.queue_free()
	var p: Dictionary = _patterns.get(pname, {})
	if bool(p.get("block_ui", false)) and not any_running_blocking():
		ui_locked = false
	var on_stop := str(p.get("trigger_on_stop", ""))
	if on_stop != "" and _patterns.has(on_stop):
		action(on_stop, tgt)
	# ⚠️ 结束回调钩子**必须在本函数**（"动画自然播完"的唯一出口）——
	#    旧实现曾误插到 action() 开头 → 表现为"动画播完了但单位不消失"（V-005-8 实测）
	var cb := str(p.get("trigger_on_stop_call", ""))
	if cb != "":
		if has_method(cb):
			call(cb, tgt)
		elif owner_node != null and is_instance_valid(owner_node) and owner_node.has_method(cb):
			owner_node.call(cb, tgt)


func _run_key(pname: String, target: Node) -> String:
	if target == null or not is_instance_valid(target):
		return pname
	return "%s#%d" % [pname, target.get_instance_id()]


func _key_pattern(key: String) -> String:
	var i := key.find("#")
	return key if i < 0 else key.substr(0, i)


func _inst_frames(pname: String) -> int:
	## Pattern 的"配置帧数" = 各 Unit 中最长的 clip 帧数之和
	var p: Dictionary = _patterns.get(pname, {})
	var best := 0
	for u in p.get("units", []):
		var total := 0
		for c in (u.get("clips", []) as Array):
			total += maxi(1, int(c.get("frames", 1)))
		best = maxi(best, total)
	return best


# ============================================================
# 逐帧推进（T2：帧数计时）
# ============================================================

func _process(_delta: float) -> void:
	if debug_hold or _running.is_empty():
		return
	# ⚠️ 必须先复制键快照并逐个校验键仍存在：循环体里 _step → 结束 → _stop_instance
	#    → 回调钩子 → 可能又起新动画 → _running 被增删，而遍历用的是旧快照
	#    → 访问已删除的键报错并打进调试断点（旧实现 V-034 实测：蜂王互杀）
	var keys: Array = _running.keys()
	for key in keys:
		if not _running.has(key):
			continue
		var nm := str(_running[key].get("name", _key_pattern(str(key))))
		var p: Dictionary = _patterns.get(nm, {})
		if anim_paused and bool(p.get("pause_global", true)):
			continue
		_step(str(key))


func _step(key: String) -> void:
	if not _running.has(key):
		return
	var st: Dictionary = _running[key]
	var pname := str(st.get("name", _key_pattern(key)))
	var p: Dictionary = _patterns.get(pname, {})
	if p.is_empty():
		_running.erase(key)
		return
	var tg: Node = _resolve_target(st)
	if tg == null:
		_running.erase(key)          # 目标已释放（弱引用失效）→ 丢弃
		return
	var units: Array = p.get("units", [])
	if units.is_empty():
		stop(key)
		return
	st["frames"] = int(st.get("frames", 0)) + 1
	# 本函数一次调用 = 推进**一个游戏帧**：所有并行 Unit 各推进一帧
	#   （旧实现曾按"当前单元"只推进一个 → 多单元 Pattern 每帧被推进多次，帧数计时失真）
	for i in units.size():
		var unit: Dictionary = units[i]
		var clips: Array = unit.get("clips", [])
		var c: int = maxi(0, int((st["c"] as Array)[i]))
		if c >= clips.size():
			continue
		_apply_clip(clips[c], st, unit, i)
		var frames: int = maxi(1, int(clips[c].get("frames", 1)))
		var f: int = int((st["f"] as Array)[i]) + 1
		(st["f"] as Array)[i] = f
		if f >= frames:
			(st["c"] as Array)[i] = c + 1
			(st["f"] as Array)[i] = 0
	# 所有单元播完 → 结束（空 clips 的单元视为已完成，否则永远不结束、主循环空转）
	var done := true
	for i in units.size():
		var nclips: int = (units[i].get("clips", []) as Array).size()
		if nclips > 0 and int((st["c"] as Array)[i]) < nclips:
			done = false
			break
	if done:
		stop(key)


func _resolve_target(st: Dictionary) -> Node:
	if not st.has("tref"):
		return null
	var wr = st["tref"]
	var tgt: Node = wr.get_ref() if wr != null else null
	if tgt == null or not is_instance_valid(tgt) or tgt.is_queued_for_deletion():
		return null
	return tgt


# ============================================================
# 5 类 Unit 的动作执行
# ============================================================

func _apply_clip(clip: Dictionary, st: Dictionary, unit: Dictionary, unit_index: int) -> void:
	var tgt := _resolve_target(st)
	if tgt == null:
		return
	match int(unit.get("type", U.MOVE_BY)):
		U.MOVE_BY:
			var step: Vector2 = clip.get("step", Vector2.ZERO)
			if tgt is Node2D:
				(tgt as Node2D).position += step
			elif tgt is Control:
				(tgt as Control).position += step
			var rot: float = float(clip.get("rot", 0.0))
			if rot != 0.0:
				if tgt is Node2D:
					(tgt as Node2D).rotation += rot
				elif tgt is Control:
					(tgt as Control).rotation += rot
		U.MOVE_TO:
			var to: Vector2 = clip.get("to", Vector2.ZERO)
			var pos: Vector2 = to
			if clip.has("from"):
				var total: int = maxi(1, int(clip.get("frames", 1)))
				var t: float = float(int((st["f"] as Array)[unit_index]) + 1) / float(total)
				pos = (clip["from"] as Vector2).lerp(to, t)
			if tgt is Node2D:
				(tgt as Node2D).position = pos
			elif tgt is Control:
				(tgt as Control).position = pos
		U.ROT_TRACK:
			var track: Node = clip.get("track", null)
			if track != null and is_instance_valid(track):
				var a := _global_pos(tgt)
				var b := _global_pos(track)
				if a.distance_to(b) > 0.01:
					var ang := (b - a).angle()
					if tgt is Node2D:
						(tgt as Node2D).global_rotation = ang
					elif tgt is Control:
						(tgt as Control).rotation = ang
		U.TINT:
			var col: Color = clip.get("color", Color.WHITE)
			if tgt is CanvasItem:
				(tgt as CanvasItem).modulate = col
		U.SPAWN_FX:
			_spawn_fx(clip, tgt)


func _global_pos(n: Node) -> Vector2:
	if n is Node2D:
		return (n as Node2D).global_position
	if n is Control:
		return (n as Control).global_position
	return Vector2.ZERO


func _spawn_fx(clip: Dictionary, tgt: Node) -> void:
	var scene: PackedScene = clip.get("scene", null)
	if scene == null or fx_parent == null:
		return
	var n: Node = scene.instantiate()
	fx_parent.add_child(n)
	if n is Node2D:
		(n as Node2D).global_position = _global_pos(tgt)
	if n.has_method("play_once"):
		n.call("play_once", int(clip.get("frames", 12)))


## 初始状态（ResetUnit）：按 pattern.inited 恢复字段
func _apply_initial(pname: String, target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	var init: Dictionary = _patterns.get(pname, {}).get("inited", {})
	for k in init:
		target.set(str(k), init[k])


# ============================================================
# 便捷播放（按「实例 id → 节点」解析）
# ============================================================

func node_of(id: String) -> Node:
	if not node_provider.is_valid():
		return null
	var n = node_provider.call(id)
	return n as Node


func play_on(id: String, pname: String) -> void:
	var n := node_of(id)
	if n != null:
		action(pname, n)


func play(name_or_id: String, pname: String) -> void:
	play_on(name_or_id, pname)
