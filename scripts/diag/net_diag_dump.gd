extends Node
## ============================================================================
##  🧪 NetDiagDump —— 运行环境诊断采集器（**联机匹配时自动下传到各自本机**）
## ============================================================================
## 目标（人 2026-10-08 要求）：
##   「尽可能全面的环境差异检测工具，包括静态代码状态和运行时代码状态，可能需要一些侵入式操作，
##     用于深入获取引擎在运行时发生的变化和数据。最后，这个工具最好能够在引擎运行联机场景开始
##     联机匹配时自动将信息下传到各自的本地计算机中，便于外部进行调取和判断」
##
## 采集内容（四段）：
##   §A 静态代码态   —— 脚本哈希（未改动/被改动一目了然）、资源哈希、关键常量的**源码文本值**
##   §B 环境态       —— 引擎/OS/屏幕/DPI/窗口/视口/stretch/渲染/项目设置/编辑器设置/停靠布局/插件
##   §C 运行时态     —— 视口/Canvas 变换/性能计数器/时间基准/音频/输入/自动加载/运行中场景树节点几何与越界
##   §D 运行时**变化**（侵入式）—— 对关键量的**持续采样**：谁、在什么时候、把值从多少改成了多少
##                      ＋ 场景切换轨迹 ＋ 联机事件流（连接/入队/配对）
##
## 落盘（**各自的本地计算机**，外部可直接调取）：
##   `user://diag/` —— 每次匹配/场景切换/退出各落一份
##   Windows 实际路径：`%APPDATA%\Godot\app_userdata\电子蜂\diag\`
##   同时把**绝对路径**打进控制台（`print`），终端日志里能直接看到去哪儿取。
##
## ⚠️ 侵入性说明：本采集器**只读**引擎与节点状态，**不修改**任何游戏数据；"侵入"仅指
##   ① 常驻 autoload ② 每 N 帧采样一次关键量 ③ 注册 `_input`/场景切换/联机信号观察者。
##   不介入联机协议、不阻塞主线程（采样限频；写盘放在 `call_deferred`）。
## 关闭方式：把 `net_config/diag.flag` 内容写 `0`（或删除该文件即恢复默认开启规则）。
## ============================================================================
const DIAG_DIR := "user://diag"
## 采样间隔（帧）：60fps 下 = 每 0.5 秒一次；只比较少量标量，开销可忽略
const SAMPLE_EVERY := 30
## 被持续监视的"关键量"（运行期被谁改动 —— 本工具的核心价值）
const WATCHED_SETTINGS := [
	"Engine.max_fps", "Engine.physics_ticks_per_second", "Engine.time_scale",
	"Engine.physics_jitter_fix", "Engine.max_physics_steps_per_frame",
	"Engine.print_error_messages", "Engine.debug/settings/stdout/verbose_stdout",
	"display/window/stretch/mode", "display/window/stretch/aspect",
	"display/window/stretch/scale", "display/window/size/viewport_width",
	"display/window/size/viewport_height", "rendering/renderer/rendering_method",
	"application/run/max_fps", "net/profile",
]

var _enabled := true
var _frame := 0
var _watched := {}          ## 路径 -> 上次观测值（用于 diff）
var _events: PackedStringArray = []   ## 事件流（场景切换/联机/窗口变化）
var _dumped_for_match := false
var _last_window_size := Vector2i.ZERO
var _last_client: Object = null
var _saw_client_connected := false
var _saw_matched := false
var _late_dump_armed := false
var _late_dump_frame := 0
var _drift_pending := false
var _drift_dump_frame := 0
## 定期快照间隔（帧）：默认 60 秒 @60fps；`net_config/diag_period.flag` 可覆盖（0 = 关）
var _period_frames := 3600
var _last_dump_abs := ""
var _diff_pass := 0


func _ready() -> void:
	_enabled = _read_flag()
	## 常驻（场景切换不销毁）
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _enabled:
		print("[DIAG] 采集器已关闭（net_config/diag.flag = 0）")
		return
	_snapshot_watched()
	_period_frames = _read_period()
	_last_window_size = DisplayServer.window_get_size()
	_log("采集器启动（autoload · 每次匹配自动落盘到 %s）" % ProjectSettings.globalize_path(DIAG_DIR))
	print("[DIAG] 📂 诊断落盘目录：%s" % ProjectSettings.globalize_path(DIAG_DIR))
	print("[DIAG] 手动落盘热键：Ctrl+F9（或调 NetDiagDump.dump(\"manual\")）")


