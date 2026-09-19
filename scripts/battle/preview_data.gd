class_name PreviewData
extends Resource
## 操作预览数据（**供 UI 调用的资源类**）
##
## 设计定位（迭代056 · 人指示「这些东西也做成资源-供UI调用的资源类」）
##   · 预览结果是**纯数据资源**：视图只读它、不自己算规则
##   · 由规则层 `RulesPreview.build()` 计算并填充；经 `BattleSignalBus.preview_ready` 广播
##   · 视图拿到后**直接渲染**：按 `kind` 取对应样式、遍历 `cells` 画格
##
## 与卡牌资源的关系：卡牌是"静态资源"（存在 game_data/*.tres），
## 预览是"运行态资源"（每步操作后重算），两者都实现 Resource，
## 视图对二者的处理方式一致（读字段 → 渲染）。

## 预览类型 —— **枚举定义在 PreviewKind**（独立命名空间，避免与 BattleState.Phase 值域撞车）
## ⚠️ 本类是 Resource，不应承载会被 Phase 混淆的枚举；统一引用 `PreviewKind.XXX`
const K := preload("res://scripts/battle/preview_kind.gd")

## 一组预览区域：同一种高亮样式下的若干格
class PreviewCell:
	var cell: Vector2i
	var kind: int = 0
	## 可选的额外语义（视图可选用）：如"该格是主目标"
	var primary: bool = false

	func _init(p_cell: Vector2i = Vector2i.ZERO, p_kind: int = 0,
			p_primary: bool = false) -> void:
		cell = p_cell
		kind = p_kind
		primary = p_primary


## ============ 资源字段（视图读这些） ============

@export var kind: int = 0
## 主区域：`[{cell: Vector2i, kind: int（PreviewKind.Kind）, primary: bool}]`
@export var cells: Array = []
## 受影响单位（如攻击目标、被治疗单位）—— 视图可直接取对象
@export var units: Array = []
## 文案（可选，视图显示在提示区）
@export var caption: String = ""
## 预览是否为空（视图可据此跳过渲染）
@export var empty: bool = true


## ============ 便捷构造 ============

## ⚠️ 返回值不写 `-> PreviewData`：新 class_name 注册前自引用会报 Identifier not found
static func make(p_kind: int, p_caption: String = ""):
	var d = load("res://scripts/battle/preview_data.gd").new()
	d.kind = p_kind
	d.caption = p_caption
	return d


func add_cell(cell: Vector2i, cell_kind: int = -1, primary: bool = false) -> void:
	var k: int = kind if cell_kind < 0 else cell_kind
	cells.append(PreviewCell.new(cell, k, primary))
	empty = false


## 加一个受影响单位
## ⚠️ `cell_kind` 必须显式给出（迭代056 实测缺陷）：
##    原实现用**顶层 kind** 给单位格打标 → 单位预览（kind=MOVE）会把**攻击目标**的格
##    也标成 MOVE，于是"被阻挡的格"又冒出来，视图会画出错的移动范围。
##    现在：单位格用调用方声明的类型（攻击目标→ATTACK，支援目标→SUPPORT）。
func add_unit(inst: UnitInstance, cell_kind: int = -1) -> void:
	if inst == null:
		return
	units.append(inst)
	empty = false
	var k: int = kind if cell_kind < 0 else cell_kind
	add_cell(inst.cell, k, true)


## 取某类格的坐标列表（视图渲染用）
func cells_of(cell_kind: int) -> Array:
	var out: Array = []
	for c in cells:
		if c.kind == cell_kind:
			out.append(c.cell)
	return out


## 是否包含某格（视图判重 / 单测用）
func has_cell(cell: Vector2i) -> bool:
	for c in cells:
		if c.cell == cell:
			return true
	return false


## 按类型分组（视图可一次拿到"移动格们 / 攻击格们"）
func grouped() -> Dictionary:
	var g := {}
	for c in cells:
		if not g.has(c.kind):
			g[c.kind] = []
		g[c.kind].append(c.cell)
	return g


func describe() -> String:
	return "PreviewData(kind=%d, cells=%d, units=%d, %s)" % [
		kind, cells.size(), units.size(), caption]
