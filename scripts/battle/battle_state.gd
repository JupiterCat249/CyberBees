class_name BattleState
extends RefCounted
## 战斗状态（**纯数据**）
##
## 铁律（迭代056 解耦目标 G1/G4）：
##   · **零 UI 依赖**：不 `preload` 任何 `scenes/`、不 `get_node`、不引用 Control/Node 类型
##   · 只有数据与纯查询；**不改状态**（改状态一律由 BattleEngine 走规则模块）
##   · 视图**不直接读**本对象的内部字段，一切经 `BattleSignalBus` 广播的快照

## 阶段（a500 回合流程 1~8）
enum Phase { RECOVER, TERRAIN, DEPLOY, ACTION }

## 对局结果（a500 胜利条件 1~4）
enum Result { NONE, ALLY_WIN, ENEMY_WIN, DRAW }

const SIDE_ALLY := 0
const SIDE_ENEMY := 1
const MAX_COST := 10              ## a500 费用 2
const EXTRA_COST_FROM_ROUND := 7  ## a500 费用 3
const ROUND_EXTRA_COST := 2
const MAX_ROUNDS := 12            ## a500 胜利条件 2
const SURRENDER_FROM_ROUND := 4   ## a500 胜利条件 4

# ---------------- 对局 ----------------
var round_no: int = 1
var active: int = SIDE_ALLY
var phase: int = Phase.RECOVER
var result: int = Result.NONE
var result_reason: String = ""

## 本回合内是否已有单位行动过（用于"行动机会"提示，不影响规则）
var actions_this_turn: int = 0

# ---------------- 双方 ----------------
## 每侧：{ cost:int, hand:Array[CardData], deck:Array[CardData], discard:Array[CardData], queen:UnitInstance }
var sides := {}

# ---------------- 棋盘 ----------------
var board: Board = null

# ---------------- 规则扩展点 ----------------
## 场地效果（地图数据；None = 无）
var map_data: MapData = null
## 场地效果已结算的回合（避免同回合重复触发）
var terrain_resolved_rounds := {}
## 本回合某侧是否已使用过指令卡（a500：指令卡在"部署与行动阶段均可使用"）
var command_used_this_phase := {SIDE_ALLY: false, SIDE_ENEMY: false}


func setup(config: BattleConfig) -> void:
	board = Board.new()
	sides = {
		SIDE_ALLY: {"cost": 0, "hand": [], "deck": [], "discard": [], "queen": null},
		SIDE_ENEMY: {"cost": 0, "hand": [], "deck": [], "discard": [], "queen": null},
	}
	map_data = config.map_data
	active = config.first_side
	round_no = 1
	phase = Phase.RECOVER
	result = Result.NONE
	result_reason = ""
	terrain_resolved_rounds = {}
	command_used_this_phase = {SIDE_ALLY: false, SIDE_ENEMY: false}


# ============================================================
#  纯查询（不改状态）
# ============================================================

func cost(side: int) -> int:
	return int(sides[side]["cost"])


func hand(side: int) -> Array:
	return sides[side]["hand"]


func deck(side: int) -> Array:
	return sides[side]["deck"]


func discard(side: int) -> Array:
	return sides[side]["discard"]


func queen(side: int) -> UnitInstance:
	return sides[side]["queen"]


func units(side: int) -> Array[UnitInstance]:
	return board.units_of(side) if board != null else ([] as Array[UnitInstance])


func all_units() -> Array[UnitInstance]:
	return board.all_units() if board != null else ([] as Array[UnitInstance])


func opponent(side: int) -> int:
	return SIDE_ENEMY if side == SIDE_ALLY else SIDE_ALLY


## 本回合的回费量（a500 费用 3：第 7 回合起 +2；[回费] 技能按单位结算）
func recover_gain(side: int) -> int:
	var gain := 0
	for u in units(side):
		if u.data != null:
			gain += u.data.refund
	if round_no >= EXTRA_COST_FROM_ROUND:
		gain += ROUND_EXTRA_COST
	return gain


## 是否是本人的回合
func is_active(side: int) -> bool:
	return active == side


## 对局是否已结束
func is_over() -> bool:
	return result != Result.NONE


## 规则只读快照（供视图显示；刻意**不含**可变集合引用，避免视图改动）
func snapshot() -> Dictionary:
	return {
		"round_no": round_no,
		"active": active,
		"phase": phase,
		"result": result,
		"ally_cost": cost(SIDE_ALLY),
		"enemy_cost": cost(SIDE_ENEMY),
		"ally_hand_size": hand(SIDE_ALLY).size(),
		"enemy_hand_size": hand(SIDE_ENEMY).size(),
		"ally_units": units(SIDE_ALLY).size(),
		"enemy_units": units(SIDE_ENEMY).size(),
	}
