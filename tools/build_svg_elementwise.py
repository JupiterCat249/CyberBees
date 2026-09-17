"""战斗 UI —— 依 SVG 原文**逐元素**映射到 Godot 节点（迭代042）

方法论（人明确）：**根本依据是 SVG 素材**；
  · 不"生搬硬套"（不是几何直译）
  · 也不"置之不理"（不是另起一套凭空设计）
  → 逐元素查 Godot 文档选**最合适的节点/组件**，用**像素与画面表现**判断效果。

本文件按 `refs/figma_base.svg` 的**元素出现顺序**逐条实现，每条给出：
  SVG 元素 → 选定节点 → 选择理由（查证来源：E:\\GodotDocx 手册 / 引擎内置文档）
"""
import io, os, sys
sys.path.insert(0, "C:/Users/27194/AppData/Local/Temp")
from svg_to_godot import parse_svg, parse_color

OUT = "Godot版Games代码/电子蜂/scenes/ui/battle_ui.tscn"
FONTS = 'PackedStringArray("Noto Sans SC", "Source Han Sans CN", "Microsoft YaHei")'
BR = "res://assets/static_ui/"

# SVG 里用到的 4 个属性图标（内嵌 PNG，已与素材库 md5 比对一致）
ICON_TEX = ["%sbase-image1-40x40.png" % BR, "%sbase-image2-40x40.png" % BR,
            "%sbase-image3-40x40.png" % BR, "%sbase-image4-40x40.png" % BR]


def col(c):
    if isinstance(c, str):
        h = c.lstrip("#")
        r, g, b = int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0
        a = int(h[6:8], 16) / 255.0 if len(h) >= 8 else 1.0
        return "Color(%.6f, %.6f, %.6f, %.6f)" % (r, g, b, a)
    r, g, b = c[0], c[1], c[2]
    a = c[3] if len(c) > 3 else 1.0
    return "Color(%.6f, %.6f, %.6f, %.6f)" % (r, g, b, a)


def n(v):
    s = "%.2f" % v
    return s.rstrip("0").rstrip(".") if "." in s else s


class Scn:
    def __init__(self, name):
        self.name, self.subs, self.exts, self.nodes = name, [], {}, []

    def _sid(self, tag, body):
        for t, b, sid in self.subs:
            if (t, b) == (tag, tuple(body)):
                return sid
        sid = "R%d" % (len(self.subs) + 1)
        self.subs.append((tag, body, sid))
        return sid

    def sb(self, bg, radius=0, bw=0, bc=None, center=True, aa=True):
        body = []
        if not center:
            body.append("draw_center = false")
        body.append("bg_color = %s" % col(bg))
        if radius:
            r = int(round(radius))
            body += ["corner_radius_top_left = %d" % r, "corner_radius_top_right = %d" % r,
                     "corner_radius_bottom_right = %d" % r, "corner_radius_bottom_left = %d" % r]
        if bw and bc:
            b = max(1, int(round(bw)))
            body += ["border_width_left = %d" % b, "border_width_top = %d" % b,
                     "border_width_right = %d" % b, "border_width_bottom = %d" % b,
                     "border_color = %s" % col(bc)]
        if not aa:
            body.append("anti_aliasing = false")
        return self._sid("StyleBoxFlat", body)

    def font(self):
        return self._sid("SystemFont", ["font_names = " + FONTS])

    def ext(self, p):
        if p not in self.exts:
            self.exts[p] = "x%d" % (len(self.exts) + 1)
        return self.exts[p]

    def panel(self, nm, par, x, y, w, h, bg, radius=0, bw=0, bc=None, center=True, mouse=2):
        sid = self.sb(bg, radius, bw, bc, center)
        self.nodes.append((nm, "Panel", par, [
            ("offset_left", n(x)), ("offset_top", n(y)),
            ("offset_right", n(x + w)), ("offset_bottom", n(y + h)),
            ("mouse_filter", str(mouse)),
            ("theme_override_styles/panel", 'SubResource("%s")' % sid)]))

    def tex(self, nm, par, x, y, w, h, path, stretch=0, tile=False, color=None):
        eid = self.ext(path)
        pr = [("offset_left", n(x)), ("offset_top", n(y)),
              ("offset_right", n(x + w)), ("offset_bottom", n(y + h)),
              ("mouse_filter", "2"), ("texture", 'ExtResource("%s")' % eid),
              ("expand_mode", "1"), ("stretch_mode", str(stretch))]
        if tile:
            pr.append(("texture_repeat", "1"))
        if color:
            pr.append(("modulate", col(color)))
        self.nodes.append((nm, "TextureRect", par, pr))

    def label(self, nm, par, x, y, w, h, text, fs, color, align="left"):
        self.nodes.append((nm, "Label", par, [
            ("offset_left", n(x)), ("offset_top", n(y)),
            ("offset_right", n(x + w)), ("offset_bottom", n(y + h)),
            ("mouse_filter", "2"),
            ("theme_override_fonts/font", 'SubResource("%s")' % self.font()),
            ("theme_override_font_sizes/font_size", str(int(round(fs)))),
            ("theme_override_colors/font_color", col(color)),
            ("horizontal_alignment", {"left": "0", "center": "1", "right": "2"}[align]),
            ("vertical_alignment", "1"),
            ("text", '"%s"' % text)]))

    def poly(self, nm, par, pts, color):
        self.nodes.append((nm, "Polygon2D", par, [
            ("polygon", "PackedVector2Array(%s)" % ", ".join("%s, %s" % (n(a), n(b)) for a, b in pts)),
            ("color", col(color))]))

    def line(self, nm, par, pts, width, color, closed=False):
        p = pts + [pts[0]] if closed else pts
        self.nodes.append((nm, "Line2D", par, [
            ("points", "PackedVector2Array(%s)" % ", ".join("%s, %s" % (n(a), n(b)) for a, b in p)),
            ("width", n(width)), ("default_color", col(color)),
            ("joint_mode", "2"), ("antialiased", "true")]))

    def write(self, path):
        L = ["[gd_scene load_steps=%d format=3]" % (len(self.exts) + len(self.subs) + 1), ""]
        for p, i in self.exts.items():
            L.append('[ext_resource type="Texture2D" path="%s" id="%s"]' % (p, i))
        if self.exts:
            L.append("")
        for tag, body, sid in self.subs:
            L.append('[sub_resource type="%s" id="%s"]' % (tag, sid))
            L += body
            L.append("")
        L += ['[node name="%s" type="Control"]' % self.name, "layout_mode = 3",
              "anchors_preset = 0", "offset_right = 1920.0", "offset_bottom = 1080.0"]
        for nm, ty, par, pr in self.nodes:
            L.append("")
            L.append('[node name="%s" type="%s" parent="%s"]' % (nm, ty, par))
            for k, v in pr:
                L.append("%s = %s" % (k, v))
        L.append("")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(L))
        return len(self.nodes)


