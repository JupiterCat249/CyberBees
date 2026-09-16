extends Node
## ⚠️ 本引擎是 Node，函数参数 `name`（Pattern 名）会与基类属性 `Node.name` 同名 →
##    GDScript 报 SHADOWED_VARIABLE_BASE_CLASS（10 处）。此处统一静音：
##    引擎内所有 `name` 语义**明确指 Pattern 名**，从不指节点名；逐个改名会牵连所有调用点且无实际收益。
##    （若日后需要区分，再把参数统一改名为 `pat`。）
@warning_ignore_start("shadowed_variable_base_class")
## 数值文本用到的工具（digit_node 等）
const D := preload("res://scenes/battle/battle_defs.gd")
## ============================================================
## BattleAnim —— **自写 Action Unit 动画引擎**（迭代004）
##
## 依据《电子蜂A5策划案/动画系统及流程.md》
## 边界约束：**T3 自写 Action Unit 系统、禁用引擎动画系统**（不使用 AnimationPlayer / Tween / AnimationTree）
##          **T2 帧数计时**（不使用 delta —— 逐帧推进）
##
## 层级：`Pattern（动画）` → `Unit（单元）` → `Clip（动作）`
##   · 一个 Pattern 由若干 Unit 顺序组成；一个 Unit 由若干 Clip 组成
##   · 单元触发后**自动按逻辑顺序执行**（动作1 → 动作2 → 动作3）
##
## 5 类 Unit（策划案「3. ActionUnit 类型」）：
##   MOVE_BY   移动/旋转**指定数值**（可叠加）
##   MOVE_TO   移动/旋转**到指定数值**（不可重复：到位即完成）
##   ROT_TRACK 旋转**追踪目标**（不可重复）
##   TINT      变色
##   SPAWN_FX  生成特效
##
## 生命周期（策划案「2. 初始化与生命周期控制」）：
##   reset_unit(名, 目标)   重置（渲染时自动初始化）
##   action(名, 目标)       开始（A 开始时/终止时可触发 B）
##   stop(名)              终止 —— **级联终止子单元，且不自动复位**（规则 3）
##
## 运行规则（策划案「4. 运行规则」）：
##   ① 顺序执行 ② 可跳转/触发/终止（支持条件）③ 终止级联不复位 ④ 可禁 UI 交互 / 受全局暂停
## ============================================================

## Unit 类型
enum U { MOVE_BY, MOVE_TO, ROT_TRACK, TINT, SPAWN_FX }

## Pattern 名 → 定义
var _patterns := {}
## Pattern 名 → 运行态
var _running := {}

## 全局：UI 交互是否被动画锁定（规则 4）
var ui_locked := false
## 迭代020：**调试用**——置 true 时冻结所有动画推进（不消耗帧数），
##   便于用截图核查"飘字/抖动是否真的画出来了"（0.5s 的表现靠工具往返很难抓到）。
##   正常游戏恒为 false；仅在需要取证时由调试脚本临时置真。
var debug_hold := false
## 迭代024：**时长自检**开关 —— 置真时每个动画结束会打印「实际帧 / 配置帧 / 耗时」，
##   用于核对"配置时长"是否真的等于"观感时长"（本次修复即靠它定位：曾出现实际 100 帧 / 配置 60 帧）。
var debug_log_timing := false
## 全局：是否暂停动画推进（规则 4）
var anim_paused := false
## 一次性特效挂载父节点（由协调器注入）
var fx_parent: Node = null


# ============================================================
# 注册与生命周期
# ============================================================

func register(name: String, spec: Dictionary) -> void:
	_patterns[name] = spec


func has_pattern(name: String) -> bool:
	return _patterns.has(name)


func pattern_names() -> Array:
	return _patterns.keys()