## 定期快照间隔（帧）；`res://net_config/diag_period.flag` 写数字可覆盖（0 = 关闭）
func _read_period() -> int:
	const P := "res://net_config/diag_period.flag"
	if not FileAccess.file_exists(P):
		return 3600
	var f := FileAccess.open(P, FileAccess.READ)
	if f == null:
		return 3600
	var v := f.get_as_text().strip_edges()
	f.close()
	if v.is_valid_int():
		return maxi(0, int(v))
	return 3600


func _input(event: InputEvent) -> void:
	## Ctrl+F9 = 手动落盘（不影响游戏输入：仅组合键）
	if not _enabled:
		return
	if event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
		var k := event as InputEventKey
		if k.keycode == KEY_F9 and k.ctrl_pressed:
			print("[DIAG] 手动落盘：%s" % dump("manual"))
			get_viewport().set_input_as_handled()


## 开关：`res://net_config/diag.flag` 内容 1/true/on = 开；0/false/off = 关；缺失 = 开（默认开，便于异机取证）
func _read_flag() -> bool:
	const P := "res://net_config/diag.flag"
	if not FileAccess.file_exists(P):
		return true
	var f := FileAccess.open(P, FileAccess.READ)
	if f == null:
		return true
	var v := f.get_as_text().strip_edges().to_lower()
	f.close()
	return not (v == "0" or v == "false" or v == "off")


func _log(s: String) -> void:
	_events.append("[%s] %s" % [Time.get_time_string_from_system(), s])


# ============================================================================
#  场景切换 / 节点变动追踪（侵入式观察者）
# ============================================================================
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_log("窗口获得焦点")
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_log("窗口失焦（注意：失焦会冻结主循环 ⇒ 影响联机与截图时序）")
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_log("收到关闭请求 ⇒ 落盘最后一份")


# ============================================================================
#  每帧：采样"变化"（侵入式的核心）+ 感知联机事件（不改协议，只观察）
# ============================================================================
func _process(_dt: float) -> void:
	if not _enabled:
		return
	_frame += 1
	## ① 窗口尺寸变化（不依赖信号，直接观察）
	var wsz := DisplayServer.window_get_size()
	if wsz != _last_window_size:
		_log("窗口尺寸变化：%s → %s" % [str(_last_window_size), str(wsz)])
		_last_window_size = wsz
	## ② 关键量变化（谁在运行时改了它 —— 逐个 diff）
	if _frame % SAMPLE_EVERY == 0:
		_diff_watched()
	## ③ 联机客户端事件（观察 NetSession.client 的出现/消失，不介入协议）
	_watch_client()
	## ④ 入局（切到战斗场景）⇒ 自动落盘
	if not _dumped_for_match and _is_battle_scene():
		_dumped_for_match = true
		_log("检测到进入战斗场景 ⇒ 自动落盘")
		dump("match_enter")
		## ⚠️ 入局瞬间只落了"基线"：此刻 UI 尚未稳定、漂移还没发生 ⇒
		##   **再排一次"稳定快照"**（约 2 秒后），这样 §D 里就有真实的变化记录可看。
		_late_dump_armed = true
		_late_dump_frame = _frame + 120
	## ⑤ 稳定后快照
	if _late_dump_armed and _frame >= _late_dump_frame:
		_late_dump_armed = false
		_log("入局 2 秒稳定快照 ⇒ 自动落盘")
		dump("match_settled")
	## ⑥ 定期快照（默认每 60 秒；可用 net_config/diag_period.flag 覆盖，写 0 = 关）
	if _period_frames > 0 and _frame % _period_frames == 0:
		_log("定期快照（每 %d 帧）⇒ 自动落盘" % _period_frames)
		dump("periodic")
	## ⑦ 漂移即落盘：关键量一旦被运行时改动，立刻存证（联机不一致最需要这个）
	if _drift_pending and _frame >= _drift_dump_frame:
		_drift_pending = false
		_log("检测到运行时变化 ⇒ 立即落盘存证")
		dump("drift")


func _is_battle_scene() -> bool:
	var cs := get_tree().current_scene
	return cs != null and String(cs.scene_file_path).ends_with("battle_scene.tscn")


func _watch_client() -> void:
	var c = NetSession.client
	if c != _last_client:
		_last_client = c
		if c != null:
			_log("联机会话客户端已建立：%s" % str(c))
		else:
			_log("联机会话客户端已释放")
	if c == null:
		return
	## 用 has_method 探测（避免给未知对象赋值 —— 本项目已知会打断点）
	var open_now := false
	if c.has_method("is_open"):
		open_now = bool(c.call("is_open"))
	if open_now and not _saw_client_connected:
		_saw_client_connected = true
		_log("联机连接已打开（开始匹配前的状态）")
	if not _saw_matched and c.has_signal("matched") and not c.is_connected("matched", _on_matched):
		c.connect("matched", _on_matched)     ## 只读观察：不影响协议
		_log("已挂上 matched 观察者")


