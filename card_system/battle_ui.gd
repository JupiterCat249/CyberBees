@tool
extends Node2D
## ============================================================
## 战斗 UI 骨架：1 个 shader 程序化绘制整幅 1920x1080 界面
##   已实现（定量内置）：棋盘+十字网格 / 两侧预览面板 / 玩家徽章 /
##   黑色卡面区 / 状态图标(图集) / 主按钮 / 4 个功能按钮(内置 SDF 图标)
##   文字与数字一律不画——等游戏逻辑函数接入后由上层节点补充
##   任何窗口/编辑器内嵌面板：整幅界面等比缩放居中，比例永不变形
## 查看：编辑器中选中本场景按 F6，或命令行运行本场景
## 验证：CARD_SHOT=路径 [CARD_W=x CARD_H=y] 运行自动截图退出
## ============================================================

const DESIGN := Vector2(1920.0, 1080.0)

var _snapping := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# 运行时：窗口尺寸变化 → 重新等比适配；OS 窗口吸附 16:9
	get_window().size_changed.connect(_update_fit)
	get_window().size_changed.connect(_snap_window_aspect)
	_update_fit()

	# 验证用：CARD_SHOT=输出路径 [CARD_W=x CARD_H=y]（默认 1920x1080）
	var shot := OS.get_environment("CARD_SHOT")
	if shot == "":
		return
	var w := 1920
	var h := 1080
	var ew := OS.get_environment("CARD_W")
	var eh := OS.get_environment("CARD_H")
	if ew != "":
		w = ew.to_int()
	if eh != "":
		h = eh.to_int()
	# 截图验证：关拉伸，1 设计像素 = 1 屏幕像素，便于逐像素检查
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = Vector2i(w, h)
	for i in 4:
		await RenderingServer.frame_post_draw
	_update_fit()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()


## 整幅 UI 等比适配当前画布视口（独立窗口拉伸 keep / 编辑器内嵌面板均正确）
func _update_fit() -> void:
	var vs := get_viewport_rect().size
	var s: float = minf(vs.x / DESIGN.x, vs.y / DESIGN.y)
	$Holder.scale = Vector2(s, s)
	$Holder.position = (vs - DESIGN * s) * 0.5


## OS 窗口尺寸吸附到最近 16:9（编辑器内嵌面板不应用拉伸，跳过）
func _snap_window_aspect() -> void:
	if _snapping:
		return
	var w := get_window()
	if w.mode != Window.MODE_WINDOWED:
		return
	# 内嵌游戏面板：窗口尺寸 == 画布视口尺寸（不应用拉伸），不干预
	if Vector2(w.size) == get_viewport_rect().size:
		return
	var k: float = minf(w.size.x / 16.0, w.size.y / 9.0)
	var target := Vector2i(int(16.0 * k), int(9.0 * k))
	if absi(target.x - w.size.x) <= 1 and absi(target.y - w.size.y) <= 1:
		return
	_snapping = true
	w.size = target
	_snapping = false
