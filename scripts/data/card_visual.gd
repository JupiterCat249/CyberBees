class_name CardVisual
extends Resource
## 卡面视觉数据（与规则解耦：同一张卡换皮不改规则）
## D-4：手牌用「立绘 + 定向裁剪」做头像 → 裁剪参数在此声明

enum FactionSide { ALLY, ENEMY }
enum CardTypeColor { QUEEN, SOLDIER, BUILDING, COMMAND }

@export var artwork: Texture2D                                  ## 立绘 / 插画 / 图标
@export var type_color: CardTypeColor = CardTypeColor.SOLDIER           ## 蜂王/建筑/兵蜂/指令
@export var faction_side: FactionSide = FactionSide.ALLY                      ## 侧边栏阵营色来源

@export_group("定向裁剪（手牌头像）")
## 手牌用立绘裁出头像：Image 在裁剪窗内的相对位置重定向。
## 定义：Image 左上角相对「裁剪窗口」的偏移量（像素）。
##   offset = (0, 0)  → 立绘左上角对齐窗口左上角（默认，看立绘的"头"通常已够）
##   y 越负 → 立绘越往上 → 窗口里越看到立绘的下半部分
##   y 越正 → 立绘越往下 → 窗口里越看到立绘的上半部分（头部）
@export var crop_offset: Vector2 = Vector2.ZERO
@export var crop_scale: float = 1.0                             ## 立绘缩放（0 = 不覆盖，用场景默认）


func validate() -> Array[String]:
	var errs: Array[String] = []
	if crop_scale < 0.0:
		errs.append("CardVisual crop_scale 为负")
	return errs
