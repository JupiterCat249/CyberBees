extends RefCounted
## 诊断用文件/路径工具（自 net_diag_dump.gd 切出 —— 迭代077 · B5 第四刀）
##
## 判据：**纯 IO**（路径进、字符串/数组出），不碰节点树、不碰运行态 ⇒ 零行为风险。
## 仍是 dev 专用：只在 NetDiagDump 触发落盘时被调用。


## 参与几何取证的节点路径（与 arena_view 的 DIAG_NODES 不完全相同：这里要的是"会越界的容器"）
static func diag_paths() -> Array:
	return ["Battle/MapView", "Battle/MapView/MapFrame",
		"Battle/HandPanelLeft", "Battle/HandPanelRight",
		"Battle/PlayerBesaInfoRight", "Battle/PlayerBesaInfoRight/BadgeImage",
		"Battle/PlayerBesaInfoRight/BadgeImage/Value",
		"Battle/PlayerBesaInfoLift", "Battle/PlayerBesaInfoLift/BadgeImage",
		"HUD/InfoPanel", "HUD/ActionBar", "HUD/ActionBar/MainButton",
		"HUD/ActionBar/Label", "HUD/MatchInfo", "HUD/FuncButtonGroup"]


## 文件 SHA256 前 16 位（静态代码态取证用）
static func file_sha(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "<缺失>"
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(f.get_buffer(f.get_length()))
	f.close()
	return h.finish().hex_encode().substr(0, 16)


static func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## 递归列文件；**跳过 .godot/.git/addons**（只需游戏代码，避免几万文件）
static func list_files(root: String, suffix: String, out: Array = []) -> Array:
	var d := DirAccess.open(root)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var full := root.path_join(n)
		if d.current_is_dir():
			if n != "." and n != ".." and n != ".godot" and n != ".git" and n != "addons":
				list_files(full, suffix, out)
		elif n.ends_with(suffix):
			out.append(full)
		n = d.get_next()
	d.list_dir_end()
	return out


## 编辑器设置里的显示/布局相关键（异机不一致排查用）
static func read_editor_settings() -> PackedStringArray:
	var res: PackedStringArray = []
	var vi := Engine.get_version_info()
	var cands := [
		"%s/editor_settings-%d.%d.tres" % [OS.get_data_dir(), int(vi.major), int(vi.minor)],
		"%s/Godot/editor_settings-%d.%d.tres" % [OS.get_data_dir(), int(vi.major), int(vi.minor)],
	]
	var txt := ""
	var used := ""
	for c in cands:
		if FileAccess.file_exists(String(c)):
			txt = FileAccess.get_file_as_string(String(c))
			used = String(c)
			break
	if txt == "":
		res.append("⚠ 读不到（外部/导出运行属正常）")
		return res
	for key in ["interface/editor/appearance/display_scale",
			"interface/editor/appearance/custom_display_scale",
			"interface/editor/appearance/editor_screen",
			"run/window_placement/screen", "run/window_placement/rect",
			"run/window_placement/game_embed_mode"]:
		var val := "<未设>"
		for line in txt.split("\n"):
			if String(line).begins_with(String(key) + " ="):
				var parts := String(line).split("=", false, 1)
				if parts.size() > 1:
					val = String(parts[1]).strip_edges()
				break
		res.append("%s = %s" % [String(key), val])
	res.append("文件：%s" % used)
	return res


## 编辑器布局里影响停靠面板的键（"同仓不同机器显示不一致"的取证关键）
static func read_layout() -> PackedStringArray:
	var res: PackedStringArray = []
	var txt := read_text("res://.godot/editor/editor_layout.cfg")
	if txt == "":
		res.append("⚠ 无 editor_layout.cfg（会自动重建默认布局）")
		return res
	for line in txt.split("\n"):
		var l := String(line).strip_edges()
		if l.begins_with("dock_split") or l.begins_with("dock_hsplit"):
			res.append(l)
	return res
