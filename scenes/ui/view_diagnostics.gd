extends RefCounted
## 运行期几何诊断（自 arena_view.gd 切出 —— 迭代073 · B5 第一刀）
##
## 为什么切它：arena_view.gd 单体 2528 行（> 1000 行 gdlint 阈值）。诊断族**对玩家画面零影响**，
## 是最适合作为第一刀的部分；切完「观感不变」是可证的，而不是靠自觉。
##
## 约定：一切需要节点的访问都经 root 参数传入 —— 本文件不持有任何视图状态。
const NODES := [
	"Battle/MapView", "Battle/MapView/MapPlate", "Battle/MapView/MapCells", "Battle/MapView/Units",
	"Battle/MapView/MapFrame",
	"Battle/HandPanelLeft", "Battle/HandPanelLeft/HandLeft",
	"Battle/HandPanelRight", "Battle/HandPanelRight/HandRight",
	"Battle/PlayerBesaInfoRight", "Battle/PlayerBesaInfoRight/BadgeImage",
	"Battle/PlayerBesaInfoRight/BadgeImage/Value",
	"Battle/PlayerBesaInfoLift", "Battle/PlayerBesaInfoLift/BadgeImage",
	"Battle/PlayerBesaInfoLift/BadgeImage/Value",
	"HUD/InfoPanel", "HUD/ActionBar", "HUD/ActionBar/MainButton", "HUD/ActionBar/Label",
	"HUD/MatchInfo", "HUD/FuncButtonGroup",
]


## 打印并（可选）截图：实测运行期几何，供异机比对
static func dump(root: Node, save_shot: bool = true) -> Dictionary:
	var vp := root.get_viewport()
	var win := root.get_window()
	var info := {
		"viewport_size": vp.get_visible_rect().size,
		"canvas_transform": vp.canvas_transform,
		"window_size": Vector2(win.size),
		"window_content_scale": win.content_scale_size,
		## ⚠️ 屏幕类 API 在 Godot 4 属于 **DisplayServer**（`Window.get_screen_get_*()` 不存在 —— 实测踩到
		##   `Invalid call. Nonexistent function 'get_screen_get_scale'`，直接把游戏停进了断点）
		"screen_scale": DisplayServer.screen_get_scale(),
		"screen_size": Vector2(DisplayServer.screen_get_size()),
		"screen_dpi": DisplayServer.screen_get_dpi(),
		"screen_count": DisplayServer.get_screen_count(),
		"window_screen": win.current_screen,
		"window_mode": win.mode,
		"stretch_mode": ProjectSettings.get_setting("display/window/stretch/mode", "<unset>"),
		"stretch_aspect": ProjectSettings.get_setting("display/window/stretch/aspect", "<unset>"),
		"design_size": Vector2(
			float(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
			float(ProjectSettings.get_setting("display/window/size/viewport_height", 0))),
	}
	print("========== 🧪 RUNTIME GEOMETRY ==========")
	print("  设计分辨率 : %s" % str(info["design_size"]))
	print("  视口(渲染区): %s" % str(info["viewport_size"]))
	print("  窗口       : %s · content_scale=%s" % [
		str(info["window_size"]), str(info["window_content_scale"])])
	print("  屏幕       : %s · scale=%.2f · dpi=%d · 屏数=%d · 本窗口屏=%d · 窗口模式=%d" % [
		str(info["screen_size"]), float(info["screen_scale"]), int(info["screen_dpi"]),
		int(info["screen_count"]), int(info["window_screen"]), int(info["window_mode"])])
	print("  Canvas变换 : 位移=%s 缩放=%s" % [
		str(info["canvas_transform"].origin), str(info["canvas_transform"].get_scale())])
	print("  stretch    : %s / %s" % [str(info["stretch_mode"]), str(info["stretch_aspect"])])
	var vw := float(info["viewport_size"].x)
	var vh := float(info["viewport_size"].y)
	var bad := 0
	for path in NODES:
		var n := root.get_node_or_null(String(path)) as Control
		if n == null:
			print("  ⚠ %s : <缺失>" % String(path))
			continue
		var gr := n.get_global_rect()
		## 越界判定：**渲染后的全局矩形**是否超出实际渲染区（含 1px 容差）
		var flags := ""
		if gr.position.x < -1.0:
			flags += " ←左越界"
		if gr.position.y < -1.0:
			flags += " ←上越界"
		if gr.end.x > vw + 1.0:
			flags += " →右越界"
		if gr.end.y > vh + 1.0:
			flags += " ↓下越界"
			bad += 1
		print("  %-46s rect=(%.0f,%.0f) size=(%.0f×%.0f) end=(%.0f,%.0f)%s" % [
			String(path), gr.position.x, gr.position.y, gr.size.x, gr.size.y,
			gr.end.x, gr.end.y, flags])
	## 手牌卡逐张（费用徽章"下移"要看卡内节点相对卡的实际偏移）
	var hn = root.get("_hand_nodes")
	if hn != null:
		for sidek in hn.keys():
			for k in hn[sidek].keys():
				var c = hn[sidek][k]
				if c == null or not is_instance_valid(c):
					continue
				var badge := c.get_node_or_null("BadgeImage") as Control
				var val := c.get_node_or_null("BadgeImage/Value") as Control
				if badge != null and val != null:
					var cb := badge.get_global_rect()
					var cv := val.get_global_rect()
					print("  手牌(side=%s) 卡=%s 徽章=(%.0f,%.0f %.0fx%.0f) 数字=(%.0f,%.0f %.0fx%.0f) Δy=%.1f" % [
						str(sidek), String(k).substr(0, 6),
						cb.position.x, cb.position.y, cb.size.x, cb.size.y,
						cv.position.x, cv.position.y, cv.size.x, cv.size.y,
						cv.position.y - cb.position.y])
					break
			break
	print("  下越界节点数：%d" % bad)
	if save_shot:
		var dir := "user://diag"
		DirAccess.make_dir_recursive_absolute(dir)
		var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
		var path := "%s/diag_%s.png" % [dir, stamp]
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var err := img.save_png(path)
		var abs_path := ProjectSettings.globalize_path(path)
		print("  📸 截图：%s（err=%d）" % [abs_path, err])
		info["shot"] = abs_path
	print("========================================")
	return info



