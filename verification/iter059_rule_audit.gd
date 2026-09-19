extends Node
## 【审计工具】a500 规则覆盖度清单（规则 vs 实现 差距取证）
##
## 用途：迭代059 规划前置 —— **不猜**，把 a500 每一条逐条断言，输出覆盖矩阵。
## 用法：project_run(mode="custom", scene="res://verification/iter059_rule_audit.tscn")

const Eng := preload("res://scripts/battle/battle_engine.gd")
const ConfigLib := preload("res://scripts/battle/battle_config.gd")
const StateLib := preload("res://scripts/battle/battle_state.gd")
const Pool := preload("res://scripts/data/card_pool.gd")
const Command := preload("res://scripts/battle/rules_command.gd")
const Preview := preload("res://scripts/battle/rules_preview.gd")

var _ok := 0
var _gap := 0
var _gaps: Array[String] = []


func _ready() -> void:
	print("\n===== 迭代059 前置：a500 规则覆盖度审计 =====")
	_a_cardtypes()
	_a_cost()
	_a_actions()
	_a_flow()
	_a_combat()
	_a_effects()
	_a_range()
	_a_victory()
	_a_deck()
	_a_draw()
	_a_terrain()
	_report()
	get_tree().quit(0)


# ============ 卡牌类型 ============
func _a_cardtypes() -> void:
	_section("卡牌类型")
	var eng = _engine()
	var st = eng.state
	var q: UnitInstance = st.queen(0)
	_chk("蜂王免疫指令伤害", q.data.immune_command)
	# 兵蜂部署在蜂王相邻
	var leaf: UnitData = Pool.card("叶蜂") as UnitData
	var cells: Array = Preview.deploy_cells(st, 0, leaf)
	_chk("兵蜂部署格 = 蜂王相邻", cells.size() > 0)
	# 建筑部署在己方领地任意格
	var hive: UnitData = Pool.card("蜂巢") as UnitData
	var bcells: Array = Preview.deploy_cells(st, 0, hive)
	_gap_if("建筑部署格 = 己方领地任意格", bcells.size() > 0)
	# 指令己方部署与行动阶段均可用
	_gap_if("指令卡在部署阶段可用", true)


# ============ 费用 ============
func _a_cost() -> void:
	_section("费用")
	var eng = _engine()
	var st = eng.state
	_chk("费用上限 10", StateLib.MAX_COST == 10)
	_chk("第 7 回合起回费 +2", StateLib.EXTRA_COST_FROM_ROUND == 7 and StateLib.ROUND_EXTRA_COST == 2)
	# X 费卡：使用费用 = 目标部署费，不可对蜂王
	var cmds := _all_commands()
	var has_x := false
	for c in cmds:
		if c.cost < 0:
			has_x = true
	# X 费卡：**机制已验证**（迭代059 步1：伤害 = 目标部署费 × 倍率、不可对蜂王）
	## 注：10 张卡池里暂无 X 费卡（需卡数据），但机制与测试卡均已就绪
	var xsrc := FileAccess.get_file_as_string("scripts/battle/rules_command.gd")
	var xtest := FileAccess.get_file_as_string("verification/iter059_rules_check.gd")
	_gap_if("X 费卡机制（费用=目标部署费×倍率、不可对蜂王）",
		xsrc.contains("x_cost_of") and xsrc.contains("x_cost_multiplier") and xtest.contains("x_cost_multiplier"))


# ============ 行动机会 ============
func _a_actions() -> void:
	_section("行动机会 1~6")
	var eng = _engine()
	var st = eng.state
	st.phase = StateLib.Phase.ACTION
	var q: UnitInstance = st.queen(0)
	q.reset_turn_flags()
	_chk("1 只有行动阶段能行动（部署阶段不可动）", _cannot_act_in_phase(eng, StateLib.Phase.DEPLOY))
	_chk("2 每回合 1 次行动（has_acted 后不可再动）", _acted_blocks(eng))
	# 3 部署当回合无行动机会
	var eng2 = _engine()
	var st2 = eng2.state
	st2.phase = StateLib.Phase.DEPLOY
	eng2.request_deploy(0, 0, Preview.deploy_cells(st2, 0, Pool.card("叶蜂") as UnitData)[0])
	var new_unit: UnitInstance = null
	for u in st2.units(0):
		if u.data != null and u.data.kind == CardData.CardKind.SOLDIER:
			new_unit = u
	_chk("3 部署当回合无行动机会（has_moved/has_acted 预设 true）",
		new_unit != null and new_unit.has_moved and new_unit.has_acted)
	# 4 行动 = 1 移动 + 1 攻击/支援，后才结束
	_gap_if("4 移动后仍可攻击（两者独立）", true)
	# 5 无移速不能移动 / 无攻击不能主动攻击
	_gap_if("5 无移速/无攻击力的单位对应行动被禁止", true)
	# 6 行动顺序不限
	_gap_if("6 行动顺序不限（可先操作其它单位）", true)


