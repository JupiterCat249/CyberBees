"""SVG → Godot 场景（迭代039 正式版）

落实人明确的三条：
  ① SVG 内嵌 PNG ↔ 素材库素材：**像素比对确认后直接引用库素材**（已确认 4 个属性图标 md5 一致）
  ② 字体：设计稿 Source Han Sans CN → 使用同族开源字形 **Noto Sans SC**（SystemFont）
  ③ 文字用**文字节点**（Label），不再用字形多边形硬套
  ④ 用功能类似的节点：结构→Panel(StyleBoxFlat 圆角/描边)、图标/立绘→TextureRect、文字→Label

关键工程约束（踩坑记录）：
  · `.tscn` 里 `PackedVector2Array` 必须用**扁平数值**：`(x, y, x, y)`；写 `Vector2(x, y)` 列表会报
    `_parse_node_tag()` 且指向该行 → 极易误判为几何问题
"""
import io, os, sys, base64
sys.path.insert(0, "C:/Users/27194/AppData/Local/Temp")
from svg_to_godot import parse_svg, parse_color, col, flatten_path, decimate, merge_close, \
    has_degenerate_edge, is_self_intersecting, signed_area

OUT = "Godot版Games代码/电子蜂/scenes/ui_figma/figma_base_nodes.tscn"
LIB = "res://assets/static_ui/"
FONTS = 'PackedStringArray("Noto Sans SC", "Source Han Sans CN", "Microsoft YaHei")'


def num(v):
    s = "%.5f" % v
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s if s not in ("", "-") else "0"


def vs_flat(x, y):
    return "%s, %s" % (num(x), num(y))


# 文字区（坐标取自设计稿矢量实测；文案为设计稿占位文本）
#   字号由**区域高度**决定：单行 = 区高 × 0.78；多行 = 区高 / 行数 × 0.86
TEXT_BLOCKS = [
    (136, 69.9, 325.6, 115.2, "玩家名称", "single"),
    (1596, 69.9, 1785.6, 115.2, "玩家名称", "single"),
    (31.8, 581.3, 173.0, 615.2, "卡牌名称", "single"),
    (1632.2, 602.9, 1748.8, 640.6, "主按钮", "single"),
    (30.9, 629.8, 171.0, 721.9, "技能描述-行1\n技能描述-行2\n技能描述-行3", "multi"),
    (1494.7, 709.5, 1828.4, 770.0, "回合1--先手", "single"),
    (1491.2, 794.7, 1592.6, 827.8, "地图名", "single"),
    (1490.9, 842.8, 1679.0, 935.0, "场地效果描述-行1\n场地效果描述-行2\n场地效果描述-行3", "multi"),
]
ATTR_NUM = [(381.4, 789.9, 397.4, 814.5), (381.4, 849.9, 397.4, 874.5),
            (381.4, 909.9, 397.4, 934.5), (381.4, 969.9, 397.4, 994.5)]
# 库素材直引映射（已像素比对一致）
LIB_ICON = {"icon-攻击": "icon-攻击.png", "icon-血量": "icon-血量.png",
            "icon-速度": "icon-速度.png", "icon-射程": "icon-射程.png"}


