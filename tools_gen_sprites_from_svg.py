"""SVD → Godot 场景（迭代040：图标/数字用 2D 精灵 + 文字用文字节点）

人明确：
  · 部分节点（费用数字、图标等）**替换为 2D 精灵**，用已有素材或 **SVG 原始文件中提取的素材**渲染
  · **文字依旧使用文字节点**（并为其设置字体）

节点选择原则（"功能类似的节点"）：
  矩形/圆角/描边 → Panel + StyleBoxFlat
  **图标 / 费用数字 / 小图形 → Sprite2D（SVG 路径栅格化的 PNG）**
  立绘等嵌入 PNG → TextureRect
  **文字 → Label（文字节点，SystemFont 指定字体）**
"""
import io, os, sys, base64
sys.path.insert(0, "C:/Users/27194/AppData/Local/Temp")
from svg_to_godot import parse_svg, parse_color, col, flatten_path, decimate, merge_close, \
    has_degenerate_edge, is_self_intersecting, signed_area
from svg_raster import raster_rings, raster_stroke, save

OUT = "Godot版Games代码/电子蜂/scenes/ui_figma/figma_base_nodes.tscn"
TEX_DIR = "Godot版Games代码/电子蜂/assets/ui_figma"
TEX_RES = "res://assets/ui_figma/"
FONTS = 'PackedStringArray("Noto Sans SC", "Source Han Sans CN", "Microsoft YaHei")'

# 文字块（真文字 → Label）；坐标为设计稿矢量实测
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


def num(v):
    s = "%.5f" % v
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s if s not in ("", "-") else "0"


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
    k = {"rect": 0, "sprite": 0, "tex": 0, "label": 0}

    for idx, el in enumerate(els):
        a = el.attrs
        f = parse_color(a.get("fill")); s = parse_color(a.get("stroke"))
        fc = f if (isinstance(f, tuple) and f[0] != "url") else None
        stroke_c = s if (isinstance(s, tuple) and s[0] != "url") else None
        fop = float(a.get("fill-opacity", "1")); sop = float(a.get("stroke-opacity", "1"))
        sw = float(a.get("stroke-width", "0") or 0); al = el.alpha

        if el.kind == "rect":
            x = float(a.get("x", 0)) + el.dx; y = float(a.get("y", 0)) + el.dy
            w = float(a.get("width", 0)); h = float(a.get("height", 0))
            if w <= 0 or h <= 0:
                continue
            k["rect"] += 1
            sid = sc.stylebox(fc if fc else (0, 0, 0, 0), float(a.get("rx", 0) or 0),
                              sw if stroke_c else 0, stroke_c, center=bool(fc))
            props = [("offset_left", num(x)), ("offset_top", num(y)),
                     ("offset_right", num(x + w)), ("offset_bottom", num(y + h)),
                     ("mouse_filter", "2"),
                     ("theme_override_styles/panel", 'SubResource("%s")' % sid)]
            if fc and (fop < 1 or al < 1):
                props.append(("modulate", col((1, 1, 1), fop * al)))
            sc.node("Rect%d" % k["rect"], "Panel", props)
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
            hh = bb[3] - bb[1]
            # 真文字（子路径多） → 交给 Label，跳过
            if fc and nsub >= 6:
                continue
            # ---- 图标 / 数字：栅格化为 PNG → Sprite2D ----
            if fc:
                clean = [(p, cl) for p, cl in rings
                         if abs(signed_area(p)) > 0.5 and not has_degenerate_edge(p, 0.05)
                         and not is_self_intersecting(p)]
                if not clean:
                    continue
                colr = (fc[0], fc[1], fc[2], fc[3] * fop * al)
                img, box = raster_rings(clean, colr, scale=4)
                name = "icon_%02d.png" % (k["sprite"] + 1)
                save(img, os.path.join(TEX_DIR, name))
                eid = sc.ext_id(TEX_RES + name)
                k["sprite"] += 1
                sc.node("Icon%02d" % k["sprite"], "Sprite2D", [
                    ("position", "Vector2(%s, %s)" % (num(box[0]), num(box[1]))),
                    ("centered", "false"),
                    ("texture", 'ExtResource("%s")' % eid)])
            elif sw > 0 and stroke_c:
                colr = (stroke_c[0], stroke_c[1], stroke_c[2], stroke_c[3] * sop * al)
                img, box = raster_stroke(rings, colr, sw, scale=4)
                name = "stroke_%02d.png" % (k["sprite"] + 1)
                save(img, os.path.join(TEX_DIR, name))
                eid = sc.ext_id(TEX_RES + name)
                k["sprite"] += 1
                sc.node("Stroke%02d" % k["sprite"], "Sprite2D", [
                    ("position", "Vector2(%s, %s)" % (num(box[0]), num(box[1]))),
                    ("centered", "false"),
                    ("texture", 'ExtResource("%s")' % eid)])
            continue

        if el.kind == "image":
            href = a.get("{http://www.w3.org/1999/xlink}href") or a.get("href") or ""
            if not href.startswith("data:image"):
                continue
            w = float(a.get("width", 0)); h = float(a.get("height", 0))
            raw = base64.b64decode(href.split(",", 1)[1])
            name = "embed_%dx%d.png" % (int(w), int(h))
            save_raw = os.path.join(TEX_DIR, name)
            os.makedirs(TEX_DIR, exist_ok=True)
            open(save_raw, "wb").write(raw)
            eid = sc.ext_id(TEX_RES + name)
            k["tex"] += 1
            sc.node("Image%d" % k["tex"], "TextureRect", [
                ("offset_left", num(el.dx)), ("offset_top", num(el.dy)),
                ("offset_right", num(el.dx + w)), ("offset_bottom", num(el.dy + h)),
                ("mouse_filter", "2"), ("expand_mode", "1"), ("stretch_mode", "0"),
                ("texture", 'ExtResource("%s")' % eid)])
            continue

    # ---- 文字节点（Label，设置字体）----
    font = sc.sid(("font", "sys"), ["font_names = " + FONTS])
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
    sc.write(OUT)
    return k


if __name__ == "__main__":
    print("节点统计:", build())