func _on_matched(code: String, seat: int, players: Array) -> void:
	_saw_matched = true
	_log("配对成功：房间=%s 座位=%d 玩家=%s ⇒ **自动落盘**" % [code, seat, str(players)])
	## 「开始联机匹配时自动下传」：配对成功即落盘（此刻含两端各自的完整环境）
	dump("net_matched")


## 只比较**少量标量**；变化才记事件（避免刷屏）
## 首次采样把**每个键各记一行"初始值"**（异机 diff 时这就是最有用的一屏），此后只记真正的变化。
func _diff_watched() -> void:
	_diff_pass += 1
	for k in WATCHED_SETTINGS:
		var now = _read_watched(String(k))
		var old = _watched.get(k, null)
		if old == null:
			_watched[k] = now
			_log("初始值：%s = %s" % [String(k), str(now)])
			continue
		if str(now) != str(old):
			_log("⚠️ 运行时变化：%s  %s → %s" % [String(k), str(old), str(now)])
			_watched[k] = now
			## 漂移即存证：稍等几帧再落盘（把同一批改动一起抓到），避免抖动式写盘
			_drift_pending = true
			_drift_dump_frame = _frame + 15


func _read_watched(key: String):
	match key:
		"Engine.max_fps": return Engine.max_fps
		"Engine.physics_ticks_per_second": return Engine.physics_ticks_per_second
		"Engine.time_scale": return Engine.time_scale
		"Engine.physics_jitter_fix": return Engine.physics_jitter_fix
		"Engine.max_physics_steps_per_frame": return Engine.max_physics_steps_per_frame
		"Engine.print_error_messages": return Engine.print_error_messages
		"Engine.debug/settings/stdout/verbose_stdout":
			return ProjectSettings.get_setting("debug/settings/stdout/verbose_stdout", "<unset>")
	return ProjectSettings.get_setting(key, "<unset>")


## 只在**启动时**把全部键标为"未初始化"（null）——
##   ⚠️ 不能把"启动瞬间的当前值"当基线：入局时 `arena_view._ready()` 会写 `Engine.max_fps = 60` 等，
##   那些写入发生在**基线之前** ⇒ 会被永远漏掉（第一版实测就是这样，§D 一直空着）。
##   标成 null 后，**第一次采样会把所有已存在的键各自报一次**（带初始值），此后才只报真正的变化。
func _snapshot_watched() -> void:
	for k in WATCHED_SETTINGS:
		_watched[k] = null


# ============================================================================
#  落盘
# ============================================================================
## `tag` 会进入文件名，便于区分"入局/配对/手动"
func dump(tag: String = "manual") -> String:
	var lines := _collect(tag)
	DirAccess.make_dir_recursive_absolute(DIAG_DIR)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	var path := "%s/diag_%s_%s.txt" % [DIAG_DIR, tag, stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[DIAG] 写盘失败：%s" % path)
		return ""
	f.store_string("\n".join(lines))
	f.close()
	var abs_path := ProjectSettings.globalize_path(path)
	_last_dump_abs = abs_path
	## ① 打进控制台（终端日志里能直接看到去哪儿取）
	print("[DIAG] 📄 诊断已落盘：%s" % abs_path)
	## ② 追加一行"最新产物"索引，便于外部脚本/人快速找到最后一份
	var idx := FileAccess.open("%s/LATEST.txt" % DIAG_DIR, FileAccess.WRITE)
	if idx != null:
		idx.store_string("tag=%s\ntime=%s\npath=%s\n" % [tag, Time.get_datetime_string_from_system(false, true), abs_path])
		idx.close()
	## ③ 复制到"下传目录"（便于外部直接取；路径可在文件头看到）
	var out_dir := "%s/outbox" % DIAG_DIR
	DirAccess.make_dir_recursive_absolute(out_dir)
	var out_path := "%s/%s" % [out_dir, path.get_file()]
	DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(out_path))
	return abs_path


func _collect(tag: String) -> PackedStringArray:
	var out: PackedStringArray = []
	out.append("========== 🧪 NET DIAG DUMP (tag=%s) ==========" % tag)
	out.append("时间：%s · 帧号：%d" % [Time.get_datetime_string_from_system(false, true), _frame])
	_section_static(out)
	_section_env(out)
	_section_runtime(out)
	_section_pixels(out)
	_section_turnstate(out)
	_section_events(out)
	out.append("========== END ==========")
	return out


