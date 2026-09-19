extends Node
## 【验证用 · 非生产】迭代059 步1：地形体系与场地效果验收
##
## 覆盖 G-1~G-5 + G-7（X 费测试卡）+ G-8（同效果按名称去重）
## 用法：project_run(mode="custom", scene="res://verification/iter059_rules_check.tscn")
##
## ⚠️ 本脚本会**生成一张 X 费测试卡资源到 verification/**（不入 game_data/ 生产目录）

const Eng := preload("res://scripts/battle/battle_engine.gd")
const ConfigLib := preload("res://scripts/battle/battle_config.gd")
const StateLib := preload("res://scripts/battle/battle_state.gd")
const Pool := preload("res://scripts/data/card_pool.gd")
const Effects := preload("res://scripts/battle/rules_effects.gd")
const Combat := preload("res://scripts/battle/rules_combat.gd")
const Command := preload("res://scripts/battle/rules_command.gd")
const Preview := preload("res://scripts/battle/rules_preview.gd")
const TerrainEff := preload("res://scripts/data/terrain_effect.gd")

const MAP_DIR := "res://game_data/maps/"
const VER_DIR := "res://verification/"

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _ready() -> void:
	print("\n===== 迭代059 步1：地形体系与场地效果验收 =====")
	_t_terrain_data()
	_t_rust_field()
	_t_forbid_zone()
	_t_sunken_reduce()
	_t_bountiful_refund()
	_t_cold_wave()
	_t_x_cost_card()
	_t_same_effect_dedupe()
	_report()
	get_tree().quit(0 if _fail == 0 else 1)


# ============ G-1 地形数据 ============
func _t_terrain_data() -> void:
	_section("G-1 地形格数据（人给坐标）")
	var expect := {
		"铁锈": [Vector2i(1, 3), Vector2i(2, 0)],
		"禁区": [Vector2i(1, 2), Vector2i(2, 1)],
		"水没": [Vector2i(0, 3), Vector2i(3, 0)],
	}
	for nm in expect.keys():
		var md: MapData = load(MAP_DIR + nm + ".tres")
		_chk("%s 地图可加载" % nm, md != null)
		if md == null:
			continue
		var want: Array = expect[nm]
		_chk("%s 地形格 = %s（实际 %s）" % [nm, str(want), str(md.terrain_cells)],
			md.terrain_cells.size() == want.size() and md.terrain_cells[0] == want[0] \
			and md.terrain_cells[1] == want[1])
		_chk("%s 有地形效果资源" % nm, md.terrain_effect != null and md.terrain_effect.is_meaningful())
	# 无地形格的图
	for nm in ["默认", "寒潮", "丰饶"]:
		var md2: MapData = load(MAP_DIR + nm + ".tres")
		_chk("%s 无地形格（人明确）" % nm, md2 != null and md2.terrain_cells.is_empty())
	# 中心对称校验
	for nm in expect.keys():
		var md3: MapData = load(MAP_DIR + nm + ".tres")
		if md3 == null or md3.terrain_cells.size() != 2:
			continue
		var a: Vector2i = md3.terrain_cells[0]
		var b: Vector2i = md3.terrain_cells[1]
		_chk("%s 两地形格关于棋盘中心中心对称" % nm,
			(a.x - 1.5) == -(b.x - 1.5) and (a.y - 1.5) == -(b.y - 1.5))


# ============ G-3 铁锈 ============
func _t_rust_field() -> void:
	_section("G-3 铁锈：地形格上的单位获得力场")
	var eng = _engine("铁锈")
	var st = eng.state
	var cell: Vector2i = st.map_data.terrain_cells[0]      ## (1,3)
	var on_cell := _put(st, "叶蜂", 0, cell)
	var off_cell := _put(st, "叶蜂", 0, Vector2i(1, 0))    ## 非地形格
	var n := Effects.grant_terrain_effects(st)
	_chk("地形格上的单位获得效果（实际赋予 %d 个）" % n, n >= 1)
	_chk("地形格单位有力场" , _has_effect(on_cell, "力场"))
	_chk("非地形格单位**没有**力场", not _has_effect(off_cell, "力场"))


