#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""测试健康闸（迭代159 · 第三轮 S2 / WS7）。

判据（全部来自 `qc/config/test_health.json`，可红）：
  1. 最慢用例超过 `slow_budget_ms` ⇒ SLOW_TEST
  2. 整轮超过 `total_budget_ms` ⇒ TOTAL_BUDGET
  3. 隔离名单（quarantine）里每条必须写 reason，且指向**真实存在**的用例 ⇒ QUARANTINE_NO_REASON / QUARANTINE_UNKNOWN

数据源：GUT 的 junit XML（每条 testcase 带 time，单位秒）。
退出码：0 绿 / 1 违规 / 2 参数或数据错误。
"""
import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET


def load_cases(path):
    root = ET.parse(path).getroot()
    cases = []
    for suite in root.iter("testsuite"):
        for tc in suite.findall("testcase"):
            cases.append({
                "file": tc.get("classname") or suite.get("name") or "",
                "test": tc.get("name") or "",
                "ms": int(round(float(tc.get("time") or 0) * 1000)),
                "status": tc.get("status") or "",
            })
    return cases


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--junit", required=True)
    ap.add_argument("--config", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    if not os.path.isfile(a.junit):
        print("[health] 找不到 junit：%s（GUT 未生成）" % a.junit)
        return 2
    cfg = {"slow_budget_ms": 3000, "total_budget_ms": 180000, "quarantine": []}
    if os.path.isfile(a.config):
        cfg.update(json.load(open(a.config, encoding="utf-8-sig")))

    cases = load_cases(a.junit)
    total_ms = sum(c["ms"] for c in cases)
    slowest = max(cases, key=lambda c: c["ms"]) if cases else None

    viol = []
    slow_budget = int(cfg.get("slow_budget_ms", 3000))
    total_budget = int(cfg.get("total_budget_ms", 180000))
    if slowest and slowest["ms"] > slow_budget:
        viol.append({"rule": "SLOW_TEST", "test": "%s::%s" % (slowest["file"], slowest["test"]),
                     "ms": slowest["ms"], "budget_ms": slow_budget,
                     "why": "单条用例耗时超预算（拆用例 / 查是否有真实等待）"})
    if total_ms > total_budget:
        viol.append({"rule": "TOTAL_BUDGET", "ms": total_ms, "budget_ms": total_budget,
                     "why": "整轮回归耗时超预算"})

    known = {"%s::%s" % (c["file"], c["test"]) for c in cases}
    quarantine = cfg.get("quarantine", []) or []
    for q in quarantine:
        key = "%s::%s" % (q.get("file", ""), q.get("test", ""))
        if not str(q.get("reason", "")).strip():
            viol.append({"rule": "QUARANTINE_NO_REASON", "test": key, "why": "隔离必须写 reason（谁判定、凭什么）"})
        if key not in known:
            viol.append({"rule": "QUARANTINE_UNKNOWN", "test": key, "why": "隔离条目指向的用例不存在（陈旧条目应删除）"})

    result = {
        "status": "ok" if not viol else "violations",
        "tests": len(cases),
        "total_ms": total_ms,
        "slowest": slowest,
        "quarantined": len(quarantine),
        "violations": viol,
        "counts": {
            "slowest_ms": slowest["ms"] if slowest else 0,
            "total_ms": total_ms,
            "quarantined": len(quarantine),
            "health_violations": len(viol),
        },
    }
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    json.dump(result, open(a.out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    if slowest:
        print("[health] tests=%d total=%dms slowest=%dms (%s::%s) quarantined=%d"
              % (len(cases), total_ms, slowest["ms"], slowest["file"], slowest["test"], len(quarantine)))
    if viol:
        print("[health] 测试健康违规 %d 处：" % len(viol))
        for v in viol[:10]:
            print("  - %-22s %s" % (v["rule"], str(v.get("test", ""))[:110]))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
