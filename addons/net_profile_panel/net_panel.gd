@tool
extends VBoxContainer
## 「联机档位」停靠面板 —— 在编辑器里**可视化查看与切换**运行档位
## ---------------------------------------------------------------------------
## 起因：运行档位原本只由纯文本开关文件 `res://net_config/profile.flag` 决定，
##       编辑器里既看不到也改不了 → 容易"改了没生效 / 不知道现在连哪台"。
## 写盘行为（切换档位时）：**同时**写
##   · `ProjectSettings net/profile`（引擎自带持久化，进 project.godot；项目设置面板也能看/改）
##   · `res://net_config/profile.flag`（旧机制同步，避免两个来源打架）
## 自动模式：`res://net_config/auto.flag` = 1/0（连上即入队、配对即进对局；验收/双实例用）
## 档位解析优先级：见 `scripts/net/net_config.gd::default_profile()`
## ⚠️ 本脚本只在**编辑器进程**内运行（`@tool`），不进入导出产物。

const NC := preload("res://scripts/net/net_config.gd")

var plugin: EditorPlugin = null

var _opt: OptionButton = null
var _url_label: Label = null
var _src_label: Label = null
var _auto_check: CheckBox = null
var _last_key: String = ""
var _loading: bool = false
var _duo_status: Label = null      ## ⭐ 迭代064「本地双开」状态行


func _ready() -> void:
	name = "联机档位"
	## ⚠️ 迭代064 环境修复（2026-10-04）：**显式声明"不要求最小高度"**。
	##   本面板与 DSH Godot 面板同处**右列上下叠放**，两者的最小高度会**累加**；
	##   曾在 150% 缩放环境下（逻辑窗口仅约 1067px）与 DSH 面板的 520px 下限一起把
	##   **编辑器底部页签条 + 状态栏顶出窗口**（底部信息栏永远看不到、重排布局无效）。
	##   故显式归零，并让长文本自行换行而不是撑高面板。
	custom_minimum_size = Vector2(0, 0)
	_build()
	_refresh(true)
	var t := Timer.new()
	t.name = "WatchTimer"
	t.wait_time = 2.0
	t.autostart = true
	t.timeout.connect(_on_watch)
	add_child(t)


func _build() -> void:
	var title := Label.new()
	title.text = "联机运行档位"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = "档位"
	row.add_child(lab)
	_opt = OptionButton.new()
	_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opt.tooltip_text = "切换后同时写入 ProjectSettings net/profile 与 net_config/profile.flag"
	_opt.item_selected.connect(_on_selected)
	row.add_child(_opt)
	add_child(row)

	_url_label = Label.new()
	_url_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_url_label.add_theme_font_size_override("font_size", 11)
	add_child(_url_label)

	_src_label = Label.new()
	_src_label.add_theme_font_size_override("font_size", 11)
	add_child(_src_label)

	_auto_check = CheckBox.new()
	## ⚠️ 迭代064 环境修复（2026-10-04 根因修复）：原来文案是
	##   「自动模式（连上即入队、配对即进对局）」── **24 字且 CheckBox 不换行**
	##   ⇒ 该控件的**最小宽度≈340px** ⇒ 迫使右侧停靠列变宽 ⇒ 吃掉主区水平空间 ⇒
	##   **编辑器底部面板带（输出/调试器/动画… 页签条 + 状态栏）被挤掉**
	##   （人实测：专注模式隐藏两侧栏后底部栏即回归 ✓；单开任一元凶插件都复现 ✓）
	##   ⇒ 文案缩短、解释放已有 tooltip；并显式允许换行、不设最小宽度。
	_auto_check.text = "自动模式"
	_auto_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_auto_check.custom_minimum_size = Vector2(0, 0)
	_auto_check.add_theme_font_size_override("font_size", 11)
	_auto_check.tooltip_text = "写 net_config/auto.flag；双实例自动验收用，人工测试请保持关闭（连上即入队、配对即进对局）"
	_auto_check.toggled.connect(_on_auto_toggled)
	add_child(_auto_check)

	var btns := HBoxContainer.new()
	var b_refresh := Button.new()
	b_refresh.text = "刷新"
	b_refresh.pressed.connect(_on_refresh_pressed)
	btns.add_child(b_refresh)
	var b_open := Button.new()
	b_open.text = "打开目录"
	b_open.tooltip_text = "在文件管理器里打开 net_config/"
	b_open.pressed.connect(_on_open_dir)
	btns.add_child(b_open)
	add_child(btns)

	## ⭐ 迭代064 新增（人 2026-10-05 选 A）：「本地双开」—— 一键把本地联机验收环境拉起来
	var duo_row := HBoxContainer.new()
	var b_duo := Button.new()
	b_duo.text = "本地双开"
	b_duo.tooltip_text = "写 test 档 + 自动模式 → 起本地中继(联机服务器/server.js, 8091) → 再拉起第二个 Godot 实例。\n两端都会连上即入队、配对即进对局；人工测试结束后请手动把自动模式关掉。"
	b_duo.pressed.connect(_on_launch_duo)
	duo_row.add_child(b_duo)
	add_child(duo_row)

	_duo_status = Label.new()
	_duo_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_duo_status.add_theme_font_size_override("font_size", 11)
	_duo_status.modulate = Color(1, 1, 1, 0.75)
	_duo_status.text = "「本地双开」= 测试档 + 自动模式 + 本地中继 + 第二实例"
	add_child(_duo_status)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.modulate = Color(1, 1, 1, 0.65)
	hint.text = "F6 运行的实例按此档位连接；命令行 --net-profile= 与 SB_NET_PROFILE 优先级更高。"
	add_child(hint)