# ============ G-4 禁区 ============
func _t_forbid_zone() -> void:
	_section("G-4 禁区：地形格不可部署（不阻挡移动与攻击）")
	var eng = _engine("禁区")
	var st = eng.state
	var fz: Vector2i = st.map_data.terrain_cells[0]        ## (1,2) —— 在我方领地内
	st.phase = StateLib.Phase.DEPLOY
	st.sides[0]["cost"] = 10
	# 建筑：己方领地任意格 → 排除禁格
	var hive: UnitData = Pool.card("蜂巢") as UnitData
	var cells: Array = Preview.deploy_cells(st, 0, hive)
	_chk("禁格不在建筑部署预览里", not cells.has(fz))
	_chk("非禁格的己方领地格仍在预览里", cells.size() > 0)
	# 直接请求部署到禁格 → 应被拒（用引擎公开查询验证）
	_chk("引擎暴露 terrain_blocks_deploy 供视图查询", eng.has_method("terrain_blocks_deploy"))
	_chk("禁格被判定为不可部署", eng.terrain_blocks_deploy(fz))
	_chk("非禁格的己方领地格可部署", not eng.terrain_blocks_deploy(Vector2i(3, 0)))
	# a500：不阻挡移动与攻击 → 移动范围里应包含禁格（若可达）
	var md: MapData = st.map_data
	var te: TerrainEffect = md.effect_at(fz)
	_chk("禁格的 blocks_move 为 false（a500：不阻挡移动）", te != null and not te.blocks_move)
	_chk("禁格的 blocks_attack 为 false（a500：不阻挡攻击）", te != null and not te.blocks_attack)


# ============ G-5 水没 ============
func _t_sunken_reduce() -> void:
	_section("G-5 水没：地形格上的单位减少 2 点指令伤害")
	var eng = _engine("水没")
	var st = eng.state
	var cell: Vector2i = st.map_data.terrain_cells[0]       ## (0,3)
	var on := _put(st, "泥蜂", 1, cell)
	var off := _put(st, "泥蜂", 1, Vector2i(1, 0))         ## 非地形格
	var r_on: int = Combat.command_damage_after_reduce(on, 6, st.map_data)
	var r_off: int = Combat.command_damage_after_reduce(off, 6, st.map_data)
	_chk("地形格单位 6 伤 → %d（应 4）" % r_on, r_on == 4)
	_chk("非地形格单位 6 伤 → %d（应 6）" % r_off, r_off == 6)
	_chk("不传地图数据时旧行为不变（6 伤 → %d）" % Combat.command_damage_after_reduce(off, 6), \
		Combat.command_damage_after_reduce(off, 6) == 6)


# ============ G-2 丰饶 ============
func _t_bountiful_refund() -> void:
	_section("G-2 丰饶：第 3/9 回合场地阶段额外 +4 费")
	var eng = _engine("丰饶")
	var st = eng.state
	st.round_no = 2                       ## 不应生效
	var c0: int = st.cost(0)
	Effects.resolve_terrain_phase(st, 0)
	_chk("第 2 回合不回费（%d → %d）" % [c0, st.cost(0)], st.cost(0) == c0)
	st.round_no = 3                       ## 应生效
	st.sides[0]["cost"] = 2
	var r: Dictionary = Effects.resolve_terrain_phase(st, 0)
	_chk("第 3 回合回费 +4（2 → %d）" % st.cost(0), st.cost(0) == 6 and int(r["refund"]) == 4)
	st.round_no = 9
	st.sides[0]["cost"] = 0
	Effects.resolve_terrain_phase(st, 0)
	_chk("第 9 回合回费 +4", st.cost(0) == 4)
	# 费用上限
	st.round_no = 3
	st.sides[0]["cost"] = 9
	Effects.resolve_terrain_phase(st, 0)
	_chk("回费不得超上限 10", st.cost(0) == 10)


# ============ 寒潮回归（确保没改坏） ============
func _t_cold_wave() -> void:
	_section("寒潮：第 3/6/9/12 回合 -2 生命（蜂王除外）")
	var eng = _engine("寒潮")
	var st = eng.state
	var u := _put(st, "泥蜂", 0, Vector2i(3, 0))
	var hp0: int = u.current_hp
	st.round_no = 2
	Effects.resolve_terrain_phase(st, 0)
	_chk("非生效回合不掉血", u.current_hp == hp0)
	st.round_no = 3
	Effects.resolve_terrain_phase(st, 0)
	_chk("第 3 回合掉 2 血（%d → %d）" % [hp0, u.current_hp], u.current_hp == hp0 - 2)
	var q: UnitInstance = st.queen(0)
	var qhp: int = q.current_hp
	Effects.resolve_terrain_phase(st, 0)
	_chk("蜂王不受寒潮影响", q.current_hp == qhp)