## §E 像素取证（**联机对端"异常叠加变暗"类问题专用**）
## 为什么需要：`modulate` 是**级联**的，读节点属性只能看到自己那一层；
##   "叠加压暗"必须看**最终渲染出来的像素**才能定性（本机实测两侧徽章 0.345 vs 0.475 ⇒ 比值 1.38 ≈ 0.65/0.22）。
## 采样点选在**两侧信息栏徽章中心**与两侧手牌区，可比出"两侧亮度是否对称"。
func _section_pixels(out: PackedStringArray) -> void:
	out.append("\n--- §E 像素取证（两侧信息栏/手牌亮度对比）---")
	## ⚠️ **headless / dummy 渲染器**下 `get_texture()` 返回 null，直接 `get_image()` 会刷一堆
	##   `ERROR: Parameter "t" is null ... texture_2d_get`（实测：双端 auto 模式跑 headless 实例时刷屏）
	##   ⇒ 取图必须**两级判空**，取不到就说明原因后跳过，不影响其余段落。
	var vp := get_viewport()
	if vp == null:
		out.append("  ⚠ 无 Viewport ⇒ 跳过")
		return
	var tex := vp.get_texture()
	if tex == null:
		out.append("  ⚠ 无帧纹理（headless / dummy 渲染器）⇒ 跳过像素取证")
		return
	var img := tex.get_image()
	if img == null:
		out.append("  ⚠ 取不到帧图像（headless 或不支持）")
		return
	var pts: Array = [
		["左·信息栏徽章", Vector2i(40, 45)],
		["右·信息栏徽章", Vector2i(1500, 45)],
		["左·手牌卡面", Vector2i(70, 190)],
		["右·手牌卡面", Vector2i(1520, 190)],
		["地图中央", Vector2i(960, 540)],
	]
	var vals := {}
	for it in pts:
		var p: Vector2i = it[1]
		if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
			out.append("  %-14s <越界>" % String(it[0]))
			continue
		var c := img.get_pixelv(p)
		var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		vals[String(it[0])] = lum
		out.append("  %-14s #%s  r=%.3f g=%.3f b=%.3f  亮度=%.3f" % [
			String(it[0]), c.to_html(false), c.r, c.g, c.b, lum])
	var l: float = float(vals.get("左·信息栏徽章", 0.0))
	var r: float = float(vals.get("右·信息栏徽章", 0.0))
	if l > 0.001 and r > 0.001:
		var ratio: float = maxf(l, r) / minf(l, r)
		out.append("  ⇒ 两侧信息栏亮度比 = %.2f（**接近 1.0 = 对称**；明显偏离说明有一侧被额外压暗/叠加）" % ratio)
		out.append("     （本机 2026-10-10 实测：`0.345 / 0.475` ⇒ 1.38，恰好 ≈ 旧口径的 0.65/0.22 ⇒ 不对称来自系数差异）")


## §A 静态代码态：脚本/资源哈希 + 关键常量源码文本值
func _section_static(out: PackedStringArray) -> void:
	out.append("\n--- §A 静态代码态 ---")
	## A1 脚本哈希（对所有 .gd 求哈希，列出**非基线**的少数几个，便于异机比对"是不是同一份代码"）
	var scripts := _list_files("res://", ".gd")
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
	## 关键文件逐个哈希（异机 diff 时一眼看出哪一个文件不同）
	for key in ["res://scenes/ui/arena_view.gd", "res://scenes/ui/battle_ui_alpha.tscn",
			"res://scripts/data/card_pool.gd", "res://game_data/decks/示范卡组.tres",
			"res://project.godot", "res://scenes/ui/battle_scene.tscn"]:
		out.append("  %-52s %s" % [key.replace("res://", ""), _file_sha(key)])
	## A2 关键常量的**源码文本值**（防止"同一常量在不同机器上被改"）
	for pair in [["res://scripts/data/card_pool.gd", "DECK_NAMES"],
			["res://scenes/ui/arena_view.gd", "DIAG_NODES"],
			["res://scripts/battle/battle_engine.gd", "PITCH"]]:
		var txt := _read_text(String(pair[0]))
		if txt == "":
			continue
		for line in txt.split("\n"):
			if String(line).begins_with("const %s" % String(pair[1])):
				out.append("  %s: %s" % [String(pair[1]), String(line).strip_edges()])
				break