## 每 2 秒自检一次外部改动（git checkout / MCP 写入 / 手工改文件）→ 面板显示始终等于真实值
func _on_watch() -> void:
	_refresh(false)


func _refresh(force: bool) -> void:
	var profs := NC.profiles()
	var cur := NC.default_profile()
	var auto_on := _read_auto()
	var key := "%s|%s|%s" % [cur, str(profs), str(auto_on)]
	if not force and key == _last_key:
		return
	_last_key = key

	var need_rebuild := _opt.item_count != profs.size()
	if not need_rebuild:
		for i in profs.size():
			if _opt.get_item_text(i) != profs[i]:
				need_rebuild = true
				break
	_loading = true
	if need_rebuild:
		_opt.clear()
		for p in profs:
			_opt.add_item(p)
	var idx := profs.find(cur)
	if idx >= 0:
		_opt.select(idx)
	else:
		_opt.selected = -1
	_loading = false

	if profs.has(cur):
		var cfg := NC.load_profile(cur)
		_url_label.text = "→ %s" % NC.resolve_url(cfg)
	else:
		_url_label.text = "→ （缺 res://net_config/net.%s.json）" % cur
	_src_label.text = "来源：%s" % NC.profile_source()
	_auto_check.set_pressed_no_signal(auto_on)


func _on_refresh_pressed() -> void:
	_refresh(true)
	print("[NET-PANEL] 手动刷新：档位=%s 来源=%s" % [NC.default_profile(), NC.profile_source()])


func _on_open_dir() -> void:
	OS.shell_open(ProjectSettings.globalize_path(NC.DIR))


