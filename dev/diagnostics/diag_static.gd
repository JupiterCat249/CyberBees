extends RefCounted
## §A 静态代码态取证（自 net_diag_dump.gd 切出 —— 迭代080 · B5 第六刀）
##
## 判据：**只读文件与源码文本**，不碰节点树、不碰运行态 ⇒ 零行为风险。
## 用途：异机排查"是不是同一份代码"——脚本汇总哈希 + 关键文件逐个哈希 + 关键常量源码文本。

const DiagIO := preload("res://dev/diagnostics/diag_io.gd")


## 关键文件：异机 diff 时一眼看出哪一个不同
const KEY_FILES := [
	"res://src/view/arena_view.gd", "res://scenes/ui/battle_ui_alpha.tscn",
	"res://src/data/card_pool.gd", "res://game_data/decks/示范卡组.tres",
	"res://project.godot", "res://scenes/ui/battle_scene.tscn",
]


## 关键常量（防"同一常量在不同机器上被改"）：[文件, 常量名]
const KEY_CONSTS := [
	["res://src/data/card_pool.gd", "DECK_NAMES"],
	["res://src/view/arena_view.gd", "DIAG_NODES"],
	["res://src/battle/battle_engine.gd", "PITCH"],
]


static func section(out: PackedStringArray) -> void:
	out.append("\n--- §A 静态代码态 ---")
	var scripts := DiagIO.list_files("res://", ".gd")
	scripts.sort()
	out.append("  .gd 脚本数：%d" % scripts.size())
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	for p in scripts:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		h.update(p.to_utf8_buffer())
		h.update(f.get_buffer(f.get_length()))
		f.close()
	out.append("  全部 .gd 汇总 SHA256：%s" % h.finish().hex_encode())
	for key in KEY_FILES:
		out.append("  %-52s %s" % [key.replace("res://", ""), DiagIO.file_sha(key)])
	for pair in KEY_CONSTS:
		var txt := DiagIO.read_text(String(pair[0]))
		if txt == "":
			continue
		for line in txt.split("\n"):
			if String(line).begins_with("const %s" % String(pair[1])):
				out.append("  %s: %s" % [String(pair[1]), String(line).strip_edges()])
				break