# ============ G-7 X 费测试卡 ============
func _t_x_cost_card() -> void:
	_section("G-7 X 费指令卡（测试卡 → verification/，测后封存）")
	var path := VER_DIR + "test_x_cost_card.tres"
	# 生成测试卡（不入 game_data/ 生产目录）
	var c := CommandData.new()
	c.id = Uuid.generate()
	c.display_name = "测试·X费打击"
	c.cost = -1                       ## X 费
	c.dmg = 0
	c.target_range = 9               ## 全图可选
	c.x_cost_multiplier = 2
	c.description = "【测试卡·非生产】X 费指令：伤害 = 目标部署费 × 2"
	var err := ResourceSaver.save(c, path)
	_chk("X 费测试卡已生成到 verification/" , err == OK and ResourceLoader.exists(path))
	var xc: CommandData = load(path)
	_chk("可回读且 cost<0（X 费）", xc != null and xc.cost < 0)
	# 走合法链：X 费伤害 = 目标部署费 × 倍率
	var eng = _engine("默认")
	var st = eng.state
	var foe := _put(st, "泥蜂", 1, Vector2i(0, 3))     ## 泥蜂部署费 4
	var r: Dictionary = Command.execute(st, xc, 0, foe)
	var dmg: int = int(r["damage"][0]["amount"]) if r["damage"].size() > 0 else -1
	_chk("X 费伤害 = 4 × 2 = 8（实际 %d）" % dmg, dmg == 8)
	# 不可对蜂王
	var q: UnitInstance = st.queen(1)
	var r2: Dictionary = Command.execute(st, xc, 0, q)
	_chk("X 费卡**不可**对蜂王使用", not bool(r2["ok"]))
	_chk("x_cost_of(蜂王) 返回 -1", Command.x_cost_of(q) == -1)


# ============ G-8 同效果按名称去重 ============
func _t_same_effect_dedupe() -> void:
	_section("G-8 相同效果最多一个（按名称去重）")
	var eng = _engine("默认")
	var st = eng.state
	var u := _put(st, "泥蜂", 0, Vector2i(3, 0))
	var e1 := Pool.make_armor(2)
	var e2 := Pool.make_armor(2)        ## 不同 UUID、同名「装甲」
	_chk("两次生成的装甲 UUID 不同（正是偏差根因）", e1.id != e2.id)
	Effects.grant(u, e1)
	var n1: int = u.effects.size()
	var applied: bool = Effects.grant(u, e2)
	_chk("第二次同名装甲**不加层**（%d → %d）" % [n1, u.effects.size()], u.effects.size() == n1)
	_chk("第二次赋予返回 false（视为刷新而非新增）", not applied)
	# 不同名仍应可叠加（如「装甲」+「力场」）
	var f := Pool.field_effect()
	Effects.grant(u, f)
	_chk("不同效果（力场）仍可并存", u.effects.size() == n1 + 1)


# ============ 工具 ============

func _engine(map_name: String):
	var e = Eng.new()
	var cfg = ConfigLib.make(Pool.build("验A"), Pool.build("验B"))
	var md: MapData = load(MAP_DIR + map_name + ".tres")
	if md != null:
		cfg.map_data = md
	e.start(cfg)
	return e


func _put(st, card_name: String, side: int, cell: Vector2i) -> UnitInstance:
	var ud: UnitData = Pool.card(card_name) as UnitData
	var u := UnitInstance.create(ud, side, cell)
	u.instance_id = "t_%s_%d_%d_%d" % [card_name, side, cell.x, cell.y]
	st.board.place(u)
	return u


func _has_effect(u: UnitInstance, nm: String) -> bool:
	for e in u.effects:
		if e.data != null and e.data.display_name == nm:
			return true
	return false


func _first_hand_index_of(st, side: int, nm: String) -> int:
	var hand: Array = st.sides[side]["hand"]
	for i in hand.size():
		if hand[i] != null and hand[i].display_name == nm:
			return i
	return -1


func _section(t: String) -> void:
	print("\n--- %s ---" % t)


func _chk(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  [PASS] ", label)
	else:
		_fail += 1
		_failures.append(label)
		print("  [FAIL] ", label)


func _report() -> void:
	print("\n===== 迭代059 步1 结果 =====")
	print("  通过 %d / 失败 %d" % [_pass, _fail])
	for f in _failures:
		print("   X ", f)
	print("==========================")
