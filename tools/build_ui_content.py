"""迭代048：UI 内容填充（依 `横版UI填充.svg` 为最高标准，策划案为补充）

设计原则（人明确）：
  · **最简**：能复用 API 就复用，少写代码；一个组件解决时不建系统
  · **为未来适配**：地图可切换、战斗界面可切主菜单 → 用「场景 = 自包含单元」+ 参数入口
  · **依 SVG**：尺寸/颜色/构成严格取自填充稿实测
  · 节点优先：能靠节点表达的不写脚本；脚本只做「内容绑定」这类节点做不到的事

产出：
  scenes/ui/card_unit.tscn   250×250 地图单位卡（可复用组件）
  scenes/ui/card_hand.tscn   200×200 手牌卡（可复用组件）
  scenes/ui/menu_main.tscn   主菜单（最小可玩入口）
  scenes/ui/level_battle.tscn 战斗关卡（自包含：背景/棋盘/手牌/单位/玩家状态/HUD）
"""
import io, os

C = {  # 取自填充稿实测与策划案 §五 颜色图鉴
    "bg": "#666666", "hand_slot": "#00000080", "board": "#999999", "frame": "#FFFFFF80",
    "unit": "#FFFFFF", "queen": "#FFD07E", "building": "#DDC29B", "order": "#D9D9D9",
    "red": "#A84331", "green": "#3B816D", "cost_orange": "#FFA300",
    "cost_plate": "#353535", "inner_stroke": "#00000033", "green_btn": "#499169",
    "func_btn": "#FFFFFF80", "func_line": "#FFFFFF1A", "detail": "#333333",
    "white": "#FFFFFF",
}
FONTS = 'PackedStringArray("Noto Sans SC", "Source Han Sans CN", "Microsoft YaHei")'
Z = "res://assets/ui/zip_original/"
ATTR = ["res://assets/ui/zip_original/attr_attack_80.png", "res://assets/ui/zip_original/attr_health_80.png",
        "res://assets/ui/zip_original/attr_speed_80.png", "res://assets/ui/zip_original/attr_range_80.png"]


def col(c):
    h = c.lstrip("#")
    r, g, b = int(h[0:2], 16)/255.0, int(h[2:4], 16)/255.0, int(h[4:6], 16)/255.0
    a = int(h[6:8], 16)/255.0 if len(h) >= 8 else 1.0
    return "Color(%.6f, %.6f, %.6f, %.6f)" % (r, g, b, a)


def n(v):
    s = "%.2f" % v
    return s.rstrip("0").rstrip(".") if "." in s else s


