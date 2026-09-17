"""战斗 UI —— **依 SVG 原文逐元素映射** + 素材取自 `素材/zip原图` 原件 + 语义化层级（迭代043）

两条本轮要求：
  ① **素材改用 zip原图 原件**：SVG 内嵌图均为原件的缩小版（如属性图标原件 80×80、SVG 只嵌 40×40；
     地图十字线蒙版原件 2020²、SVG 只嵌 2000²）→ 直接引原件，避免二次缩放失真
  ② **重组节点层级**：消除"同一父节点下 40 个同级节点"的平铺结构 → 按语义分层，子项挂在所属模块下
"""
import io, os

OUT = "Godot版Games代码/电子蜂/scenes/ui/battle_ui.tscn"
Z = "res://assets/ui/zip_original/"
FONTS = 'PackedStringArray("Noto Sans SC", "Source Han Sans CN", "Microsoft YaHei")'


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
        self.name, self.subs, self.exts, self.nodes, self.conns = name, [], {}, [], []

    def _sid(self, tag, body):
        for t, b, sid in self.subs:
            if (t, b) == (tag, tuple(body)):
                return sid
        sid = "R%d" % (len(self.subs) + 1)
        self.subs.append((tag, body, sid))
        return sid

    def sb(self, bg, radius=0, bw=0, bc=None, center=True):
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
        return self._sid("StyleBoxFlat", body)

    def font(self, bold=False):
        body = ["font_names = " + FONTS] + (["font_weight = 700"] if bold else [])
        return self._sid("SystemFont", body)

    def ext(self, p):
        if p not in self.exts:
            self.exts[p] = "x%d" % (len(self.exts) + 1)
        return self.exts[p]

    def _add(self, nm, ty, par, props):
        self.nodes.append((nm, ty, par, props))

    def group(self, nm, par, x=0, y=0, w=1, h=1):
        self._add(nm, "Control", par, [("offset_left", n(x)), ("offset_top", n(y)),
                                       ("offset_right", n(x + w)), ("offset_bottom", n(y + h)),
                                       ("mouse_filter", "2")])

    def panel(self, nm, par, x, y, w, h, bg, radius=0, bw=0, bc=None, center=True):
        sid = self.sb(bg, radius, bw, bc, center)
        self._add(nm, "Panel", par, [("offset_left", n(x)), ("offset_top", n(y)),
                                     ("offset_right", n(x + w)), ("offset_bottom", n(y + h)),
                                     ("mouse_filter", "2"),
                                     ("theme_override_styles/panel", 'SubResource("%s")' % sid)])

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
        self._add(nm, "TextureRect", par, pr)

    def label(self, nm, par, x, y, w, h, text, fs, color, align="left", bold=False):
        self._add(nm, "Label", par, [("offset_left", n(x)), ("offset_top", n(y)),
                                     ("offset_right", n(x + w)), ("offset_bottom", n(y + h)),
                                     ("mouse_filter", "2"),
                                     ("theme_override_fonts/font", 'SubResource("%s")' % self.font(bold)),
                                     ("theme_override_font_sizes/font_size", str(int(round(fs)))),
                                     ("theme_override_colors/font_color", col(color)),
                                     ("horizontal_alignment", {"left": "0", "center": "1", "right": "2"}[align]),
                                     ("vertical_alignment", "1"),
                                     ("text", '"%s"' % text)])

    def button(self, nm, par, x, y, w, h, bg, radius=10, text="", fs=0, fg="#FFFFFF"):
        s_n = self.sb(bg, radius)
        s_h = self.sb("#8A8A8A" if bg == "#999999" else "#FFFFFFB3", radius)
        pr = [("offset_left", n(x)), ("offset_top", n(y)),
              ("offset_right", n(x + w)), ("offset_bottom", n(y + h)),
              ("mouse_default_cursor_shape", "2"),
              ("theme_override_styles/normal", 'SubResource("%s")' % s_n),
              ("theme_override_styles/hover", 'SubResource("%s")' % s_h),
              ("theme_override_styles/pressed", 'SubResource("%s")' % s_h)]
        if text:
            pr += [("theme_override_fonts/font", 'SubResource("%s")' % self.font(True)),
                   ("theme_override_font_sizes/font_size", str(int(fs))),
                   ("theme_override_colors/font_color", col(fg)), ("text", '"%s"' % text)]
        self._add(nm, "Button", par, pr)

    def conn(self, frm, sig, meth):
        self.conns.append('[connection signal="%s" from="%s" to="." method="%s"]' % (sig, frm, meth))

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
        for c in self.conns:
            L.append("")
            L.append(c)
        L.append("")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(L))
        return len(self.nodes)


