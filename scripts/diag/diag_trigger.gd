extends RefCounted
## 诊断的手动触发器（迭代081）
##
## 为什么需要它：F8 依赖**窗口键盘焦点**，而且笔记本上 F8 常常要按 Fn；
## 一旦游戏窗口没拿到焦点（或按的是媒体键），人就会"按了没反应"，且无从判断是哪种。
## 这个触发器改用**文件**做信号：把 user://diag_now.flag 建出来即可，与键盘、焦点无关。

const FLAG := "user://diag_now.flag"


## 命中即触发一次（并删掉 flag，避免重复）；返回是否触发
static func poll(tree: SceneTree) -> bool:
	if not FileAccess.file_exists(FLAG):
		return false
	var d := DirAccess.open("user://")
	if d != null:
		d.remove("diag_now.flag")
	var cs: Node = tree.current_scene if tree != null else null
	if cs != null and cs.has_method("dump_runtime_geometry"):
		## 不 await：这里只要"发出请求"，dump 自己会在帧边界后跑（与 F8 同一条路）
		cs.dump_runtime_geometry(true)
	return true
