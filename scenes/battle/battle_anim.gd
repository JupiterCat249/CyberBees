extends Node
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
	_running[name] = {"i": 0, "c": 0, "f": 0, "target": target}
	var p: Dictionary = _patterns[name]
	var on_start := str(p.get("trigger_on_start", ""))
	if on_start != "" and _patterns.has(on_start):
		action(on_start, target)
	if bool(p.get("block_ui", false)):
		ui_locked = true


## 重置：把目标恢复到 Pattern 的初始状态
func reset_unit(name: String, target: Node = null) -> void:
	_apply_initial(name, target)


## 终止：级联终止（本 Pattern 的所有 Unit 一并终止），**不复位**（规则 3）；终止时可触发下一动画
func stop(name: String) -> void:
	if not _running.has(name):
		return
	var tgt: Node = _running[name].get("target", null)
	_running.erase(name)
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


func is_running(name: String) -> bool:
	return _running.has(name)


func running_names() -> Array:
	return _running.keys()


func _any_running_blocking() -> bool:
	for n in _running:
		if bool(_patterns.get(n, {}).get("block_ui", false)):
			return true
	return false


# ============================================================
# 逐帧推进（T2：帧数计时）
# ============================================================

func _process(_delta: float) -> void:
	if _running.is_empty():
		return
	for name in _running.keys():
		var p: Dictionary = _patterns.get(name, {})
		if anim_paused and bool(p.get("pause_global", true)):
			continue
		_step(name)


func _step(name: String) -> void:
	var st: Dictionary = _running[name]
	var p: Dictionary = _patterns[name]
	var units: Array = p.get("units", [])
	var i: int = int(st["i"])
	if i >= units.size():
		stop(name)
		return
	var unit: Dictionary = units[i]
	var clips: Array = unit.get("clips", [])
	var c: int = int(st["c"])
	if c >= clips.size():
		st["i"] = i + 1
		st["c"] = 0
		st["f"] = 0
		return
	_apply_clip(clips[c], st, unit)
	var frames: int = maxi(1, int(clips[c].get("frames", 1)))
	st["f"] = int(st["f"]) + 1
	if int(st["f"]) >= frames:
		st["c"] = c + 1
		st["f"] = 0


# ============================================================
# 5 类 Unit 的动作执行
# ============================================================

func _apply_clip(clip: Dictionary, st: Dictionary, unit: Dictionary) -> void:
	var tgt: Node = st.get("target", null)
	if tgt == null or not is_instance_valid(tgt):
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


## 注册默认 Pattern（cfg 可覆盖幅度/帧数，便于按表现规范调参而不改代码）
func register_defaults(cfg: Dictionary = {}) -> void:
	var amp: float = float(cfg.get("shake_amp", 6.0))      # 单位受击抖动幅度(px)
	var eamp: float = float(cfg.get("aoe_amp", 12.0))      # AOE 地图抖动幅度(px)

	# ① 单位受击抖动：左右往复（MOVE_BY **可叠加**）→ 末段反向抵消回原位
	register("受击抖动", {
		"units": [{"type": U.MOVE_BY, "clips": [
			{"frames": 2, "step": Vector2(amp, 0)},
			{"frames": 2, "step": Vector2(-amp * 2.0, 0)},
			{"frames": 2, "step": Vector2(amp * 2.0, 0)},
			{"frames": 2, "step": Vector2(-amp, 0)},
		]}],
	})
	# ② 单位受伤闪红（TINT 变色）：#FF2000 → 橙 → 白
	register("受伤闪红", {
		"units": [
			{"type": U.TINT, "clips": [{"frames": 2, "color": DAMAGE_COLOR}]},
			{"type": U.TINT, "clips": [{"frames": 2, "color": Color("ff8800")}]},
			{"type": U.TINT, "clips": [{"frames": 2, "color": Color.WHITE}]},
		],
	})
	# ③ AOE 地图抖动：幅度更大、帧数更长（作用于地图根节点）
	register("地图抖动", {
		"units": [{"type": U.MOVE_BY, "clips": [
			{"frames": 2, "step": Vector2(0, -eamp)},
			{"frames": 2, "step": Vector2(0, eamp)},
			{"frames": 2, "step": Vector2(-eamp, 0)},
			{"frames": 2, "step": Vector2(eamp, 0)},
			{"frames": 2, "step": Vector2(-eamp * 0.5, 0)},
			{"frames": 2, "step": Vector2(eamp * 0.5, 0)},
		]}],
	})
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


## 按表现规范：数值文本字号随数值增长（返回字号）
func text_size_for(value: int) -> int:
	var v: int = absi(value)
	if v >= 8:
		return 72
	if v >= 5:
		return 60
	if v >= 3:
		return 52
	return 44


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


## 绑定共享 Model：连接游戏信号 → 驱动本引擎
func bind(st: Node) -> void:
	_state = st
	if st == null:
		return
	# ① 受击：战斗结算信号（此前全项目无人接收）→ 受击方抖动 + 受伤闪红；反击方也抖动
	if st.combat != null and not st.combat.attack_resolved.is_connected(_on_attack_resolved):
		st.combat.attack_resolved.connect(_on_attack_resolved)
	# ② 卡牌登场：状态重绘后为新出现的单位卡播登场（瞬间动作，无前摇）
	if not st.state_changed.is_connected(_on_state_changed):
		st.state_changed.connect(_on_state_changed)
	# ③ 胜负：终止全部动画（stop_all 不复位，符合规则 3）
	if not st.battle_ended.is_connected(_on_battle_ended):
		st.battle_ended.connect(_on_battle_ended)


func _node_of(id: int) -> Node:
	if not node_provider.is_valid():
		return null
	var n = node_provider.call(id)
	return n if (n != null and is_instance_valid(n)) else null


func _on_attack_resolved(aid: int, tid: int, dmg: int, counter: int, countered: bool) -> void:
	if dmg > 0:
		var tn: Node = _node_of(tid)
		if tn != null:
			action("受击抖动", tn)
			action("受伤闪红", tn)
	if countered and counter > 0 and aid != tid:
		var an: Node = _node_of(aid)
		if an != null:
			action("受击抖动", an)


func _on_state_changed() -> void:
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
func shake_map(map_node: Node = null) -> void:
	var tgt: Node = map_node
	if tgt == null and _state != null:
		tgt = _state.get_parent()
	if tgt != null:
		action("地图抖动", tgt)


## 清除已见记录（对局重开时调用）
func clear_seen() -> void:
	_seen.clear()
