"""区域级像素比对：把设计稿基准与我方渲染的同一区域并排放大，便于逐个组件判断映射是否合适"""
from PIL import Image
import sys, os

REF = "C:/Users/27194/AppData/Local/Temp/base_ref_ok.png"
MINE = sys.argv[1] if len(sys.argv) > 1 else "C:/Users/27194/AppData/Local/Temp/semantic_ui2.png"


def crop_pair(name, box, zoom=2, outdir="C:/Users/27194/AppData/Local/Temp/cmp"):
    os.makedirs(outdir, exist_ok=True)
    x, y, w, h = box
    ref = Image.open(REF).convert("RGB").crop((x, y, x + w, y + h))
    mine_full = Image.open(MINE).convert("RGB")
    sx, sy = mine_full.width / 1920.0, mine_full.height / 1080.0
    mine = mine_full.crop((int(x * sx), int(y * sy), int((x + w) * sx), int((y + h) * sy)))
    mine = mine.resize(ref.size, Image.LANCZOS)
    z = (int(w * zoom), int(h * zoom))
    ref_z = ref.resize(z, Image.NEAREST); mine_z = mine.resize(z, Image.NEAREST)
    sheet = Image.new("RGB", (z[0], z[1] * 2 + 8), (255, 0, 255))
    sheet.paste(ref_z, (0, 0)); sheet.paste(mine_z, (0, z[1] + 8))
    p = os.path.join(outdir, name + ".png")
    sheet.save(p)
    # 数值差异
    import numpy as np
    a = np.asarray(ref).astype(int); b = np.asarray(mine).astype(int)
    nd = (np.abs(a - b).max(axis=2) > 24).sum()
    print("%-22s 区域%dx%d  显著差异像素=%d (%.2f%%)  → %s" % (name, w, h, nd, 100 * nd / (w * h), p))


if __name__ == "__main__":
    # 逐区：区域名，[x, y, w, h]，放大倍数
    REGIONS = [
        ("1_地图板与外框", [440, 20, 360, 300], 2),
        ("2_费用徽章与玩家名", [20, 20, 340, 140], 2),
        ("3_手牌区左上角", [20, 140, 260, 200], 2),
        ("4_左下信息面板", [20, 560, 420, 500], 1),
        ("5_主按钮与右段", [1470, 560, 440, 130], 1),
        ("6_功能按钮组", [1520, 940, 400, 120], 1),
        ("7_右侧文字区", [1470, 690, 440, 260], 1),
    ]
    for nm, box, z in REGIONS:
        crop_pair(nm, box, z)
