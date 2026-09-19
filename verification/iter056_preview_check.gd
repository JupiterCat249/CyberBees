extends Node
## 【验证用 · 非生产】迭代056 操作预览（PreviewData 资源）自检
##
## 验证：
##   ① PreviewData 是 **Resource**（可作资源被 UI 调用）
##   ② 部署预览（兵蜂=蜂王相邻 / 建筑=己方领地）
##   ③ 移动预览（走格子 + **被单位阻挡**）
##   ④ 攻击预览（曼哈顿射程 + **不被阻挡**）
##   ⑤ 指令预览（治疗→己方 / 伤害→敌方 / X费不可选蜂王）
##   ⑥ 支援预览（己方 + 射程内）
##   ⑦ 引擎经 selection_changed 信号**带出预览资源**

const PV := preload("res://scripts/battle/preview_data.gd")
const K := preload("res://scripts/battle/preview_kind.gd")
const Preview := preload("res://scripts/battle/rules_preview.gd")
const EngLib := preload("res://scripts/battle/battle_engine.gd")
const ConfigLib := preload("res://scripts/battle/battle_config.gd")
const StateLib := preload("res://scripts/battle/battle_state.gd")
const Bus := preload("res://scripts/battle/battle_signal_bus.gd")
const Pool := preload("res://scripts/data/card_pool.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _got_preview: Resource = null


func _ready() -> void:
	_test_is_resource()
	_test_deploy_preview()
	_test_move_preview()
	_test_attack_preview()
	_test_command_preview()
	_test_support_preview()
	await _test_engine_signal()
	_report()
	get_tree().quit(0 if _fail == 0 else 1)


## ① 资源性
func _test_is_resource() -> void:
	var d: Resource = PV.make(K.Kind.MOVE, "测试")
	_chk("PreviewData 是 Resource（可作资源被 UI 调用）", d is Resource)
	_chk("有 kind / cells / units / caption 字段",
		"kind" in d and "cells" in d and "units" in d and "caption" in d)
	d.add_cell(Vector2i(1, 1))
	d.add_cell(Vector2i(1, 2))
	_chk("add_cell 后 empty=false 且 cells=2", not d.empty and d.cells.size() == 2)
	_chk("cells_of(MOVE) 取到 2 格", d.cells_of(K.Kind.MOVE).size() == 2)
	_chk("has_cell((1,1)) 为真", d.has_cell(Vector2i(1, 1)))
	var g: Dictionary = d.grouped()
	_chk("grouped() 按类型分组", g.has(K.Kind.MOVE) and g[K.Kind.MOVE].size() == 2)


## ② 部署预览
func _test_deploy_preview() -> void:
	var st = _new_state()
	# 兵蜂：蜂王（绿方行3列1）相邻的空格 = (2,1)(3,0)(3,2)
	var leaf: UnitData = Pool.card("叶蜂") as UnitData
	var cells: Array = Preview.deploy_cells(st, 0, leaf)
	_chk("兵蜂部署格 = 蜂王相邻空格（3 格，实际 %d）" % cells.size(), cells.size() == 3)
	_chk("含 (2,1) 与 (3,0) 与 (3,2)",
		cells.has(Vector2i(2, 1)) and cells.has(Vector2i(3, 0)) and cells.has(Vector2i(3, 2)))
	_chk("不含己方蜂王所在格 (3,1)", not cells.has(Vector2i(3, 1)))
	# 建筑：己方领地（行 2/3）任意空格 = 8 - 1（蜂王占 1）= 7
	var hive: UnitData = Pool.card("蜂巢") as UnitData
	var bcells: Array = Preview.deploy_cells(st, 0, hive)
	_chk("建筑部署格 = 己方领地空格（7 格，实际 %d）" % bcells.size(), bcells.size() == 7)
	_chk("全在己方领地（行 >= 2）", _all_own(bcells))


func _all_own(cells: Array) -> bool:
	for c in cells:
		if c.x < 2:
			return false
	return true


## ③ 移动预览（走格子 + 被单位阻挡）
func _test_move_preview() -> void:
	var st = _new_state()
	var leaf: UnitData = Pool.card("叶蜂") as UnitData      ## move 2
	# 放到 (2,1)，其上方 (1,1) 放一个敌单位阻挡
	var u := UnitInstance.create(leaf, 0, Vector2i(2, 1))
	u.instance_id = "u_test"
	st.board.place(u)
	var enemy := UnitInstance.create(Pool.card("泥蜂") as UnitData, 1, Vector2i(1, 1))
	enemy.instance_id = "e_test"
	st.board.place(enemy)
	var pv: Resource = Preview.build(st, 2, -1, u)
	var mv: Array = K.cells_from(pv, K.Kind.MOVE)
	_chk("移动预览非空（移2，实际 %d 格）" % mv.size(), mv.size() > 0)
	_chk("**移动被单位阻挡**：(1,1) 不可达", not mv.has(Vector2i(1, 1)))
	_chk("未被阻挡的方向可达（(2,0) 或 (2,2) 至少一个）",
		mv.has(Vector2i(2, 0)) or mv.has(Vector2i(2, 2)))
	st.board.remove(enemy)
	var pv2: Resource = Preview.build(st, 2, -1, u)
	_chk("移除阻挡后 (1,1) 变为可达", K.cells_from(pv2, K.Kind.MOVE).has(Vector2i(1, 1)))


## ④ 攻击预览（曼哈顿射程 + 不被阻挡）
func _test_attack_preview() -> void:
	var st = _new_state()
	var leaf: UnitData = Pool.card("叶蜂") as UnitData      ## range 1
	var u := UnitInstance.create(leaf, 0, Vector2i(2, 1))
	u.instance_id = "u_atk"
	st.board.place(u)
	# 射程内（曼哈顿 1）
	var near := UnitInstance.create(Pool.card("泥蜂") as UnitData, 1, Vector2i(1, 1))
	near.instance_id = "e_near"
	st.board.place(near)
	# 射程外（曼哈顿 3）
	var far := UnitInstance.create(Pool.card("泥蜂") as UnitData, 1, Vector2i(0, 3))
	far.instance_id = "e_far"
	st.board.place(far)
	var pv: Resource = Preview.build(st, 2, -1, u)
	var atk: Array = pv.units
	_chk("攻击预览命中射程内敌单位（1 个，实际 %d）" % atk.size(), atk.size() == 1)
	_chk("射程外单位不在预览内", atk.has(near) and not atk.has(far))
	# 攻击不被阻挡：中间隔一个友军也不影响（曼哈顿 2 用泥蜂 range2 测）
	var bee := UnitInstance.create(Pool.card("泥蜂") as UnitData, 1, Vector2i(0, 3))
	bee.instance_id = "e_shooter"
	st.board.place(bee)
	var shooter := UnitInstance.create(Pool.card("泥蜂") as UnitData, 0, Vector2i(3, 1))
	shooter.instance_id = "u_shooter"
	st.board.place(shooter)
	var blocker := UnitInstance.create(leaf, 0, Vector2i(2, 1))
	blocker.instance_id = "u_blocker"
	st.board.place(blocker)
	var pv2: Resource = Preview.build(st, 2, -1, shooter)
	_chk("**攻击不被单位阻挡**（隔着自己的单位仍可攻击 (1,1)）",
		pv2.units.has(near))


## ⑤ 指令预览
func _test_command_preview() -> void:
	var st = _new_state()
	var ally := UnitInstance.create(Pool.card("泥蜂") as UnitData, 0, Vector2i(3, 2))
	ally.instance_id = "a1"
	st.board.place(ally)
	var foe := UnitInstance.create(Pool.card("泥蜂") as UnitData, 1, Vector2i(1, 1))
	foe.instance_id = "f1"
	st.board.place(foe)
	# 治疗 → 己方
	var heal: CommandData = Pool.card("治疗") as CommandData
	var tg: Array = Preview.command_targets(st, 0, heal)
	_chk("治疗指令目标 = 己方单位（含蜂王与泥蜂）",
		tg.has(ally) and tg.has(st.queen(0)) and not tg.has(foe))
	# 电击 → 敌方
	var shock: CommandData = Pool.card("电击") as CommandData
	var tg2: Array = Preview.command_targets(st, 0, shock)
	_chk("伤害指令目标 = 敌方单位", tg2.has(foe) and not tg2.has(ally))


## ⑥ 支援预览
func _test_support_preview() -> void:
	var st = _new_state()
	var bumble: UnitData = Pool.card("熊蜂") as UnitData
	var u := UnitInstance.create(bumble, 0, Vector2i(2, 1))
	u.instance_id = "sup"
	st.board.place(u)
	var sk: SkillData = null
	for s in bumble.skills:
		if s.kind == SkillData.Kind.SUPPORT:
			sk = s
	_chk("熊蜂带支援技能", sk != null)
	if sk == null:
		return
	var pv: Resource = Preview.build(st, 3, -1, u, sk)
	_chk("支援预览类型 = SUPPORT", pv.kind == K.Kind.SUPPORT)
	_chk("支援目标含己方蜂王（射程 0 → 自身）", pv.units.has(u) or pv.units.has(st.queen(0)))


## ⑦ 引擎信号带出预览资源
func _test_engine_signal() -> void:
	var eng = EngLib.new()
	var dd := Pool.build("测试")
	var errs := ConfigLib.make(dd, Pool.build("测试2")).validate()
	_chk("配置校验通过（1 蜂王 + 8 常规）", errs.is_empty())
	var ok: bool = eng.start(ConfigLib.make(Pool.build("测试"), Pool.build("测试2")))
	_chk("引擎开局成功", ok)
	# 连信号
	if Bus.shared().has_signal(Bus.SIG_SELECTION):
		Bus.shared().connect(Bus.SIG_SELECTION,
			func(_k: int, _id: String, pv: Resource, _u: Array) -> void:
				_got_preview = pv,
			CONNECT_ONE_SHOT)
	eng.select_hand(0, 0)
	for _i in 3:
		await get_tree().process_frame
	_chk("**信号 selection_changed 带出 PreviewData 资源**", _got_preview is Resource)
	if _got_preview is Resource:
		_chk("预览资源带部署格（选中手牌 0 = 叶蜂）", _got_preview.cells.size() > 0)
		_chk("预览 kind = DEPLOY", _got_preview.kind == K.Kind.DEPLOY)


# ================= 工具 =================

func _new_state():
	var st = StateLib.new()
	st.setup(ConfigLib.make(Pool.build("绿"), Pool.build("红")))
	# 手动铺：绿方蜂王 (3,1)、红方蜂王 (0,1)
	var q0 := UnitInstance.create(Pool.card("金刚蜂王") as UnitData, 0, Vector2i(3, 1))
	q0.instance_id = "q0"
	st.sides[0]["queen"] = q0
	st.board.place(q0)
	var q1 := UnitInstance.create(Pool.card("金刚蜂王") as UnitData, 1, Vector2i(0, 1))
	q1.instance_id = "q1"
	st.sides[1]["queen"] = q1
	st.board.place(q1)
	return st


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  [PASS] ", label)
	else:
		_fail += 1
		_failures.append(label)
		print("  [FAIL] ", label)


func _report() -> void:
	print("\n===== 迭代056 操作预览（PreviewData 资源）自检 =====")
	print("  通过 %d / 失败 %d" % [_pass, _fail])
	for f in _failures:
		print("   ✗ ", f)
	print("==================================================")
