extends SceneTree

const Scene := preload("res://scenes/ui/battle_scene.tscn")
const Fixture := preload("res://tests/support/battle_fixture.gd")

var _scene: Node = null
var _step := 0
var _atk := ""
var _foe := ""


func _init() -> void:
	_scene = Scene.instantiate()
	root.add_child(_scene)


func _count() -> int:
	var fx = _scene.get("_fx_root")
	var n := 0
	if fx != null:
		for ch in fx.get_children():
			if ch.has_meta("preview_hint"):
				n += 1
	return n


func _texts() -> Array:
	var out: Array = []
	var fx = _scene.get("_fx_root")
	if fx != null:
		for ch in fx.get_children():
			if ch.has_meta("preview_hint"):
				var lb = ch.get_node_or_null("Text")
				out.append(String(lb.text) if lb != null else "?")
	return out


func _process(_dt: float) -> bool:
	_step += 1
	if _step == 3:
		var e = _scene.get("engine")
		var pair: Array = []
		for x in 3:
			for y in 3:
				var a := Vector2i(x, y)
				var b := Vector2i(x + 1, y)
				if e.state.board.is_empty(a) and e.state.board.is_empty(b):
					pair = [a, b]
					break
			if pair.size() > 0:
				break
		if pair.size() < 2:
			print("[P] 无空格对")
			quit(1)
			return true
		e.state.active = 0
		e.state.phase = e.state.Phase.ACTION
		var atk := Fixture.place_unit(e, 0, "泥蜂", pair[0])
		var foe := Fixture.place_unit(e, 1, "泥蜂", pair[1])
		_scene._on_unit_spawned(atk, atk.cell)
		_scene._on_unit_spawned(foe, foe.cell)
		_atk = atk.instance_id
		_foe = foe.instance_id
		return false
	if _step == 5:
		_scene._on_unit_clicked(_atk)
		return false
	if _step == 7:
		print("[P] 选我方单位后 floats=", _count(), " ", str(_texts()))
		_scene._on_unit_clicked(_foe)
		return false
	if _step == 9:
		print("[P] 待确认后 floats=", _count(), " ", str(_texts()))
		_scene._on_main_pressed()
		return false
	if _step == 40:
		print("[P] 执行后 floats=", _count(), " ", str(_texts()))
		var ok := ResourceLoader.exists("res://game_data/fx/fx_params.tres")
		print("[P] 资源存在=", ok, " 加载=", str(load("res://game_data/fx/fx_params.tres")) if ok else "N/A")
		quit(0)
		return true
	return false
