"""把 SVG 路径直接**栅格化**成 PNG 纹理（供 Sprite2D / TextureRect 使用）

用途（人明确）：图标、费用数字这类**图形化元素**用 2D 精灵渲染 —— 既比自绘多边形更还原，
也不必硬套成文字节点；而**真正的文字**仍用文字节点（Label）+ 指定字体。
"""
import io, os
from PIL import Image, ImageDraw, ImageChops


def raster_rings(rings, color, scale=4, pad=2):
    """把若干环（每个环是 [(x,y), ...] 绝对坐标）填充为 PNG

    rings: [(pts, closed), ...]  —— 同一路径的全部子路径（nonzero 填充，正确处理"0"这类带孔字形）
    color: (r, g, b, a) 0~1
    """
    allv = [p for pts, _ in rings for p in pts]
    x0 = min(p[0] for p in allv) - pad
    y0 = min(p[1] for p in allv) - pad
    x1 = max(p[0] for p in allv) + pad
    y1 = max(p[1] for p in allv) + pad
    w = max(2, int(round((x1 - x0) * scale)))
    h = max(2, int(round((y1 - y0) * scale)))
    rgba = (int(color[0] * 255), int(color[1] * 255), int(color[2] * 255),
            int((color[3] if len(color) > 3 else 1.0) * 255))
    # 非零环绕填充：逐环 XOR —— 才能正确处理 "0"「回」等**带孔**字形
    #   （简单叠加多项式会把内孔填实，实测数字变成实心块）
    mask = Image.new("1", (w, h), 0)
    md = ImageDraw.Draw(mask)
    for pts, _cl in rings:
        if len(pts) < 3:
            continue
        poly = [((p[0] - x0) * scale, (p[1] - y0) * scale) for p in pts]
        ring = Image.new("1", (w, h), 0)
        ImageDraw.Draw(ring).polygon(poly, fill=1)
        mask = ImageChops.logical_xor(mask, ring)
    img = Image.new("RGBA", (w, h), rgba)
    img.putalpha(mask.convert("L").point(lambda v: 255 if v else 0))
    # 超采样后缩小 ⇒ 抗锯齿
    img = img.resize((max(2, int(round(x1 - x0))), max(2, int(round(y1 - y0)))),
                     Image.LANCZOS)
    return img, (x0, y0, x1, y1)


def raster_stroke(rings, color, width, scale=4, pad=2):
    """描边路径 → PNG（Line2D 的精灵替代）"""
    allv = [p for pts, _ in rings for p in pts]
    x0 = min(p[0] for p in allv) - pad - width
    y0 = min(p[1] for p in allv) - pad - width
    x1 = max(p[0] for p in allv) + pad + width
    y1 = max(p[1] for p in allv) + pad + width
    w = max(2, int(round((x1 - x0) * scale)))
    h = max(2, int(round((y1 - y0) * scale)))
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rgba = (int(color[0] * 255), int(color[1] * 255), int(color[2] * 255),
            int((color[3] if len(color) > 3 else 1.0) * 255))
    lw = max(1, int(round(width * scale)))
    for pts, cl in rings:
        if len(pts) < 2:
            continue
        poly = [((p[0] - x0) * scale, (p[1] - y0) * scale) for p in pts]
        if cl:
            poly.append(poly[0])
        d.line(poly, fill=rgba, width=lw, joint="curve")
    img = img.resize((max(2, int(round(x1 - x0))), max(2, int(round(y1 - y0)))),
                     Image.LANCZOS)
    return img, (x0, y0, x1, y1)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")
    return path