## 开始播放（携带目标节点）：先按 Pattern 的 inited 重置目标（渲染时自动初始化）
func action(name: String, target: Node = null) -> void:
	if not _patterns.has(name):
		return
	_apply_initial(name, target)
	# ⚠️ 只存**弱引用**：节点被 free 后若还持有强引用，从字典取出并赋值这一步就会报
	#    "Trying to assign invalid previously freed instance"（V-004-17 实测）——弱引用取到 null 即安全丢弃
	# 迭代019 缺陷修复：运行态**按"pattern + 目标实例"分别追踪** ——
	#   此前以 pattern 名为键，同一 pattern 用在多个目标上时**后开始的会覆盖前一个**，
	#   被覆盖的节点永不被 stop() → 永不释放（飘字会持续泄漏；溅射/链式伤害一次生成多个飘字）。
	var key := _run_key(name, target)
	if _running.has(key):
		stop(key)      # 同一目标重播：先收尾上一段（含一次性特效释放），再起新的
	# i/c/f 改为**按单元下标的数组**：i=当前 clip 下标，f=该 clip 已播帧数（迭代024）
	var n_units := (_patterns[name].get("units", []) as Array).size()
	var zeros: Array = []
	for _k in n_units:
		zeros.append(0)
	_running[key] = {"name": name, "i": 0, "c": zeros.duplicate(), "f": zeros.duplicate(),
		"tref": weakref(target), "t0": Time.get_ticks_msec(), "frames": 0}
	var p: Dictionary = _patterns[name]
	var on_start := str(p.get("trigger_on_start", ""))
	if on_start != "" and _patterns.has(on_start):
		action(on_start, target)
	if bool(p.get("block_ui", false)):
		ui_locked = true


## 运行态键：`pattern名#实例ID`（target 为 null 时退化为 pattern 名）
func _run_key(name: String, target: Node) -> String:
	if target == null or not is_instance_valid(target):
		return name
	return "%s#%d" % [name, target.get_instance_id()]


## 运行态键 → pattern 名
func _key_pattern(key: String) -> String:
	var i := key.find("#")
	return key if i < 0 else key.substr(0, i)


## 重置：把目标恢复到 Pattern 的初始状态
func reset_unit(name: String, target: Node = null) -> void:
	_apply_initial(name, target)


## 终止：级联终止（本 Pattern 的所有 Unit 一并终止），**不复位**（规则 3）；终止时可触发下一动画
func stop(name: String) -> void:
	# 支持两种入参：**实例键**（pattern#id）停单个实例；**pattern 名**停该 pattern 的全部实例
	var keys: Array = []
	if _running.has(name):
		keys.append(name)
	else:
		for k in _running.keys():
			if _key_pattern(str(k)) == name:
				keys.append(k)
	if keys.is_empty():
		return
	for k0 in keys:
		_stop_instance(str(k0))


## 收尾单个运行实例：释放一次性特效、解锁 UI、按定义触发后续动画
func _stop_instance(key: String) -> void:
	if not _running.has(key):
		return
	# 目标用弱引用取（可能已释放 → null）
	var tgt: Node = null
	var st0: Dictionary = _running[key]
	if st0.has("tref"):
		var wr0 = st0["tref"]
		tgt = wr0.get_ref() if wr0 != null else null
	var name := str(st0.get("name", _key_pattern(key)))
	# 迭代024 埋点：动画**实际**存活帧数与耗时（核对"配置时长"与"观感时长"是否一致）
	if debug_log_timing:      # 迭代024：默认关闭；核查时长时置真（BattleAnim.debug_log_timing = true）
		var cfgf := _inst_frames(name)
		var gotf := int(st0.get("frames", 0))
		var ms := Time.get_ticks_msec() - int(st0.get("t0", 0))
		print("[anim] %s 结束：实际帧=%d 配置帧=%d 耗时=%dms %s" % [
			name, gotf, cfgf, ms, ("OK" if absf(float(gotf - cfgf)) <= 2.0 else "不符")])
	_running.erase(key)
	# 一次性特效（浮字等）：播完自释放
	if tgt != null and is_instance_valid(tgt) and tgt.has_meta("fx_once"):
		tgt.queue_free()
	var p: Dictionary = _patterns.get(name, {})
	if bool(p.get("block_ui", false)) and not _any_running_blocking():
		ui_locked = false
	var on_stop := str(p.get("trigger_on_stop", ""))
	if on_stop != "" and _patterns.has(on_stop):
		action(on_stop, tgt)


func stop_all() -> void:
	for n in _running.keys():
		_running.erase(n)
	ui_locked = false


## 该 pattern 是否有任意实例在播（键为 `pattern#id`，故按前缀匹配）
func is_running(name: String) -> bool:
	for k in _running.keys():
		if _key_pattern(str(k)) == name:
			return true
	return false


