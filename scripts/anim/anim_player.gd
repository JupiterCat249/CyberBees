extends Node
## AnimPlayer —— 数据驱动动画引擎（Pattern → Unit → Clip）
##
## 依据：《电子蜂A5策划案/动画系统及流程.md》§一（层级 / 生命周期 / 5 类 Unit / 4 条运行规则）
## 边界：T2（帧数计时，不用 delta）· T3 v1.10（自写系统，**数据在 Resources**）
##       · 回放一致性（动画进度 = 帧数的纯函数：每帧恰好推进 1 步）
##
## 代码风格：**静态风格**（全量类型标注；类型取自全局类 AnimPattern / AnimUnit / AnimClip）
##
## 数据：`game_data/anims/*.tres`（一文件一条 Pattern）→ `load_library()`
## 用法：`action("受击抖动", 节点, 伤害值)` · `stop("受击抖动")` · `stop_all()`
##
## ⚠️ 三条旧实现实测换来的硬约束（必须保留）：
##   1. 运行表按 **「Pattern 名 + 目标实例 id」** 分键 —— 旧实现按 Pattern 名分键，
##      同一 Pattern 用在多目标上会互相覆盖 → 节点永不释放（迭代019 飘字泄漏）
##   2. 每帧**恰好推进 1 步**，且一次推进**全部并行单元各一帧**（迭代024：否则「配置帧 ≠ 实际帧」）
##   3. 遍历运行表前**先复制键快照**（迭代034：结束回调会增删运行表 → 访问已删键崩溃）
##   4. 末帧**同一处收尾**（基础动画 §一：「播完立即退场」，不额外等帧）
const ANIM_DIR: String = "res://game_data/anims"

signal instance_finished(pattern_name: StringName, target: Node)
signal ui_lock_changed(locked: bool)

var node_provider: Callable = Callable()   ## 备用解析：instance_id → 节点
var fx_parent: Node = null                 ## SPAWN_FX 宿主（空则挂到目标父节点）
var anim_paused: bool = false              ## 全局暂停（pause_global=false 的 Pattern 不受影响）
var debug_log_timing: bool = false

var _patterns: Dictionary = {}    ## StringName → AnimPattern
var _running: Dictionary = {}     ## "Pattern名#目标实例id" → 运行态 Dictionary
var _ui_locked: bool = false


func _ready() -> void:
	load_library()


# ============================================================
#  数据（Resources）—— 新增动画 = 加一个 .tres，不改代码
# ============================================================

func load_library() -> void:
	_patterns.clear()
	var d: DirAccess = DirAccess.open(ANIM_DIR)
	if d == null:
		push_warning("AnimPlayer: 动画目录不存在 %s" % ANIM_DIR)
		return
	for f: String in d.get_files():
		if f.ends_with(".tres"):
			register(load("%s/%s" % [ANIM_DIR, f]) as AnimPattern)


func register(p: AnimPattern) -> void:
	if p == null or p.pattern_name.is_empty():
		return
	_patterns[p.pattern_name] = p


func has_pattern(pname: StringName) -> bool:
	return _patterns.has(pname)


func pattern_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _patterns.keys():
		out.append(k)
	return out


# ============================================================
#  生命周期（§一之2）：ResetUnit / Action / Stop
# ============================================================

