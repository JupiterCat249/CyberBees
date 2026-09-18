class_name BattleAnimDriver
extends Node
## BattleAnimDriver —— 把 **GameState 的规则事件**翻译成 **ActionUnit 动画**
##
## 分层定位：
##   GameState（规则）──信号──▶ 本类（翻译）──action()──▶ ActionUnit（表现）
##   · 本类**不持有规则状态**、不改规则；只决定"发生 X 事件时播哪个动画"
##   · 目标节点从 `node_provider` 解析（由接线层提供「单位 instance_id → 节点」映射）
##
## ⚠️ 时序要点（沿用旧实现踩过的坑）：
##   · 单位**退场**必须等动画播完才真正移除 → `单位退场` 的 `trigger_on_stop_call`
##     回调 `on_unit_fade_out_done(节点)`：本类收到后把"待移除"名单交给接线层处理
##   · 运行时遍历运行表时**先复制键快照**（引擎内部已做）；本类的回调里也只做挂起登记

signal unit_fade_out_done(instance_id: String)

const AU := preload("res://scripts/game/action_unit.gd")
const Presets := preload("res://scripts/game/anim_presets.gd")

var engine: Node = null                ## ActionUnit 实例
var node_provider: Callable = Callable()
var _pending_remove := {}              ## 退场动画中：instance_id → true

## 事件队列：规则事件先排队，由本类在下一帧统一触发动画
##   （避免"信号回调里再改树"造成的遍历被改问题）
var _queue: Array = []


func _ready() -> void:
	engine = AU.new()
	engine.name = "ActionUnit"
	add_child(engine)
	Presets.register_all(engine)
	engine.node_provider = func(id: String) -> Node:
		return node_provider.call(id) if node_provider.is_valid() else null


## 接线层注入：单位 instance_id → 节点
func set_node_provider(f: Callable) -> void:
	node_provider = f

## 接线层注入：一次性特效（飘字）的宿主
func set_fx_parent(n: Node) -> void:
	if engine != null:
		engine.fx_parent = n


# ============================================================
# 规则事件 → 动画
# ============================================================

func on_unit_spawned(inst: UnitInstance) -> void:
	play_for(inst, "部署落位")
	play_for(inst, "卡牌登场")

func on_unit_moved(inst: UnitInstance) -> void:
	play_for(inst, "移动落位")

func on_unit_damaged(inst: UnitInstance, amount: int) -> void:
	if inst == null or amount <= 0:
		return
	play_for(inst, "受击抖动", amount)
	float_text_at(inst, amount, "damage")

func on_effect_changed(inst: UnitInstance) -> void:
	play_for(inst, "增益脉冲")

func on_command_cast(caster: UnitInstance) -> void:
	play_for(caster, "施放闪白")

func on_cost_recovered(side: int, amount: int, at: Vector2) -> void:
	if amount == 0:
		return
	float_text_raw(amount, "refund", at)

## 单位退场：先播淡出，**播完**才通知接线层真正移除
func on_unit_removed(inst: UnitInstance) -> void:
	if inst == null:
		return
	var node := _node_of(inst.instance_id)
	if node == null:
		unit_fade_out_done.emit(inst.instance_id)
		return
	_pending_remove[inst.instance_id] = true
	engine.action("单位退场", node)


## `单位退场` 的结束回调（由 ActionUnit 在"动画自然播完"时调用）
func on_unit_fade_out_done(node: Node) -> void:
	if node == null:
		return
	# 反查 instance_id
	for id in _pending_remove.keys():
		if _node_of(String(id)) == node:
			_pending_remove.erase(id)
			unit_fade_out_done.emit(String(id))
			return


# ============================================================
# 便捷
# ============================================================

func play_for(inst: UnitInstance, pname: String, value: int = 0) -> void:
	if inst == null:
		return
	var node := _node_of(inst.instance_id)
	if node == null:
		return
	if pname == "受击抖动":
		# 抖动是**按数值即时生成**的（幅度/时长随伤害），故不能只注册静态 pattern
		var built: Dictionary = Presets.build_shake(pname, value, hash(inst.instance_id) + value)
		engine.register(pname, built)
	engine.action(pname, node)


## 在单位所在位置飘一个数值
func float_text_at(inst: UnitInstance, value: int, kind: String) -> void:
	if inst == null or engine == null or engine.fx_parent == null:
		return
	var node := _node_of(inst.instance_id)
	if node == null:
		return
	var at: Vector2 = node.global_position + Vector2(0, 60)
	float_text_raw(value, kind, at)


func float_text_raw(value: int, kind: String, at: Vector2) -> void:
	if engine == null or engine.fx_parent == null or value == 0:
		return
	var lbl: Label = Presets.make_float_label(value, kind)
	engine.fx_parent.add_child(lbl)
	lbl.position = at
	engine.action("浮字上浮", lbl)


func _node_of(instance_id: String) -> Node:
	if node_provider.is_valid():
		return node_provider.call(instance_id) as Node
	return null


## 是否有动画锁着 UI（结算演出期间禁止点击）
func ui_locked() -> bool:
	return engine != null and engine.ui_locked


func stop_all() -> void:
	if engine != null:
		engine.stop_all()
	_pending_remove.clear()