## 正在播放的 **pattern 名**（去重，不含实例 id）
func running_names() -> Array:
	var out: Array = []
	for k in _running.keys():
		var nm := str(_running[k].get("name", _key_pattern(str(k))))
		if not out.has(nm):
			out.append(nm)
	return out


func _any_running_blocking() -> bool:
	for k in _running.keys():
		var nm := str(_running[k].get("name", _key_pattern(str(k))))
		if bool(_patterns.get(nm, {}).get("block_ui", false)):
			return true
	return false


# ============================================================
# 逐帧推进（T2：帧数计时）
# ============================================================

func _process(_delta: float) -> void:
	if debug_hold:
		return          # 迭代020：调试冻结（表现停在当前帧，便于截图取证）
	if _running.is_empty():
		return
	for key in _running.keys():
		var nm := str(_running[key].get("name", _key_pattern(str(key))))
		var p: Dictionary = _patterns.get(nm, {})
		if anim_paused and bool(p.get("pause_global", true)):
			continue
		_step(str(key))


func _step(key: String) -> void:
	if not _running.has(key):
		return
	var st: Dictionary = _running[key]
	var name := str(st.get("name", _key_pattern(key)))
	var p: Dictionary = _patterns.get(name, {})
	if p.is_empty():
		_running.erase(key)
		return
	# ⚠️ 目标已被释放 / 已被 queue_free（View 重建单位节点时会发生）→ 丢弃该动画，
	#    否则会给"已释放实例"写属性，触发 "Trying to assign invalid previously freed instance"
	#    并让游戏停在调试器断点（表现为卡死）—— V-004-16 实测缺陷
	var tg: Node = null
	if st.has("tref"):
		var wr = st["tref"]
		tg = wr.get_ref() if wr != null else null
	if tg == null:
		_running.erase(key)      # 目标已释放（弱引用失效）→ 丢弃
		return
	if not is_instance_valid(tg) or tg.is_queued_for_deletion():
		_running.erase(key)
		return
	# 迭代024 缺陷修复：**本函数一次调用 = 推进一个游戏帧**，因此在同一次调用里
	#   **把所有 units（并行单元）各推进一帧**。
	#   此前实现按"当前单元下标"一次只推进一个单元，导致多单元 Pattern（如浮字=移动+变色）
	#   每帧被推进多次 → 帧数计时失真（实测浮字配置 60 帧却调用 100 次、耗时 1711ms）。
	var units: Array = p.get("units", [])
	if units.is_empty():
		stop(key)
		return
	st["frames"] = int(st.get("frames", 0)) + 1      # 实例存活帧数（用于实测时长）
	for i in units.size():
		var unit: Dictionary = units[i]
		var clips: Array = unit.get("clips", [])
		var c: int = maxi(0, int((st["c"] as Array)[i]))
		if c >= clips.size():
			continue
		_apply_clip(clips[c], st, unit)
		var frames: int = maxi(1, int(clips[c].get("frames", 1)))
		var f: int = int((st["f"] as Array)[i]) + 1
		(st["f"] as Array)[i] = f
		if f >= frames:
			(st["c"] as Array)[i] = c + 1
			(st["f"] as Array)[i] = 0
	# 所有单元都播完 → 结束
	# ⚠️ 空 clips 的单元必须视为"已完成"，否则 done 永远为 false → 该实例永不停、主循环空转（实测卡死）
	var done := true
	for i in units.size():
		var nclips: int = (units[i].get("clips", []) as Array).size()
		if nclips > 0 and int((st["c"] as Array)[i]) < nclips:
			done = false
			break
	if done:
		stop(key)


# ============================================================
# 5 类 Unit 的动作执行
# ============================================================

