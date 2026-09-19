extends Node
## 【验证用 · 非生产】迭代057 新战斗系统**运行层端到端**自检
##
## 人要求（U-2）：「尝试在运行层进行验证」—— 本脚本不走“引擎单独测”，
##   而是**实例化真实场景 battle_scene.tscn**（挂 arena_view.gd），看信号与 UI 是否真的跑通。
##
## 验证链：开局→手牌→部署→行动→换手

const Pool := preload("res://scripts/data/card_pool.gd")
const K := preload("res://scripts/battle/preview_kind.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _scene: Control = null


func _ready() -> void:
	await _run()


func _run() -> void:
	var ps := load("res://scenes/ui/battle_scene.tscn") as PackedScene
	_chk("战斗场景可加载", ps != null)
	if ps == null:
		_report(); get_tree().quit(1); return
	_scene = ps.instantiate() as Control
	_chk("战斗场景可实例化", _scene != null)
	add_child(_scene)
	await _tick(10)

	var view = _scene                       ## 根节点挂了 arena_view.gd
	_chk("根节点挂了 arena_view.gd", view.get_script() != null)
	var eng = view.get("engine")
	_chk("视图已建起 BattleEngine", eng != null)
	if eng == null:
		_report(); get_tree().quit(1); return
	var st = eng.state
	_chk("引擎状态存在", st != null)
	if st == null:
		_report(); get_tree().quit(1); return

	# ① 开局：双方蜂王 + 指定中心对称坐标
	var qa: UnitInstance = st.queen(0)
	var qe: UnitInstance = st.queen(1)
	_chk("我方蜂王在位", qa != null)
	_chk("敌方蜂王在位", qe != null)
	if qa != null:
		_chk("我方蜂王坐标 = (行1,列3)（人指定）", qa.cell == Vector2i(1, 3))
	if qe != null:
		_chk("敌方蜂王坐标 = (行2,列0)（人指定）", qe.cell == Vector2i(2, 0))
	_chk("开局费用：先手 4（回费后）", st.cost(0) == 4)
	_chk("开局费用：后手 2（后手 +2）", st.cost(1) == 2)
	_chk("开局阶段 = 部署（回费/场地已自动推进）", st.phase == 2)

	# ② 手牌经容器排布
	var hl: Control = _scene.get_node("Battle/HandPanelLeft/HandLeft")
	var hr: Control = _scene.get_node("Battle/HandPanelRight/HandRight")
	_chk("我方手牌区有 4 张（容器装下了）", hr.get_child_count() == 4)
	_chk("敌方手牌区有 4 张", hl.get_child_count() == 4)
	_chk("手牌容器 columns = 2（未回退单列）", int(hr.get("columns")) == 2)

	# ③ 部署
	var hand_before: int = st.hand(0).size()
	var cost_before: int = st.cost(0)
	var units_before: int = st.units(0).size()
	eng.select_hand(0, 0)
	await _tick(3)
	var pv: Resource = eng.current_preview()
	_chk("选中手牌后有部署预览", pv != null and int(pv.kind) == K.Kind.DEPLOY)
	var targets: Array = pv.cells if pv != null else []
	_chk("部署预览有可选格", targets.size() > 0)
	if targets.size() > 0:
		var cell: Vector2i = targets[0].cell
		var ok: bool = eng.request_deploy(0, 0, cell)
		await _tick(3)
		_chk("部署请求成功", ok)
		_chk("场上我方单位 +1", st.units(0).size() == units_before + 1)
		_chk("手牌 -1", st.hand(0).size() == hand_before - 1)
		_chk("费用按卡费扣除（叶蜂=2）", st.cost(0) == cost_before - 2)
		_chk("单位节点已渲染到棋盘（双方蜂王+新单位）", _count_unit_nodes() >= 3)

	# ④ 推进到行动 → 刚部署单位不可行动（a500 行动机会 3）
	var ok2: bool = eng.request_end_phase()
	await _tick(3)
	_chk("部署→行动阶段", ok2 and st.phase == 3)
	var mover: UnitInstance = null
	for u in st.units(0):
		if u.data != null and u.data.kind == CardData.CardKind.SOLDIER:
			mover = u
			break
	if mover != null:
		eng.select_unit(0, mover)
		await _tick(3)
		var pv2: Resource = eng.current_preview()
		var moves: Array = K.cells_from(pv2, K.Kind.MOVE)
		_chk("选中单位后拿到移动预览", moves.size() >= 0)
		var can: bool = eng.request_move(0, mover, moves[0] if moves.size() > 0 else mover.cell)
		_chk("刚部署的单位本回合不可移动（a500 行动机会 3）", not can)

	# ⑤ 换手
	var ended: bool = eng.request_end_phase()
	await _tick(8)
	_chk("结束回合后换到红方", ended and st.active == 1)
	_chk("红方手牌补至 4 张（a500 抽卡 4）", st.hand(1).size() == 4)

	_report()
	get_tree().quit(0 if _fail == 0 else 1)


func _tick(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _count_unit_nodes() -> int:
	var root := _scene.get_node_or_null("Battle/MapView/Units")
	return root.get_child_count() if root != null else 0


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  [PASS] ", label)
	else:
		_fail += 1
		_failures.append(label)
		print("  [FAIL] ", label)


func _report() -> void:
	print("\n===== 迭代057 运行层端到端自检 =====")
	print("  通过 %d / 失败 %d" % [_pass, _fail])
	for f in _failures:
		print("   X ", f)
	print("==================================")