## 🎨 只读颜色探针（供"某处异常变暗/叠加"类问题取证）：
##   从**当前帧的渲染结果**上采样若干点，打印实际像素 RGB —— 比读 `modulate` 更能定性"叠加压暗"。
##   用法：`NetDiagDump.probe_colors([Vector2i(40,45), Vector2i(1500,45), ...])`
##   ⚠️ 必须在**渲染完成之后**取（本函数内部等一帧 post_draw），且**不要在 game_eval 里 await**
##      —— 改成发射信号/直接调用让它在帧边界后跑（见 `_on_diag_request` 的同款约定）。
func probe_colors(points: Array = []) -> void:
	var pts: Array = points
	if pts.is_empty():
		## 默认采样：红方信息栏徽章 / 绿方信息栏徽章 / 左右手牌卡面 / 地图底
		pts = [Vector2i(40, 45), Vector2i(1500, 45), Vector2i(70, 190), Vector2i(1520, 190), Vector2i(960, 540)]
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var lines: PackedStringArray = []
	lines.append("========== 🎨 COLOR PROBE ==========")
	lines.append("视口=%s · 窗口=%s" % [str(get_viewport().get_visible_rect().size), str(get_window().size)])
	for p in pts:
		var v: Vector2i = p
		if v.x < 0 or v.y < 0 or v.x >= img.get_width() or v.y >= img.get_height():
			lines.append("  %s : <越界>" % str(v))
			continue
		var c := img.get_pixelv(v)
		var lin := c.to_html(false)
		## 同时给出"还原到 0..1 的 sRGB 值"与"±1px 邻域均值"（抗锯齿/描边干扰）
		var acc := Vector3.ZERO
		var n := 0
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var q := Vector2i(v.x + dx, v.y + dy)
				if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
					var cc := img.get_pixelv(q)
					acc += Vector3(cc.r, cc.g, cc.b)
					n += 1
		var avg := acc / maxf(1.0, float(n))
		lines.append("  %-14s 像素=#%s (r=%.3f g=%.3f b=%.3f) · 3x3均值=(%.3f, %.3f, %.3f)" % [
			str(v), lin, c.r, c.g, c.b, avg.x, avg.y, avg.z])
		lines.append("                所在节点=%s" % _node_at(v))
	lines.append("===================================")
	for l in lines:
		print(l)


## 反查某屏幕点命中的 Control（`gui_get_hovered_control` 只给鼠标处，这里按几何求交）
func _node_at(p: Vector2i) -> String:
	var cs := get_tree().current_scene
	if cs == null:
		return "<无场景>"
	var best := ""
	var best_area := INF
	var stack: Array[Node] = [cs]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		var c := n as Control
		if c == null or not c.is_visible_in_tree():
			continue
		var r := _visible_bounds(c)
		if r.has_point(Vector2(p)):
			var a := r.get_area()
			if a < best_area:
				best_area = a
				best = String(c.get_path())
	return best if best != "" else "<无>"