func _apply_clip(clip: Dictionary, st: Dictionary, unit: Dictionary) -> void:
	# ⚠️ 从**弱引用**解析目标：节点已释放则 get_ref() 返回 null（绝不直接存强引用）
	var tgt: Node = null
	if st.has("tref"):
		var wr = st["tref"]
		tgt = wr.get_ref() if wr != null else null
	if tgt == null or not is_instance_valid(tgt) or tgt.is_queued_for_deletion():
		return
	match int(unit.get("type", U.MOVE_BY)):
		U.MOVE_BY:
			# 移动/旋转**指定数值**（可叠加）
			var step: Vector2 = clip.get("step", Vector2.ZERO)
			if tgt is Node2D:
				(tgt as Node2D).position += step
			elif tgt is Control:
				(tgt as Control).position += step
			var rot: float = float(clip.get("rot", 0.0))
			if rot != 0.0 and tgt is Node2D:
				(tgt as Node2D).rotation += rot
		U.MOVE_TO:
			# 移动/旋转**到指定数值**（不可重复）：有 from 则插值，否则直接置位
			var to: Vector2 = clip.get("to", Vector2.ZERO)
			var pos: Vector2 = to
			if clip.has("from"):
				var total: int = maxi(1, int(clip.get("frames", 1)))
				var t: float = float(int(st["f"]) + 1) / float(total)
				pos = (clip["from"] as Vector2).lerp(to, t)
			if tgt is Node2D:
				(tgt as Node2D).position = pos
			elif tgt is Control:
				(tgt as Control).position = pos
		U.ROT_TRACK:
			# 旋转追踪目标（不可重复）
			var track: Node = clip.get("track", null)
			if track != null and is_instance_valid(track) and tgt is Node2D and track is Node2D:
				var a: Vector2 = (tgt as Node2D).global_position
				var b: Vector2 = (track as Node2D).global_position
				if a.distance_to(b) > 0.01:
					(tgt as Node2D).global_rotation = (b - a).angle()
		U.TINT:
			var col: Color = clip.get("color", Color.WHITE)
			if tgt is CanvasItem:
				(tgt as CanvasItem).modulate = col
		U.SPAWN_FX:
			_spawn_fx(clip, tgt)


func _spawn_fx(clip: Dictionary, tgt: Node) -> void:
	var scene: PackedScene = clip.get("scene", null)
	if scene == null or fx_parent == null:
		return
	var n: Node = scene.instantiate()
	fx_parent.add_child(n)
	if n is Node2D and tgt is Node2D:
		(n as Node2D).global_position = (tgt as Node2D).global_position
	if n.has_method("play_once"):
		n.call("play_once", int(clip.get("frames", 12)))


