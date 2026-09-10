extends Node2D
## ============================================================
## BattleBgFx —— 背景与背景特效层
##   ① 背景替换（非硬编码）：运行时读取框架 shader 源码 → 注入背景函数 → 把
##      硬编码灰底 `vec3 col = COL_BG;` 换成对该函数的调用 → 赋给本场景材质副本。
##      不改 card-system 任何文件（材质 resource_local_to_scene=true）。
##   ② 层同步：文字层 / 背景层 / 特效层 跟随框架 Holder 的等比缩放与居中。
##   ③ 背景特效（扫描线）是场景里的 FxLayer/BgFilter（TextureRect 平铺）+ AnimationPlayer 动画。
## ============================================================

const D := preload("res://scenes/battle/battle_defs.gd")

signal scan_offset_changed(offset: float)   ## 扫描线相位（供其他背景贴图同步，避免各自计算）

var holder: Node2D = null
var overlay: Node2D = null
var bg_layer: Node2D = null
var fx_layer: Node2D = null

var _bg_mat: ShaderMaterial = null
var _scan_offset := 0.0


func _ready() -> void:
	get_window().size_changed.connect(sync_layers)


## 由协调器注入依赖
func setup(h: Node2D, bl: Node2D, fl: Node2D, ov: Node2D) -> void:
	holder = h
	bg_layer = bl
	fx_layer = fl
	overlay = ov
	inject_background()
	sync_layers()


## 非硬编码的「背景替换」：注入背景采样函数并调用它
func inject_background() -> void:
	if holder == null:
		return
	var rect := holder.get_node_or_null(NodePath("Rect")) as ColorRect
	if rect == null:
		return
	var mat := rect.material as ShaderMaterial
	if mat == null or mat.shader == null:
		return
	var src: String = mat.shader.code
	if src.contains("bg_sample"):
		mat.set_shader_parameter("bg_tex", load(D.BG_BLURRED_PATH))
		return
	var anchor := "const vec3 COL_BG = vec3(0.35);"
	var call_anchor := "vec3 col = COL_BG;"
	if not src.contains(anchor) or not src.contains(call_anchor):
		push_warning("背景注入跳过：框架 shader 结构已变（未找到注入锚点）")
		return
	var inject := anchor + "\n"
	inject += "uniform sampler2D bg_tex : source_color, filter_linear;\n"
	inject += "uniform sampler2D scan_tex : source_color, filter_linear;\n"
	inject += "uniform float bg_mix = 1.0;\n"
	inject += "uniform float scan_mix = " + str(D.SCAN_MIX) + ";\n"
	inject += "uniform float scan_offset = 0.0;\n"
	inject += "vec3 bg_sample(vec2 px) {\n"
	inject += "\tvec2 tuv = clamp(px / RES, vec2(0.0), vec2(1.0));\n"
	inject += "\tvec3 c = mix(COL_BG, texture(bg_tex, tuv).rgb, bg_mix);\n"
	inject += "\tvec2 suv = fract(vec2(px.x / " + str(D.SCAN_TILE_PX) + ", (px.y + scan_offset) / " + str(D.SCAN_TILE_PX) + "));\n"
	inject += "\tvec4 s = texture(scan_tex, suv);\n"
	inject += "\treturn mix(c, s.rgb, s.a * scan_mix);\n"
	inject += "}"
	src = src.replace(anchor, inject)
	src = src.replace(call_anchor, "vec3 col = bg_sample(px);")
	var sh := Shader.new()
	sh.code = src
	mat.shader = sh
	mat.set_shader_parameter("bg_tex", load(D.BG_BLURRED_PATH))
	mat.set_shader_parameter("bg_mix", 1.0)
	mat.set_shader_parameter("scan_tex", load(D.SCAN_TILE_PATH))
	mat.set_shader_parameter("scan_mix", D.SCAN_MIX)
	_bg_mat = mat


## 扫描线相位推进：按帧数计时（a500/项目约束：不使用 delta），并广播给其他背景贴图
func _process(_delta: float) -> void:
	if _bg_mat == null:
		return
	_scan_offset = fmod(_scan_offset + D.SCAN_SPEED, D.SCAN_TILE_PX)
	_bg_mat.set_shader_parameter("scan_offset", _scan_offset)
	scan_offset_changed.emit(_scan_offset)


## 各层跟随框架 Holder 的等比缩放与居中（任何窗口都不变形）
func sync_layers() -> void:
	if holder == null:
		return
	for n in [overlay, bg_layer, fx_layer]:
		var nd := n as Node2D
		if nd != null:
			nd.scale = holder.scale
			nd.position = holder.position
