@tool
extends EditorScript
## ============================================================
## 卡牌图集烘焙（Godot 内置，替代外部 PowerShell 脚本）
##
## 作用：把 card_system/icons/ 下的 8 个彩色图标
##   白化 → alpha 裁紧 → 等比重铺居中 → 写入 card_atlas.png 的第 10-17 格
## 数字格 0-9 保持不动（数字由系统字体一次性烘焙，无需重做）。
##
## 用法：
##   1. 在 Godot 脚本编辑器里打开本文件
##   2. 菜单「文件 → 运行」（快捷键 Ctrl+Shift+X）
##   3. 输出面板看到「card_atlas 烘焙完成」即成功，图集自动重新导入
##
## 新增/替换图标：把同名 PNG 放进 card_system/icons/ 后再运行一次即可。
## 图标顺序（= shader 图标索引）：
##   0攻击(attack) 1速度(speed) 2血量(hp) 3射程(range)
##   4兵蜂(soldier) 5建筑(building) 6指令(command) 7蜂王(queen)
## ============================================================

const ATLAS_RES := "res://card_system/card_atlas.png"
const ICON_DIR_RES := "res://card_system/icons/"
const ICON_FILES := [
	"attack.png", "speed.png", "hp.png", "range.png",
	"soldier.png", "building.png", "command.png", "queen.png",
]

const CELL := 96       # 图集格子边长 px
const INNER := 84      # 图标内容区边长（格内 6px 边距）
const ALPHA_THRESHOLD := 20.0 / 255.0


func _run() -> void:
	var atlas_path := ProjectSettings.globalize_path(ATLAS_RES)
	var atlas := Image.load_from_file(atlas_path)
	if atlas == null:
		push_error("找不到图集：%s（请先确认 card_atlas.png 存在）" % atlas_path)
		return

	for k in ICON_FILES.size():
		var icon_path := ProjectSettings.globalize_path(ICON_DIR_RES + ICON_FILES[k])
		var src := Image.load_from_file(icon_path)
		if src == null:
			push_error("找不到图标：%s" % icon_path)
			continue
		src.convert(Image.FORMAT_RGBA8)

		# ① 白化（RGB 置白，保留 alpha）+ ② 计算 alpha 包围盒
		var x0 := src.get_width()
		var y0 := src.get_height()
		var x1 := -1
		var y1 := -1
		for y in src.get_height():
			for x in src.get_width():
				var p := src.get_pixel(x, y)
				if p.a > ALPHA_THRESHOLD:
					src.set_pixel(x, y, Color(1.0, 1.0, 1.0, p.a))
					x0 = min(x0, x)
					x1 = max(x1, x)
					y0 = min(y0, y)
					y1 = max(y1, y)
		if x1 < 0:
			push_warning("图标 %s 没有任何不透明像素，跳过" % ICON_FILES[k])
			continue

		# ③ alpha 裁紧
		var iw: int = x1 - x0 + 1
		var ih: int = y1 - y0 + 1
		var tight := src.get_region(Rect2i(x0, y0, iw, ih))

		# ④ contain 等比重铺到 INNER x INNER
		var s: float = min(float(INNER) / float(iw), float(INNER) / float(ih))
		var dw: int = max(1, roundi(iw * s))
		var dh: int = max(1, roundi(ih * s))
		tight.resize(dw, dh, Image.INTERPOLATE_BILINEAR)

		# ⑤ 居中合成到图集第 (10 + k) 格
		var dx: int = (10 + k) * CELL + int(round((CELL - dw) / 2.0))
		var dy: int = int(round((CELL - dh) / 2.0))
		atlas.blend_rect(tight, Rect2i(0, 0, dw, dh), Vector2i(dx, dy))
		print("  图标 %d %s → 格 %d（裁紧 %dx%d → 重铺 %dx%d）" % [k, ICON_FILES[k], 10 + k, iw, ih, dw, dh])

	var err := atlas.save_png(atlas_path)
	if err != OK:
		push_error("图集保存失败：%s" % error_string(err))
		return

	# 通知编辑器重新导入，shader 立即用到新图集
	EditorInterface.get_resource_filesystem().reimport_files([ATLAS_RES])
	print("card_atlas 烘焙完成 → %s" % ATLAS_RES)
