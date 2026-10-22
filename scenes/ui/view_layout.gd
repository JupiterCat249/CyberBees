extends RefCounted
## 布局适配族（自 arena_view 切出 —— 迭代084 · B5 第七刀）
##
## ⚠️⚠️ 人 2026-09-19 硬约束：**不要改字号**。
##   本文件里的所有字号/位置/描边数值都是**逐字搬过来的**，一个都没有动。
##   改动这里的任何数字前，先看各函数上方的实测记录（哪一版改小了被否过）。
##
## 判据：这些函数只读/写**已经存在的控件与窗口**，不做布局重排、不改设计数值；
##   因此可以整块切出，用「运行期几何 dump 逐字节比对」证明结构未变。

## 适配长文案与地形提示
## ⚠️ **人 2026-09-19 明确要求：不要改字号。**
##   之前这里把主按钮 60→30、阶段提示 24→20，导致字号变小（尤其手牌/详情区属性区）。
##   现只保留**自动换行**（不改字号），字号一律沿用素材场景原值。
static func fit_text_labels(root: Node, on_center_label: Callable,
		on_center_badge: Callable) -> void:
	var se := root.get_node_or_null("HUD/MatchInfo/SiteEffect") as Label
	if se != null:
		se.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	## ⭐ 迭代064 遗留修复（人 2026-10-05「左侧单位技能详细信息栏存在文本超出边框来到战斗地图而没有自动换行」）：
	##   **实测根因**：`HUD/InfoPanel/SkillDesc` 的框宽 **300px**，而技能描述**单行文本宽 444px**、
	##   `autowrap_mode = 0`（无换行）且 `clip_text = false` ⇒ 文字**直接画出框外**、
	##   越过面板右缘（面板右缘 430）压到战斗地图上 ✗。
	##   修法：与右下面板 `SiteEffect` **同一口径** —— 只开**自动换行**，**不改字号**（守 2026-09-19 硬约束）。
	##   `CardName` 同理补上（当前卡名未溢出，但卡名长度由数据决定，属同类隐患；换行只对更长的卡名生效）。
	for dp in ["HUD/InfoPanel/SkillDesc", "HUD/InfoPanel/CardName"]:
		var dl := root.get_node_or_null(dp) as Label
		if dl != null:
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	## ⭐ 迭代064 B7（修 P-11 = 清单 UI-7「主按钮存在文本不对齐问题（在一些情况下如添加额外的文字）」）
	## 根因（**实测**，不是猜）：主按钮 `Label` 的框只有 **240px**，而 **Control 会按"最小尺寸"把自己撑大** ——
	##   文案一长（实测 `绿方胜（蜂王被击杀）` = **420px**）框就长到 420，但它的 `position` **固定 x=80 不动**
	##   ⇒ 文字从框左边缘起排、直接冲出屏幕右缘。所以**改 `horizontal_alignment` 无效**（它本来就是居中 1）。
	## 修法：监听 Label 的 `resized`，每次按**按钮实际宽度重新水平居中** —— 不动字号、不动按钮尺寸。
	var lb := root.get_node_or_null("HUD/ActionBar/Label") as Control
	if lb != null and not lb.resized.is_connected(on_center_label):
		lb.resized.connect(on_center_label)
		on_center_label.call()
	## ⭐ 迭代064 B7（修 P-06 = 清单 UI-12「文本达到两位数时没居中」/ UI-19「费用为 10 时 UI 文本溢出」）
	## 根因与主按钮**完全同源**（实测）：费用 `Label` 的框只有 **38px**，而 **`Control` 会按最小尺寸
	##   被文案撑大** —— "10" 实测 **77px** ⇒ 框长到 77，但 `position` 不动 ⇒ 文字**中心偏离徽章约 20px**、
	##   右端**溢出徽章**（截图实测那个 "0" 探出徽章右缘）。
	## 修法：按**徽章实际宽度**重新水平居中；**绝不动字号**（人 2026-09-19 硬约束：不得覆写素材字号 ——
	##   历史上正是"手牌费用徽章 48→26"这类覆写被否）。
	for bp in ["Battle/PlayerBesaInfoRight/BadgeImage", "Battle/PlayerBesaInfoLift/BadgeImage"]:
		var badge := root.get_node_or_null(bp) as Control
		if badge == null or badge.has_meta("b7_badge_centered"):
			continue
		badge.set_meta("b7_badge_centered", true)
		var v := badge.get_node_or_null("Value") as Control
		if v != null:
			v.resized.connect(on_center_badge.bind(badge))
			center_badge_value(badge)


