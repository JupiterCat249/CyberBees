extends SceneTree
## 一次性探针：确认"后果预览浮字"在**选中我方可攻击单位**时是否已经生成。
## 用法：godot --headless --path <repo> -s res://qc/probe_preview_hint.gd

const Scene := preload("res://scenes/ui/battle_scene.tscn")
const Fixture := preload("res://tests/support/battle_fixture.gd")

var _scene: Node = null
var _step := 0


func _init() -> void:
	_scene = Scene.instantiate()
	root.add_child(_scene)


func _process(_dt: float) -> bool:
	_step += 1
	if _step == 3:
		var e = _scene.get("engine")
		print("[P] engine=", e != null)
		if e == null:
			quit(1)
			return true
		## 放一个我方单位与一个能反击的敌方单位（相邻 ⇒ 双方都在射程内）
		var atk := Fixture.place_unit(e, 0, "泥蜂", Vector2i(1, 1))
		var foe := Fixture.place_unit(e, 1, "泥蜂", Vector2i(1, 2))
		print("[P] atk=", atk.instance_id if atk != null else "null", " foe=", foe.instance_id if foe != null else "null")
		e.state.active = 0
		e.state.phase = e.state.Phase.ACTION
		_scene._on_unit_clicked(atk.instance_id)
		return false
	if _step == 6:
		var pv = _scene.get("_preview")
		print("[P] STEP1 preview=", pv != null, " kind=", pv.kind if pv != null else -1,
			" hints=", str(pv.hints) if pv != null else "{}")
		print("[P] STEP1 floats=", _hints())
		## 第二步：点敌方 ⇒ 待确认
		var e = _scene.get("engine")
		var foe_id: String = ""
		for u in e.state.board.all_units():
			if int(u.side) == 1:
				foe_id = u.instance_id
		_scene._on_unit_clicked(foe_id)
		return false
	if _step == 9:
		var pv = _scene.get("_preview")
		var e = _scene.get("engine")
		print("[P] STEP2 pending_cell=", str(e.command_cell), " pending_action=", e.pending_action)
		print("[P] STEP2 hints=", str(pv.hints) if pv != null else "{}")
		print("[P] STEP2 floats=", _hints())
		quit(0)
		return true
	return false


func _hints() -> String:
	var fx = _scene.get("_fx_root")
	if fx == null:
		return "(no fx_root)"
	var out: Array = []
	for ch in fx.get_children():
		if ch.has_meta("preview_hint"):
			var lb = ch.get_node_or_null("Text")
			out.append(lb.text if lb != null else "?")
	return " | ".join(out) if out.size() > 0 else "(none)"
