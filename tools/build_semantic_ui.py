"""语义化构建战斗 UI（迭代041）

原则（人明确）：**不是把 SVG 直译成节点**，而是从设计稿提取「信息与逻辑」，用 Godot 节点**重新实现**。
  · 语义命名：节点名表达用途（Battle.HandPanel.Left / MainButton.Label），不是 Rect37 / Poly12
  · 可复用组件做成**子场景**：费用徽章、地图单位卡、手牌词条
  · 用**合适的节点**：面板=Panel+StyleBoxFlat，图片=TextureRect，文字=Label（设字体），按钮=Button
  · 颜色/尺寸/文本集中取自 design/battle_ui_spec.json（改设计先改规范，再重建）
"""
import io, os, json, sys

SPEC = json.load(io.open("Godot版Games代码/电子蜂/design/battle_ui_spec.json", encoding="utf-8"))
OUT_DIR = "Godot版Games代码/电子蜂/scenes/ui"
C = SPEC["颜色"]
FONTS = 'PackedStringArray("Noto Sans SC", "Source Han Sans CN", "Microsoft YaHei")'
ICON = SPEC["属性图标"]
ATTR_ICON = ["res://assets/ui/icon_attr_%d.png" % i for i in range(1, 5)]


def col(hexstr):
    h = hexstr.lstrip("#")
    if len(h) == 3:
        h = "".join(ch * 2 for ch in h)
    r, g, b = int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0
    a = int(h[6:8], 16) / 255.0 if len(h) >= 8 else 1.0
    return "Color(%.6f, %.6f, %.6f, %.6f)" % (r, g, b, a)


def n(v):
    s = "%.2f" % v
    return s.rstrip("0").rstrip(".") if "." in s else s


class Tscn:
    def __init__(self, name, size=None, script=None):
        self.name, self.size, self.script = name, size, script
        self.subs, self.exts, self.nodes = [], {}, []

    def _sid(self, tag, body):
        key = (tag, tuple(body))
        for i, (t, b, sid) in enumerate(self.subs):
            if (t, b) == key:
                return sid
        sid = "R%d" % (len(self.subs) + 1)
        self.subs.append((tag, body, sid))
        return sid

    def stylebox(self, bg, radius=0, border=0, bcol=None, center=True):
        body = []
        if not center:
            body.append("draw_center = false")
        body.append("bg_color = %s" % (col(bg) if isinstance(bg, str) else bg))
        if radius:
            r = int(round(radius))
            body += ["corner_radius_top_left = %d" % r, "corner_radius_top_right = %d" % r,
                     "corner_radius_bottom_right = %d" % r, "corner_radius_bottom_left = %d" % r]
        if border and bcol:
            b = max(1, int(round(border)))
            body += ["border_width_left = %d" % b, "border_width_top = %d" % b,
                     "border_width_right = %d" % b, "border_width_bottom = %d" % b,
                     "border_color = %s" % (col(bcol) if isinstance(bcol, str) else bcol)]
        return self._sid("StyleBoxFlat", body)

    def sysfont(self):
        return self._sid("SystemFont", ["font_names = " + FONTS])

    def ext(self, path):
        if path not in self.exts:
            self.exts[path] = "x%d" % (len(self.exts) + 1)
        return self.exts[path]

    def panel(self, name, parent, x, y, w, h, bg, radius=0, border=0, bcol=None,
              center=True, mouse=2):
        sid = self.stylebox(bg, radius, border, bcol, center)
        self.nodes.append((name, "Panel", parent, [
            ("offset_left", n(x)), ("offset_top", n(y)),
            ("offset_right", n(x + w)), ("offset_bottom", n(y + h)),
            ("mouse_filter", str(mouse)),
            ("theme_override_styles/panel", 'SubResource("%s")' % sid)]))

    def group(self, name, parent, x=0, y=0, w=1, h=1, node_type="Control"):
        self.nodes.append((name, node_type, parent, [
            ("offset_left", n(x)), ("offset_top", n(y)),
            ("offset_right", n(x + w)), ("offset_bottom", n(y + h)),
            ("mouse_filter", "2")]))

    def texture(self, name, parent, x, y, w, h, path, stretch=0, tile=False):
        eid = self.ext(path)
        props = [("offset_left", n(x)), ("offset_top", n(y)),
                 ("offset_right", n(x + w)), ("offset_bottom", n(y + h)),
                 ("mouse_filter", "2"), ("texture", 'ExtResource("%s")' % eid),
                 ("expand_mode", "1"), ("stretch_mode", str(stretch))]
        if tile:
            props.append(("texture_repeat", "1"))
        self.nodes.append((name, "TextureRect", parent, props))

    def label(self, name, parent, x, y, w, h, text, fs, color, align="left", vcenter=True):
        self.nodes.append((name, "Label", parent, [
            ("offset_left", n(x)), ("offset_top", n(y)),
            ("offset_right", n(x + w)), ("offset_bottom", n(y + h)),
            ("mouse_filter", "2"),
            ("theme_override_fonts/font", 'SubResource("%s")' % self.sysfont()),
            ("theme_override_font_sizes/font_size", str(int(fs))),
            ("theme_override_colors/font_color", col(color)),
            ("horizontal_alignment", {"left": "0", "center": "1", "right": "2"}[align]),
            ("vertical_alignment", "1" if vcenter else "0"),
            ("text", '"%s"' % text.replace("\n", "\\n"))]))

    def button(self, name, parent, x, y, w, h, text, fs, bg, fg):
        sid_n = self.stylebox(bg, 10.0)
        self.nodes.append((name, "Button", parent, [
            ("offset_left", n(x)), ("offset_top", n(y)),
            ("offset_right", n(x + w)), ("offset_bottom", n(y + h)),
            ("mouse_default_cursor_shape", "2"),
            ("theme_override_fonts/font", 'SubResource("%s")' % self.sysfont()),
            ("theme_override_font_sizes/font_size", str(int(fs))),
            ("theme_override_colors/font_color", col(fg)),
            ("theme_override_styles/normal", 'SubResource("%s")' % sid_n),
            ("text", '"%s"' % text)]))

    def write(self, path):
        L = ["[gd_scene load_steps=%d format=3]" % (len(self.exts) + len(self.subs) + 2), ""]
        for p, i in self.exts.items():
            L.append('[ext_resource type="Texture2D" path="%s" id="%s"]' % (p, i))
        if self.script:
            eid = "x%d" % (len(self.exts) + 1)
            L.append('[ext_resource type="Script" path="%s" id="%s"]' % (self.script, eid))
        L.append("")
        for tag, body, sid in self.subs:
            L.append('[sub_resource type="%s" id="%s"]' % (tag, sid))
            L += body
            L.append("")
        rp = ["layout_mode = 3", "anchors_preset = 0"]
        if self.size:
            rp += ["offset_right = %s" % n(self.size[0]), "offset_bottom = %s" % n(self.size[1])]
        if self.script:
            rp.append('script = ExtResource("x%d")' % (len(self.exts) + 1))
        L += ['[node name="%s" type="Control"]' % self.name] + rp
        for nm, ty, par, props in self.nodes:
            L.append("")
            L.append('[node name="%s" type="%s" parent="%s"]' % (nm, ty, par))
            for k, v in props:
                L.append("%s = %s" % (k, v))
        L.append("")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(L))
        return len(self.nodes)