## §B 环境态
func _section_env(out: PackedStringArray) -> void:
	out.append("\n--- §B 环境态 ---")
	var vi := Engine.get_version_info()
	out.append("  Godot：%s · hash=%s · 构建=%s" % [
		str(vi.get("string", "?")), str(vi.get("hash", "?")), str(vi.get("build", "?"))])
	out.append("  OS：%s %s · 处理器=%s · 语言=%s" % [
		OS.get_name(), OS.get_version(), OS.get_processor_name(), OS.get_locale()])
	out.append("  DisplayServer：%s · 屏幕数=%d" % [
		DisplayServer.get_name(), DisplayServer.get_screen_count()])
	for i in DisplayServer.get_screen_count():
		out.append("    screen[%d] size=%s usable=%s scale=%.3f dpi=%d refresh=%.2f" % [
			i, str(DisplayServer.screen_get_size(i)), str(DisplayServer.screen_get_usable_rect(i)),
			DisplayServer.screen_get_scale(i), DisplayServer.screen_get_dpi(i),
			DisplayServer.screen_get_refresh_rate(i)])
	var win := get_window()
	out.append("  窗口：size=%s pos=%s mode=%d screen=%d 可缩放=%s" % [
		str(win.size), str(win.position), int(win.mode), int(win.current_screen),
		str(ProjectSettings.get_setting("display/window/size/resizable", true))])
	out.append("  content_scale：size=%s mode=%d aspect=%d" % [
		str(win.content_scale_size), int(win.content_scale_mode), int(win.content_scale_aspect)])
	out.append("  视口：visible_rect=%s · canvas_transform 位移=%s 缩放=%s" % [
		str(get_viewport().get_visible_rect()), str(get_viewport().canvas_transform.origin),
		str(get_viewport().canvas_transform.get_scale())])
	out.append("  渲染：%s · %s · 驱动=%s · 适配器=%s" % [
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")),
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", "?")),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()])
	for k in WATCHED_SETTINGS:
		out.append("  %-46s = %s" % [String(k), str(_read_watched(String(k)))])
	out.append("  编辑器设置：")
	for kl in _read_editor_settings():
		out.append("    %s" % String(kl))
	out.append("  停靠布局（.godot/editor/editor_layout.cfg）：")
	for kl in _read_layout():
		out.append("    %s" % String(kl))


## §C 运行时态：性能/时间/音频/输入/场景树几何
func _section_runtime(out: PackedStringArray) -> void:
	out.append("\n--- §C 运行时态 ---")
	out.append("  帧号=%d · FPS=%.1f · 物理FPS=%.1f · time_scale=%.3f" % [
		Engine.get_frames_drawn(), Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
		Engine.time_scale])
	for m in [["TIME_FPS", Performance.TIME_FPS], ["TIME_PROCESS", Performance.TIME_PROCESS],
			["MEMORY_STATIC", Performance.MEMORY_STATIC],
			["OBJECT_COUNT", Performance.OBJECT_COUNT],
			["OBJECT_NODE_COUNT", Performance.OBJECT_NODE_COUNT],
			["RENDER_TOTAL_DRAW_CALLS_IN_FRAME", Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME],
			["RENDER_TOTAL_OBJECTS_IN_FRAME", Performance.RENDER_TOTAL_OBJECTS_IN_FRAME],
			["AUDIO_OUTPUT_LATENCY", Performance.AUDIO_OUTPUT_LATENCY]]:
		out.append("  %-36s = %s" % [String(m[0]), str(Performance.get_monitor(int(m[1])))])
	out.append("  音频驱动：%s · 输出设备=%s" % [
		AudioServer.get_driver_name(), AudioServer.output_device])
	out.append("  鼠标：%s · 触摸模拟鼠标=%s" % [
		str(get_viewport().get_mouse_position()),
		str(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", "<unset>"))])
	## 自动加载清单
	var autoloads: Array[String] = []
	for k in ProjectSettings.get_property_list():
		var nm := String(k.get("name", ""))
		if nm.begins_with("autoload/"):
			autoloads.append("%s = %s" % [nm, str(ProjectSettings.get_setting(nm))])
	out.append("  自动加载（%d）：%s" % [autoloads.size(), str(autoloads)])
	## 场景树几何 + 越界判定（**渲染后的真实屏幕坐标**）
	var vp_size := get_viewport().get_visible_rect().size
	out.append("  场景树根：%s（%s）" % [
		str(get_tree().current_scene), str(get_tree().get_node_count())])
	out.append("  --- 关键节点全局矩形（越界自动标注）---")
	out.append("  ⚠️ 被**旋转**的节点（联机镜像 seat=1 时 `MapView` 绕中心转 180°）用 `get_global_rect()`")
	out.append("     量到的是\"左上角\"**假值** ⇒ 本工具同时给出\"可见范围\"（按四角变换求包围盒）并以它判越界：")
	var bad := 0
	var cs := get_tree().current_scene
	for path in _diag_paths():
		if cs == null:
			break
		var n := cs.get_node_or_null(String(path)) as Control
		if n == null:
			continue
		var r := n.get_global_rect()
		var rot: float = _ctl_global_rotation(n)
		var rot_deg: float = rad_to_deg(rot)
		var bb := _visible_bounds(n)
		var fl := ""
		if bb.position.y < -1.0:
			fl += " ←上越界"
		if bb.position.x < -1.0:
			fl += " ←左越界"
		if bb.end.x > vp_size.x + 1.0:
			fl += " →右越界"
		if bb.end.y > vp_size.y + 1.0:
			fl += " ↓下越界"
			bad += 1
		out.append("    %-42s rect=(%.0f,%.0f) %.0fx%.0f%s" % [
			String(path), r.position.x, r.position.y, r.size.x, r.size.y,
			("  ⟲%.0f°" % rot_deg) if rot_deg > 0.5 else ""])
		out.append("      └ 可见范围=(%.0f,%.0f)…(%.0f,%.0f)%s" % [
			bb.position.x, bb.position.y, bb.end.x, bb.end.y, fl])
	out.append("    ⚠️ 下越界节点数：%d（视口 %s）" % [bad, str(vp_size)])


## Control 的**全局旋转弧度**（归一化到 [0, TAU)）。
## ⚠️ `Control` **没有** `global_rotation`（那是 Node2D 的属性）—— 实测踩到
##   `Invalid access to property or key 'global_rotation'` 会把游戏停进断点。
##   Control 只有局部 `rotation`（相对父），全局旋转要从 `get_global_transform()` 取。
func _ctl_global_rotation(n: Control) -> float:
	var r: float = n.get_global_transform().get_rotation()
	r = fmod(r, TAU)
	if r < 0.0:
		r += TAU
	return absf(r)


## 节点"真正可见"的屏幕范围（**考虑旋转/缩放**）。
## 为什么需要：旋转过的 Control 用 `get_global_rect()` 会返回假"左上角" —— 实测对方机器
##   `MapView`（seat=1 镜像 180°）被报成 (1459,1040)，而它实际仍在 (459,40)
##   ⇒ 旧版工具据此**误报"右越界/下越界"**（两个假阳性）。改取四角变换后的包围盒即可。
func _visible_bounds(n: Control) -> Rect2:
	if _ctl_global_rotation(n) < 0.001 and n.scale.is_equal_approx(Vector2.ONE):
		return n.get_global_rect()
	var xf := n.get_global_transform()
	var p0: Vector2 = xf * Vector2.ZERO
	var p1: Vector2 = xf * Vector2(n.size.x, 0.0)
	var p2: Vector2 = xf * Vector2(0.0, n.size.y)
	var p3: Vector2 = xf * n.size
	var mn: Vector2 = p0.min(p0.min(p1).min(p2.min(p3)))
	var mx: Vector2 = p0.max(p0.max(p1).max(p2.max(p3)))
	return Rect2(mn, mx - mn)


## §F 回合态 / 压暗规律快照（**专治"联机两端变化规律不一致"**）
## 为什么需要：压暗口径是 `_info_tint(side)` = f(side, my_seat, active) ——
##   两端各自算，**任一项不同就会让"变化规律"看着不一样**（而单看一端永远自洽）。
##   人 2026-10-10 描述：「本机变化规律正确，对方**异常变暗后再叠加已有的规律**」
##   ⇒ 必须把**两端的 自座位 / 当前行动方 / 实际压暗值**摆在一起比，才能定位。
## 本段同时打印：座位与回合态、四个信息栏节点的**实际 modulate**、手牌区位置与 modulate。
func _section_turnstate(out: PackedStringArray) -> void:
	out.append("\n--- §F 回合态 / 压暗规律（两端应各自自洽；比对两端本段即可看出分歧）---")
	var cs := get_tree().current_scene
	if cs == null:
		out.append("  <无场景>")
		return
	var seat = cs.get("my_seat")
	out.append("  my_seat（本端座位）        = %s" % str(seat))
	var eng = cs.get("engine")
	if eng != null and eng.get("state") != null:
		var st = eng.get("state")
		out.append("  engine.state.active（行动方）= %s" % str(st.get("active")))
		out.append("  engine.state.phase（阶段）  = %s" % str(st.get("phase")))
		out.append("  engine.state.round（回合）  = %s" % str(st.get("round")))
		out.append("  engine.sel_kind / sel_unit  = %s / %s" % [
			str(eng.get("sel_kind")), str(eng.get("sel_unit"))])
	else:
		out.append("  ⚠ 取不到 engine.state（可能非战斗场景）")
	## 四个信息栏节点的实际压暗值（**这是"规律"的最终体现**）
	for p in [["左·PlayerBesaInfoLift（敌方）", "Battle/PlayerBesaInfoLift"],
			["右·PlayerBesaInfoRight（我方）", "Battle/PlayerBesaInfoRight"]]:
		var n := cs.get_node_or_null(String(p[1])) as Control
		if n == null:
			out.append("  %-30s <缺失>" % String(p[0]))
			continue
		var m := n.modulate
		out.append("  %-30s modulate=(%.3f, %.3f, %.3f, %.2f)  pos=%s" % [
			String(p[0]), m.r, m.g, m.b, m.a, str(n.position)])
	## 手牌区（位置体现镜像；modulate 体现手牌压暗）
	for p in [["左·HandPanelLeft", "Battle/HandPanelLeft"],
			["右·HandPanelRight", "Battle/HandPanelRight"]]:
		var n := cs.get_node_or_null(String(p[1])) as Control
		if n == null:
			out.append("  %-30s <缺失>" % String(p[0]))
			continue
		out.append("  %-30s modulate=(%.3f, %.3f, %.3f, %.2f)  pos=%s" % [
			String(p[0]), n.modulate.r, n.modulate.g, n.modulate.b, n.modulate.a, str(n.position)])
	## 手牌卡亮/灰（每张卡的 modulate —— 口径：只按部署费用，理论上两端应一致）
	var hn = cs.get("_hand_nodes")
	if hn != null:
		for sidek in hn.keys():
			var d = hn[sidek]
			var idx := 0
			for k in d.keys():
				var c = d[k]
				idx += 1
				if c == null or not is_instance_valid(c):
					continue
				out.append("  手牌 side=%s #%d modulate=(%.3f,%.3f,%.3f,%.2f)" % [
					str(sidek), idx, c.modulate.r, c.modulate.g, c.modulate.b, c.modulate.a])
	## ⭐ 地图单位几何（**迭代065 数据镜像的取证位**）——
	##   人 2026-10-10 报「对端初始两个蜂王普遍向右向下各移动一格」；本段给出：
	##   规范格（元数据）· 节点局部位置 · 全局位置 · 旋转 · 以及**该规范格节点自身的局部位置**。
	##   ⇒ 两端各发一份：若"规范格相同、而节点的 local 与该格节点的 local 不等"，即定位/镜像有偏。
	var units_root := cs.get_node_or_null("Battle/MapView/Units") as Control
	var cells_root2 := cs.get_node_or_null("Battle/MapView/MapCells") as Control
	out.append("  --- 地图单位几何（规范格 → 节点位置 → 该格节点位置）---")
	if units_root == null:
		out.append("    <无 Units 容器>")
	else:
		var ucount := 0
		for u in units_root.get_children():
			var uc := u as Control
			if uc == null:
				continue
			ucount += 1
			var canon = uc.get_meta("cell", null)
			var cell_local := "<无格节点>"
			var cell_global := "-"
			if canon != null and cells_root2 != null:
				var cn := cells_root2.get_node_or_null("Cell_%d_%d" % [int(canon.x), int(canon.y)]) as Control
				if cn != null:
					cell_local = str(cn.position)
					cell_global = str(cn.global_position)
			out.append("    %-20s 规范格=%s | 单位 local=%s global=%s rot=%.4f | 该格 local=%s global=%s | 吻合=%s" % [
				String(uc.name), str(canon), str(uc.position), str(uc.global_position), uc.rotation,
				cell_local, cell_global,
				str(str(uc.position) == cell_local)])
		if ucount == 0:
			out.append("    (当前无单位)")


## §D 运行时变化 + 事件流
func _section_events(out: PackedStringArray) -> void:
	out.append("\n--- §D 运行时变化 / 事件流（侵入式观察）---")
	if _events.is_empty():
		out.append("  （无）")
	for e in _events:
		out.append("  %s" % String(e))


# ============================================================================
#  工具
# ============================================================================
func _diag_paths() -> Array:
	return ["Battle/MapView", "Battle/MapView/MapFrame",
		"Battle/HandPanelLeft", "Battle/HandPanelRight",
		"Battle/PlayerBesaInfoRight", "Battle/PlayerBesaInfoRight/BadgeImage",
		"Battle/PlayerBesaInfoRight/BadgeImage/Value",
		"Battle/PlayerBesaInfoLift", "Battle/PlayerBesaInfoLift/BadgeImage",
		"HUD/InfoPanel", "HUD/ActionBar", "HUD/ActionBar/MainButton",
		"HUD/ActionBar/Label", "HUD/MatchInfo", "HUD/FuncButtonGroup"]


func _file_sha(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "<缺失>"
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(f.get_buffer(f.get_length()))
	f.close()
	return h.finish().hex_encode().substr(0, 16)


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _list_files(root: String, suffix: String, out: Array = []) -> Array:
	var d := DirAccess.open(root)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var full := root.path_join(n)
		if d.current_is_dir():
			## 跳过缓存/仓库/插件（只需游戏代码，避免几万文件）
			if n != "." and n != ".." and n != ".godot" and n != ".git" and n != "addons":
				_list_files(full, suffix, out)
		elif n.ends_with(suffix):
			out.append(full)
		n = d.get_next()
	d.list_dir_end()
	return out


func _read_editor_settings() -> PackedStringArray:
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


func _read_layout() -> PackedStringArray:
	var res: PackedStringArray = []
	var txt := _read_text("res://.godot/editor/editor_layout.cfg")
	if txt == "":
		res.append("⚠ 无 editor_layout.cfg（会自动重建默认布局）")
		return res
	for line in txt.split("\n"):
		var l := String(line).strip_edges()
		if l.begins_with("dock_split") or l.begins_with("dock_hsplit"):
			res.append(l)
	return res
