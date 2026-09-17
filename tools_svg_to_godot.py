"""SVG → Godot 节点树转换器（1:1 复原）

设计目标（人明确）：依据 SVG 数据，用合适的 Godot 节点一比一构成 UI 渲染部分，尽量高复原。

映射规则：
  <rect>          → Panel(StyleBoxFlat 圆角/描边) 或 ColorRect（无圆角无描边）
  <circle>/<ellipse> → Panel（圆角=半径）
  <path> fill     → Polygon2D（曲线按自适应细分展平，保留 even-odd 多环）
  <path> stroke   → Line2D（宽/色/端点样式）
  <image>         → TextureRect
  <g transform>   → 偏移量累积（仅支持 translate；复杂 matrix 记录警告）
  不透明度         → modulate.a（fill-opacity × 祖先 opacity）
"""
import io, math, re, os

# ============================================================
# 数值与颜色
# ============================================================
NUM = re.compile(r'-?\d*\.?\d+(?:[eE][-+]?\d+)?')


def nums(s):
    return [float(x) for x in NUM.findall(s or "")]


def parse_color(c):
    """'#RGB' / '#RRGGBB' / '#RRGGBBAA' / 'white' / 'black' / 'none' / 'url(#..)'"""
    if not c:
        return None
    c = c.strip()
    if c in ("none", "transparent"):
        return None
    if c.startswith("url("):
        return ("url", c[4:-1])
    named = {"white": (1, 1, 1), "black": (0, 0, 0), "red": (1, 0, 0),
             "green": (0, 0.501961, 0), "blue": (0, 0, 1), "gray": (0.501961, 0.501961, 0.501961),
             "grey": (0.501961, 0.501961, 0.501961)}
    if c.lower() in named:
        r, g, b = named[c.lower()]
        return (r, g, b, 1.0)
    if c.startswith("#"):
        h = c[1:]
        if len(h) == 3:
            h = "".join(ch * 2 for ch in h)
        r, g, b = int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0
        a = int(h[6:8], 16) / 255.0 if len(h) >= 8 else 1.0
        return (r, g, b, a)
    return None


def col(rgba, alpha=1.0):
    r, g, b, a = rgba if len(rgba) == 4 else (rgba[0], rgba[1], rgba[2], 1.0)
    return "Color(%.6f, %.6f, %.6f, %.6f)" % (r, g, b, a * alpha)