# ============================================================
# 逐元素实现（顺序 = SVG 中元素出现顺序）
# ============================================================
def build():
    s = Scn("BattleUI")
    # ① <rect 0,0 1920x1080 #666666>            → Panel(StyleBoxFlat 纯色)
    s.panel("Background", ".", 0, 0, 1920, 1080, "#666666", 0)
    s.nodes.append(("Battle", "Control", ".", [("mouse_filter", "2")]))

    # ② <rect 459,40 1000x1000 #999999 rx=10>    → Panel(圆角 10)
    s.panel("BoardPlate", "Battle", 459, 40, 1000, 1000, "#999999", 10)
    # ③ 同尺寸无圆角 #999999（SVG 里用于裁切图案）→ 已被 ② 覆盖，跳过
    # ④ <rect ... fill=url(pattern0) fill-opacity=0.1>  → TextureRect(平铺, modulate α=0.1)
    #    pattern0 = 十字纹理 2000×2000（SVG 内嵌 image0）
    s.tex("BoardCrossPattern", "Battle", 459, 40, 1000, 1000, BR + "base-image0-2000x2000.png",
          stretch=1, tile=True, color="#FFFFFF1A")
    # ⑤ <rect 457,38 1004x1004 rx=12 stroke=white sw=4>  → Panel(仅描边, StyleBoxFlat 原生支持)
    s.panel("BoardFrame", "Battle", 457, 38, 1004, 1004, "#00000000", 12, 4, "#FFFFFF80", center=False)
    # ⑥ <rect 1490,150 400x400 black 0.2 rx=10>  → Panel(手牌区底)
    s.panel("HandPanelRight", "Battle", 1490, 150, 400, 400, "#00000033", 10)
    # ⑦ <rect 1490,570 400x100 #999999 rx=10>    → **Button**（这是主操作，需可交互）
    s.nodes.append(("MainButton", "Button", "Battle", [
        ("offset_left", "1490"), ("offset_top", "570"), ("offset_right", "1890"),
        ("offset_bottom", "670"), ("mouse_default_cursor_shape", "2"),
        ("theme_override_fonts/font", 'SubResource("%s")' % s.font()),
        ("theme_override_font_sizes/font_size", "34"),
        ("theme_override_colors/font_color", col("#FFFFFF")),
        ("theme_override_styles/normal", 'SubResource("%s")' % s.sb("#999999", 10)),
        ("theme_override_styles/hover", 'SubResource("%s")' % s.sb("#8A8A8A", 10)),
        ("theme_override_styles/pressed", 'SubResource("%s")' % s.sb("#7D7D7D", 10)),
        ("text", '"主按钮"')]))
    # ⑧ <rect 1492,572 396x96 rx=8 stroke=white sw=4>  → Panel(仅描边)
    s.panel("MainButtonInnerLine", "Battle", 1492, 572, 396, 96, "#00000000", 8, 4, "#FFFFFF1A", center=False)
    # ⑨ <rect 1752,570 138x100 black 0.2>        → Panel(右段)
    s.panel("MainButtonSeg", "Battle", 1752, 570, 138, 100, "#00000033", 0)
    # ⑩⑫⑭⑯ <rect 80x80 white 0.5 rx=10>（×4）   → Panel + Button（可交互功能键）
    for i, x in enumerate((1540, 1630, 1720, 1810)):
        nm = ["Settings", "Emote", "Info", "Back"][i]
        s.nodes.append((nm, "Button", "Battle", [
            ("offset_left", str(x)), ("offset_top", "960"),
            ("offset_right", str(x + 80)), ("offset_bottom", "1040"),
            ("mouse_default_cursor_shape", "2"),
            ("theme_override_styles/normal", 'SubResource("%s")' % s.sb("#FFFFFF80", 10)),
            ("theme_override_styles/hover", 'SubResource("%s")' % s.sb("#FFFFFFB3", 10)),
            ("theme_override_styles/pressed", 'SubResource("%s")' % s.sb("#FFFFFFCC", 10))]))
        # ⑪⑬⑮⑰ 内描边 76x76 rx=8 white 0.1
        s.panel(nm + "InnerLine", "Battle", x + 2, 962, 76, 76, "#00000000", 8, 4, "#FFFFFF1A", center=False)
    # ⑱ <rect 30,740 300x300 #333333 rx=10>      → Panel(详情块)
    s.panel("DetailBlock", "Battle", 30, 740, 300, 300, "#333333", 10)
    # ⑲ <rect 32,742 296x296 rx=8 stroke=black sw=4> → Panel(仅描边)
    s.panel("DetailBlockLine", "Battle", 32, 742, 296, 296, "#00000000", 8, 4, "#000000", center=False)
    # ⑳㉑㉒㉓ <rect 340,y 40x40 fill=url(patternN)>  → TextureRect（4 个属性图标，PNG 素材）
    for i, y in enumerate((780, 840, 900, 960)):
        s.tex("AttrIcon%d" % (i + 1), "Battle", 340, y, 40, 40, ICON_TEX[i])
    # ㉔ <rect 30,150 400x400 black 0.2 rx=10>    → Panel(左手牌区底)
    s.panel("HandPanelLeft", "Battle", 30, 150, 400, 400, "#00000033", 10)

    # ---- 白色文字路径（SVG 中为字形 path；语义上就是**文字** → Label，设字体）----
    s.label("TextCardName", "Battle", 31.8, 574, 200, 46, "卡牌名称", 44, "#FFFFFF")
    s.label("TextSkillDesc", "Battle", 30.9, 626, 260, 100,
            "技能描述-行1\n技能描述-行2\n技能描述-行3", 28, "#FFFFFF")
    for i, y in enumerate((789.9, 849.9, 909.9, 969.9)):
        s.label("AttrValue%d" % (i + 1), "Battle", 381.4, y - 5, 40, 35, "0", 30, "#FFFFFF")
    # 玩家名（左右）+ 徽章数字 + 右侧信息（这些在底座稿中为字形/占位，语义 = 文字）
    s.label("TextPlayerLeft", "Battle", 136, 66, 220, 48, "玩家名称", 44, "#FFFFFF")
    s.label("TextPlayerRight", "Battle", 1596, 66, 220, 48, "玩家名称", 44, "#FFFFFF")
    s.label("TextTurnInfo", "Battle", 1494.7, 706, 360, 62, "回合1--先手", 48, "#FFFFFF")
    s.label("TextMapName", "Battle", 1491.2, 790, 140, 40, "地图名", 32, "#FFFFFF")
    s.label("TextSiteEffect", "Battle", 1490.9, 840, 220, 100,
            "场地效果描述-行1\n场地效果描述-行2\n场地效果描述-行3", 24, "#FFFFFF")
    s.label("MainButtonLabel", "Battle", 1492, 572, 396, 96, "主按钮", 34, "#FFFFFF", "center")

    # ---- 费用徽章：SVG 为 <path> 尖顶六边形 + 黑色描边 + 白数字块 ----
    #     六边形是**固定形状的徽章**→ Polygon2D(填充) + Line2D(描边) 最贴切
    for side, cx in (("Left", 81.08), ("Right", 1539.88)):
        r = 49.3
        hw = r * 0.8660254
        pts = [(cx, 90 - r), (cx + hw, 90 - r * 0.5), (cx + hw, 90 + r * 0.5),
               (cx, 90 + r), (cx - hw, 90 + r * 0.5), (cx - hw, 90 - r * 0.5)]
        s.poly("CostBadge%s" % side, "Battle", pts, "#FFA300")
        s.line("CostBadge%sLine" % side, "Battle", pts, 4.0, "#00000080", closed=True)
        # 白数字块 37×54（SVG rect）
        x = 61 if side == "Left" else 1521
        s.panel("CostBadge%sNumber" % side, "Battle", x, 63, 37, 54, "#FFFFFF", 0)
        s.label("CostBadge%sValue" % side, "Battle", x, 63, 37, 54, "0", 34, "#111111", "center")
    return s


if __name__ == "__main__":
    sc = build()
    print("节点数:", sc.write(OUT))
