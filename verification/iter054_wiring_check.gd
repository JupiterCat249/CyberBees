extends Node
## 【验证用 · 非生产】验证 battle_scene 接线：绑数据 → 信号回路 → 渲染
## 状态：待封存（验证用，非生产文件）
## 对应迭代：迭代054 检查点 C4
##
## 验证内容：
##   ① 三个素材场景能被组合场景正确实例化
##   ② 数据绑定：手牌(CardData) / 单位(UnitInstance) 能正确显示
##   ③ 信号回路：子组件 → 控制器 → 外层（证明"靠信号通信、互不引用"成立）
##   ④ 逻辑下发态：可出牌/可选中 能正确作用到节点

const SANDBOX_SCENE := "res://scenes/ui/battle_scene.tscn"
const SHOT := "res://verification/iter054_wiring_shot.png"

var _log: Array[String] = []
var _scene: Control = null
var _got := {"hand_clicked": 0, "unit_clicked": 0, "main": 0}


func _ready() -> void:
	_seed_data()
	_scene = (load(SANDBOX_SCENE) as PackedScene).instantiate()
	add_child(_scene)
	# 让容器/控件完成布局
	await get_tree().process_frame
	await get_tree().process_frame

	# ── ③ 信号回路：外层只连控制器的信号，不碰子组件 ──
	_scene.hand_card_clicked.connect(func(id): _got["hand_clicked"] += 1; _log.append("外层收到 hand_card_clicked(%s)" % id))
	_scene.unit_clicked.connect(func(id): _got["unit_clicked"] += 1; _log.append("外层收到 unit_clicked(%s)" % id))
	_scene.main_button_pressed.connect(func(): _got["main"] += 1; _log.append("外层收到 main_button_pressed"))

	_bind_sandbox()
	await get_tree().process_frame
	await get_tree().process_frame

	# ── ④ 逻辑下发态 ──
	_scene.set_hand_playable(PackedStringArray([_cards[0].id]))
	_scene.set_units_selectable(PackedStringArray([_insts[0].instance_id]))
	_scene.set_hand_selected(_cards[0].id)
	await get_tree().process_frame

	_verify()
	await _shoot()
	get_tree().quit(0)


# ---------------- 构造验证用数据（运行时生成，不入生产资源） ----------------

var _cards: Array[CardData] = []
var _insts: Array[UnitInstance] = []


func _seed_data() -> void:
	# 手牌 4 张：三种类型（验证类型底色）
	var specs := [
		["叶蜂", CardData.CardKind.SOLDIER, 2, "支援"],
		["蜂巢", CardData.CardKind.BUILDING, 4, ""],
		["电击", CardData.CardKind.COMMAND, 3, "指令"],
		["金刚蜂王", CardData.CardKind.QUEEN, 8, "机场"],
	]
	for s in specs:
		var c := CardData.new()
		c.id = Uuid.generate()
		c.display_name = s[0]
		c.kind = s[1]
		c.cost = s[2]
		c.glossary = s[3]
		c.skill_name = "验证技能"
		c.description = "【验证】这是运行时构造的卡，仅用于接线取证，不入生产资源。"
		_cards.append(c)

	# 单位 2 个：我方 + 敌方（验证阵营色），其中一个带效果（验证四维修正）
	var unit_specs := [
		["泥蜂", 0, Vector2i(1, 2), 3, 4, 2],
		["熊蜂", 1, Vector2i(1, 0), 5, 8, 1],
	]
	for u in unit_specs:
		var d := UnitData.new()
		d.id = Uuid.generate()
		d.display_name = u[0]
		d.kind = CardData.CardKind.SOLDIER
		d.cost = 2
		d.atk = u[3]
		d.hp = u[4]
		d.move = 1
		d.attack_range = u[5]
		var inst := UnitInstance.create(d, u[1], u[2])
		# 敌方那个加一个效果 → 攻击力 5 + 1 = 6（验证"乘优先于加"与效果不叠加）
		if u[1] == 1:
			var e := EffectData.new()
			e.id = Uuid.generate()
			e.display_name = "攻击提升"
			e.atk_add = 1
			inst.apply_effect(e)
			# 再施加一次同名效果 → 应**不叠加**（T14）
			inst.apply_effect(e)
		_insts.append(inst)