## 把费用数字**水平居中到徽章宽度内**（供 `Value.resized` 回调；幂等）
## ⚠️ 与 `on_center_label.call()` 同一套思路：**只挪位置、不动字号/尺寸**
static func center_badge_value(badge: Control) -> void:
	## ⚠️ **修正（人 2026-10-05 实测：费用数字普遍**向右偏移**、而模板场景本身是正确居中的）**：
	##   原实现 `lb.position.x = (badge.size.x - lb.size.x) * 0.5` **是错的** ——
	##   模板里 `Value` 本来就是居中的 38px 文本框（`offset 30.9..68.9`，锚点在父左上），
	##   我又按"父左上角 + 当前框宽"重算了一遍 `position` ⇒ **叠加了一次偏移** ⇒ 整体右移。
	##   正确做法（**与模板单数字时的视觉完全等价**，且两位数也永远居中）：
	##   让文本框**覆盖整个徽章** + 文本水平/垂直居中 ⇒ 任意位数都居中、也不会因最小尺寸被撑大而偏移。
	##   （对齐中心 (30.9+68.9)/2 = 49.9 ≈ 徽章中心 ⇒ 单数字结果与模板一致 ✓）
	if badge == null:
		return
	var lb := badge.get_node_or_null("Value") as Control
	if lb == null:
		return
	## ⭐ 迭代067（人 2026-10-10：「费用数字过度靠下…可能需要做自适应」）：
	##   见 `center_badge_value_geometry()` —— 两处（信息栏 / 手牌卡）**共用同一实现**，杜绝分叉。
	center_badge_value_geometry(badge)


## ⭐ 费用数字的**确定性字体**（迭代065 续，人 2026-10-10「对端费用数字依然偏下」的根因修法）
##   为何必须显式绑定：两个 `Value` 原本用 `SystemFont` + 候选族名 ⇒ **按机器上装了什么字体解析**
##   （本机 Noto Sans SC：`ascent=65/descent=13/高=78`；对端若落到 Microsoft YaHei 则行盒比例不同）
##   ⇒ 同为"垂直居中"，**字形的视觉落点却差若干像素** ⇒ 外观随机器变化，违反"不假设两台一致"。
##   绑到项目内已入库的 `assets/fonts/NotoSansSC-Bold.ttf` ⇒ **两端同一字体文件、同一行盒**。
const NUMBER_FONT_PATH := "res://assets/fonts/NotoSansSC-Bold.ttf"
static var _number_font: Font = null


static func apply_number_font(lb: Control) -> void:
	if lb == null or not (lb is Label):
		return
	## 幂等：已经绑过同一字体就不再动
	if lb.has_meta("num_font_done"):
		return
	if _number_font == null and ResourceLoader.exists(NUMBER_FONT_PATH):
		var res := load(NUMBER_FONT_PATH)
		if res is FontFile:
			var ff := res as FontFile
			## ⚠️ **就绪判据不能只看 `data`**：导入字体是**压缩懒加载**（`.import` 里 `compress=true`，
			##    实际数据在 `res://.godot/imported/*.fontdata`），`data` 可能非空而 TextServer 仍拿不到字形
			##    ⇒ 此时挂 override 会持续刷 `Parameter "fd" is null`（实测）。
			##    改用**能真正驱动 TextServer 的探测**（`get_height`）当就绪判据，探测失败就本轮不绑、下次再试。
			var ok := false
			if ff.data != null and ff.data.size() > 0:
				var h := 0.0
				h = ff.get_height(48)      ## 触发字形数据加载；未就绪时会报错但被下面的容错吃掉
				ok = h > 0.0
			if ok:
				_number_font = ff
	if _number_font == null:
		return                       ## 字体缺失/未就绪时保持原状（不阻断渲染，下次再试）
	## ⚠️ **延到首帧之后应用**：实测在 `_ready()` 期间挂 override，会撞上**首帧布局/字形数据绑定**，
	##    刷 8 次 `Parameter "fd" is null`（每个费用数字一次），之后自愈。
	##    `call_deferred` 让应用落在本轮布局结束之后 ⇒ 既不报错，绑定时机也不影响观感。
	if not lb.has_meta("num_font_pending"):
		lb.set_meta("num_font_pending", true)
		lb.call_deferred("add_theme_font_override", "font", _number_font)
		lb.set_meta("num_font_done", true)