func action(pname: StringName, target: Node = null, value: int = 0) -> String:
	var pat: AnimPattern = _patterns.get(pname, null)
	if pat == null or target == null or not is_instance_valid(target):
		return ""
	var key: String = _key(pname, target)
	if _running.has(key):
		## 重播：先按自然收尾结束上一条（回位），避免位移累积
		_finish(key, true)
	var units: Array[AnimUnit] = pat.units
	if units.is_empty():
		return ""
	var grow: bool = pat.extra_frames > 0 and value >= pat.value_threshold
	var ci: Array[int] = []
	var cf: Array[int] = []
	var ex: Array[int] = []
	for i: int in range(units.size()):
		ci.append(0)
		cf.append(0)
		ex.append(pat.extra_frames if grow else 0)
	_running[key] = {
		"pat": pat, "name": pname, "target": target, "value": value,
		"ci": ci, "cf": cf, "extra": ex,
		"base_pos": _pos(target), "base_rot": target.rotation, "base_mod": target.modulate,
		"total": _total_frames(pat, grow),
		"children": [],   ## 规则3：本动画触发的子动画键（终止时**级联**终止）
	}
	_refresh_ui_lock()
	if not pat.trigger_on_start.is_empty():
		var ck: String = action(pat.trigger_on_start, target, value)
		if not ck.is_empty():
			var kids: Array = _running[key]["children"]
			kids.append(ck)
	if debug_log_timing:
		print("[ANIM] start %s → %s (frames=%d)" % [pname, target.name, _running[key]["total"]])
	return key


func stop(pname: StringName) -> void:
	## 终止 = 移出运行表、**不复位**（§一之4 规则3：终止级联且不复位）
	var prefix: String = "%s#" % pname
	for k: String in _running.keys():
		if k.begins_with(prefix):
			_finish(k, false)


func stop_all() -> void:
	for k: String in _running.keys():
		_finish(k, false)


func is_running(pname: StringName) -> bool:
	var prefix: String = "%s#" % pname
	for k: String in _running.keys():
		if k.begins_with(prefix):
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
	for k: String in _running.keys():
		if _running.has(k):
			_step(k)


func _step(key: String) -> void:
	var st: Dictionary = _running[key]
	var pat: AnimPattern = st["pat"]
	var target: Node = st["target"]
	if target == null or not is_instance_valid(target):
		_finish(key, false)
		return
	if anim_paused and pat.pause_global:
		return
	var units: Array[AnimUnit] = pat.units
	var ci: Array[int] = st["ci"]
	var cf: Array[int] = st["cf"]
	var ex: Array[int] = st["extra"]
	for i: int in range(units.size()):
		var u: AnimUnit = units[i]
		if u == null or u.clips.is_empty() or ci[i] >= u.clips.size():
			continue
		var clip: AnimClip = u.clips[ci[i]]
		var want: int = clip.frames + (ex[i] if ci[i] == u.clips.size() - 1 else 0)
		_apply(clip, target, st, cf[i], want, i)
		cf[i] += 1
		if cf[i] >= want:
			cf[i] = 0
			ci[i] += 1
	if _all_done(units, ci):
		_finish(key, true)


## 全部单元的动作是否已跑完（**末帧同一处收尾**：本帧跑完即结束，不额外等帧）
func _all_done(units: Array[AnimUnit], ci: Array[int]) -> bool:
	for i: int in range(units.size()):
		var u: AnimUnit = units[i]
		if u == null or u.clips.is_empty():
			continue
		if ci[i] < u.clips.size():
			return false
	return true


func _apply(clip: AnimClip, target: Node, st: Dictionary, done_frames: int, want: int, ui: int) -> void:
	## 规则2（§一之4 line 27）：**动作开始时**可跳转/触发/终止其他单元或动画（条件门控）
	if done_frames == 0:
		_apply_rules(clip, target, st, ui)
	var scale: float = 1.0
	var ref: int = st["pat"].value_ref
	if ref > 0:
		scale = clampf(float(st["value"]) / float(ref), 0.35, 2.5)
	match clip.kind:
		AnimClip.Kind.MOVE_BY:
			## 可叠加：每帧累加（位移 / 旋转）
			_set_pos(target, _pos(target) + clip.offset * scale)
			target.rotation += clip.rotation_step
		AnimClip.Kind.MOVE_TO:
			## 不可重复：frames 帧内线性到位
			var goal: Vector2 = (st["base_pos"] as Vector2) + clip.offset * scale
			var remain: int = maxi(1, want - done_frames)
			_set_pos(target, _pos(target).lerp(goal, 1.0 / float(remain)))
		AnimClip.Kind.ROT_TRACK:
			if not String(clip.track_node).is_empty():
				var tn: Node = target.get_node_or_null(clip.track_node)
				if tn is Node2D and target is Node2D:
					target.rotation = ((tn as Node2D).global_position - (target as Node2D).global_position).angle()
		AnimClip.Kind.TINT:
			target.modulate = clip.tint
		AnimClip.Kind.SPAWN_FX:
			if done_frames == 0 and clip.fx_scene != null:
				var host: Node = fx_parent if fx_parent != null else target.get_parent()
				if host != null:
					host.add_child(clip.fx_scene.instantiate())