func _bind_sandbox() -> void:
	_scene.set_player_names("验证方·绿", "验证方·红")
	_scene.set_cost(0, "4")
	_scene.set_cost(1, "2")
	_scene.set_main_button("开始部署", true)
	_scene.set_match_info("回合6--先手", "丰饶", "场地效果：第3、9回合玩家额外回复4点费用（验证文本）")
	_scene.set_hand(_cards, true)
	for i in _insts.size():
		_scene.add_unit(_insts[i])
	_scene.show_card_detail(_cards[0])


# ---------------- 校验 ----------------

func _verify() -> void:
	var ok := true
	# ① 结构
	var units_parent := _scene.get_node_or_null("Battle/MapView/Units")
	var hand_parent := _scene.get_node_or_null("Battle/HandPanelRight/HandRight")
	_chk("容器 Units 存在", units_parent != null)
	_chk("容器 HandRight 存在", hand_parent != null)
	# ② 绑定
	_chk("手牌卡实例数 = 4", hand_parent.get_child_count() == 4 if hand_parent else false)
	_chk("单位卡实例数 = 2", units_parent.get_child_count() == 2 if units_parent else false)
	# ③ 子组件类型 + 脚本
	var hc := hand_parent.get_child(0) if hand_parent and hand_parent.get_child_count() > 0 else null
	_chk("手牌卡带控制器脚本", hc != null and hc.get_script() != null)
	# ④ 效果不叠加（T14）
	_chk("同名效果不叠加（层数=1）", _insts[1].effects.size() == 1)
	# ⑤ 攻击力修正 5+1=6
	_chk("攻击力含效果修正 = 6", _insts[1].atk() == 6)
	# ⑥ 运行态与数据分离（R1/R2）：改实例不改数据
	var before := _insts[0].data.hp
	_insts[0].damage(2)
	_chk("运行态扣血不污染数据层", _insts[0].data.hp == before and _insts[0].current_hp == before - 2)
	# ⑦ 信号回路：手动触发子组件信号 → 应到达外层
	if hc != null:
		hc.hand_clicked.emit(_cards[0].id)
	_chk("手牌信号到达外层", _got["hand_clicked"] == 1)
	var uc := units_parent.get_child(0) if units_parent and units_parent.get_child_count() > 0 else null
	if uc != null:
		uc.unit_clicked.emit("test")
	_chk("单位信号到达外层", _got["unit_clicked"] == 1)
	var mb := _scene.get_node_or_null("HUD/ActionBar/MainButton")
	if mb != null:
		mb.pressed.emit()
	_chk("主按钮信号到达外层", _got["main"] == 1)
	# ⑧ 逻辑下发态生效
	var mod_ok: bool = hc != null and hc.modulate.a > 0.99
	_chk("可出牌态已作用到节点", mod_ok)
	# ⑨ 详情区已写入
	var cn: Label = _scene.get_node_or_null("HUD/InfoPanel/CardName")
	_chk("详情区卡名已绑定", cn != null and cn.text == _cards[0].display_name)

	print("\n========== 迭代054 接线取证 ==========")
	for line in _log:
		print("  ", line)
	print("======================================")


var _fails := 0
func _chk(label: String, cond: bool) -> void:
	if cond:
		print("  [PASS] ", label)
	else:
		_fails += 1
		print("  [FAIL] ", label)
		_log.append("FAIL: " + label)


func _shoot() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("res://verification/iter054_wiring_shot.png")
	print("截图保存:", SHOT, "err=", err, " 失败项=", _fails)
