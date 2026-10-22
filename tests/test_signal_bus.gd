extends GutTest
## G4 回归闸 —— 信号总线契约（运行期对账，补静态闸的盲区）
##
## 为什么需要这条：
##   本项目信号走字符串中介（const SIG_X := "x" + signal x(...)），
##   gdlint / gdcruiser 都看不见收发关系 ⇒ 静态闸只有一半，运行期必须有对账。
##   本测试只看"声明与常量表是否自洽"；接线是否完整由 qc 的 G3 信号闸负责。

const BusLib := preload("res://scripts/battle/battle_signal_bus.gd")


func _const_map() -> Dictionary:
	var bus = BusLib.shared()
	return bus.get_script().get_script_constant_map()


func _script_signals(bus: Node) -> Dictionary:
	## 只取**脚本声明**的信号；get_signal_list() 会连 Node 内置信号（ready/renamed/…）一起返回
	var out := {}
	for sig in bus.get_script().get_script_signal_list():
		out[String(sig["name"])] = true
	return out


func test_shared_returns_same_instance() -> void:
	var a = BusLib.shared()
	var b = BusLib.shared()
	assert_not_null(a, "总线单例应可获取")
	assert_same(a, b, "shared() 必须返回同一实例（多实例会让信号丢半边）")


func test_every_const_declares_a_real_signal() -> void:
	var bus = BusLib.shared()
	var declared := _script_signals(bus)
	var consts := _const_map()

	var checked := 0
	for key in consts.keys():
		var k := String(key)
		if not k.begins_with("SIG_"):
			continue
		checked += 1
		var sig_name := String(consts[key])
		assert_true(declared.has(sig_name), "常量 %s 指向的信号 %s 未在总线上声明" % [k, sig_name])

	assert_true(checked > 0, "应至少有一个 SIG_ 常量被检查")


func test_no_orphan_signal_without_const() -> void:
	## 反向对账：脚本里声明了却没有常量的信号 = 无法被发射也无法被订阅（死声明）
	var bus = BusLib.shared()
	var const_names := {}
	var consts := _const_map()
	for key in consts.keys():
		var k := String(key)
		if k.begins_with("SIG_"):
			const_names[String(consts[key])] = true

	for sig in bus.get_script().get_script_signal_list():
		var sig_name := String(sig["name"])
		assert_true(const_names.has(sig_name), "信号 %s 没有对应的 SIG_ 常量（死声明）" % sig_name)
