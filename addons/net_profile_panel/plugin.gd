@tool
extends EditorPlugin
## 联机档位面板（编辑器插件）—— 把"运行档位"从**不可见的文本开关**变成**编辑器里可看的控件**
## ---------------------------------------------------------------------------
## 背景：运行档位原先只由纯文本文件 `res://net_config/profile.flag` 决定，
##       编辑器里看不到、也改不了（只能手写文件）→ 出现过"改了档位却不知道连的是哪台"。
## 做法（全部用**引擎自带**能力）：
##   · `EditorPlugin` + `add_control_to_dock()` → 右侧停靠面板（见 `net_panel.gd`）
##   · `ProjectSettings.add_property_info()` → 把 `net/profile` 注册成**枚举型项目设置**，
##     于是「项目设置 → 常规 → net」里也会出现一个下拉框（双入口，同一份数据）
##   · 面板切换时 `ProjectSettings.save()` → 随项目持久化进 `project.godot`
## 档位解析优先级（唯一实现处）：`scripts/net/net_config.gd::default_profile()`
## ⚠️ 仅编辑器进程内运行，**不进入导出产物**。

const DockScript := preload("res://addons/net_profile_panel/net_panel.gd")
const NC := preload("res://scripts/net/net_config.gd")

var dock: Control = null


func _enter_tree() -> void:
	_register_setting()
	dock = DockScript.new()
	dock.plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	print("[NET-PANEL] 「联机档位」面板已注册 · 当前档位=%s（来源：%s）" % [NC.default_profile(), NC.profile_source()])


func _exit_tree() -> void:
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null


## 把 `net/profile` 注册为**项目设置**：项目设置面板里就会以**枚举下拉**呈现，
## 并且随项目写进 `project.godot`（这就是"用引擎自带功能做持久化 + 可视化"的关键一步）。
func _register_setting() -> void:
	var profs := NC.profiles()
	if profs.is_empty():
		profs = [NC.DEFAULT_PROFILE]
	if not ProjectSettings.has_setting(NC.SETTING):
		ProjectSettings.set_setting(NC.SETTING, NC.DEFAULT_PROFILE)
	ProjectSettings.set_initial_value(NC.SETTING, NC.DEFAULT_PROFILE)
	ProjectSettings.add_property_info({
		"name": NC.SETTING,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": ",".join(PackedStringArray(profs)),
	})
