#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""易碎用例归因（迭代159 · 第三轮 S2 / WS7）。

同一套回归跑 N 次，比较每次的**失败集合**：
  · 每次都失败 ⇒ 真失败（不是 flaky）
  · 有的次失败、有的次通过 ⇒ **flaky**（判红，要求归因/隔离，不许静默重跑掩盖）

退出码：0 = 无 flaky；1 = 检测到 flaky；2 = 参数/数据错误。
不接入 `qc all`（要跑多轮，耗时由人显式触发）。
"""
import argparse, sys, xml.etree.ElementTree as ET


def failing(path):
    root = ET.parse(path).getroot()
    out = set()
    for suite in root.iter("testsuite"):
        for tc in suite.findall("testcase"):
            st = (tc.get("status") or "").lower()
            if st in ("fail", "failed", "error"):
                out.add("%s::%s" % (tc.get("classname") or suite.get("name") or "", tc.get("name") or ""))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--junit", required=True, help="逗号分隔的多份 junit")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    paths = [p for p in a.junit.split(",") if p.strip()]
    if len(paths) < 2:
        print("[flaky] 至少需要 2 份 junit（跑 2 轮以上才有意义）")
        return 2
    sets = [failing(p) for p in paths]
    always = set.intersection(*sets) if sets else set()
    anyf = set.union(*sets) if sets else set()
    flips = sorted(anyf - always)
    result = {"runs": len(paths), "always_failing": sorted(always), "flaky": flips}
    import json, os
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    json.dump(result, open(a.out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("[flaky] 跑 %d 轮：真失败 %d 条，flaky %d 条" % (len(paths), len(always), len(flips)))
    for t in flips[:20]:
        print("  - FLAKY: %s" % t)
    return 1 if flips else 0


if __name__ == "__main__":
    sys.exit(main())
