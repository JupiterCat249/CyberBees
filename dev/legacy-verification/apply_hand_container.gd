extends SceneTree
## 【生产工具】把"容器布局契约"写入手牌容器场景
##
## 为何用脚本而不是手改文本：本仓 `battle_ui_alpha.tscn` 含大量编辑器生成的
##   `unique_id` / `parent_id_path`（继承链与节点识别依赖它们）——
##   手写/重生成 .tscn 极易弄坏这些字段。脚本只做"行级插入/替换"，**保留其余内容不动**。
##
## 为何不用 MCP node_* + scene_save：`GridContainer` 的 `columns` 虽是普通属性，
##   但 `h_separation` / `v_separation` 是**主题常量**（只能写成 `theme_override_constants/...`），
##   MCP 无对应工具；且把两者写在一起才能保证契约完整。
##
## 用法：godot --headless --path <游戏仓> --script verification/apply_hand_container.gd
##
## 契约（人 2026-09-19 裁决 Q-1）：手牌容器 = **2 列** · 间距 **0**（手牌自动填充手牌区）
## 依据：Godot 文档 class_gridcontainer —— columns 决定列数、行数自适应；
##   h_separation / v_separation 默认 4（本处显式归零）

const SCENE := "res://scenes/ui/battle_ui_alpha.tscn"
const TARGETS := ["HandLeft", "HandRight"]   ## GridContainer 节点名
const COLUMNS := 2
const SEPARATION := 0


func _initialize() -> void:
	var f := FileAccess.open(SCENE, FileAccess.READ)
	if f == null:
		printerr("无法读取 ", SCENE)
		quit(1)
		return
	var lines := f.get_as_text().split("\n")
	f.close()

	var out: PackedStringArray = []
	var i := 0
	var applied := 0
	while i < lines.size():
		var ln: String = lines[i]
		out.append(ln)
		# 命中目标容器声明行
		if _is_target_header(ln):
			applied += 1
			# 向后复制原有属性行，直到块结束；期间剔除旧契约行（幂等）
			i += 1
			var body: Array = []
			while i < lines.size() and not lines[i].begins_with("["):
				var b: String = lines[i]
				if not b.begins_with("columns =") \
						and not b.begins_with("theme_override_constants/h_separation") \
						and not b.begins_with("theme_override_constants/v_separation"):
					body.append(b)
				i += 1
			# 写契约：columns + 间距归零（显式，防被改回默认 4）
			out.append("columns = %d" % COLUMNS)
			out.append("theme_override_constants/h_separation = %d" % SEPARATION)
			out.append("theme_override_constants/v_separation = %d" % SEPARATION)
			for b in body:
				out.append(b)
			continue
		i += 1

	if applied != TARGETS.size():
		printerr("契约未完整应用：命中 %d / 期望 %d" % [applied, TARGETS.size()])
		quit(1)
		return

	var w := FileAccess.open(SCENE, FileAccess.WRITE)
	w.store_string("\n".join(out))
	w.close()
	print("[apply_hand_container] 已写入容器契约：%s -> columns=%d, separation=%d" % [
		str(TARGETS), COLUMNS, SEPARATION])
	quit(0)


func _is_target_header(ln: String) -> bool:
	if not ln.begins_with("[node name=\""):
		return false
	if not ln.contains("type=\"GridContainer\""):
		return false
	for t in TARGETS:
		if ln.contains("name=\"%s\"" % t):
			return true
	return false