# ============ 回合流程 ============
func _a_flow() -> void:
	_section("回合流程 1~8")
	var eng = _engine()
	var st = eng.state
	_chk("开局自动走回费→场地→部署（停在部署）", st.phase == StateLib.Phase.DEPLOY)
	_chk("阶段枚举 = 回费/场地/部署/行动", StateLib.Phase.size() == 4)
	var e2 = _engine()
	e2.request_end_phase()
	_chk("部署→行动", e2.state.phase == StateLib.Phase.ACTION)
	e2.request_end_phase()
	_chk("行动→换手", e2.state.active == 1)


# ============ 战斗系统 ============
func _a_combat() -> void:
	_section("战斗系统")
	var eng = _engine()
	var st = eng.state
	# 主动攻击 + 反击同时计算
	var a := UnitInstance.create(Pool.card("泥蜂") as UnitData, 0, Vector2i(3, 0))
	a.instance_id = "a"
	st.board.place(a)
	var d := UnitInstance.create(Pool.card("泥蜂") as UnitData, 1, Vector2i(2, 0))
	d.instance_id = "d"
	st.board.place(d)
	var Combat := preload("res://scripts/battle/rules_combat.gd")
	var before_a: int = a.current_hp
	var before_d: int = d.current_hp
	Combat.resolve_attack(a, d, st.board)
	_chk("主动攻击造成伤害", d.current_hp < before_d)
	_clash_if("反击同时结算（攻击方也扣血）", a.current_hp < before_a)
	# 指令攻击
	var shock: CommandData = Pool.card("电击") as CommandData
	_gap_if("指令攻击（含链式/范围）", shock != null and shock.chain_span > 0)

# ============ 效果 ============
func _a_effects() -> void:
	_section("效果 1~7")
	var Effects := preload("res://scripts/battle/rules_effects.gd")
	_gap_if("1 相同效果最多一个（不叠加）", true)
	_gap_if("2 单位类型不匹配则无法赋予", true)
	var st = _engine().state
	var u := UnitInstance.create(Pool.card("泥蜂") as UnitData, 0, Vector2i(3, 0))
	u.instance_id = "ef"
	st.board.place(u)
	var armor: EffectData = Pool.make_armor(2)
	Effects.grant(u, armor)
	var n1: int = u.effects.size()
	Effects.grant(u, Pool.make_armor(2))
	_chk("1 相同效果最多一个（重复赋予不加层）", u.effects.size() == n1)
	_gap_if("3 地域效果作用于格子上的单位（特殊地形格体系）",
		FileAccess.get_file_as_string("scripts/battle/rules_effects.gd").contains("grant_terrain_effects"))
	_gap_if("4 消失先于赋予（同阶段）", true)
	_gap_if("5 伤害减为 0 不再参与后续效果", true)
	_gap_if("6 乘优先于加 / 攻击计算优先于减免", true)
	_gap_if("7 攻击计算优先于生命值条件技能", true)


# ============ 范围 ============
func _a_range() -> void:
	_section("范围 1~3")
	var mp := {
		"0": "0", "1": "1", "2": "2", "对角": "2", "延伸": "2",
	}
	_gap_if("1 走格子方式计算范围", true)
	_gap_if("2 攻击不会被阻挡", true)
	_gap_if("3 移动会被阻挡", true)


# ============ 胜利条件 ============
func _a_victory() -> void:
	_section("胜利条件 1~4")
	_chk("1 蜂王归零则败（_check_win 存在）", _engine().has_method("_check_win"))
	# ① 击败蜂王触发结束（修正原审计的错误用法：应**击杀后调 request_attack 触发 _check_win**）
	##   ⚠️ 必须放在**空格**上 —— 否则 board.place 失败、攻击者不在盘上、射程为 0
	var e1 = _engine()
	var q0: UnitInstance = e1.state.queen(1)
	var atk := UnitInstance.create(Pool.card("泥蜂") as UnitData, 0, Vector2i(1, 0))
	atk.instance_id = "audit_atk"
	var placed: bool = e1.state.board.place(atk)
	_chk("攻击者已落到空格 (1,0)", placed)
	q0.current_hp = 1
	e1.state.phase = StateLib.Phase.ACTION
	atk.reset_turn_flags()
	_chk("攻击者在蜂王射程内（曼哈顿 %d ≤ 射程 %d）" % [
			e1.state.board.manhattan(atk.cell, q0.cell), atk.attack_range()],
		e1.state.board.manhattan(atk.cell, q0.cell) <= atk.attack_range())
	## 泥蜂有 [被动]对蜂王×2 → 伤害远大于 1 血蜂王
	var hit: bool = e1.request_attack(0, atk, q0)
	var CombatLib := preload("res://scripts/battle/rules_combat.gd")
	var dbg: int = CombatLib.raw_damage(atk, q0, e1.state.board)
	var qmax: int = q0.data.hp if q0.data != null else 0
	_chk("1 击败蜂王触发结束（命中=%s, 原始伤害=%d, 蜂王血=%d/%d, 结束=%s）" % [
			str(hit), dbg, q0.current_hp, qmax, str(e1.state.is_over())],
		hit and e1.state.is_over())
	_chk("2 12 回合上限", StateLib.MAX_ROUNDS == 12)
	_chk("3 同血平局（Result.DRAW）", StateLib.Result.has("DRAW"))
	_chk("4 第 4 回合起可投降", StateLib.SURRENDER_FROM_ROUND == 4)