## 初始状态（ResetUnit）：恢复 pattern.inited 声明的字段
func _apply_initial(name: String, target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	var init: Dictionary = _patterns.get(name, {}).get("inited", {})
	for key in init:
		target.set(str(key), init[key])


# ============================================================
# 迭代004 默认 Pattern（依据《动画系统及流程.md》二、动画顺序与表现规范）
# ============================================================

## 受伤/回费/回血 文本色（表现规范）
const DAMAGE_COLOR := Color("ff2000")   ## 受伤
const REFUND_COLOR := Color("ffa300")   ## 回费
const HEAL_COLOR := Color("00dd00")     ## 回血
const TURN_MINE := Color("499169")      ## 我方回合 UI
const TURN_FOE := Color("a84331")       ## 敌方回合 UI
const NEUTRAL_COLOR := Color(1, 1, 1, 0.5)  ## #FFFFFF-50%（中性/结束态）


## UI 回合色（表现规范「UI状态与颜色映射」）：我方 #499169 / 敌方 #A84331
func turn_color(is_mine: bool) -> Color:
	return TURN_MINE if is_mine else TURN_FOE


## 注册默认 Pattern（cfg 可覆盖幅度/帧数，便于按表现规范调参而不改代码）
func register_defaults(_cfg: Dictionary = {}) -> void:

	# ① 单位受击抖动 / ③ AOE 地图抖动：**定义只有一处** —— 统一由 _register_shake 构建
	#   （迭代022：此前默认序列与运行时重新注册各写一份，时长/段数会互相打架）
	_register_shake("受击抖动", D.SHAKE_AMP_UNIT, 5, D.SHAKE_FRAMES_UNIT)
	_register_shake("地图抖动", D.SHAKE_AMP_MAP, 5, D.SHAKE_FRAMES_MAP)   # value=5 为基准（不延长）
	# ② 场景内飘字（含回费数字）：同样在默认注册时就建好，避免"查不到/两处定义"
	_register_float_pattern()
	# ④ 卡牌登场：**瞬间动作（无前摇）** —— 第 1 帧即到位，只做淡入
	register("卡牌登场", {
		"units": [
			{"type": U.TINT, "clips": [{"frames": 1, "color": Color(1, 1, 1, 0.0)}]},
			{"type": U.TINT, "clips": [{"frames": 4, "color": Color(1, 1, 1, 1.0)}]},
		],
	})
	# ⑤ 卡牌退场：末帧即刻消失（无后摇）
	register("卡牌退场", {
		"units": [{"type": U.TINT, "clips": [
			{"frames": 3, "color": Color(1, 0.6, 0.6, 1.0)},
			{"frames": 2, "color": Color(1, 1, 1, 0.0)},
		]}],
	})
	# ⑥ 回合色（我方/敌方）：UI 状态与颜色映射
	register("回合色-我方", {"units": [{"type": U.TINT, "clips": [{"frames": 1, "color": TURN_MINE}]}]})
	register("回合色-敌方", {"units": [{"type": U.TINT, "clips": [{"frames": 1, "color": TURN_FOE}]}]})

	# ⑧ 迭代004 检查点5/11 · **禁 UI 交互**演示 Pattern（block_ui）—— 用于实测"动画期间点击被拦"
	#   真实用途：结算演示 / 胜负演出等"期间不允许操作"的整段表现
	register("结算演示", {
		"units": [
			{"type": U.TINT, "clips": [{"frames": 20, "color": Color(1, 1, 1, 1)}]},
		],
		"block_ui": true,          # 运行期间 ui_locked = true
		"pause_global": true,
	})
	# ⑨ 迭代004 检查点5 · **不受全局暂停**演示 Pattern（pause_global=false）—— 实测暂停语义
	register("常驻呼吸", {
		"units": [
			{"type": U.TINT, "clips": [{"frames": 10, "color": Color(1, 1, 1, 1)}]},
		],
		"pause_global": false,     # 全局暂停时仍继续推进
	})

	# ⑦ 迭代004 检查点6 · 瞬时动作表现（六类中补齐：部署/移动/使用指令/数值buff）
	#   部署：落位下沉 → 回弹（瞬间动作，无前摇）
	register("部署落位", {
		"units": [{"type": U.MOVE_BY, "clips": [
			{"frames": 1, "step": Vector2(0, 8)},
			{"frames": 2, "step": Vector2(0, -8)},
		]}],
	})
	#   移动：一次短促左右微移（无前摇）
	# 迭代026（人实测：**移动时的抖动过于影响观感**）→ 移除左右抖动，只做"落位"
	#   原为 +5 / -10 / +5 的 3 帧左右抖，移动时会与受击抖动混淆；现仅保留一次轻微下沉回弹（纵向，不左右晃）
	register("移动落位", {
		"units": [{"type": U.MOVE_BY, "clips": [
			{"frames": 1, "step": Vector2(0, 3)},
			{"frames": 1, "step": Vector2(0, -3)},
		]}],
	})
	#   使用指令：施放者闪白一次（第 1 帧即亮 = 无前摇）
	register("施放闪白", {
		"units": [
			{"type": U.TINT, "clips": [{"frames": 1, "color": Color(1, 1, 1, 1)}]},
			{"type": U.TINT, "clips": [{"frames": 1, "color": Color(1.0, 0.95, 0.6, 1)}]},
			{"type": U.TINT, "clips": [{"frames": 2, "color": Color.WHITE}]},
		],
	})
	#   数值 buff：目标变色脉冲（增益绿 / 减益红，由调用方选择）
	register("增益脉冲", {
		"units": [
			{"type": U.TINT, "clips": [{"frames": 1, "color": Color("66ff88")}]},
			{"type": U.TINT, "clips": [{"frames": 3, "color": Color.WHITE}]},
		],
	})
	register("减益脉冲", {
		"units": [
			{"type": U.TINT, "clips": [{"frames": 1, "color": Color("ff6666")}]},
			{"type": U.TINT, "clips": [{"frames": 3, "color": Color.WHITE}]},
		],
	})


## 按**单位 id** 播放动画（内部经 node_provider 解析节点；解析不到则静默跳过）
## —— 供各逻辑模块接线使用，避免它们直接依赖 View 的内部字段
func play_on_unit(unit_id: int, pname: String) -> void:
	var n: Node = _node_of(unit_id)
	if n != null:
		action(pname, n)


## 带数值的抖动（幅度随数值缩放）
func play_shake_on_unit(unit_id: int, value: int) -> void:
	var n: Node = _node_of(unit_id)
	if n != null:
		shake_unit(n, value)


## ============================================================
## 浮动数值文本（迭代004 检查点7/8）—— 回费 #FFA300 / 受伤 #FF2000 / 回血 #00DD00，字号随数值
## 用引擎自身的 Pattern 驱动「上浮 + 淡出」（无前摇：第 1 帧即到位），播完自释放
## ============================================================
func float_text(value: int, kind: String, at: Vector2, parent: Node = null) -> Node:
	if value == 0:
		return null
	var host: Node = parent if parent != null else fx_parent
	if host == null:
		return null
	var show_v: int = absi(value)
	var lbl: Node = D.digit_node(show_v, float(text_size_for(show_v)), text_color(kind), at)
	if lbl == null:
		return null
	lbl.set_meta("fx_once", true)          # 播完自释放（在 stop 时处理）
	host.add_child(lbl)
	_ensure_float_pattern()
	action("浮字上浮", lbl)
	return lbl


func _ensure_float_pattern() -> void:
	if _patterns.has("浮字上浮"):
		return
	# 迭代023（人实测"太快了"）：飘字时长上修到 60 帧 = 1.0s（含回费数字）
	#   上浮 40 帧（递减步长）+ 淡出 20 帧；时长/上浮帧数取自 battle_defs 常量（单一来源）
	_register_float_pattern()


func _register_float_pattern() -> void:
	var total: int = D.FLOAT_TEXT_FRAMES
	var rise: int = mini(D.FLOAT_TEXT_RISE, total - 1)
	var fade: int = maxi(1, total - rise)
	@warning_ignore("integer_division")
	var seg: int = maxi(1, rise / 5)
	var clips_move: Array = []
	var steps: Array = [-8, -7, -5, -3, -2]
	for sv in steps:
		clips_move.append({"frames": seg, "step": Vector2(0, sv)})
	register("浮字上浮", {
		"units": [
			{"type": U.MOVE_BY, "clips": clips_move},
			{"type": U.TINT, "clips": [
				{"frames": rise, "color": Color(1, 1, 1, 1)},
				{"frames": fade, "color": Color(1, 1, 1, 0)},
			]},
		],
	})


## 按表现规范（基础动画.md §三）：**数值越大字号越大**，在 0~25 区间**线性映射**。
## 字号单位为**固定设计空间像素（1920×1080 基准）**；屏幕整体缩放时内容比例不变（T2 用帧数，此处为设计空间尺寸）。
## ⚠️ 迭代019（人明确）：BASE/MAX 先按设计空间**预设**，随后按**实机测试结果返工**调整这两个常量即可。
const TEXT_FS_BASE := 40    ## 数值 0 时的字号（设计空间 px）
const TEXT_FS_MAX := 96     ## 数值 ≥ TEXT_FS_VMAX 时的字号（设计空间 px）
const TEXT_FS_VMAX := 25    ## 规范区间上限（A5：绝大多数数值落在 0~25）

func text_size_for(value: int) -> int:
	var v: int = mini(absi(value), TEXT_FS_VMAX)
	var k: float = float(v) / float(TEXT_FS_VMAX)
	return int(round(lerpf(float(TEXT_FS_BASE), float(TEXT_FS_MAX), k)))


## 数值文本颜色（按种类）
func text_color(kind: String) -> Color:
	match kind:
		"damage":
			return DAMAGE_COLOR
		"refund":
			return REFUND_COLOR
		"heal":
			return HEAL_COLOR
	return Color.WHITE


# ============================================================
# 表现时机接入（迭代004 第4b步）—— **引擎自连接**
# 设计：不改协调器顶层作用域；引擎持有共享 Model，自己监听信号驱动 Pattern
# ============================================================

## 共享 Model（bind 时记录）
var _state: Node = null
## 单位 id → 表现节点 的解析回调（由协调器注入；避免依赖 View 内部字段）
var node_provider: Callable = Callable()
## 已播过登场的单位 id
var _seen := {}


## 绑定共享 Model：连接**语义明确、低频**的游戏信号 → 驱动本引擎
## ⚠️ 经验（V-004-4）：**不要用 state_changed（重绘信号）驱动逐帧动画** ——
##    该信号频率高、易与状态推进形成同帧重入；只接语义明确的低频信号。
func bind(st: Node) -> void:
	_state = st
	if st == null:
		return
	# ① 受击：战斗结算信号（此前全项目无人接收）→ 受击方抖动 + 受伤闪红；反击方也抖动
	if st.combat != null and not st.combat.attack_resolved.is_connected(_on_attack_resolved):
		st.combat.attack_resolved.connect(_on_attack_resolved)
	# ② 胜负：终止全部动画（stop_all 不复位，符合规则 3）
	if not st.battle_ended.is_connected(_on_battle_ended):
		st.battle_ended.connect(_on_battle_ended)
	# ③ 卡牌登场：改由**低频的 turn_started** 驱动探测（每回合开始探测一次，不跟重绘）
	if not st.turn_started.is_connected(_on_turn_started_anim):
		st.turn_started.connect(_on_turn_started_anim)


func _node_of(id: int) -> Node:
	if not node_provider.is_valid():
		return null
	var n = node_provider.call(id)
	return n if (n != null and is_instance_valid(n)) else null


func _on_attack_resolved(aid: int, tid: int, dmg: int, counter: int, countered: bool) -> void:
	# 迭代021 缺陷修复：战斗信号在 combat.attack() 内**同步发出**，而调用方随后会 `refresh()` ——
	#   refresh 会**重建棋盘单位节点**，于是打在旧节点上的抖动/闪红随旧节点被丢弃
	#   （实测：攻击后受击单位位移 = 0，即"抖动从未生效"）。
	#   → 推迟到**本帧末**执行 `call_deferred`：此时 refresh 已完成，取到的是**新节点**，表现才留得住。
	_deferred_hit_fx.call_deferred(aid, tid, dmg, counter, countered)


func _deferred_hit_fx(aid: int, tid: int, dmg: int, counter: int, countered: bool) -> void:
	if dmg > 0:
		var tn: Node = _node_of(tid)
		if tn != null:
			shake_unit(tn, dmg)          # 幅度随伤害数值缩放
			action("受伤闪红", tn)
	if countered and counter > 0 and aid != tid:
		var an: Node = _node_of(aid)
		if an != null:
			shake_unit(an, counter)


func _on_state_changed() -> void:
	pass   # 已废弃：不再用重绘信号驱动逐帧动画（见 bind 的注释）


## 回合开始（低频）：探测并播出"卡牌登场"（瞬间动作，无前摇）
func _on_turn_started_anim(_side: String, _rn: int) -> void:
	if _state == null:
		return
	for id in _state.units.keys():
		if _seen.has(id):
			continue
		var n: Node = _node_of(id)
		if n != null:
			_seen[id] = true
			action("卡牌登场", n)


func _on_battle_ended(_winner: String) -> void:
	stop_all()


## AOE 地图抖动：技能命中多个目标（溅射/链式）时由技能层调用
## value>0 时**幅度随数值缩放**（伤害越高抖得越狠）—— 检查点9
func shake_map(map_node: Node = null, value: int = 0) -> void:
	var tgt: Node = map_node
	if tgt == null and _state != null:
		tgt = _state.get_parent()
	if tgt != null:
		_register_shake("地图抖动", D.SHAKE_AMP_MAP, value, D.SHAKE_FRAMES_MAP)
		action("地图抖动", tgt)


## 单位受击抖动（幅度随数值缩放）—— 检查点9
func shake_unit(tgt: Node, value: int = 0) -> void:
	if tgt == null:
		return
	_register_shake("受击抖动", D.SHAKE_AMP_UNIT, value, D.SHAKE_FRAMES_UNIT)
	action("受击抖动", tgt)


## 幅度随数值缩放：以 4 点为基准线性放大，钳制在 [0.6x, 2.0x]（避免过小看不清 / 过大失稳）
func _scaled_amp(base: float, value: int) -> float:
	if value <= 0:
		return base
	return base * clampf(float(value) / 4.0, 0.6, 2.0)


## 按缩放后的幅度**重新注册**抖动 Pattern（幅度属 Pattern 数据，就地更新即可）
## 迭代026（人实测策略）：高伤害**优先延长时间**（而非堆幅度）——
##   总帧数 = 基准帧数 + round(BONUS_MAX × clamp((伤害-4)/8, 0, 1))
##   段数与衰减不变，故"每段帧数"随之变长 → 高伤害抖得更久、且单次摇摆更舒缓（不 Q 弹）
func _shake_frames_for(pname: String, value: int) -> int:
	var base_frames: int = D.SHAKE_FRAMES_MAP if pname == "地图抖动" else D.SHAKE_FRAMES_UNIT
	if value <= 4:
		return base_frames
	var t01: float = clampf(float(value - 4) / 4.0, 0.0, 1.0)   # 伤害 ≤6 不延长；≥7 延长一段（≈0.88s）
	# 以**整段**为单位延长：每段帧数 = 总帧数 / SHAKE_STEPS 会取整，
	# 若延长量不是段长的整数倍，多出的帧会被取整吃掉（迭代026 实测 56→52）
	var steps_up: int = int(round(t01))                      # 0 或 1 段（伤害 ≥7 → 1 段）
	return base_frames + steps_up * D.SHAKE_FRAMES_BONUS_MAX


func _register_shake(pname: String, base_amp: float, value: int, _frames: int) -> void:
	# 迭代019：此处**不能**用旧的四段等幅序列 —— 它会在运行时覆盖 `_build_defaults` 里
	#   已按《基础动画.md》§四 修正过的"弹性衰减 + 固定时长"定义（此前 8/16 帧的偏差即由此产生）。
	#   现在只**按数值重算振幅**，时序沿用规范：受击 15 帧（0.25s）· 地图 30 帧（0.5s）。
	var amp: float = _scaled_amp(base_amp, value)
	var is_map: bool = pname == "地图抖动"      # 地图抖动走 上下→左右 往复；单位抖动走左右
	var k: int = D.SHAKE_STEPS
	var total: int = _shake_frames_for(pname, value)   # 迭代026：高伤害延长时长
	@warning_ignore("integer_division")
	var per: int = maxi(1, total / k)
	# ============================================================
	# 波形生成（迭代027 重大修正）：**围绕原位对称震荡**
	#
	# 迭代026 及以前：直接交替 ±振幅并累加 → 由于 MOVE_BY 是**累加**位移，
	#   累加和序列的**均值不为 0**（实测 +7.3px），整段动画都偏在一侧 →
	#   观感就是"单位先右移一段、在新位置震动、结束时才跳回原位"（人实测指出）。
	#
	# 现在：先算出**逐段的目标位置**（标准弹性衰减：递减的峰值 0→+A→-A′→+A″…），
	#   再**减去位置均值**做居中，最后**转为相邻位移（step）**。
	#   → 首段即围绕原位、全程对称、末段精确回到 0。
	# ============================================================
	var loc: Array = []                  # 目标位置（相对原位）
	var mag := amp
	var sign_ := 1.0
	var cur := 0.0
	for i in k:
		cur += sign_ * mag
		loc.append(cur)
		mag *= D.SHAKE_DECAY
		sign_ = -sign_
	# ① 居中：减去均值（这是"基准位置=原始位置"的关键）
	var mean := 0.0
	for v in loc:
		mean += float(v)
	mean /= float(k)
	for i in k:
		loc[i] = float(loc[i]) - mean
	# ② 末尾归零（收尾必须回到原位）
	loc[k - 1] = 0.0
	# ③ 位置 → 相邻位移（step）；地图抖动走"上下→左右"交替，单位抖动走左右
	var clips: Array = []
	var prev := 0.0
	for i in k:
		var step: float = float(loc[i]) - prev
		prev = float(loc[i])
		if is_map:
			clips.append({"frames": per, "step": (Vector2(0, step) if i % 2 == 0 else Vector2(step, 0))})
		else:
			clips.append({"frames": per, "step": Vector2(step, 0)})
	register(pname, {"units": [{"type": U.MOVE_BY, "clips": clips}]})


## 清除已见记录（对局重开时调用）
func clear_seen() -> void:
	_seen.clear()

## 迭代024：该 Pattern 各单元中**最长**的帧数（并行口径 = 动画时长）
func _inst_frames(name: String) -> int:
	var p: Dictionary = _patterns.get(name, {})
	var mx := 0
	for u in (p.get("units", []) as Array):
		var f := 0
		for c in (u.get("clips", []) as Array):
			f += int(c.get("frames", 0))
		mx = maxi(mx, f)
	return mx