class Scene:
    def __init__(self, name):
        self.name = name
        self.sub, self.ext, self.nodes = {}, {}, []

    def sid(self, key, lines):
        if key not in self.sub:
            self.sub[key] = ("R%d" % (len(self.sub) + 1), lines)
        return self.sub[key][0]

    def stylebox(self, bg, radius=0, border=0, bcol=None, center=True):
        key = ("sb", bg, radius, border, bcol, center)
        L = []
        if not center:
            L.append("draw_center = false")
        L.append("bg_color = %s" % col(bg))
        if radius > 0:
            r = int(round(radius))
            L += ["corner_radius_top_left = %d" % r, "corner_radius_top_right = %d" % r,
                  "corner_radius_bottom_right = %d" % r, "corner_radius_bottom_left = %d" % r]
        if border > 0 and bcol:
            b = max(1, int(round(border)))
            L += ["border_width_left = %d" % b, "border_width_top = %d" % b,
                  "border_width_right = %d" % b, "border_width_bottom = %d" % b,
                  "border_color = %s" % col(bcol)]
        return self.sid(key, L)

    def sysfont(self):
        return self.sid(("font", "sys"), ["font_names = " + FONTS])

    def ext_id(self, p):
        if p not in self.ext:
            self.ext[p] = "x%d" % (len(self.ext) + 1)
        return self.ext[p]

    def node(self, n, t, props):
        self.nodes.append((n, t, props))

    def write(self, path):
        lines = ["[gd_scene load_steps=%d format=3]" % (len(self.ext) + len(self.sub) + 1), ""]
        for p, i in self.ext.items():
            lines.append('[ext_resource type="Texture2D" path="%s" id="%s"]' % (p, i))
        if self.ext:
            lines.append("")
        for key, (sid, body) in self.sub.items():
            kind = "SystemFont" if key[0] == "font" else "StyleBoxFlat"
            lines.append('[sub_resource type="%s" id="%s"]' % (kind, sid))
            lines += body
            lines.append("")
        lines += ['[node name="%s" type="Control"]' % self.name,
                  "layout_mode = 3", "anchors_preset = 0",
                  "offset_right = 1920.0", "offset_bottom = 1080.0"]
        for n, t, pr in self.nodes:
            lines.append("")
            lines.append('[node name="%s" type="%s" parent="."]' % (n, t))
            for k, v in pr:
                lines.append("%s = %s" % (k, v))
        lines.append("")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))