# ============================================================
# ① 费用徽章（子场景，可复用）：六边形 + 数字
# ============================================================
def build_badge():
    sc = Tscn("CostBadge", size=(100, 100))
    # 外轮廓 bounds 86.6×98.6 → 以中心 (81,90) 为原点放回本组件 (50,50)
    # 六个顶点（尖顶）
    cx, cy, r = 50.0, 50.0, 49.3
    hw = r * 0.8660254
    pts = [(cx, cy - r), (cx + hw, cy - r * 0.5), (cx + hw, cy + r * 0.5),
           (cx, cy + r), (cx - hw, cy + r * 0.5), (cx - hw, cy - r * 0.5)]
    sc.nodes.append(("HexBg", "Polygon2D", ".", [
        ("polygon", "PackedVector2Array(%s)" % ", ".join("%s, %s" % (n(x), n(y)) for x, y in pts)),
        ("color", col(C["费用橙"]))]))
    sc.nodes.append(("HexOutline", "Line2D", ".", [
        ("points", "PackedVector2Array(%s)" %
         ", ".join("%s, %s" % (n(x), n(y)) for x, y in pts + [pts[0]])),
        ("width", "4.0"), ("default_color", col("#00000080")),
        ("joint_mode", "2"), ("antialiased", "true")]))
    sc.label("Number", ".", 30, 20, 40, 56, "0", 40, C["文字深"], "center")
    return sc


