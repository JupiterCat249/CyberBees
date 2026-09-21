extends Node
## AnimPlayer —— 数据驱动动画引擎（Pattern → Unit → Clip）
##
## 依据：《电子蜂A5策划案/动画系统及流程.md》§一（层级 / 生命周期 / 5 类 Unit / 4 条运行规则）
## 边界：T2（帧数计时，不用 delta）· T3 v1.10（自写系统，**数据在 Resources**）
##       · 回放一致性（动画进度 = 帧数的纯函数：每帧恰好推进 1 步）
##
## 数据：`game_data/anims/*.tres`（一文件一条 Pattern）→ `load_library()`
## 用法：`action("受击抖动", 节点, 伤害值)` · `stop("受击抖动")` · `stop_all()`
##
## ⚠️ 三条旧实现实测换来的硬约束（必须保留）：
##   1. 运行表按 **「Pattern 名 + 目标实例 id」** 分键 —— 旧实现按 Pattern 名分键，
##      同一 Pattern 用在多目标上会互相覆盖 → 节点永不释放（迭代019 飘字泄漏）
##   2. 每帧**恰好推进 1 步**，且一次推进**全部并行单元各一帧**（迭代024：否则「配置帧 ≠ 实际帧」）
##   3. 遍历运行表前**先复制键快照**（迭代034：结束回调会增删运行表 → 访问已删键崩溃）
const ANIM_DIR := "res://game_data/anims"
const PatternLib := preload("res://scripts/anim/anim_pattern.gd")
const UnitLib := preload("res://scripts/anim/anim_unit.gd")
const ClipLib := preload("res://scripts/anim/anim_clip.gd")

signal instance_finished(pattern_name: String, target: Node)
signal ui_lock_changed(locked: bool)

var node_provider: Callable = Callable()   ## 备用解析：instance_id → 节点
var fx_parent: Node = null                 ## SPAWN_FX 宿主（空则挂到目标父节点）
var anim_paused := false                   ## 全局暂停（pause_global=false 的 Pattern 不受影响）
var debug_log_timing := false

var _patterns := {}    ## 名 → AnimPattern
var _running := {}     ## "Pattern名#目标实例id" → 运行态
var _ui_locked := false


func _ready() -> void:
	load_library()


# ============================================================
#  数据（Resources）—— 新增动画 = 加一个 .tres，不改代码
# ============================================================

func load_library() -> void:
	_patterns.clear()
	var d := DirAccess.open(ANIM_DIR)
	if d == null:
		push_warning("AnimPlayer: 动画目录不存在 %s" % ANIM_DIR)
		return
	for f in d.get_files():
		if String(f).ends_with(".tres"):
			register(load("%s/%s" % [ANIM_DIR, f]))


func register(p) -> void:
	if p == null or p.get_script() != PatternLib:
		return
	if String(p.pattern_name) != "":
		_patterns[p.pattern_name] = p


func has_pattern(pname: String) -> bool:
	return _patterns.has(pname)


func pattern_names() -> Array:
	return _patterns.keys()


# ============================================================
#  生命周期（§一之2）：ResetUnit / Action / Stop
# ============================================================

func action(pname: String, target: Node = null, value: int = 0) -> void:
	var pat = _patterns.get(pname, null)
	if pat == null or target == null or not is_instance_valid(target):
		return
	var key := _key(pname, target)
	if _running.has(key):
		_finish(key, true)          ## 重播：先按自然收尾结束上一条（回位），避免位移累积
	var units: Array = pat.units
	if units.is_empty():
		return
	var grow: bool = (int(pat.extra_frames) > 0) and (value >= int(pat.value_threshold))
	var ci := []
	var cf := []
	var ex := []
	for i in range(units.size()):
		ci.append(0)
		cf.append(0)
		ex.append(pat.extra_frames if grow else 0)
	_running[key] = {
		"pat": pat, "name": pname, "target": target, "value": value,
		"ci": ci, "cf": cf, "extra": ex,
		"base_pos": _pos(target), "base_rot": target.rotation, "base_mod": target.modulate,
		"total": _total_frames(pat, grow),
	}
	_refresh_ui_lock()
	if String(pat.trigger_on_start) != "":
		action(pat.trigger_on_start, target, value)
	if debug_log_timing:
		print("[ANIM] start %s → %s (frames=%d)" % [pname, target.name, _running[key]["total"]])


func stop(pname: String) -> void:
	## 终止 = 移出运行表、**不复位**（§一之4 规则3：终止级联且不复位）
	for k in _running.keys():
		if String(k).begins_with(pname + "#"):
			_finish(String(k), false)


func stop_all() -> void:
	for k in _running.keys():
		_finish(String(k), false)


