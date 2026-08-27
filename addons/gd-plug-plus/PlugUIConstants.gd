class_name PlugUIConstants

# ===========================================================================
# 1. Theme Colors
# 用于 Tree 行文本着色，表示各种状态。改变颜色会影响整体视觉风格。
# ===========================================================================

const COLOR_UNKNOWN = Color(0.6, 0.6, 0.6)  ## 未知状态 — 灰色
const COLOR_CHECKING = Color(0.9, 0.8, 0.2)  ## 正在检查 / 待确认变更 — 黄色
const COLOR_UP_TO_DATE = Color(0.3, 0.85, 0.4)  ## 已是最新 — 绿色
const COLOR_BEHIND = Color(0.95, 0.3, 0.3)  ## 有新版本可更新 / 错误 — 红色
const COLOR_UPDATING = Color(0.9, 0.7, 0.1)  ## 正在更新中 — 橙黄
const COLOR_UPDATED = Color(0.4, 0.7, 1.0)  ## 已更新 / 当前分支 — 蓝色
const COLOR_ACTION = Color(0.82, 0.82, 0.82)  ## 可点击操作文本 — 浅灰
const COLOR_COMMIT = Color(0.9, 0.5, 0.5)  ## commit hash 显示色
const COLOR_URL = Color(0.65, 0.65, 0.65)  ## URL / 描述文本 — 暗灰
const COLOR_CONFLICT = Color(0.95, 0.3, 0.3)  ## 目录冲突警告 — 红色(同 BEHIND)

# ===========================================================================
# 2. Installed Tree 列布局
# 10 列: Name, Description, Version, Branch/Tag, Commit, UpdateTime,
#         Actions, Lock, Update, Uninstall
# 值越大该列越宽；expand=true 的列会自动填充剩余空间。
# ===========================================================================

const INSTALLED_COL_WIDTHS: Array[int] = [40, 100, 70, 100, 80, 190, 50, 50, 60, 50]
const INSTALLED_COL_EXPAND: Array[bool] = [
	true, true, false, false, false, false, false, false, false, false
]

# ===========================================================================
# 3. Search Tree 列布局
# 9 列: Checkbox, Status, Name, Version, Type, Branch/Tag, Commit,
#        RepoPath, Author
# ===========================================================================

const SEARCH_COL_WIDTHS: Array[int] = [36, 100, 110, 70, 85, 120, 100, 110, 50]
const SEARCH_COL_EXPAND: Array[bool] = [false, false, true, false, false, false, false, true, true]

## 搜索结果 Tree 控件的最小高度(px)。值越大，搜索区域在面板中占比越大。
const SEARCH_TREE_MIN_HEIGHT = 150

# ===========================================================================
# 4. Console 控制台面板
# 位于主界面底部，可折叠展开。
# ===========================================================================

## 折叠时控制台标题栏高度(px)。影响底部常驻占用空间。
const CONSOLE_HEADER_HEIGHT = 28

## 展开时控制台总高度(px)。值越大日志可视区域越大，主内容区越小。
const CONSOLE_EXPANDED_HEIGHT = 180

## 控制台日志字体大小(px)。
const CONSOLE_FONT_SIZE = 12

# ===========================================================================
# 5. Dialog 对话框尺寸
# 各弹窗的默认/最小尺寸。值越大弹窗越大，内容越不容易被截断。
# ===========================================================================

## 分支/标签选择弹窗尺寸
const BRANCH_POPUP_SIZE = Vector2i(360, 400)

## 提交记录选择弹窗尺寸，宽度需容纳 hash + message 两列
const COMMIT_POPUP_SIZE = Vector2i(520, 450)

## 提交弹窗中 hash 列的固定宽度(px)
const COMMIT_POPUP_HASH_COL_WIDTH = 100

## 详情弹窗最小宽度(px)
const DETAIL_DIALOG_MIN_WIDTH = 480

## 详情弹窗中值文本最小宽度(px)，影响长文本的换行位置
const DETAIL_LABEL_MIN_WIDTH = 300

## 提示/错误消息弹窗最小宽度(px)
const TOAST_MIN_WIDTH = 360

## SelectorPopup 的默认尺寸
const SELECTOR_DEFAULT_SIZE = Vector2i(360, 400)

# ===========================================================================
# 6. Spacing 间距与边距
# 控制 UI 元素之间的留白。值越大空间感越强，但可用面积越小。
# ===========================================================================

## 标准外边距(px) — 面板、搜索栏等内缩进
const MARGIN_STANDARD = 8

## 紧凑外边距(px) — 搜索栏顶部/底部
const MARGIN_COMPACT = 4

## 标准子控件间距(px) — 按钮之间、图标与文字之间
const SEPARATION_STANDARD = 8

## 较大间距(px) — 弹窗内容分组之间、overlay VBox
const SEPARATION_LARGE = 12

## 紧凑间距(px) — SelectorPopup 内部 VBox
const SEPARATION_COMPACT = 4

## 详情对话框网格水平间距(px) — key:value 之间的横向间隔
const DETAIL_H_SEPARATION = 16

## 详情对话框网格垂直间距(px) — 行与行之间的纵向间隔
const DETAIL_V_SEPARATION = 8

# ===========================================================================
# 7. Misc UI 杂项 UI 元素
# ===========================================================================

## 搜索栏中搜索按钮与安装按钮之间的间隔宽度(px)
const SEARCH_BAR_SPACER_WIDTH = 40

## 加载动画图标尺寸(px, 宽=高)。值越大动画越醒目。
const SPINNER_SIZE = 20

## SelectorPopup 中 Tree 控件的最小高度(px)
const SELECTOR_TREE_MIN_HEIGHT = 280

# ===========================================================================
# 8. Animation 动画参数
# ===========================================================================

## 加载 spinner 旋转速度，乘以 TAU 得到弧度/秒。值越大转越快。
const SPINNER_SPEED = 0.8

# ===========================================================================
# 9. Git 参数
# ===========================================================================

## commit hash 截取显示长度，标准 Git 短 hash 为 7 位
const SHORT_COMMIT_LENGTH = 7

## 拉取提交记录最大条数。值越大能选择的历史越深，但加载越慢。
const COMMIT_LOG_LIMIT = 50

## git fetch --deepen 的深度
const FETCH_DEEPEN_COUNT = 50
