# 字体包体（UI 用）

> 最后更新：2026-09-17
> 用途：电子蜂 UI 界面字体（战斗 UI、卡牌、地图单位等）

## 一、设计规范 → 实际字体 对应关系

| 设计规范（`电子蜂对战空间_静态UI说明.md` §1.1） | 本包体提供的字体 | 说明 |
|---|---|---|
| 字体族 **Source Han Sans CN** | **Noto Sans SC** | 二者**同源**：Source Han Sans 由 Adobe 主导、Noto Sans CJK 由 Google 发行，**共享同一套字形设计与同一份 OFL 授权**（本包字体元数据里版权仍写 `Copyright 2014-2021 Adobe … Reserved Font Name 'Source'`） |
| 细体统一 **Medium** | `NotoSansSC-Medium.ttf`（wght=500） | 静态实例 |
| 粗体统一 **Bold** | `NotoSansSC-Bold.ttf`（wght=700） | 静态实例 |
| —（备用） | `NotoSansSC-VF.ttf`（可变字体 wght 100~900） | 需要极端字重或二次调级时使用 |

⚠️ 若你手上有**原版 Source Han Sans CN**（Adobe 官方发行），可直接替换本包体，二者字形一致、可无缝换用。

## 二、文件清单

| 文件 | 大小 | 字重 | Godot 中 `font_weight` | 用途 |
|---|---:|---|---|---|
| `NotoSansSC-Medium.ttf` | 10.1 MB | 500 | 500 | 正文、说明文字 |
| `NotoSansSC-Bold.ttf` | 10.1 MB | 700 | 700 | 标题、玩家名、按钮等强调文字 |
| `NotoSansSC-VF.ttf` | 16.9 MB | 100–900 可变 | 任意 | 备用/调级 |
| `OFL.txt` | 4.4 KB | — | — | SIL Open Font License 1.1 正文（**随包分发必附**） |

字形覆盖：**30890 字形**（其中 CJK 20976），设计稿用到的字符全部齐备。

## 三、Godot 中使用

### 方式 A：直接引用字体文件（推荐，随项目走）
```gdscript
var bold: FontFile = load("res://assets/fonts/NotoSansSC-Bold.ttf")
label.add_theme_font_override("font", bold)
label.add_theme_font_size_override("font_size", 51)
```

### 方式 B：用可变字体指定字重（只带一个文件）
```gdscript
var vf: FontFile = load("res://assets/fonts/NotoSansSC-VF.ttf")
var fv := FontVariation.new()
fv.base_font = vf
fv.variation_opentype = {"wght": 700}      # 500 = Medium，700 = Bold
label.add_theme_font_override("font", fv)
```

### 方式 C：系统字体（**不打包字体**，依赖运行环境已安装）
```gdscript
var sf := SystemFont.new()
sf.font_names = PackedStringArray(["Noto Sans SC", "Source Han Sans CN", "Microsoft YaHei"])
sf.font_weight = 700
label.add_theme_font_override("font", sf)
```
> 当前 `scenes/ui/battle_ui.tscn` 用的是**方式 C**（`SystemFont`）。
> 如需**脱离系统字体**稳定渲染，请改用 A 或 B 并把字体加入项目导出资源。

### 字号参考（设计稿实测换算）
设计稿的 SVG 文字是**字形路径**，实测字高后按 **汉字 ≈ 0.925×字号、数字 ≈ 0.750×字号** 换算：

| 文本 | 设计字高 | 字号 |
|---|---:|---:|
| 玩家名称 | 47 | 51 |
| 主按钮 | 39 | 42 |
| 卡牌名称 | 35 | 38 |
| 地图名 | 34 | 37 |
| 回合1--先手 | 30 | 32 |
| 属性数值 0 | 25 | 27 |
| 场地效果描述 | 24/行 | 26 |
| 技能描述 | 23/行 | 25 |
| 费用徽章 0 | 49 | 65 |

（量测工具：`tools/font_metrics.tscn`；对照演示：`tools/font_demo.tscn`）

## 四、授权（SIL OFL 1.1）
- 本字体以 **SIL Open Font License 1.1** 发布，**允许**：自由使用、修改、**再分发（含商用与嵌入应用）**
- **要求**：① 再分发时必须随附 `OFL.txt`；② 不得单独售卖字体本身；③ 若修改字体，**不得继续使用保留字体名 `Source` / `Noto`**
- 本包体为**未修改**的官方字形（仅做字重实例化与命名整理），随附 `OFL.txt` 即满足授权要求
- 版权：`Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'`

## 五、打包分发
```bash
zip -j 电子蜂-字体包体-v1.zip NotoSansSC-Medium.ttf NotoSansSC-Bold.ttf NotoSansSC-VF.ttf OFL.txt README.md
```
（`.import` 是 Godot 的导入元数据，**分发时无需包含**）