## ⭐ 迭代064 新增（人 2026-10-05 裁定方案 A）：「本地双开」一键拉起本地联机验收环境
##   ① 写 **test 档 + 自动模式**（与 NetConfig 口径一致的两处来源：ProjectSettings + flag 文件）
##   ② 起**本地中继**（`联机服务器/server.js --config config.test.json`，测试端口 8091）
##   ③ 拉起**第二个 Godot 实例**（`--net-profile=test --net-auto`）
##   ④ 本实例自己按 F5/F6 运行即可（同样读到 `auto.flag` ⇒ **连上即入队、配对即进对局**）
##   ⚠️ 人工测试结束后请把面板「自动模式」关掉（否则下次运行仍会自动入队）。
##   ⚠️ `OS.create_process` **不解析 PATH、也不带工作目录** ⇒ 中继统一交给 `cmd /C cd /d … && start node …`；
##      第二个实例用 `OS.get_executable_path()`（绝对路径）直起。
func _on_launch_duo() -> void:
	var notes: PackedStringArray = PackedStringArray()
	# ① 档位 + 自动模式
	ProjectSettings.set_setting(NC.SETTING, "test")
	ProjectSettings.save()
	_write_text_file(NC.DIR + "/profile.flag", "test")
	_write_text_file(NC.DIR + "/auto.flag", "1")
	notes.append("已写 test 档 + 自动模式")
	# ② 本地中继
	## ⚠️ 三次实测教训（保留备查）：`OS.create_process` **不做 PATH 解析、不带工作目录**，
	##   且会对**每个参数加引号** ✗ ⇒
	##     ① 整条 cmd 串（内含引号）当**一个参数** → 二次转义 ✗
	##     ② `start <title> /D <路径> node …` 多参数 → 实测 8091 未监听 ✗
	##     ③ 生成 `_duo_relay.bat` + `cmd /C <bat>` → 实测 8091 仍未监听 ✗
	##   ✅ **唯一实测可行**：**node 绝对路径 + 全绝对路径参数直起**（下方实现）。
	##      node 的绝对路径用 `OS.execute("where", ["node"], out, true)` 解析（Godot 的 OS.execute 会捕获输出 ✓）。
	var relay_dir := ProjectSettings.globalize_path("res://联机服务器")
	var server_js := relay_dir + "/server.js"
	if FileAccess.file_exists(server_js):
		var node_exe := "node"
		var where_out: Array = []
		if OS.execute("where", ["node"], where_out, true) == 0 and where_out.size() > 0:
			var line := String(where_out[0]).strip_edges()
			if line != "":
				node_exe = line
		OS.create_process(node_exe, [server_js, "--config", relay_dir + "/config.test.json"], false)
		notes.append("已请求启动中继(8091)")
	else:
		notes.append("缺 联机服务器/server.js，中继未起")
	# ③ 第二个实例
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	var pid := OS.create_process(exe, ["--path", proj, "--net-profile=test", "--net-auto"], false)
	if pid > 0:
		notes.append("第二实例 pid=%d" % pid)
	else:
		notes.append("第二实例启动失败(exe=%s)" % exe)
	# ④ 反馈（把命令实况也打出来，便于取证）
	var msg := "本地双开：" + " · ".join(notes) + " → 本实例请按 F5/F6 运行"
	if _duo_status != null:
		_duo_status.text = msg
	print("[NET-PANEL] %s" % msg)
	print("[NET-PANEL]   中继目录=%s" % relay_dir)
	print("[NET-PANEL]   第二实例可执行=%s" % exe)
	_refresh(true)


func _on_selected(idx: int) -> void:
	if _loading or idx < 0:
		return
	var picked := _opt.get_item_text(idx)
	ProjectSettings.set_setting(NC.SETTING, picked)
	ProjectSettings.save()
	_write_text_file(NC.DIR + "/profile.flag", picked)
	print("[NET-PANEL] 档位 → %s（已写 ProjectSettings %s 与 net_config/profile.flag）" % [picked, NC.SETTING])
	_refresh(true)


func _on_auto_toggled(on: bool) -> void:
	_write_text_file(NC.DIR + "/auto.flag", "1" if on else "0")
	print("[NET-PANEL] 自动模式 → %s" % ("开" if on else "关"))
	_refresh(true)


func _read_auto() -> bool:
	var p := NC.DIR + "/auto.flag"
	if not FileAccess.file_exists(p):
		return false
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return false
	var v := f.get_as_text().strip_edges().to_lower()
	f.close()
	return v == "1" or v == "true" or v == "on"


func _write_text_file(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[NET-PANEL] 写入失败 %s（err=%d）" % [path, FileAccess.get_open_error()])
		return
	f.store_string(content)
	f.close()