## 规则2：Clip 开始时评估条件 → 触发 / 终止 / 跳转（全部为数据字段，非脚本语言）
##   跳转语义：**只能向后跳**（目标单元下标 > 当前单元下标）—— 杆绝自跳死循环
func _apply_rules(clip: AnimClip, target: Node, st: Dictionary, ui: int) -> void:
	if not _cond_ok(clip, st):
		return
	var value: int = int(st["value"])
	if not clip.on_start_trigger.is_empty():
		var ck: String = action(clip.on_start_trigger, target, value)
		if not ck.is_empty():
			var kids: Array = st["children"]
			kids.append(ck)
	if not clip.on_start_stop.is_empty():
		stop(clip.on_start_stop)
	var units: Array[AnimUnit] = st["pat"].units
	if clip.on_start_goto_unit > ui and clip.on_start_goto_unit < units.size():
		var ci: Array[int] = st["ci"]
		var cf: Array[int] = st["cf"]
		for i: int in range(units.size()):
			ci[i] = 0 if i == clip.on_start_goto_unit else units[i].clips.size()
			cf[i] = 0


## 条件判断（数据驱动；NONE = 恒真）
func _cond_ok(clip: AnimClip, st: Dictionary) -> bool:
	match clip.condition:
		AnimClip.Cond.VALUE_GTE:
			return int(st["value"]) >= clip.cond_value
		AnimClip.Cond.VALUE_LT:
			return int(st["value"]) < clip.cond_value
	return true


func _finish(key: String, restore: bool) -> void:
	if not _running.has(key):
		return
	var st: Dictionary = _running[key]
	_running.erase(key)
	## 规则3（§一之4 line 28）：**终止会一并终止子单元与动作**（级联；级联项不复位）
	for ck: String in (st.get("children", []) as Array):
		if _running.has(ck):
			_finish(ck, false)
	var target: Node = st["target"]
	if target != null and is_instance_valid(target):
		if restore:
			_set_pos(target, st["base_pos"])
			target.rotation = st["base_rot"]
		var pat: AnimPattern = st["pat"]
		if not pat.trigger_on_stop.is_empty():
			action(pat.trigger_on_stop, target, int(st["value"]))
		instance_finished.emit(st["name"], target)
		if debug_log_timing:
			print("[ANIM] finish %s on %s" % [st["name"], target.name])
	_refresh_ui_lock()


func _refresh_ui_lock() -> void:
	var lock: bool = false
	for k: String in _running.keys():
		if bool(_running[k]["pat"].block_ui):
			lock = true
			break
	if lock != _ui_locked:
		_ui_locked = lock
		ui_lock_changed.emit(lock)


# ============================================================
#  工具
# ============================================================

func _key(pname: StringName, target: Node) -> String:
	return "%s#%d" % [pname, target.get_instance_id()]


func _total_frames(pat: AnimPattern, grow: bool) -> int:
	var mx: int = 0
	for u: AnimUnit in pat.units:
		if u == null:
			continue
		var s: int = 0
		for c: AnimClip in u.clips:
			if c != null:
				s += c.frames
		if grow and not u.clips.is_empty():
			s += pat.extra_frames
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
