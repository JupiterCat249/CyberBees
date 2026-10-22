extends RefCounted

const StateLib := preload("res://scripts/battle/battle_state.gd")
## 规则层**纯查询**（自 BattleEngine 切出 —— 迭代075 · B5 第二刀）
##
## 判据（切片时立的规矩，后续加入者请遵守）：
##   · 只读 state 与入参，**不改状态、不发信号**；
##   · 因此可以脱离引擎实例单独测试，也不怕被视图频繁调用；
##   · 与视图的"显示口径"直接相关（例如手牌亮/灰只看费用），口径文字写在各函数上方。


## 该格是否因地形禁止部署（a500「禁区」：障碍地形无法部署，但不阻挡移动与攻击）
static func terrain_blocks_deploy(state, cell: Vector2i) -> bool:
	if state == null or state.map_data == null:
		return false
	var te: TerrainEffect = state.map_data.effect_at(cell)
	if te == null:
		return false
	return te.blocks_deploy


## 某方当前能否负担某张卡（**显示口径**：只考虑部署费）
## ⭐ 人 2026-09-19 明确：手牌亮/灰**只看部署费用**，不看阶段、不看是否行动方
##   · X 费卡（cost < 0）视为随时可负担
static func can_afford_card(state, side: int, card: CardData) -> bool:
	if state == null or card == null:
		return false
	if side < 0 or side >= state.sides.size():
		return false
	if card.cost < 0:
		return true                              ## X 费卡：费用不固定
	return card.cost <= state.cost(side)


## 手牌 index 当前是否可负担（显示口径；与实际可执行性分开）
static func hand_affordable(state, side: int, index: int) -> bool:
	var hand: Array = state.sides[side]["hand"] if state != null else []
	if index < 0 or index >= hand.size():
		return false
	return can_afford_card(state, side, hand[index])


## 手牌 index 当前是否可打出（**执行口径**：费用 + 阶段 + 当前行动方）
static func can_play_hand(state, side: int, index: int) -> bool:
	if state == null or side != state.active:
		return false
	if not hand_affordable(state, side, index):
		return false
	return state.phase == state.Phase.DEPLOY or state.phase == state.Phase.ACTION


## 当前选中的手牌（无则 null）
static func selected_hand_card(state, sel_kind: int, sel_hand_index: int) -> CardData:
	if state == null or sel_kind != 1 or sel_hand_index < 0:
		return null
	var hand: Array = state.sides[state.active]["hand"]
	if sel_hand_index >= hand.size():
		return null
	return hand[sel_hand_index]




## 蜂王开局位置（a500 对战准备 9 · 人 2026-09-19 最终指定：上下行、中心对称）
##   · 我方蜂王 (行3, 列2) · 红方蜂王 (行0, 列1)
##   · 坐标约定：Vector2i(行, 列)；行 0 在上（红方领地）、行 3 在下（我方领地）
##   · 对称校验：我方偏移 (+1.5, +0.5) 与红方 (−1.5, −0.5) 互为相反数（棋盘 4×4，中心 (1.5,1.5)）
static func queen_cell(side: int) -> Vector2i:
	return Vector2i(3, 2) if side == 0 else Vector2i(0, 1)


## 胜负换算：**side 与 Result 是两套语义，不能混用**（迭代059 实测缺陷）
##   enum Result { NONE=0, ALLY_WIN=1, ENEMY_WIN=2, DRAW=3 } vs SIDE_ALLY=0 / SIDE_ENEMY=1
##   直接把 side 赋给 result → 胜者是绿方时恰好等于 Result.NONE → 对局看起来"没结束"
static func result_of_winner(winner_side: int) -> int:
	return StateLib.Result.ALLY_WIN if winner_side == StateLib.SIDE_ALLY else StateLib.Result.ENEMY_WIN


## 该单位此刻射程内是否有可攻击目标（供"行动后自动切目标"判定；与预览同源 —— 都用 attackable()）
static func has_attackable(state, unit: UnitInstance) -> bool:
	if state == null or unit == null or unit.has_acted:
		return false
	return not state.board.attackable(unit, state.board.all_units()).is_empty()

## 弃牌消耗（a500 抽卡 6：消耗等同部署费用；**X 费卡消耗 10 点费用**）
static func discard_cost_of(card: CardData) -> int:
	if card == null:
		return 0
	if card.cost < 0:
		return 10
	return card.cost
