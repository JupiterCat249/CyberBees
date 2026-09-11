> 状态：已封存（验证用，非生产文件）
> 对应迭代·检查点：迭代003.1 · G-01 防护尝试
> 封存日期：2026-08-27
> 说明：MCP test_run 无法发现/实例化（错误 #882），该路线放弃；改用启动自检方案。

extends Node
## ============================================================
## 编辑器侧防护测试（缓解 G-01：编辑器脚本缓冲把旧版本写回磁盘）
##
## 由 MCP 的 test_run 在**编辑器进程内**执行（非游戏进程），因此可访问 EditorInterface。
## 作用：
##   ① 读取并强制打开 text_editor/behavior/files/auto_reload_scripts_on_external_change
##      —— 该设置为 true 时，外部改动会被编辑器**重新载入**，而不是保留陈旧缓冲后回写
##   ② 关闭所有已打开的脚本标签（**不保存**：close_file 的第二参数传 false，
##      避免把编辑器里的旧缓冲写回磁盘 —— 这正是被抹掉 battle_flow.gd 的机制）
## ============================================================

const RELOAD_KEY := "text_editor/behavior/files/auto_reload_scripts_on_external_change"


func test_editor_guard() -> void:
	var es := EditorInterface.get_editor_settings()

	# ① 外部改动自动重载
	var has_key: bool = es.has_setting(RELOAD_KEY)
	var before: Variant = es.get_setting(RELOAD_KEY) if has_key else "<无此项>"
	es.set_setting(RELOAD_KEY, true)
	print("[guard] %s : %s -> %s" % [RELOAD_KEY, str(before), str(es.get_setting(RELOAD_KEY))])

	# ② 关闭脚本标签（不保存）
	var se := EditorInterface.get_script_editor()
	var opens: Array = se.get_open_scripts()
	var paths: Array = []
	for sc in opens:
		paths.append(str(sc.resource_path))
	print("[guard] 关闭前打开的脚本(%d): %s" % [paths.size(), str(paths)])
	if se.has_method("close_file"):
		for p in paths:
			se.call("close_file", p, false)   # false = 不保存，绝不回写缓冲
		print("[guard] 已调用 close_file(..., false) 关闭全部脚本标签")
	else:
		print("[guard] 该编辑器版本无 close_file，跳过关闭（仅依赖 ① 的自动重载）")
	print("[guard] 关闭后仍打开: %d 个" % se.get_open_scripts().size())