class Scn:
    def __init__(self, name, w=1920, h=1080, script=None):
        self.name, self.w, self.h, self.script = name, w, h, script
        self.subs, self.exts, self.nodes, self.conns = [], {}, [], []

    def _sid(self, tag, body):
        for t, b, sid in self.subs:
            if (t, b) == (tag, tuple(body)):
                return sid
        sid = "R%d" % (len(self.subs)+1)
        self.subs.append((tag, body, sid))
        return sid

    def sb(self, bg, radius=0, bw=0, bc=None, center=True):
        b = []
        if not center:
            b.append("draw_center = false")
        b.append("bg_color = %s" % col(bg))
        if radius:
            r = int(round(radius))
            b += ["corner_radius_top_left = %d" % r, "corner_radius_top_right = %d" % r,
                  "corner_radius_bottom_right = %d" % r, "corner_radius_bottom_left = %d" % r]
        if bw and bc:
            w = max(1, int(round(bw)))
            b += ["border_width_left = %d" % w, "border_width_top = %d" % w,
                  "border_width_right = %d" % w, "border_width_bottom = %d" % w,
                  "border_color = %s" % col(bc)]
        return self._sid("StyleBoxFlat", b)

    def font(self, bold=False):
        return self._sid("SystemFont", ["font_names = " + FONTS] + (["font_weight = 700"] if bold else []))

    def ext(self, p):
        if p not in self.exts:
            self.exts[p] = "x%d" % (len(self.exts)+1)
        return self.exts[p]

    def add(self, nm, ty, par, props):
        self.nodes.append((nm, ty, par, props))

    def grp(self, nm, par, x=0, y=0, w=1, h=1, ty="Control"):
        self.add(nm, ty, par, [("offset_left", n(x)), ("offset_top", n(y)),
                               ("offset_right", n(x+w)), ("offset_bottom", n(y+h)),
                               ("mouse_filter", "2")])

    def rect(self, nm, ty, par, x, y, w, h, **kw):
        box = kw.pop("box", None)
        sid = self.sb(kw.pop("bg", "#00000000"), kw.pop("radius", 0), kw.pop("bw", 0), kw.pop("bc", None),
                      kw.pop("center", True))
        props = [("offset_left", n(x)), ("offset_top", n(y)),
                 ("offset_right", n(x+w)), ("offset_bottom", n(y+h))]
        if box == "Raw":
            props = [("position", "Vector2(%s, %s)" % (n(x), n(y))), ("size", "Vector2(%s, %s)" % (n(w), n(h)))]
        props += [("mouse_filter", str(kw.pop("mouse", 2)))]
        if ty == "Panel":
            props.append(("theme_override_styles/panel", 'SubResource("%s")' % sid))
        self.add(nm, ty, par, props + [(k, str(v)) for k, v in kw.items()])

    def tex(self, nm, par, x, y, w, h, path, stretch=0, tile=False, color=None):
        eid = self.ext(path)
        pr = [("offset_left", n(x)), ("offset_top", n(y)),
              ("offset_right", n(x+w)), ("offset_bottom", n(y+h)), ("mouse_filter", "2"),
              ("texture", 'ExtResource("%s")' % eid), ("expand_mode", "1"), ("stretch_mode", str(stretch))]
        if tile:
            pr.append(("texture_repeat", "1"))
        if color:
            pr.append(("modulate", col(color)))
        self.add(nm, "TextureRect", par, pr)

    def label(self, nm, par, x, y, w, h, text, fs, color, align="left", bold=False, valign="1"):
        self.add(nm, "Label", par, [("offset_left", n(x)), ("offset_top", n(y)),
                                    ("offset_right", n(x+w)), ("offset_bottom", n(y+h)),
                                    ("mouse_filter", "2"),
                                    ("theme_override_fonts/font", 'SubResource("%s")' % self.font(bold)),
                                    ("theme_override_font_sizes/font_size", str(int(fs))),
                                    ("theme_override_colors/font_color", col(color)),
                                    ("horizontal_alignment", {"left": "0", "center": "1", "right": "2"}[align]),
                                    ("vertical_alignment", valign),
                                    ("text", '"%s"' % text)])

    def button(self, nm, par, x, y, w, h, text, fs, bg, fg, radius=10, bold=True):
        self.add(nm, "Button", par, [("offset_left", n(x)), ("offset_top", n(y)),
                                     ("offset_right", n(x+w)), ("offset_bottom", n(y+h)),
                                     ("mouse_default_cursor_shape", "2"),
                                     ("theme_override_fonts/font", 'SubResource("%s")' % self.font(bold)),
                                     ("theme_override_font_sizes/font_size", str(int(fs))),
                                     ("theme_override_colors/font_color", col(fg)),
                                     ("theme_override_styles/normal", 'SubResource("%s")' % self.sb(bg, radius)),
                                     ("theme_override_styles/hover", 'SubResource("%s")' % self.sb("#8A8A8A", radius)),
                                     ("theme_override_styles/pressed", 'SubResource("%s")' % self.sb("#7D7D7D", radius)),
                                     ("text", '"%s"' % text)])

    def conn(self, frm, sig, meth):
        self.conns.append('[connection signal="%s" from="%s" to="." method="%s"]' % (sig, frm, meth))

    def write(self, path):
        LS = len(self.exts) + len(self.subs) + 2
        L = ["[gd_scene load_steps=%d format=3]" % LS, ""]
        for p, i in self.exts.items():
            L.append('[ext_resource type="Texture2D" path="%s" id="%s"]' % (p, i))
        if self.script:
            L.append('[ext_resource type="Script" path="%s" id="s1"]' % self.script)
        L.append("")
        for tag, body, sid in self.subs:
            L.append('[sub_resource type="%s" id="%s"]' % (tag, sid))
            L += body
            L.append("")
        rp = ["layout_mode = 3", "anchors_preset = 0"]
        if self.w:
            rp += ["offset_right = %s" % n(self.w), "offset_bottom = %s" % n(self.h)]
        if self.script:
            rp.append('script = ExtResource("s1")')
        L += ['[node name="%s" type="Control"]' % self.name] + rp
        for nm, ty, par, pr in self.nodes:
            L.append("")
            L.append('[node name="%s" type="%s" parent="%s"]' % (nm, ty, par))
            for k, v in pr:
                L.append("%s = %s" % (k, str(v)))
        for c in self.conns:
            L.append("")
            L.append(c)
        L.append("")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(L))
        return len(self.nodes)


