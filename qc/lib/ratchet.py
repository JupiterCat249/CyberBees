#!/usr/bin/env python3
"""棘轮：把本次各闸的计数与基线比较，只降不升。

方向约定（判据固定，不做智能判断）：
  · key 以 "test:" 开头  → 越高越好（覆盖率类）
  · 其余                  → 越低越好（债务类）

用法：
  ratchet.py --baseline qc/baseline.json --current qc/out/counts.json --update --iteration iter068
  --update 只在「无上升项」时写回；有上升项一律拒绝写。
"""
import argparse, datetime, json, os, sys

def load(path, default):
    if not os.path.isfile(path):
        return default
    with open(path, encoding="utf-8-sig") as f:
        return json.load(f)

UP_KEYS = ("test:passing",)
# 参考类：随实现自然增减，不参与棘轮判定（否则"删掉一个死信号"会被误判成覆盖率下降）
# arch:type_cycles 原为参考类；人 2026-10-22 裁定"类型环必须治理" → 转为棘轮指标（越低越好）
## info = 只记录、不判升降的指标（"变大"本身不是债务）
##   ⚠️ 新增 info 项必须同时说明理由：测试文件数/脚本数会随覆盖增长；断言数同理。
INFO_KEYS = ("test:asserts", "signals:declared", "signals:undetectable",
             "test:scripts_loaded", "test:scripts_on_disk", "qc:selftest_total", "size:warn_files",
             ## 体积趋势指标（迭代145 改 info）：硬上限由 size 闸（code 口径）守；
             ##   合法功能开发会让代码增长，趋势只做看板、不再当作债务。
             "size:arena_view", "size:battle_engine", "size:net_diag_dump",
             "size:max_lines", "size:max_bytes")

def direction(key):
    if key in INFO_KEYS:
        return "info"
    # 覆盖类指标越高越好；其余（含 test:failures）越低越好
    return "up" if key in UP_KEYS else "down"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--current", required=True)
    ap.add_argument("--iteration", default="")
    ap.add_argument("--update", action="store_true")
    a = ap.parse_args()

    cur = load(a.current, {})
    base_doc = load(a.baseline, {"iteration": "", "updated": "", "counts": {}, "history": []})
    base = base_doc.get("counts", {})
    # 首次建立基线：此时没有"上一版"可比较，全部计数直接冻结（不判上升，否则永远建不起来）
    bootstrap = not base

    rows, worse, better = [], [], []
    for key in sorted(set(cur) | set(base)):
        c = int(cur.get(key, 0))
        b = int(base.get(key, 0))
        d = direction(key)
        delta = c - b
        if key not in base:
            # 新引入的指标：没有"上一版"可比 → 记为 new（既不是改善也不是退化），
            # 由 snapshot 冻结进基线。删除式作弊仍会被抓（base 有、current 缺 → count 0）。
            rows.append((key, b, c, delta, "new"))
            continue
        if d == "info":
            status = "info"
        elif d == "down":
            status = "same" if delta == 0 else ("BETTER" if delta < 0 else "WORSE")
        else:
            status = "same" if delta == 0 else ("BETTER" if delta > 0 else "WORSE")
        rows.append((key, b, c, delta, status))
        if status == "WORSE" and not bootstrap:
            worse.append((key, b, c))
        elif status == "BETTER":
            better.append((key, b, c))

    print("%-34s %6s %6s %7s" % ("metric", "base", "now", "delta"))
    print("-" * 60)
    for key, b, c, delta, status in rows:
        mark = {"same": "", "BETTER": "<-", "WORSE": "!!", "info": "i", "new": "?"}[status]
        print("%-34s %6d %6d %+7d  %s" % (key, b, c, delta, mark))

    if bootstrap:
        print("")
        print("[bootstrap] 首次建立基线：%d 个指标被冻结（不计上升项）。" % len(cur))
    elif worse:
        print("")
        print("[FAIL] 出现上升项 %d 个 —— 棘轮拒绝通过：" % len(worse))
        for key, b, c in worse:
            print("  + %s: %d -> %d" % (key, b, c))
    else:
        print("")
        print("[OK] 无上升项；改善 %d 项。" % len(better) if better else "[OK] 无上升项，也无改善。")

    if a.update:
        if worse:
            print("[skip] 有上升项，基线不写回。")
            return 1
        doc = {
            "iteration": a.iteration or base_doc.get("iteration", ""),
            "updated": datetime.date.today().isoformat(),
            "counts": cur,
            "history": (base_doc.get("history") or []) + [{
                "iteration": a.iteration or base_doc.get("iteration", ""),
                "date": datetime.date.today().isoformat(),
                "counts": cur,
            }],
        }
        os.makedirs(os.path.dirname(a.baseline), exist_ok=True)
        with open(a.baseline, "w", encoding="utf-8") as f:
            json.dump(doc, f, ensure_ascii=False, indent=2, sort_keys=True)
        print("[written] baseline <- %s" % a.baseline)
        return 0
    return 1 if worse else 0

if __name__ == "__main__":
    sys.exit(main())
