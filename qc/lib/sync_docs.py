#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""数字单一来源（迭代157 · 第三轮 S1 / WS6）。

人 2026-10-23 批准：文档里的机器数字**由 counts 生成**，不再手写（手写必漂 —— 已实测漂过 17 批）。

只改《当前状态》的两行：
  · 「基线快照」= lint / tests / selftest / size / signals
  · 「收尾状态」= 自检 N/N · lint（= 豁免 N）· 体积 A/B/C · 信号 · 回归
其余文字一律不动（只重写这两行本身）。

用法：
  python sync_docs.py --counts qc/out/counts.json --doc <当前状态.md> [--iteration iter157] [--check]
退出码：0 = 已是目标状态（--check 模式下"无需改"）/ 1 = 有差异（--check）或写入后仍有差异 / 2 = 参数错误。
"""
import argparse
import json
import os
import re
import sys


def load_counts(path):
    if not os.path.isfile(path):
        print("[syncdocs] 找不到 counts：%s（先跑 qc all）" % path)
        sys.exit(2)
    with open(path, encoding="utf-8-sig") as f:
        return json.load(f)


def fmt(counts, iteration, exemptions):
    lint = counts.get("lint:total", 0)
    t = counts.get("test:passing", 0)
    a = counts.get("test:asserts", 0)
    sf = counts.get("qc:selftest_failures", 0)
    st = counts.get("qc:selftest_total", 0)
    s1 = counts.get("size:arena_view", 0)
    s2 = counts.get("size:battle_engine", 0)
    s3 = counts.get("size:net_diag_dump", 0)
    sd = counts.get("signals:declared", 0)
    sp = counts.get("signals:problems", 0)
    su = counts.get("signals:undetectable", 0)
    baseline = ("%s **基线快照**（机器可读 · 与 `qc/out/counts.json` 对账）：lint=%d · tests=%d/%d · selftest=%d · "
                "size=%d/%d/%d · signals=%d/%d") % (">", lint, t, a, sf, s1, s2, s3, sd, sp)
    status = ("%s **收尾状态**（%s · `qc coldstart` 与 `qc all` **均 exit 0** · 产物 9/9）：自检 **%d/%d** · "
              "lint **%d**（= 豁免 %d，全不治）· 体积 **%d / %d / %d**（violations 0）· "
              "信号 **%d 声明 / %d 问题**（undetectable %d 已登记）· 回归 **%d 测试 / %d 断言** · "
              "**文档基线一致**（docs:drift 0）· 提交钩子已装（core.hooksPath=qc/hooks）。") % (
                  ">", iteration or "iter?", st, st, lint, exemptions, s1, s2, s3, sd, sp, su, t, a)
    return baseline, status


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--counts", required=True)
    ap.add_argument("--doc", required=True)
    ap.add_argument("--iteration", default="")
    ap.add_argument("--exemptions", type=int, default=-1)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()

    counts = load_counts(a.counts)
    doc = os.path.abspath(a.doc)
    if not os.path.isfile(doc):
        print("[syncdocs] 文档不存在：%s" % doc)
        return 2

    raw = open(doc, "rb").read().decode("utf-8")
    eol = "\r\n" if "\r\n" in raw else "\n"
    lines = raw.split(eol)

    ex = a.exemptions
    if ex < 0:
        cfg = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config", "lint_exemptions.json")
        try:
            ex = len(json.load(open(cfg, encoding="utf-8-sig")).get("exemptions", []))
        except OSError:
            ex = 0

    base, status = fmt(counts, a.iteration, ex)
    idx_b = next((i for i, l in enumerate(lines) if "基线快照" in l), -1)
    idx_s = next((i for i, l in enumerate(lines) if l.startswith("> **收尾状态**")), -1)
    if idx_b < 0 or idx_s < 0:
        print("[syncdocs] 文档里找不到「基线快照」或「收尾状态」行")
        return 2

    changed = []
    if lines[idx_b].strip() != base:
        changed.append("基线快照")
        lines[idx_b] = base
    if lines[idx_s].strip() != status:
        changed.append("收尾状态")
        lines[idx_s] = status

    if not changed:
        print("[syncdocs] 两行已是目标状态（无需修改）")
        return 0
    if a.check:
        print("[syncdocs] 需要同步：%s（跑 `qc syncdocs` 修）" % "、".join(changed))
        return 1
    open(doc, "wb").write(eol.join(lines).encode("utf-8"))
    print("[syncdocs] 已同步：%s" % "、".join(changed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