## 把徽章里的数字**几何居中**到徽章正中（幂等；供信息栏与手牌卡**两处共用**）
## ⭐ 为什么两处要共用一个实现：人 2026-10-10 反馈"联机对端**费用数字过度靠下**" ——
##   两边原来各写一套（信息栏走 `_center_badge_value`、手牌走 `_apply_one_hand_params`），
##   任何一处漏掉就会出现"本机正常、对端偏下"的机器相关差异。统一到一个函数，杜绝分叉。
## ⚠️ 保持 `Value` 仍是徽章的**直接子节点**（路径 `BadgeImage/Value` 被多处按路径取用）。
static func center_badge_value_geometry(badge: Control) -> void:
	if badge == null:
		return
	## ⚠️ **幂等/防重入**（实测踩到栈溢出）：本函数会改 `Value` 的尺寸，而 `_center_badge_value`
	##   又把该节点的 `resized` 接到这里 ⇒ 不加守卫会**无限递归**（Stack overflow）。
	##   徽章的父框尺寸不变时无需重算 ⇒ 用"上次算过的父框尺寸"做记忆即可。
	var stamp := badge.size
	if badge.has_meta("vcenter_stamp") and badge.get_meta("vcenter_stamp") == stamp:
		return
	badge.set_meta("vcenter_stamp", stamp)
	var lb := badge.get_node_or_null("Value") as Control
	if lb == null:
		return
	lb.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	## ⭐⭐ 迭代065 续：**费用数字改用「项目自带字体」**（根因修法，异机度量一致）
	##   人 2026-10-10：「对端**手牌与玩家信息栏的费用数字依然偏下**」；而本机实测**几何完全正确**
	##   （徽章与 `Value` 同矩形、`H/V` 都居中、offsets 全 0）⇒ 差异只能在**字形/字体**。
	##   **查明**：这两个 `Value` 用的是**系统字体** `SystemFont`，候选
	##     `["Noto Sans SC","Source Han Sans CN","Microsoft YaHei"]`
	##     ⇒ **哪台机装了什么字体，就解析到不同的族**（本机落到 Noto Sans SC：`ascent=65/descent=13`；
	##       对端大概率落到 Microsoft YaHei，**行盒比例不同**）⇒ 同为"垂直居中"，**数字的视觉落点却不同** ✗
	##   **修法**：显式绑定项目内已随仓的 `assets/fonts/NotoSansSC-Bold.ttf`（`FontFile`）
	##     ⇒ **两端解析到同一个字体文件 ⇒ 行盒完全相同 ⇒ 数字落点一致**。
	apply_number_font(lb)
	if lb is Label:
		var l := lb as Label
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		## ⚠️ **单行文本不要显式设尺寸**：字体最小尺寸会把高度撑成"行盒高"（实测 38×78，
		##   远大于徽章可用空间 ⇒ 位置算成负值、反而偏离中心）。
		##   只把它铺满父框 + 对齐标记 ⇒ 任意位数都居中。
		## ⚠️ 2026-10-10 **尝试过"按字形墨迹居中"但已回退**（实测把数字甩出徽章，见迭代065 §八）：
		##   根因是 `Value` 的 `size` 被其**最小尺寸**反复夹回行盒高（`custom_minimum_size` 也压不住），
		##   且信息栏徽章的 `size` 在 `_ready` 阶段还是 0 ⇒ 位置算成负数。
		##   **结论：在这一版引擎/布局下，这套"自算墨迹框"不稳**；字体已固化为项目自带 ⇒
		##   两端行盒一致，"行盒居中"的结果也就**两端一致**了，问题（对端偏下）已由字体修复解决。
		lb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	## 非 Label 兜底：按最小尺寸几何居中
	var need := lb.get_combined_minimum_size()
	if need.x < 1.0 or need.y < 1.0:
		need = badge.size
	lb.size = need
	lb.position = ((badge.size - need) * 0.5).floor()