# ══════════════════════════════════════════════════════════
# ① 地图单位卡 250×250（填充稿实测）
# ══════════════════════════════════════════════════════════
def build_unit_card():
    s = Scn("UnitCard", 250, 250)
    s.rect("Body", "Panel", ".", 0, 0, 250, 250, bg=C["unit"], radius=10)
    s.rect("SideLeft", "Panel", ".", 0, 0, 40, 250, bg=C["green"], radius=10)
    s.rect("SideRight", "Panel", ".", 210, 0, 40, 250, bg=C["green"], radius=10)
    s.rect("CostPlate", "Panel", ".", 0, 0, 40, 40, bg=C["cost_plate"])
    s.label("Cost", ".", 0, 0, 40, 40, "0", 26, C["white"], "center")
    s.grp("Artwork", ".", 47, 8, 155.83, 233)
    s.rect("Art", "Panel", "Artwork", 0, 0, 155.83, 233, bg="#3A3A3A")   # 立绘占位（待接素材：填入 TextureRect 即可）
    # 四维属性：40×40 数值格 + 40×40 图标格（左列攻击/血量，右列移动/射程）
    for side, cx in (("L", 0), ("R", 210)):
        for i, (tag, yy) in enumerate((("A", 65), ("B", 105), ("C", 160), ("D", 200))):
            idx = {"LA": 0, "LB": 1, "LC": 2, "LD": 3, "RA": 0, "RB": 1, "RC": 2, "RD": 3}["%s%s" % (side, tag)]
            s.grp("Attr%s%s" % (side, tag), ".", cx, yy, 40, 40)
            s.rect("ValueCell", "Panel", "Attr%s%s" % (side, tag), 0, 0, 40, 40, bg="#FFFFFFCC")
            s.label("Value", "Attr%s%s" % (side, tag), 0, 4, 40, 32, "0", 24, "#222222", "center")
            s.tex("Icon", "Attr%s%s" % (side, tag), 0, 40, 40, 40, ATTR[idx], color="#222222")
    s.rect("InnerLine", "Panel", ".", 1, 1, 248, 248, bg="#00000000", radius=9, bw=2,
           bc=C["inner_stroke"], center=False)
    return s