def build():
    s = Scn("BattleUI")

    # ── 层级：BattleUI ─┬─ Background
    #                  ├─ Battle ─┬─ MapView ─┬─ MapPlate / MapMask / MapFrame
    #                  │          │           └─ MapCells
    #                  │          ├─ HandPanelLeft / HandPanelRight
    #                  │          └─ CostBadgeLeft / CostBadgeRight
    #                  └─ HUD ─┬─ InfoPanel ─┬─ CardName / SkillDesc
    #                          │             └─ DetailBlock ─┬─ DetailFrame ── Artwork
    #                          │                             └─ Attributes ─ 4×(Icon+Value)
    #                          ├─ ActionBar ─┬─ MainButton / MainButtonSeg
    #                          │             └─ FuncButtonGroup ─ Func1..4
    #                          └─ MatchInfo ─ TurnInfo / MapName / SiteEffect
    s.panel("Background", ".", 0, 0, 1920, 1080, "#666666", 0)

    # ══ Battle / MapView ══
    s.group("Battle", ".")
    s.group("MapView", "Battle", 459, 40, 1000, 1000)
    s.panel("MapPlate", "Battle/MapView", 0, 0, 1000, 1000, "#999999", 10)
    # 地图十字线：**引用 zip原图原件**（原尺寸 1010²，含 4px 描边余量 → 铺到 1004²）
    s.tex("MapMask", "Battle/MapView", -2, -2, 1004, 1004, Z + "map_mask_2020.png")
    s.panel("MapFrame", "Battle/MapView", -2, -2, 1004, 1004, "#00000000", 12, 4, "#FFFFFF80", center=False)
    # 4×4 地图格：每个 250²，原点 (459,40) + i*250
    # 地图格：**运行时状态元素**（格子高亮/选中/落子），底座稿中不出现
    #   → 保留容器供运行时按需实例化，底座不铺贴图
    s.group("MapCells", "Battle/MapView", 0, 0, 1000, 1000)

    # ══ Battle / 手牌区 ══
    s.panel("HandPanelLeft", "Battle", 30, 150, 400, 400, "#00000033", 10)
    s.panel("HandPanelRight", "Battle", 1490, 150, 400, 400, "#00000033", 10)

    # ══ Battle / 费用徽章（zip原图原件 100×100 → 放 200×200？实际设计 86.6×98.6）══
    for side, bx in (("Left", 36.7), ("Right", 1496.7)):
        s.group("CostBadge%s" % side, "Battle", bx, 41.7, 90, 99)
        s.tex("BadgeImage", "Battle/CostBadge%s" % side, 0, 0, 86.6, 97.3, Z + "cost_badge_200.png")
        s.label("Value", "Battle/CostBadge%s" % side, 26, 22, 34, 53, "0", 30, "#FFFFFF", "center", True)

    # ══ HUD / InfoPanel ══
    s.group("HUD", ".")
    s.group("InfoPanel", "HUD", 30, 570, 400, 470)
    s.label("CardName", "HUD/InfoPanel", 1.8, 4, 240, 46, "卡牌名称", 52, "#FFFFFF", bold=True)
    s.label("SkillDesc", "HUD/InfoPanel", 0.9, 56, 300, 100,
            "技能描述-行1\n技能描述-行2\n技能描述-行3", 30, "#FFFFFF")
    # 详情块（构图：边框层 + 立绘层）
    s.group("DetailBlock", "HUD/InfoPanel", 0, 170, 300, 300)
    s.panel("BlockBg", "HUD/InfoPanel/DetailBlock", 0, 0, 300, 300, "#333333", 10)
    s.panel("BlockFrame", "HUD/InfoPanel/DetailBlock", 2, 2, 296, 296, "#00000000", 8, 4, "#000000", center=False)
    s.panel("Artwork", "HUD/InfoPanel/DetailBlock", 0, 0, 300, 300, "#333333", 10)
    # 属性行：4×(图标 + 数值) —— 挂在 Attributes 下（不再平铺到根）
    s.group("Attributes", "HUD/InfoPanel", 310, 210, 200, 240)
    for i, y in enumerate((0, 60, 120, 180)):
        row = "Row%d" % (i + 1)
        s.group(row, "HUD/InfoPanel/Attributes", 0, y, 110, 40)
        icon = ["attr_attack_80.png", "attr_health_80.png", "attr_speed_80.png", "attr_range_80.png"][i]
        s.tex("Icon", "HUD/InfoPanel/Attributes/%s" % row, 0, 0, 40, 40, Z + icon)
        s.label("Value", "HUD/InfoPanel/Attributes/%s" % row, 41, 2, 40, 36, "0", 30, "#FFFFFF")

    # ══ HUD / ActionBar ══
    s.group("ActionBar", "HUD", 1490, 570, 400, 100)
    s.button("MainButton", "HUD/ActionBar", 0, 0, 400, 100, "#999999", 10)
    s.panel("MainButtonSeg", "HUD/ActionBar", 262, 0, 138, 100, "#00000033", 0)
    s.panel("MainButtonText", "HUD/ActionBar", 2, 2, 396, 96, "#00000000", 8, 4, "#FFFFFF1A", center=False)
    s.label("Label", "HUD/ActionBar", 80, 26, 240, 48, "主按钮", 38, "#FFFFFF", "center", bold=True)

    # 功能按钮组
    s.group("FuncButtonGroup", "HUD", 1540, 960, 350, 80)
    for i, nm in enumerate(("Settings", "Emote", "Info", "Back")):
        # 每个功能键自成一组（按钮 + 内描边 + 图标），避免同级平铺
        s.group(nm, "HUD/FuncButtonGroup", i * 90, 0, 80, 80)
        s.button("Button", "HUD/FuncButtonGroup/%s" % nm, 0, 0, 80, 80, "#FFFFFF80", 10)
        s.panel("Frame", "HUD/FuncButtonGroup/%s" % nm, 2, 2, 76, 76, "#00000000", 8, 4, "#FFFFFF1A", center=False)
        # 图标待定：原图 `战斗UI-功能按钮133x100` 是**整块按钮底图**（非图标），
        # 与 Button 底/描边重复 → 底座阶段不叠加，图标素材另取

    # ══ HUD / MatchInfo（对局信息）══
    s.group("MatchInfo", "HUD", 1490, 700, 400, 250)
    s.label("TurnInfo", "HUD/MatchInfo", 4.7, 6, 360, 70, "回合1--先手", 60, "#FFFFFF", bold=True)
    s.label("MapName", "HUD/MatchInfo", 1.2, 88, 200, 44, "地图名", 40, "#FFFFFF", bold=True)
    s.label("SiteEffect", "HUD/MatchInfo", 0.9, 138, 300, 100,
            "场地效果描述-行1\n场地效果描述-行2\n场地效果描述-行3", 30, "#FFFFFF")

    # 玩家名（挂在各自徽章旁 → 归入 Battle/CostBadge* 同级分组 PlayerNames）
    s.group("PlayerNames", "Battle")
    s.label("Left", "Battle/PlayerNames", 136, 66, 220, 48, "玩家名称", 48, "#FFFFFF", bold=True)
    s.label("Right", "Battle/PlayerNames", 1596, 66, 220, 48, "玩家名称", 48, "#FFFFFF", bold=True)

    # 信号连线（场景级，零胶水代码）
    s.conn("HUD/ActionBar/MainButton", "pressed", "_on_main_button_pressed")
    return s


if __name__ == "__main__":
    sc = build()
    cnt = sc.write(OUT)
    print("节点数:", cnt)