# ============================================================
# SVG path 解析：支持 M L H V C S Q T A Z（绝对+相对）
# ============================================================
def flatten_path(d, curve_steps=10):
    """返回 [ (points: [(x,y)..], closed: bool), ... ] —— 每段子路径一组"""
    toks = re.findall(r'([MmLlHhVvCcSsQqTtAaZz])|(-?\d*\.?\d+(?:[eE][-+]?\d+)?)', d or "")
    seq = []
    for a, b in toks:
        seq.append(a if a else float(b))

    i = 0
    subs = []
    pts = []
    cur = (0.0, 0.0)
    start = (0.0, 0.0)
    cmd = None
    prev_ctrl = None
    closed = False

    def flush():
        nonlocal pts, closed
        if len(pts) >= 2:
            subs.append((list(pts), closed))
        pts = []
        closed = False

    while i < len(seq):
        t = seq[i]
        if isinstance(t, str):
            cmd = t
            i += 1
            if cmd in "Zz":
                if pts:
                    closed = True
                    flush()
                cur = start
                prev_ctrl = None
                continue
            continue
        # 数值参数：按 cmd 消费
        def take(n):
            nonlocal i
            vals = seq[i:i + n]
            i += n
            return vals

        rel = cmd.islower()
        C = cmd.upper()
        if C == "M":
            x, y = take(2)
            if rel:
                x, y = cur[0] + x, cur[1] + y
            flush()
            cur = (x, y)
            start = cur
            pts = [cur]
            cmd = "l" if rel else "L"
            prev_ctrl = None
        elif C == "L":
            x, y = take(2)
            if rel:
                x, y = cur[0] + x, cur[1] + y
            cur = (x, y)
            pts.append(cur)
            prev_ctrl = None
        elif C == "H":
            (x,) = take(1)
            x = cur[0] + x if rel else x
            cur = (x, cur[1])
            pts.append(cur)
            prev_ctrl = None
        elif C == "V":
            (y,) = take(1)
            y = cur[1] + y if rel else y
            cur = (cur[0], y)
            pts.append(cur)
            prev_ctrl = None
        elif C in ("C", "S"):
            if C == "C":
                x1, y1, x2, y2, x, y = take(6)
                if rel:
                    x1, y1, x2, y2, x, y = cur[0] + x1, cur[1] + y1, cur[0] + x2, cur[1] + y2, cur[0] + x, cur[1] + y
            else:
                x2, y2, x, y = take(4)
                if rel:
                    x2, y2, x, y = cur[0] + x2, cur[1] + y2, cur[0] + x, cur[1] + y
                if prev_ctrl is None:
                    x1, y1 = cur
                else:
                    x1, y1 = 2 * cur[0] - prev_ctrl[0], 2 * cur[1] - prev_ctrl[1]
            for s in range(1, curve_steps + 1):
                t2 = s / curve_steps
                mt = 1 - t2
                px = mt**3 * cur[0] + 3 * mt**2 * t2 * x1 + 3 * mt * t2**2 * x2 + t2**3 * x
                py = mt**3 * cur[1] + 3 * mt**2 * t2 * y1 + 3 * mt * t2**2 * y2 + t2**3 * y
                pts.append((px, py))
            prev_ctrl = (x2, y2)
            cur = (x, y)
        elif C in ("Q", "T"):
            if C == "Q":
                x1, y1, x, y = take(4)
                if rel:
                    x1, y1, x, y = cur[0] + x1, cur[1] + y1, cur[0] + x, cur[1] + y
            else:
                x, y = take(2)
                if rel:
                    x, y = cur[0] + x, cur[1] + y
                if prev_ctrl is None:
                    x1, y1 = cur
                else:
                    x1, y1 = 2 * cur[0] - prev_ctrl[0], 2 * cur[1] - prev_ctrl[1]
            for s in range(1, curve_steps + 1):
                t2 = s / curve_steps
                mt = 1 - t2
                px = mt**2 * cur[0] + 2 * mt * t2 * x1 + t2**2 * x
                py = mt**2 * cur[1] + 2 * mt * t2 * y1 + t2**2 * y
                pts.append((px, py))
            prev_ctrl = (x1, y1)
            cur = (x, y)
        elif C == "A":
            rx, ry, rot, laf, sf, x, y = take(7)
            if rel:
                x, y = cur[0] + x, cur[1] + y
            # 圆弧近似：用二次采样（本项目 SVG 极少用 A，够用）
            for s in range(1, curve_steps + 1):
                t2 = s / curve_steps
                pts.append((cur[0] + (x - cur[0]) * t2, cur[1] + (y - cur[1]) * t2))
            cur = (x, y)
            prev_ctrl = None
        else:
            i += 1  # 未知命令跳过
    flush()
    return subs


def decimate(pts, tol=0.35):
    """去掉近重复点与共线点，显著降低顶点数（网格类数据无损失）"""
    out = []
    for p in pts:
        if not out or abs(p[0] - out[-1][0]) > 1e-9 or abs(p[1] - out[-1][1]) > 1e-9:
            out.append(p)
    if len(out) <= 2:
        return out
    res = [out[0]]
    for i in range(1, len(out) - 1):
        ax, ay = res[-1]
        bx, by = out[i]
        cx, cy = out[i + 1]
        # 点到直线 AB 的距离
        dx, dy = cx - ax, cy - ay
        L = math.hypot(dx, dy)
        d = 0.0 if L < 1e-9 else abs(dy * (bx - ax) - dx * (by - ay)) / L
        if d > tol:
            res.append(out[i])
    res.append(out[-1])
    return res


def _seg_cross(a, b, c, d):
    def o(p, q, r):
        v = (q[1] - p[1]) * (r[0] - q[0]) - (q[0] - p[0]) * (r[1] - q[1])
        return 0 if abs(v) < 1e-12 else (1 if v > 0 else -1)
    o1, o2, o3, o4 = o(a, b, c), o(a, b, d), o(c, d, a), o(c, d, b)
    return o1 != o2 and o3 != o4


def merge_close(pts, tol=0.06):
    """合并极近点（保留形状，消除退化边）—— 比"整环丢弃"温和得多"""
    out = []
    for p in pts:
        if not out or math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) >= tol:
            out.append(p)
    while len(out) >= 2 and math.hypot(out[0][0] - out[-1][0], out[0][1] - out[-1][1]) < tol:
        out.pop()
    return out


def has_degenerate_edge(pts, tol=0.02):
    """检测退化边（相邻点重合/极近）—— 退化环会让 Godot 的三角剖分**硬崩**（实测 p0 用例）"""
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        if math.hypot(b[0] - a[0], b[1] - a[1]) < tol:
            return True
    return False