# ══════════════════════════════════════════════════════════
# ② 手牌卡 200×200（填充稿实测）
# ══════════════════════════════════════════════════════════
def build_hand_card():
    s = Scn("HandCard", 200, 200)
    s.rect("Body", "Panel", ".", 0, 0, 200, 200, bg=C["unit"], radius=10)
    s.grp("Artwork", ".", 10, 10, 180, 180)
    s.rect("Art", "Panel", "Artwork", 0, 0, 180, 180, bg="#3A3A3A")   # 插画占位（待接素材：填入 TextureRect 即可）
    s.rect("CostPlate", "Panel", ".", 2, 18, 23, 33, bg=C["white"])
    s.label("Cost", ".", 2, 18, 23, 33, "0", 20, "#111111", "center")
    s.rect("InnerLine", "Panel", ".", 2, 2, 196, 196, bg="#00000000", radius=8, bw=4,
           bc="#333333", center=False)
    return s


# ══════════════════════════════════════════════════════════
# ③ 战斗关卡（自包含单元；地图可换、可返回主菜单）
# ══════════════════════════════════════════════════════════
def build_level_battle():
    s = Scn("LevelBattle", 1920, 1080, script="res://scenes/ui/level_battle.gd")
    s.rect("Background", "Panel", ".", 0, 0, 1920, 1080, bg=C["bg"])
    # ── 棋盘（地图切换就换这里的贴图/名称）──
    s.grp("Board", ".", 459, 40, 1000, 1000)
    s.rect("Plate", "Panel", "Board", 0, 0, 1000, 1000, bg=C["board"], radius=10)
    s.tex("Terrain", "Board", 0, 0, 1000, 1000, Z + "map_mask_2020.png")
    s.rect("Outline", "Panel", "Board", -2, -2, 1004, 1004, bg="#00000000", radius=12, bw=4,
           bc=C["frame"], center=False)
    s.grp("Units", "Board", 0, 0, 1000, 1000)      # 运行时挂单位卡
    s.grp("Cells", "Board", 0, 0, 1000, 1000)      # 运行时挂地图格状态
    # ── 敌方（上）：手牌区 + 费用/玩家名 ──
    s.grp("SideEnemy", ".", 0, 0, 1920, 560)
    s.rect("HandSlot", "Panel", "SideEnemy", 30, 150, 400, 400, bg=C["hand_slot"], radius=10)
    s.grp("Hand", "SideEnemy", 30, 150, 400, 400)
    s.grp("CostBadge", "SideEnemy", 36.7, 41.7, 90, 99)
    s.tex("Badge", "SideEnemy/CostBadge", 0, 0, 87.8, 99.8, Z + "cost_badge_200.png")
    s.label("Value", "SideEnemy/CostBadge", 26, 2, 34, 94, "0", 65, C["white"], "center", True)
    s.label("Name", "SideEnemy", 136, 64, 240, 48, "玩家名称", 51, C["white"], bold=True)
    # ── 我方（下）：手牌区 + 费用/玩家名 ──
    s.grp("SidePlayer", ".", 1490, 150, 400, 400)
    s.rect("HandSlot", "Panel", "SidePlayer", 0, 0, 400, 400, bg=C["hand_slot"], radius=10)
    s.grp("Hand", "SidePlayer")
    s.grp("CostBadge", ".", 1496.7, 41.7, 90, 99)
    s.tex("Badge", "CostBadge", 0, 0, 87.8, 99.8, Z + "cost_badge_200.png")
    s.label("Value", "CostBadge", 26, 2, 34, 94, "0", 65, C["white"], "center", True)
    s.label("Name", ".", 1596, 64, 240, 48, "玩家名称", 51, C["white"], bold=True)
    # ── 左下：卡牌详情 ──
    s.grp("CardInfo", ".", 30, 570, 400, 470)
    s.label("CardName", "CardInfo", 1.8, 4, 260, 52, "卡牌名称", 38, C["white"], bold=True)
    s.label("SkillDesc", "CardInfo", 0.9, 56, 300, 100,
            "技能描述-行1\n技能描述-行2\n技能描述-行3", 25, C["white"])
    s.rect("Detail", "Panel", "CardInfo", 0, 170, 300, 300, bg=C["detail"], radius=10)
    s.rect("DetailLine", "Panel", "CardInfo", 2, 172, 296, 296, bg="#00000000", radius=8, bw=4,
           bc="#000000", center=False)
    s.grp("Artwork", "CardInfo", 0, 170, 300, 300)
    # 四维数值（数值 + 图标）
    for i, yy in enumerate((0, 60, 120, 180)):
        s.grp("Attr%d" % (i+1), ".", 298.6, 780+yy, 120, 40)
        s.label("Value", "Attr%d" % (i+1), 0, 4, 46, 32, "0", 27, C["white"], "center")
        s.tex("Icon", "Attr%d" % (i+1), 46, 0, 40, 40, ATTR[i], color="#222222")
    # ── 右下：主按钮 + 对局信息 + 功能键 ──
    s.button("MainButton", ".", 1490, 570, 400, 100, "完成部署", 42, C["green_btn"], C["white"])
    s.rect("MainButtonLine", "Panel", ".", 1492, 572, 396, 96, bg="#00000000", radius=8, bw=4,
           bc=C["func_line"], center=False)
    s.grp("MatchInfo", ".", 1490, 700, 400, 250)
    s.label("TurnInfo", "MatchInfo", 4.7, 2, 360, 40, "回合6--先手", 32, C["white"], bold=True)
    s.label("MapName", "MatchInfo", 1.2, 88, 200, 40, "丰饶", 37, C["white"], bold=True)
    s.label("SiteEffect", "MatchInfo", 0.9, 138, 320, 100,
            "场地效果：第3、9回合玩家额外回复4点费用", 26, C["white"])
    for i, nm in enumerate(("Settings", "Emote", "Info", "Back")):
        bx = 1540 + i*90
        s.button(nm, ".", bx, 960, 80, 80, "", 1, C["func_btn"], C["white"])
        s.rect(nm + "Line", "Panel", ".", bx+2, 962, 76, 76, bg="#00000000", radius=8, bw=4,
               bc=C["func_line"], center=False)
        s.tex(nm + "Icon", ".", bx, 960, 80, 80, "res://assets/ui/func_icons/func_%d_%s.png"
              % (i+1, ("settings", "emote", "info", "back")[i]))
    s.conn("MainButton", "pressed", "_on_main_button_pressed")
    s.conn("Back", "pressed", "_on_back_pressed")
    return s