func is_running(pname: String) -> bool:
	for k in _running.keys():
		if String(k).begins_with(pname + "#"):
			return true
	return false


func running_count() -> int:
	return _running.size()


func ui_locked() -> bool:
	return _ui_locked


# ============================================================
#  帧推进（T2：每帧恰好 1 步；一次推全部并行单元）
# ============================================================

func _process(_delta: float) -> void:
	## ⚠️ 先复制键快照（迭代034）
	for k in _running.keys():
		if _running.has(k):
			_step(String(k))


func _step(key: String) -> void:
	var st: Dictionary = _running[key]
	var pat = st["pat"]
	var target = st["target"]
	if target == null or not is_instance_valid(target):
		_finish(key, false)
		return
	if anim_paused and pat.pause_global:
		return
	var units: Array = pat.units
	var ci: Array = st["ci"]
	var cf: Array = st["cf"]
	var ex: Array = st["extra"]
	var all_done := true
	for i in range(units.size()):
		var u = units[i]
		if u == null or u.clips.is_empty() or ci[i] >= u.clips.size():
			continue
		all_done = false
		var clip = u.clips[ci[i]]
		var want: int = clip.frames + (int(ex[i]) if ci[i] == u.clips.size() - 1 else 0)
		_apply(clip, target, st, int(cf[i]), want)
		cf[i] = int(cf[i]) + 1
		if int(cf[i]) >= want:
			cf[i] = 0
			ci[i] = int(ci[i]) + 1
	if all_done:
		_finish(key, true)


func _apply(clip, target: Node, st: Dictionary, done_frames: int, want: int) -> void:
	var scale := 1.0
	var ref: int = st["pat"].value_ref
	if ref > 0:
		scale = clampf(float(st["value"]) / float(ref), 0.35, 2.5)
	match int(clip.kind):
		ClipLib.Kind.MOVE_BY:
			## 可叠加：每帧累加（位移/旋转）
			_set_pos(target, _pos(target) + clip.offset * scale)
			target.rotation += clip.rotation_step
		ClipLib.Kind.MOVE_TO:
			## 不可重复：frames 帧线性到位
			var goal: Vector2 = st["base_pos"] + clip.offset * scale
			var remain := maxi(1, want - done_frames)
			_set_pos(target, _pos(target).lerp(goal, 1.0 / float(remain)))
		ClipLib.Kind.ROT_TRACK:
			if String(clip.track_node) != "":
				var tn := target.get_node_or_null(clip.track_node)
				if tn is Node2D and target is Node2D:
					target.rotation = ((tn as Node2D).global_position - (target as Node2D).global_position).angle()
		ClipLib.Kind.TINT:
			target.modulate = clip.tint
		ClipLib.Kind.SPAWN_FX:
			if done_frames == 0 and clip.fx_scene != null:
				var host: Node = fx_parent if fx_parent != null else target.get_parent()
				if host != null:
					host.add_child(clip.fx_scene.instantiate())


func _finish(key: String, restore: bool) -> void:
	if not _running.has(key):
		return
	var st: Dictionary = _running[key]
	_running.erase(key)
	var target = st["target"]
	if target != null and is_instance_valid(target):
		if restore:
			_set_pos(target, st["base_pos"])
			target.rotation = st["base_rot"]
		var pat = st["pat"]
		if String(pat.trigger_on_stop) != "":
			action(pat.trigger_on_stop, target, int(st["value"]))
		instance_finished.emit(String(st["name"]), target)
		if debug_log_timing:
			print("[ANIM] finish %s on %s" % [st["name"], target.name])
	_refresh_ui_lock()


func _refresh_ui_lock() -> void:
	var lock := false
	for k in _running.keys():
		if bool(_running[k]["pat"].block_ui):
			lock = true
			break
	if lock != _ui_locked:
		_ui_locked = lock
		ui_lock_changed.emit(lock)


# ============================================================
#  工具
# ============================================================

func _key(pname: String, target: Node) -> String:
	return "%s#%d" % [pname, target.get_instance_id()]


func _total_frames(pat, grow: bool) -> int:
	var mx := 0
	for u in pat.units:
		if u == null:
			continue
		var s := 0
		for c in u.clips:
			if c != null:
				s += int(c.frames)
		if grow and not u.clips.is_empty():
			s += int(pat.extra_frames)
		mx = maxi(mx, s)
	return mx


## 位置读写：兼容 Node2D 与 Control（两者都有 position，但基类 Node 没有）
func _pos(n: Node) -> Vector2:
	if n is Node2D:
		return (n as Node2D).position
	if n is Control:
		return (n as Control).position
	return Vector2.ZERO


func _set_pos(n: Node, v: Vector2) -> void:
	if n is Node2D:
		(n as Node2D).position = v
	elif n is Control:
		(n as Control).position = v
