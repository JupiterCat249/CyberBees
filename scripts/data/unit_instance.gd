class_name UnitInstance
extends RefCounted
## 单位的**运行态**（与数据层严格分离 —— 设计案 §3.3 R2）
##
## 为什么必须分离：Godot 对同一路径的资源只加载一份实例（官方手册），
## 若把 current_hp 写进 UnitData，则"一个叶蜂掉血"会让场上所有叶蜂一起掉血。

signal hp_changed(inst: UnitInstance, old_hp: int, new_hp: int)
signal effects_changed(inst: UnitInstance)
signal acted_changed(inst: UnitInstance)

var data: UnitData                       ## ← 只读引用，**绝不写回**
var side: int = 0                        ## 0 = 绿方(我) / 1 = 红方(敌)（D3/D6）
var cell: Vector2i = Vector2i.ZERO
var current_hp: int = 0                  ## ← 可变的在这里
var effects: Array[EffectRuntime] = []
var has_moved: bool = false
var has_acted: bool = false
var instance_id: String = ""             ## UUID（D-4）：每个实例独立 ID


static func create(p_data: UnitData, p_side: int, p_cell: Vector2i) -> UnitInstance:
	var inst := UnitInstance.new()
	inst.setup(p_data, p_side, p_cell)
	return inst


func setup(p_data: UnitData, p_side: int, p_cell: Vector2i) -> void:
	data = p_data
	side = p_side
	cell = p_cell
	current_hp = p_data.hp if p_data != null else 0   ## 初值来自数据，之后只改本实例
	instance_id = Uuid.generate()


# ---------------- 只读访问（视图层取值的唯一入口） ----------------

func card_name() -> String:
	return data.display_name if data != null else ""


func is_alive() -> bool:
	return current_hp > 0


## 含效果修正后的攻击力（乘优先于加 —— a500 口径）
func atk() -> int:
	var v := float(data.atk)
	for e in effects:
		v *= e.data.atk_mul
	for e in effects:
		v += float(e.data.atk_add)
	return maxi(0, int(round(v)))


func max_hp() -> int:
	return data.hp if data != null else 0


func move_range() -> int:
	return data.move if data != null else 0


func attack_range() -> int:
	return data.attack_range if data != null else 0


func has_effect(effect_id: String) -> bool:
	for e in effects:
		if e.data != null and e.data.id == effect_id:
			return true
	return false


# ---------------- 变更（只在本实例上） ----------------

func set_hp(v: int) -> void:
	var old := current_hp
	current_hp = clampi(v, 0, max_hp())
	if current_hp != old:
		hp_changed.emit(self, old, current_hp)


## 直接扣血（**不再在此处减免**）
## ⚠️ 迭代056 修正：原先这里也做 `dmg_reduce` 减免，而规则层的 `raw_damage()` 同样减过一次
##    → **伤害被双重减免**（装甲 2 + 攻击 4 会算成 0 伤害）。a500「攻击计算优先于伤害减免」
##    要求减免只算一次，故减免职责**统一收归规则层**（RulesCombat.raw_damage）。
func damage(amount: int) -> int:
	var real := maxi(0, amount)          # 入参已由规则层扣完减免
	set_hp(current_hp - real)
	return real


func heal(amount: int) -> void:
	set_hp(current_hp + amount)


## T14：相同效果最多一个 → 已存在则**不叠加**（只刷新计数）
func apply_effect(e: EffectData) -> bool:
	if e == null:
		return false
	for ex in effects:
		if ex.data != null and ex.data.id == e.id:
			ex.turns = e.duration
			effects_changed.emit(self)
			return false
	effects.append(EffectRuntime.new(e))
	effects_changed.emit(self)
	return true


func remove_effect(effect_id: String) -> void:
	for i in range(effects.size() - 1, -1, -1):
		if effects[i].data != null and effects[i].data.id == effect_id:
			effects.remove_at(i)
			effects_changed.emit(self)
			return


func mark_moved() -> void:
	has_moved = true
	acted_changed.emit(self)


func mark_acted() -> void:
	has_acted = true
	acted_changed.emit(self)


func reset_turn_flags() -> void:
	has_moved = false
	has_acted = false
	acted_changed.emit(self)