# ══════════════════════════════════════════════════════════
# ④ 主菜单（最小可玩入口）
# ══════════════════════════════════════════════════════════
def build_menu_main():
    s = Scn("MenuMain", 1920, 1080, script="res://scenes/ui/menu_main.gd")
    s.rect("Background", "Panel", ".", 0, 0, 1920, 1080, bg=C["bg"])
    s.label("Title", ".", 0, 220, 1920, 120, "电子蜂", 96, C["white"], "center", bold=True)
    s.label("Subtitle", ".", 0, 350, 1920, 60, "A5 · 4×4 格战术卡牌对战", 34, "#DDDDDD", "center")
    s.button("StartButton", ".", 760, 540, 400, 100, "开始对战", 42, C["green_btn"], C["white"])
    s.button("DeckButton", ".", 760, 660, 400, 80, "卡组", 34, "#999999", C["white"])
    s.button("SettingsButton", ".", 760, 760, 400, 80, "设置", 34, "#999999", C["white"])
    s.button("QuitButton", ".", 760, 860, 400, 80, "退出", 34, "#999999", C["white"])
    s.conn("StartButton", "pressed", "_on_start_pressed")
    s.conn("QuitButton", "pressed", "_on_quit_pressed")
    return s


if __name__ == "__main__":
    for nm, sc in (("card_unit.tscn", build_unit_card()), ("card_hand.tscn", build_hand_card()),
                   ("level_battle.tscn", build_level_battle()), ("menu_main.tscn", build_menu_main())):
        print("%-22s 节点 %d" % (nm, sc.write("Godot版Games代码/电子蜂/scenes/ui/" + nm)))