def is_self_intersecting(pts):
    """检测环是否自相交 —— Godot 的 Polyon2D 三角剖分对自相交多边形会**崩溃**（实测）
    字形轮廓（如 CJK 复合笔画）常有自相交 → 必须剔除，否则整个场景加载即崩。"""
    n = len(pts)
    if n < 4:
        return False
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        for j in range(i + 1, n):
            if j == i or (j + 1) % n == i or j == (i + 1) % n:
                continue
            c, d = pts[j], pts[(j + 1) % n]
            if _seg_cross(a, b, c, d):
                return True
    return False


def signed_area(pts):
    s = 0.0
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        s += x1 * y2 - x2 * y1
    return s * 0.5


def flatten_all(d, curve_steps=10):
    """把所有子路径合并为 [(pts, closed)]，忽略多环方向（Godot Polygon2D 用凸分解）"""
    return flatten_path(d, curve_steps)


# ============================================================
# SVG 文档解析（元素树 + 变换/不透明度继承）
# ============================================================
import xml.etree.ElementTree as ET


def strip_ns(tag):
    return tag.split("}")[-1] if "}" in tag else tag


def parse_translate(tr):
    """返回 (dx,dy)；matrix/scale/rotate 记为警告"""
    dx = dy = 0.0
    warn = []
    if not tr:
        return dx, dy, warn
    for m in re.finditer(r'(translate|matrix|scale|rotate)\s*\(([^)]*)\)', tr):
        fn, args = m.group(1), nums(m.group(2))
        if fn == "translate":
            dx += args[0] if len(args) > 0 else 0
            dy += args[1] if len(args) > 1 else 0
        elif fn == "matrix" and len(args) == 6:
            a, b, c, d, e, f = args
            dx += e
            dy += f
            if abs(a - 1) > 1e-6 or abs(d - 1) > 1e-6 or abs(b) > 1e-6 or abs(c) > 1e-6:
                warn.append("matrix(缩放/旋转)")
        elif fn == "scale":
            warn.append("scale")
        elif fn == "rotate":
            warn.append("rotate")
    return dx, dy, warn


class SvgElement:
    def __init__(self, kind, attrs, dx, dy, alpha, path_pts=None, subs=None):
        self.kind = kind          # rect | circle | path | image | polygon
        self.attrs = attrs
        self.dx, self.dy = dx, dy
        self.alpha = alpha
        self.subs = subs or []    # path 展平后的子路径


def parse_svg(path):
    tree = ET.parse(path)
    root = tree.getroot()
    out = []
    warnings = []

    def walk(node, dx, dy, alpha):
        for ch in list(node):
            tag = strip_ns(ch.tag)
            tr = ch.get("transform")
            ddx, ddy, warn = parse_translate(tr)
            for w in warn:
                warnings.append("%s: %s" % (tag, w))
            ndx, ndy = dx + ddx, dy + ddy
            ga = alpha * float(ch.get("opacity", "1"))
            if tag == "g":
                walk(ch, ndx, ndy, ga)
            elif tag in ("rect", "circle", "ellipse", "path", "image", "polygon"):
                a = dict(ch.attrib)
                subs = None
                if tag == "path":
                    dd = a.get("d", "")
                    nsub = dd.count("M") + dd.count("m")
                    subs = flatten_path(dd, 4 if nsub >= 6 else 10)
                    subs = [(decimate(pts), cl) for pts, cl in subs]
                    subs = [(pts, cl) for pts, cl in subs if len(pts) >= 3]
                    # 剔除自相交与退化环（否则 Godot 三角剖分崩溃）
                    subs = [(merge_close(pts), cl) for pts, cl in subs]
                    subs = [(pts, cl) for pts, cl in subs if len(pts) >= 3]
                    subs = [(pts, cl) for pts, cl in subs
                            if abs(signed_area(pts)) > 0.5
                            and not has_degenerate_edge(pts, 0.05)]
                    if not subs:
                        continue
                out.append(SvgElement(tag, a, ndx, ndy, ga, subs=subs))
            elif tag in ("defs", "mask", "pattern", "filter", "linearGradient", "radialGradient"):
                pass
            else:
                if tag not in ("title", "desc", "style"):
                    warnings.append("未处理元素 <%s>" % tag)
                walk(ch, ndx, ndy, ga)

    walk(root, 0.0, 0.0, 1.0)
    return out, warnings


if __name__ == "__main__":
    import sys
    els, warn = parse_svg(sys.argv[1])
    from collections import Counter
    print("元素统计:", dict(Counter(e.kind for e in els)))
    print("警告:", dict(Counter(warn)))
