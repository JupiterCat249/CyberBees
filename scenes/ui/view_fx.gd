extends RefCounted
## 视觉特效播放族（自 arena_view 切出 —— 迭代078 · B5 第五刀）
##
## 判据：这些函数**只操作已存在的节点与动画器**（飘字层 / 单位节点 / anim），
##   不新建布局、不改字号与配色表 ⇒ 切出去不改变任何"设计上的"观感。
##
## 依赖一律显式传入（不持视图引用）：anim / unit_nodes / shake_frame / pending_exit。
## 这样它能被单独读懂与替换，也不会因为视图改名而静默失效。


## 飘字（§二之1：回费/数值 buff/战斗结算；§二之2：三色 + **数值越大字体越大**）
## ⚠️ 颜色/字号放**子节点**：`浮字上浮` 的淡出是 TINT（绝对 modulate），
##   若把颜色放在动画目标本身会被白色冲掉（迭代060 实测踩坑）
static func float_at(fx_root: Control, scene: PackedScene, anim, anchor: Control,
		text: String, color: Color, value: int, fs: Dictionary) -> void:
	if fx_root == null or anchor == null or not is_instance_valid(anchor):
		return
	var ft: Control = scene.instantiate()
	var lb: Label = ft.get_node("Text")
	lb.text = text
	lb.modulate = color
	var t: float = clampf(float(value) / float(fs["ref"]), 0.0, 1.0)
	var px: int = int(round(lerpf(float(fs["base"]), float(fs["max"]), t)))
	lb.add_theme_font_size_override("font_size", px)
	fx_root.add_child(ft)
	## 坐标空间：飘字挂 EffectsTop（与视图根同原点的整屏 Control）→ 用 global 差值换算
	ft.position = anchor.global_position + Vector2(anchor.size.x * 0.5 - 100.0, -20.0) \
		- fx_root.global_position
	if anim != null:
		anim.action("浮字上浮", ft)   # 注意：飘字直接对**节点**播；_play 是按 instance_id 找单位节点的另一条路


## 受击抖动（§二之2：受到攻击即抖；**数值越大越剧烈**）
##   触发条件是"受到攻击/伤害的事件"，不是"血量是否变化"（人 2026-09-21）
##   同一帧多来源只算一次 → 按帧号去重（shake_frame: instance_id → 帧号）
static func shake(shake_frame: Dictionary, anim, inst, value: int, on_play: Callable) -> void:
	if anim == null or inst == null:
		return
	var fid: int = Engine.get_process_frames()
	if int(shake_frame.get(inst.instance_id, -1)) == fid:
		return
	shake_frame[inst.instance_id] = fid
	on_play.call("受击抖动", inst, maxi(1, value))


## 播动画：目标节点由 instance_id 解析；不在册则跳过（不报错、不吞）
static func play(anim, unit_nodes: Dictionary, pname: String, inst, value: int = 0) -> void:
	if anim == null or inst == null:
		return
	var n: Control = unit_nodes.get(inst.instance_id, null)
	if n != null and is_instance_valid(n):
		anim.action(pname, n, value)


## 动画自然播完的收尾（基础动画 §一：播完立即退场，不额外等帧）
##   · `单位退场` / `浮字上浮` → 释放节点（否则淡到 α=0 后永久滞留＝泄漏）
##   · 待退场排队：该单位身上动画**全部播完**后才开始淡出（人 2026-09-21）
static func on_anim_finished(pending_exit: Dictionary, anim, pname: StringName,
		target: Node, start_exit: Callable) -> void:
	if target == null or not is_instance_valid(target):
		return
	var n := String(pname)
	if n == "单位退场" or n == "浮字上浮":
		target.queue_free()
		return
	var tid: int = target.get_instance_id()
	if pending_exit.has(tid) and anim != null and anim.running_count_on(target) == 0:
		pending_exit.erase(tid)
		start_exit.call(target)
