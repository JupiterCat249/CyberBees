extends RefCounted
## 对端呈现的**状态登记**（自 arena_view 切出 —— 迭代096 · B5 第十二刀）
##
## 判据：这里只存"对端正在看什么"的**簿记** —— 不碰节点、不读规则、不发信号。
##   白框 / 范围 / 标框的渲染仍由 arena_view 与 view_preview 负责 ⇒ 切出来不改变任何观感。
##
## 为什么要单列（这层曾被写成散落的赋值）：三条不变式必须成组成立
##   · 对端**每次换选中** ⇒ 旧的预览登记（单位 or 指令范围）先作废，否则会在对手屏幕上留下幻影范围；
##   · 挂预览的**单位死亡/被移除** ⇒ 立刻作废（arena_view._on_unit_removed 的判定依据）；
##   · 本地**自己开始操作** ⇒ 远端登记整体让位，避免"先看过对端、再选自己"时残留来源标记。
##   把不变式收在一处，才不会在若干函数里各写一遍、各漏一处。

## 对端当前选中的格（白框通道）。x < 0 = 无
var sel_cell := Vector2i(-1, -1)
## 这条预览挂在对端哪个**单位**上（instance_id）；空串 = 没挂
var preview_id := ""
## 对端**指令卡**的待确认中心格；x < 0 = 无
var command_cell := Vector2i(-1, -1)
## 当前 arena_view._preview 是否来自对端（旧"远端不给单位打标"口径已作废，仅作来源标记）
var is_remote := false


## 对端换选中：**先作废旧登记**，再记新格
func begin_select(cell: Vector2i) -> void:
	preview_id = ""
	command_cell = Vector2i(-1, -1)
	sel_cell = cell


## 对端单位预览：登记挂在该单位上
func bind_unit(instance_id: String) -> void:
	preview_id = instance_id
	is_remote = true


## 对端指令卡效果范围：登记以格为键
func bind_command(cell: Vector2i) -> void:
	command_cell = cell
	is_remote = true


## 撤销"挂单位"的登记（对端没选中单位 / 本地开始操作时）
func clear_unit() -> void:
	preview_id = ""
	is_remote = false


## 撤销"指令待确认格"的登记
func clear_command() -> void:
	command_cell = Vector2i(-1, -1)


## 该单位是否是当前远端预览的持有者（_on_unit_removed 用来判定是否必须作废）
func holds(instance_id: String) -> bool:
	return preview_id != "" and preview_id == instance_id


## 清掉全部登记（本地选中变化 / 预览整体作废）
func reset() -> void:
	sel_cell = Vector2i(-1, -1)
	preview_id = ""
	command_cell = Vector2i(-1, -1)
	is_remote = false