# ============================================================
# ② 地图单位卡（子场景，可复用）：250×250
# ============================================================
def build_unit_card():
    u = SPEC["地图单位卡"]
    sc = Tscn("UnitCard", size=(250, 250))
    sc.panel("CardBg", ".", 0, 0, 250, 250, C["单位底"], 10.0)
    sc.panel("RailLeft", ".", 0, 0, 40, 250, C["我方阵营"], 10.0)
    sc.panel("RailRight", ".", 210, 0, 40, 250, C["我方阵营"], 10.0)
    sc.panel("CostPlate", ".", 0, 0, 40, 40, C["费用格底"], 0.0)
    sc.label("Cost", ".", 0, 2, 40, 36, "0", 26, C["文字浅"], "center")
    sc.texture("Art", ".", 47, 8, 155.83, 233, "res://assets/static_ui/fill-image12-306x463.png")
    rows = [("Attack", 0, 65, ICON["攻击"]), ("Defense", 0, 105, ICON["生命"]),
            ("Move", 210, 160, ICON["速度"]), ("Range", 210, 200, ICON["射程"])]
    for nm, cx, cy, icon in rows:
        sc.panel("Cell" + nm, ".", cx, cy, 40, 40, C["属性数值底"], 0.0)
        sc.label("Value" + nm, ".", cx, cy + 3, 40, 34, "0", 22, C["文字深"], "center")
        sc.panel("Cell" + nm + "Icon", ".", cx, cy + 40, 40, 40, C["属性图标底"], 0.0)
        sc.texture("Icon" + nm, ".", cx + 7, cy + 47, 26, 26, icon)
    sc.panel("CardOutline", ".", 1, 1, 248, 248, "#00000000", 9.0, 2, "#00000033", False)
    return sc


# ============================================================
# ③ 手牌词条（子场景，可复用）：200×200
# ============================================================
def build_hand_card():
    sc = Tscn("HandCard", size=(200, 200))
    sc.panel("CardBg", ".", 0, 0, 200, 200, C["单位底"], 10.0)
    sc.texture("Art", ".", 10, 10, 180, 180, "res://assets/static_ui/fill-image11-320x320.png")
    sc.panel("CostPlate", ".", 8, 8, 23, 33, "#FFFFFFE6", 0.0)
    sc.label("Cost", ".", 8, 10, 23, 30, "0", 22, C["文字深"], "center")
    sc.label("Name", ".", 10, 172, 180, 24, "卡牌", 18, C["文字深"], "center")
    sc.panel("CardOutline", ".", 2, 2, 196, 196, "#00000000", 8.0, 4, "#333333", False)
    return sc


