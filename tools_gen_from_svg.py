"""SVG → Godot .tscn（干净版生成器）

要点（迭代038 教训）：
  · 只输出**被实际引用**的 sub_resource（未引用的子资源会让 Godot 报 "_parse_node_tag" 语法错）
  · 逐块自检：节点头行必须独占一行、属性行不得为空
  · Polygon2D 环：合并近点 + 去掉退化边 + 拒绝自相交（Godot 三角剖分对退化环会硬崩）
"""
import io, os, sys, base64, math, re
sys.path.insert(0, "C:/Users/27194/AppData/Local/Temp")
from svg_to_godot import parse_svg, parse_color, col, flatten_path, decimate, merge_close, \
    has_degenerate_edge, is_self_intersecting, signed_area

OUT_DIR = "Godot版Games代码/电子蜂/scenes/ui_figma"
ASSET_DIR = "Godot版Games代码/电子蜂/assets/static_ui"


def num(v):
    """Godot 数值字面量：固定小数、去尾零、避免科学计数法"""
    s = "%.6f" % v
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s if s not in ("", "-") else "0"


def vs(x, y):
    return "Vector2(%s, %s)" % (num(x), num(y))


class Out:
    def __init__(self, root):
        self.root = root
        self.sub = {}          # key → (id, lines)
        self.nodes = []
        self.ext = {}
        self.warnings = []

    def sub_id(self, key, lines):
        if key not in self.sub:
            sid = "R%d" % (len(self.sub) + 1)
            self.sub[key] = (sid, lines)
        return self.sub[key][0]

    def stylebox(self, bg, radius=0, border=0, bcol=None, center=True):
        key = ("sb", bg, radius, border, bcol, center)
        L = ['[sub_resource type="StyleBoxFlat" id="R0"]']
        L = ['bg_color = %s' % col(bg)]
        if not center:
            L.insert(0, "draw_center = false")
        if radius > 0:
            r = int(round(radius))
            L += ["corner_radius_top_left = %d" % r, "corner_radius_top_right = %d" % r,
                  "corner_radius_bottom_right = %d" % r, "corner_radius_bottom_left = %d" % r]
        if border > 0 and bcol:
            b = max(1, int(round(border)))
            L += ["border_width_left = %d" % b, "border_width_top = %d" % b,
                  "border_width_right = %d" % b, "border_width_bottom = %d" % b,
                  "border_color = %s" % col(bcol)]
        return self.sub_id(key, L)

    def ext_id(self, path):
        if path not in self.ext:
            self.ext[path] = "x%d" % (len(self.ext) + 1)
        return self.ext[path]

    def node(self, name, typ, props):
        self.nodes.append((name, typ, props))

    def write(self, path, scene_name):
        # 校验
        for n, t, pr in self.nodes:
            if "\n" in n or "[" in n or '"' in n:
                raise ValueError("非法节点名: %r" % n)
            for k, v in pr:
                if v is None or v == "":
                    raise ValueError("节点 %s 属性 %s 为空值" % (n, k))
        lines = []
        lines.append('[gd_scene load_steps=%d format=3]' %
                     (len(self.ext) + len(self.sub) + 1))
        lines.append("")
        for p, i in self.ext.items():
            lines.append('[ext_resource type="Texture2D" path="%s" id="%s"]' % (p, i))
        if self.ext:
            lines.append("")
        for key, (sid, body) in self.sub.items():
            lines.append('[sub_resource type="StyleBoxFlat" id="%s"]' % sid)
            lines += body
            lines.append("")
        lines.append('[node name="%s" type="Control"]' % scene_name)
        lines.append("layout_mode = 3")
        lines.append("anchors_preset = 0")
        lines.append("offset_right = 1920.0")
        lines.append("offset_bottom = 1080.0")
        for n, t, pr in self.nodes:
            lines.append("")
            lines.append('[node name="%s" type="%s" parent="."]' % (n, t))
            for k, v in pr:
                lines.append("%s = %s" % (k, v))
        lines.append("")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
        return len(self.ext), len(self.sub), len(self.nodes)


def rect_props(x, y, w, h):
    return [("offset_left", num(x)), ("offset_top", num(y)),
            ("offset_right", num(x + w)), ("offset_bottom", num(y + h)),
            ("mouse_filter", "2")]