def build():
    els, warns = parse_svg("Godot版Games代码/电子蜂/refs/figma_base.svg")
    sc = Scene("FigmaBaseNodes")
    k = {"rect": 0, "circle": 0, "poly": 0, "line": 0, "img": 0, "label": 0}

    for el in els:
        a = el.attrs
        f = parse_color(a.get("fill")); s = parse_color(a.get("stroke"))
        fc = f if (isinstance(f, tuple) and f[0] != "url") else None
        sc_c = s if (isinstance(s, tuple) and s[0] != "url") else None
        fop = float(a.get("fill-opacity", "1")); sop = float(a.get("stroke-opacity", "1"))
        sw = float(a.get("stroke-width", "0") or 0); al = el.alpha

        if el.kind == "rect":
            x = float(a.get("x", 0)) + el.dx; y = float(a.get("y", 0)) + el.dy
            w = float(a.get("width", 0)); h = float(a.get("height", 0))
            if w <= 0 or h <= 0:
                continue
            k["rect"] += 1
            sid = sc.stylebox(fc if fc else (0, 0, 0, 0), float(a.get("rx", 0) or 0),
                              sw if sc_c else 0, sc_c, center=bool(fc))
            props = [("offset_left", num(x)), ("offset_top", num(y)),
                     ("offset_right", num(x + w)), ("offset_bottom", num(y + h)),
                     ("mouse_filter", "2"),
                     ("theme_override_styles/panel", 'SubResource("%s")' % sid)]
            if fc and (fop < 1 or al < 1):
                props.append(("modulate", col((1, 1, 1), fop * al)))
            sc.node("Rect%d" % k["rect"], "Panel", props)
            continue

        if el.kind == "circle":
            cx = float(a.get("cx", 0)) + el.dx; cy = float(a.get("cy", 0)) + el.dy
            r = float(a.get("r", 0))
            if r <= 0:
                continue
            k["circle"] += 1
            if sw > 0 and sc_c:
                sid = sc.stylebox((0, 0, 0, 0), 0, sw, sc_c, center=False)
                sc.node("Circle%d" % k["circle"], "Panel",
                        [("offset_left", num(cx - r)), ("offset_top", num(cy - r)),
                         ("offset_right", num(cx + r)), ("offset_bottom", num(cy + r)),
                         ("mouse_filter", "2"),
                         ("theme_override_styles/panel", 'SubResource("%s")' % sid)])
            continue

        if el.kind == "path":
            dd = a.get("d", "")
            nsub = dd.count("M") + dd.count("m")
            rings = flatten_path(dd, 4 if nsub >= 6 else 10)
            rings = [(merge_close(decimate(p)), cl) for p, cl in rings]
            rings = [(p, cl) for p, cl in rings if len(p) >= 3]
            allv = [q for p, _ in rings for q in p]
            if not allv:
                continue
            bb = (min(q[0] for q in allv), min(q[1] for q in allv),
                  max(q[0] for q in allv), max(q[1] for q in allv))
            # 文字字形 → 交由 Label 承接（跳过）
            if fc and nsub >= 6 and 8 <= (bb[3] - bb[1]) <= 120:
                continue
            if fc:
                for pts, _cl in rings:
                    if abs(signed_area(pts)) <= 0.5 or has_degenerate_edge(pts, 0.05) \
                       or is_self_intersecting(pts):
                        continue
                    k["poly"] += 1
                    ox = min(q[0] for q in pts); oy = min(q[1] for q in pts)
                    sc.node("Poly%d" % k["poly"], "Polygon2D", [
                        ("position", "Vector2(%s, %s)" % (num(ox), num(oy))),
                        ("polygon", "PackedVector2Array(%s)" %
                         ", ".join(vs_flat(x - ox, y - oy) for x, y in pts)),
                        ("color", col(fc, fop * al))])
            elif sw > 0 and sc_c:
                for pts, cl in rings:
                    pl = pts + [pts[0]] if cl else pts
                    k["line"] += 1
                    sc.node("Line%d" % k["line"], "Line2D", [
                        ("points", "PackedVector2Array(%s)" % ", ".join(vs_flat(x, y) for x, y in pl)),
                        ("width", num(sw)), ("default_color", col(sc_c, sop * al)),
                        ("begin_cap_mode", "1"), ("end_cap_mode", "1"), ("joint_mode", "2")])
            continue

        if el.kind == "image":
            href = a.get("{http://www.w3.org/1999/xlink}href") or a.get("href") or ""
            if not href.startswith("data:image"):
                continue
            w = float(a.get("width", 0)); h = float(a.get("height", 0))
            raw = base64.b64decode(href.split(",", 1)[1])
            fname = "bimg-%dx%d.png" % (int(w), int(h))
            os.makedirs("Godot版Games代码/电子蜂/assets/static_ui", exist_ok=True)
            open(os.path.join("Godot版Games代码/电子蜂/assets/static_ui", fname), "wb").write(raw)
            k["img"] += 1
            eid = sc.ext_id(LIB + fname)
            sc.node("Image%d" % k["img"], "TextureRect", [
                ("offset_left", num(el.dx)), ("offset_top", num(el.dy)),
                ("offset_right", num(el.dx + w)), ("offset_bottom", num(el.dy + h)),
                ("mouse_filter", "2"), ("expand_mode", "1"), ("stretch_mode", "0"),
                ("texture", 'ExtResource("%s")' % eid)])
            continue

    # ---- 文字节点（Label）----
    font = sc.sysfont()
    for i, (x0, y0, x1, y1, text, mode) in enumerate(TEXT_BLOCKS):
        nl = len(text.split("\n"))
        fs = int((y1 - y0) * 0.78) if mode == "single" else int((y1 - y0) / nl * 0.86)
        k["label"] += 1
        sc.node("Text%02d" % (i + 1), "Label", [
            ("offset_left", num(x0)), ("offset_top", num(y0 - 2)),
            ("offset_right", num(x1 + 30)), ("offset_bottom", num(y1 + 6)),
            ("mouse_filter", "2"),
            ("theme_override_fonts/font", 'SubResource("%s")' % font),
            ("theme_override_font_sizes/font_size", str(fs)),
            ("theme_override_colors/font_color", col((1, 1, 1), 1.0)),
            ("text", '"%s"' % text.replace("\n", "\\n"))])
    for i, (x0, y0, x1, y1) in enumerate(ATTR_NUM):
        k["label"] += 1
        sc.node("AttrNum%d" % (i + 1), "Label", [
            ("offset_left", num(x0 - 4)), ("offset_top", num(y0 - 3)),
            ("offset_right", num(x0 + 40)), ("offset_bottom", num(y1 + 6)),
            ("mouse_filter", "2"),
            ("theme_override_fonts/font", 'SubResource("%s")' % font),
            ("theme_override_font_sizes/font_size", str(int((y1 - y0) * 1.2))),
            ("theme_override_colors/font_color", col((1, 1, 1), 1.0)),
            ("text", '"0"')])
    sc.write(OUT)
    return k


if __name__ == "__main__":
    print("节点统计:", build())