# ============================================================
# ④ 主场景：战斗界面（语义化层次）
# ============================================================
def build_battle():
    A = SPEC["区域"]
    sc = Tscn("BattleUI", size=(1920, 1080))

    # ---- Background ----
    sc.panel("Background", ".", 0, 0, 1920, 1080, C["背景"], 0.0)

    # ---- Battle → Board ----
    b = A["地图板"]; f = A["地图外框"]
    sc.group("Battle", ".")
    sc.group("Board", "Battle")
    sc.panel("Plate", "Battle/Board", b["位置"][0], b["位置"][1], b["尺寸"][0], b["尺寸"][1], C["地图板"], 10.0)
    sc.texture("Texture", "Battle/Board", b["位置"][0], b["位置"][1], b["尺寸"][0], b["尺寸"][1],
               "res://assets/static_ui/fill-image0-1000x1000.png")
    sc.panel("Frame", "Battle/Board", f["位置"][0], f["位置"][1], f["尺寸"][0], f["尺寸"][1],
             "#00000000", 12.0, 4, C["地图外框"], False)
    sc.group("Units", "Battle/Board")

    # ---- Battle → Hands（左右手牌区 + 地图单位卡实例占位）----
    sc.group("HandPanels", "Battle")
    hl = A["左手牌区"]; hr = A["右手牌区"]
    sc.panel("Left", "Battle/HandPanels", hl["位置"][0], hl["位置"][1], hl["尺寸"][0], hl["尺寸"][1],
             C["手牌区底"], 10.0)
    sc.panel("Right", "Battle/HandPanels", hr["位置"][0], hr["位置"][1], hr["尺寸"][0], hr["尺寸"][1],
             C["手牌区底"], 10.0)

    # ---- Battle → CostBadges（费用徽章实例）----
    sc.group("CostBadges", "Battle")
    for side, pos in (("Left", (37.7, 40.7)), ("Right", (1496.7, 40.7))):
        # 费用徽章 = 尖顶六边形（节点绘制）+ 数字块；半径/中心取自设计稿实测
        cx = pos[0] + 43.3
        cy = pos[1] + 49.3
        r = 49.3
        hw = r * 0.8660254
        hexpts = [(cx, cy - r), (cx + hw, cy - r * 0.5), (cx + hw, cy + r * 0.5),
                  (cx, cy + r), (cx - hw, cy + r * 0.5), (cx - hw, cy - r * 0.5)]
        sc.nodes.append(("Badge" + side + "Hex", "Polygon2D", "Battle/CostBadges", [
            ("polygon", "PackedVector2Array(%s)" %
             ", ".join("%s, %s" % (n(x), n(y)) for x, y in hexpts)),
            ("color", col(C["费用橙"]))]))
        sc.nodes.append(("Badge" + side + "Outline", "Line2D", "Battle/CostBadges", [
            ("points", "PackedVector2Array(%s)" %
             ", ".join("%s, %s" % (n(x), n(y)) for x, y in hexpts + [hexpts[0]])),
            ("width", "4.0"), ("default_color", col("#00000080")),
            ("joint_mode", "2"), ("antialiased", "true")]))
        sc.panel("Badge" + side + "Number", "Battle/CostBadges", pos[0] + 23.3, pos[1] + 22.3, 37, 54,
                 "#FFFFFF", 0.0)

    # ---- HUD → 左下信息面板 / 右下主按钮 / 功能按钮 ----
    sc.group("HUD", ".")
    p = A["左下信息面板"]
    sc.panel("InfoPanel", "HUD", p["位置"][0], p["位置"][1], p["尺寸"][0], p["尺寸"][1], C["面板白"], 10.0)
    d = A["卡牌详情块"]
    sc.panel("DetailBlock", "HUD", d["位置"][0], d["位置"][1], d["尺寸"][0], d["尺寸"][1], C["详情块"], 10.0)
    sc.panel("DetailOutline", "HUD", d["位置"][0] + 2, d["位置"][1] + 2, d["尺寸"][0] - 4, d["尺寸"][1] - 4,
             "#00000000", 8.0, 4, C["详情块描边"], False)
    # 属性行：每行 = 「数值块（40×40）+ 图标块（40×40）」，块底色按规范
    #   图标为白色素材 → 在浅色块上不可见，故重着色为规范色 #222222-70%（见 assets/ui/icon_attr_*.png）
    for i, (x, y) in enumerate(SPEC["属性数值"]["位置"]):
        iy = y - 9.9
        sc.texture("AttrIcon%d" % (i + 1), "HUD", x - 41.4, iy, 40, 40, ATTR_ICON[i])
        sc.panel("AttrValueCell%d" % (i + 1), "HUD", x - 41.4 - 40, iy, 40, 40, C["属性数值底"], 0.0)
        sc.label("AttrValue%d" % (i + 1), "HUD", x - 41.4 - 40, iy + 3, 40, 34, "0", 24, C["文字深"], "center")

    mb = A["主按钮"]
    sc.button("MainButton", "HUD", mb["位置"][0], mb["位置"][1], mb["尺寸"][0], mb["尺寸"][1],
              SPEC["文本"][3]["文案"], 34, C["主按钮_可用"], "#0F1A14")
    seg = mb["右段"]
    sc.panel("MainButtonSeg", "HUD", seg["位置"][0], seg["位置"][1], seg["尺寸"][0], seg["尺寸"][1],
             seg["色"], 0.0)

    fb = A["功能按钮组"]
    sc.group("FuncButtons", "HUD")
    names = ["Settings", "Emote", "Info", "Back"]
    actions = ["设置", "表情", "信息", "退出"]
    for i in range(fb["数量"]):
        x = fb["起点"][0] + (fb["按钮尺寸"][0] + fb["间距"]) * i
        sc.panel(names[i], "HUD/FuncButtons", x, fb["起点"][1], fb["按钮尺寸"][0], fb["按钮尺寸"][1],
                 C["功能按钮底"], 10.0)
        sc.label(actions[i], "HUD/FuncButtons", x, fb["起点"][1] + 24, fb["按钮尺寸"][0], 32,
                 actions[i], 16, C["文字深"], "center")

    # ---- Text（文字节点，统一设字体）----
    sc.group("Text", ".")
    for t in SPEC["文本"]:
        x0, y0, x1, y1 = t["区"]
        txt = t["文案"] if isinstance(t["文案"], str) else "\n".join(t["文案"])
        nl = 1 if isinstance(t["文案"], str) else len(t["文案"])
        fs = (y1 - y0) * 0.78 if nl == 1 else (y1 - y0) / nl * 0.86
        nm = t["节点"].split(".")[-1]
        side = t["节点"].split(".")[0]
        sc.label("%s_%s" % (side, nm), "Text", x0, y0 - 2, (x1 - x0) + 30, (y1 - y0) + 10,
                 txt, fs, C["文字浅"], t.get("对齐", "left"))
    return sc


if __name__ == "__main__":
    outs = []
    sc = build_badge();      outs.append(("cost_badge.tscn", sc.write(os.path.join(OUT_DIR, "cost_badge.tscn"))))
    sc = build_unit_card();  outs.append(("unit_card.tscn", sc.write(os.path.join(OUT_DIR, "unit_card.tscn"))))
    sc = build_hand_card();  outs.append(("hand_card.tscn", sc.write(os.path.join(OUT_DIR, "hand_card.tscn"))))
    sc = build_battle();     outs.append(("battle_ui.tscn", sc.write(os.path.join(OUT_DIR, "battle_ui.tscn"))))
    for name, cnt in outs:
        print("%-18s 节点=%d" % (name, cnt))