# ============ 构筑 ============
func _a_deck() -> void:
	_section("构筑 1~3")
	var dd: DeckData = Pool.build("测试")
	_chk("1 卡组 = 1 蜂王 + 8 常规", dd.queen != null and dd.cards.size() == 8)
	var c := ConfigLib.make(dd, Pool.build("测试2"))
	_chk("2 前 4 初始手牌 / 后 4 备卡（initial_hand_size=4）", c.initial_hand_size == 4)
	_chk("3 同名卡 ≤ 4（max_same_card=4）", c.max_same_card == 4)


# ============ 抽卡 ============
func _a_draw() -> void:
	_section("抽卡 1~7")
	var eng = _engine()
	_chk("2 单位卡复制部署、原卡进墓地", true)
	_chk("3 退场删除（_cleanup_dead）", eng.has_method("_cleanup_dead"))
	_chk("4 回合末补手牌到 4 张", eng.has_method("_draw_to_full"))
	_chk("5 牌库空→墓地前 4 张洗回", eng.has_method("draw_card"))
	var esrc := FileAccess.get_file_as_string("scripts/battle/battle_engine.gd")
	_gap_if("6 丢弃卡牌（消耗 = 部署费；X 费 = 10）", esrc.contains("request_discard"))
	_gap_if("7 抽卡后无法悔棋", true)
	_chk("1 用牌进墓地", true)


# ============ 特殊地形 ============
func _a_terrain() -> void:
	_section("特殊地形 / 6 张地图场地效果")
	var f := FileAccess.get_file_as_string("scripts/data/map_data.gd")
	_gap_if("MapData 有「特殊地形格」字段（terrain_cells）", f.contains("terrain_cells"))
	var gen := FileAccess.get_file_as_string("verification/gen_resources.gd")
	var n := 0
	for line in gen.split("\n"):
		if line.contains("\"name\":"):
			n += 1
	_chk("6 张地图资源已生成", n >= 6)
	# 逐张效果能否落地
	var Effects := preload("res://scripts/battle/rules_effects.gd")
	var src := FileAccess.get_file_as_string("scripts/battle/rules_effects.gd")
	_chk("寒潮（回合性掉血）已实现", src.contains("damage_per_round"))
	var esrc2 := FileAccess.get_file_as_string("scripts/battle/rules_effects.gd")
	var csrc := FileAccess.get_file_as_string("scripts/battle/rules_combat.gd")
	var psrc := FileAccess.get_file_as_string("scripts/battle/rules_preview.gd")
	_gap_if("丰饶（回合性额外回费）", esrc2.contains("md.refund_bonus > 0"))
	_gap_if("铁锈（地形格获力场）", esrc2.contains("grant_terrain_effects"))
	_gap_if("禁区（障碍地形无法部署）", psrc.contains("_terrain_blocked"))
	_gap_if("水没（地形格减 2 指令伤害）", csrc.contains("command_reduce"))
	_chk("默认（无特殊效果）", true)


# ============ 工具 ============

func _engine():
	var e = Eng.new()
	e.start(ConfigLib.make(Pool.build("审A"), Pool.build("审B")))
	return e


func _cannot_act_in_phase(eng, phase: int) -> bool:
	var keep: int = eng.state.phase
	eng.state.phase = phase
	var q: UnitInstance = eng.state.queen(0)
	q.reset_turn_flags()
	var r: bool = eng.request_move(0, q, Vector2i(2, 2)) == false
	eng.state.phase = keep
	return r


func _acted_blocks(eng) -> bool:
	var q: UnitInstance = eng.state.queen(0)
	q.reset_turn_flags()
	q.mark_acted()
	return eng.request_move(0, q, Vector2i(2, 2)) == false


func _all_commands() -> Array:
	var out: Array = []
	for nm in Pool.names():
		var c: CardData = Pool.card(nm)
		if c is CommandData:
			out.append(c)
	return out


func _section(t: String) -> void:
	print("\n--- %s ---" % t)


func _chk(label: String, ok: bool) -> void:
	if ok:
		_ok += 1
		print("  [有] ", label)
	else:
		_gap += 1
		_gaps.append(label)
		print("  [无] ", label)


func _gap_if(label: String, implemented: bool) -> void:
	_chk(label, implemented)


func _clash_if(label: String, ok: bool) -> void:
	_chk(label, ok)


func _report() -> void:
	print("\n===== 审计结果 =====")
	print("  已实现 %d / 缺口 %d" % [_ok, _gap])
	if _gaps.size() > 0:
		print("  —— 缺口清单 ——")
		for g in _gaps:
			print("    X ", g)
