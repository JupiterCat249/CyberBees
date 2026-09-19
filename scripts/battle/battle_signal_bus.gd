extends Node
## BattleSignalBus —— 战斗**信号总线**（**唯一通信中枢**）
##
## 用法（不注册 Autoload，避免全局名冲突与加载顺序坑）：
##   const Bus := preload("res://scripts/battle/battle_signal_bus.gd")
##   Bus.shared()                     # 取全局唯一实例（脚本内静态持有）
##   Bus.signal_x.emit(...)           # 发；Bus.signal_x.connect(...) 收
##
## 为什么不用 Autoload：① `class_name` 与 Autoload 同名会报 "hides an autoload singleton"
## ② `--check-only` 下 autoload 全局名不参与编译 ③ 记忆体记录过"Autoload _ready 早于场景
## _ready → 信号被漏接"的坑。preload 单例三条全避开，且仍是单一中枢。
##
## 设计意图（迭代056 · a500 重建）
##   · **规则层不引用 UI，UI 不读规则状态**：两侧都只通过本总线通信
##   · 规则层：结算完后 `BattleSignalBus.xxx.emit(...)` 广播
##   · 视图层：`BattleSignalBus.xxx.connect(_on_xxx)` 订阅，回调参数**直接给出对象与数值**
##
## 为什么用总线而不是"规则对象自己发信号"：
##   ① 视图只需知道**一个**连接目标，不必持有规则对象引用（连引用都解耦）
##   ② 规则层可独立实例化测试（无场景、无 Node 树依赖）
##   ③ 新增视图（战报/小地图/回放）零改动规则层
##
## 信号参数约定（依据 Godot 手册 §Signals：信号可写具名参数，emit 可传任意实参）：
##   · **一律用具名参数**，名字即语义 → 视图回调签名自解释
##   · 参数**直接给对象引用**（`UnitInstance` / `CardData` / `EffectData`）与**数值**，
##     视图不反查全局状态、不做 id→对象 的查找
##   · 需要额外上下文（如"哪一侧"）由发射方在参数里带全，不给视图留猜测空间
##
## ⚠️ 本文件**不 import 任何 scenes/、不 get_node、不判规则**。

# ============================================================
#  信号名常量
#  ⚠️ GDScript 不允许经 preload 的脚本类访问 `signal` 成员，故发射一侧统一用
#     `Bus.shared().emit_signal(Bus.SIG_XXX, ...)`；名字集中在此定义，**不写裸字符串**。
# ============================================================

const SIG_BATTLE_STARTED := "battle_started"
const SIG_ROUND_STARTED := "round_started"
const SIG_TURN_STARTED := "turn_started"
const SIG_TURN_ENDED := "turn_ended"
const SIG_PHASE_STARTED := "phase_started"
const SIG_PHASE_ENDED := "phase_ended"
const SIG_BATTLE_ENDED := "battle_ended"
const SIG_COST_CHANGED := "cost_changed"
const SIG_CARD_DRAWN := "card_drawn"
const SIG_HAND_CHANGED := "hand_changed"
const SIG_DECK_RESHUFFLED := "deck_reshuffled"
const SIG_CARD_DISCARDED := "card_discarded"
const SIG_CARD_PLAYABLE := "card_playable_changed"
const SIG_UNIT_SPAWNED := "unit_spawned"
const SIG_UNIT_MOVED := "unit_moved"
const SIG_UNIT_DAMAGED := "unit_damaged"
const SIG_UNIT_HEALED := "unit_healed"
const SIG_UNIT_REMOVED := "unit_removed"
const SIG_ATTACK_RESOLVED := "attack_resolved"
const SIG_COMMAND_RESOLVED := "command_resolved"
const SIG_EFFECT_GRANTED := "effect_granted"
const SIG_EFFECT_EXPIRED := "effect_expired"
const SIG_UNIT_STATS := "unit_stats_changed"
const SIG_SELECTION := "selection_changed"
const SIG_ACTION_AVAIL := "action_availability"
const SIG_MAIN_BUTTON := "main_button_state"
const SIG_LOG := "log_added"

# ============================================================
#  对局生命周期
# ============================================================