def build(svg_path, scene_name, out_path, img_prefix):
    els, warns = parse_svg(svg_path)
    o = Out(scene_name)
    o.warnings += warns
    counts = {"rect": 0, "circle": 0, "poly": 0, "line": 0, "image": 0, "skip_self": 0, "skip_pat": 0}

    for el in els:
        a = el.attrs
        f = parse_color(a.get("fill"))
        s = parse_color(a.get("stroke"))
        fill_c = f if (isinstance(f, tuple) and f[0] != "url") else None
        stroke_c = s if (isinstance(s, tuple) and s[0] != "url") else None
        fop = float(a.get("fill-opacity", "1"))
        sop = float(a.get("stroke-opacity", "1"))
        sw = float(a.get("stroke-width", "0") or 0)
        al = el.alpha
        if (f is not None and isinstance(f, tuple) and f[0] == "url") or \
           (s is not None and isinstance(s, tuple) and s[0] == "url"):
            counts["skip_pat"] += 1

        if el.kind == "rect":
            x = float(a.get("x", 0)) + el.dx
            y = float(a.get("y", 0)) + el.dy
            w = float(a.get("width", 0)); h = float(a.get("height", 0))
            if w <= 0 or h <= 0:
                continue
            counts["rect"] += 1
            nm = "Rect%d" % counts["rect"]
            sid = o.stylebox(fill_c if fill_c else (0, 0, 0, 0), float(a.get("rx", 0) or 0),
                             sw if stroke_c else 0, stroke_c, center=bool(fill_c))
            props = rect_props(x, y, w, h) + [("theme_override_styles/panel", 'SubResource("%s")' % sid)]
            if fill_c and (fop < 1 or al < 1):
                props.append(("modulate", col((1, 1, 1), fop * al)))
            o.node(nm, "Panel", props)
            continue

        if el.kind == "circle":
            cx = float(a.get("cx", 0)) + el.dx; cy = float(a.get("cy", 0)) + el.dy
            r = float(a.get("r", 0))
            if r <= 0:
                continue
            counts["circle"] += 1
            nm = "Circle%d" % counts["circle"]
            if sw > 0 and stroke_c:
                sid = o.stylebox((0, 0, 0, 0), 0, sw, stroke_c, center=False)
                o.node(nm, "Panel", rect_props(cx - r, cy - r, 2 * r, 2 * r) +
                       [("theme_override_styles/panel", 'SubResource("%s")' % sid)])
            elif fill_c:
                sid = o.stylebox(fill_c, r, 0, None, True)
                o.node(nm, "Panel", rect_props(cx - r, cy - r, 2 * r, 2 * r) +
                       [("modulate", col((1, 1, 1), fop * al)),
                        ("theme_override_styles/panel", 'SubResource("%s")' % sid)])
            continue

        if el.kind == "path":
            dd = a.get("d", "")
            nsub = dd.count("M") + dd.count("m")
            rings = flatten_path(dd, 4 if nsub >= 6 else 10)
            rings = [(merge_close(decimate(pts)), cl) for pts, cl in rings]
            rings = [(pts, cl) for pts, cl in rings if len(pts) >= 3]
            if fill_c:
                for i, (pts, _cl) in enumerate(rings):
                    if abs(signed_area(pts)) <= 0.5 or has_degenerate_edge(pts, 0.05) \
                       or is_self_intersecting(pts):
                        counts["skip_self"] += 1
                        continue
                    counts["poly"] += 1
                    ox = min(p[0] for p in pts); oy = min(p[1] for p in pts)
                    rel = [(x - ox, y - oy) for x, y in pts]
                    o.node("Poly%d" % counts["poly"], "Polygon2D", [
                        ("position", vs(ox, oy)),
                        # ⚠️ 关键：.tscn 里 PackedVector2Array 必须用**扁平数值**（x, y, x, y ...），
                        #    写成 Vector2(x, y) 列表会让 Godot 报 _parse_node_tag 语法错（实测根因）
                        ("polygon", "PackedVector2Array(%s)" %
                         ", ".join("%s, %s" % (num(x), num(y)) for x, y in rel)),
                        ("color", col(fill_c, fop * al)),
                    ])
            elif sw > 0 and stroke_c:
                for i, (pts, cl) in enumerate(rings):
                    pl = pts + [pts[0]] if cl else pts
                    counts["line"] += 1
                    o.node("Line%d" % counts["line"], "Line2D", [
                        ("points", "PackedVector2Array(%s)" %
                         ", ".join("%s, %s" % (num(x), num(y)) for x, y in pl)),
                        ("width", num(sw)),
                        ("default_color", col(stroke_c, sop * al)),
                        ("begin_cap_mode", "1"), ("end_cap_mode", "1"), ("joint_mode", "2"),
                    ])
            continue

        if el.kind == "image":
            href = a.get("{http://www.w3.org/1999/xlink}href") or a.get("href") or ""
            if not href.startswith("data:image"):
                continue
            w = float(a.get("width", 0)); h = float(a.get("height", 0))
            raw = base64.b64decode(href.split(",", 1)[1])
            fname = "%s-%dx%d.png" % (img_prefix, int(w), int(h))
            os.makedirs(ASSET_DIR, exist_ok=True)
            open(os.path.join(ASSET_DIR, fname), "wb").write(raw)
            counts["image"] += 1
            eid = o.ext_id("res://assets/static_ui/" + fname)
            o.node("Image%d" % counts["image"], "TextureRect", [
                ("offset_left", num(el.dx)), ("offset_top", num(el.dy)),
                ("offset_right", num(el.dx + w)), ("offset_bottom", num(el.dy + h)),
                ("mouse_filter", "2"), ("expand_mode", "1"), ("stretch_mode", "0"),
                ("texture", 'ExtResource("%s")' % eid),
            ])
    res = o.write(out_path, scene_name)
    return res, counts, set(o.warnings)


if __name__ == "__main__":
    res, counts, warns = build("Godot版Games代码/电子蜂/refs/figma_base.svg", "FigFigmaBase",
                               os.path.join(OUT_DIR, "figma_base.tscn"), "bimg")
    print("figma_base.tscn: ext=%d sub=%d nodes=%d" % res)
    print("转换统计:", counts)
    print("解析警告:", warns)