## 开局（a500 对战准备 9：部署蜂王，开始第一个回合）
signal battle_started(first_side: int, round_no: int, ally_name: String, enemy_name: String)
## 新一轮开始（两名玩家各走完回费/场地/部署/行动四阶段）
signal round_started(round_no: int)
## 某方回合开始
signal turn_started(side: int, round_no: int)
## 某方回合结束（a500 抽卡 4：回合结束后补手牌到 4 张）
signal turn_ended(side: int, round_no: int)
## 阶段开始（a500 回合流程 1~8）
signal phase_started(side: int, phase: int, round_no: int)
## 阶段结束
signal phase_ended(side: int, phase: int)
## 对局结束（a500 胜利条件 1~4）
signal battle_ended(result: int, reason: String)

# ============================================================
#  资源（费用 / 卡牌）
# ============================================================

## 费用变化（a500 费用 1~3）
signal cost_changed(side: int, cost: int, delta: int)
## 抽到一张卡（a500 抽卡 4）
signal card_drawn(side: int, card: CardData, hand_size: int)
## 手牌整体变化（供视图重建手牌）
signal hand_changed(side: int, hand: Array, playable_mask: Array)
## 牌库抽完 → 墓地前 4 张洗回（a500 抽卡 5）
signal deck_reshuffled(side: int, count: int)
## 丢弃卡牌（a500 抽卡 6：消耗等同部署费用）
signal card_discarded(side: int, card: CardData, cost_paid: int)
## 休卡：某张手牌变为"可出/不可出"（视图只更新那一张，避免整手重建）
signal card_playable_changed(side: int, hand_index: int, playable: bool, reason: String)

# ============================================================
#  单位
# ============================================================

## 单位入场（a500 抽卡 2：使用单位卡时复制一份部署）
signal unit_spawned(inst: UnitInstance, cell: Vector2i)
## 单位移动
signal unit_moved(inst: UnitInstance, from: Vector2i, to: Vector2i)
## 单位受伤（damage = 实际扣血；归零则随后 unit_removed）
signal unit_damaged(inst: UnitInstance, damage: int, hp_after: int, source: String)
## 单位治疗
signal unit_healed(inst: UnitInstance, amount: int, hp_after: int)
## 单位退场（a500 抽卡 3：被击败直接删除卡牌）
signal unit_removed(inst: UnitInstance, reason: String)

# ============================================================
#  战斗结算
# ============================================================

## 主动攻击 + 反击**同时结算**（a500 战斗 1~2）
signal attack_resolved(attacker: UnitInstance, defender: UnitInstance,
		damage_to_defender: int, damage_to_attacker: int, counter_valid: bool)
## 指令卡结算（a500 战斗 3）
signal command_resolved(side: int, card: CommandData, targets: Array,
		damage: int, healed: int)

# ============================================================
#  效果
# ============================================================

## 获得效果（a500 效果 1~3）
signal effect_granted(inst: UnitInstance, effect: EffectData, source: String)
## 效果消失（a500 效果 4：消失先于赋予）
signal effect_expired(inst: UnitInstance, effect: EffectData)
## 某单位的数值发生变化（攻/血/效果集合）→ 视图只需刷新该单位
signal unit_stats_changed(inst: UnitInstance)

# ============================================================
#  交互 / UI 状态（**规则层下发，视图只表现**）
# ============================================================

## 选中态与可操作集合变化（视图据此高亮；参数是**只读快照**，视图不反查）
signal selection_changed(kind: int, id: String, selectable_cells: Array,
		selectable_units: Array)
## 行动机会可用性（a500 行动机会 1~6）
signal action_availability(side: int, can_deploy: bool, can_move: bool,
		can_act: bool, can_end_phase: bool)
## 主按钮文案与可用态（视图只显示，不判断）
signal main_button_state(text: String, enabled: bool)
## 战报文本
signal log_added(text: String, level: int)

# ============================================================
#  便捷：清空所有连接（重开一局 / 视图重建时用）
# ============================================================

## 全局唯一实例（首次调用时创建，挂在场景树根下）
static var _instance: Node = null

static func shared() -> Node:
	if _instance == null or not is_instance_valid(_instance):
		var tree := Engine.get_main_loop() as SceneTree
		_instance = preload("res://scripts/battle/battle_signal_bus.gd").new()
		_instance.name = "BattleSignalBus"
		if tree != null and tree.root != null:
			tree.root.add_child.call_deferred(_instance)
	return _instance


func disconnect_all_of(target: Object) -> void:
	## 断开 target 与本总线全部信号之间的连接（避免视图重建后重复响应）
	for sig in get_signal_list():
		var sname := String(sig["name"])
		var s: Signal = get(sname)
		if s == null:
			continue
		for c in s.get_connections():
			if c["callable"].get_object() == target:
				s.disconnect(c["callable"])
