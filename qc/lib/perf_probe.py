#!/usr/bin/env python3
"""perf —— 性能读数基线（G4 批次3 · 迭代171）

读数来源：GUT 的 junit XML（qc test 每次都会写），不额外跑 Godot。
做法：
  · 首次运行：把当前每个用例耗时与总耗时写成基线（qc/config/perf_baseline.json）；
  · 之后：总耗时超过基线 ×(1+tolerance) 记 regression；单用例超过 ×(1+2*tolerance) 记 warn；
  · mode=info（默认）只报告不判红；mode=strict 时 regression 判红。
用法：perf.py --junit qc/out/gut.junit.xml --config qc/config/perf.json --baseline qc/config/perf_baseline.json [--update] [--out qc/out/perf.json]
退出码：0 通过/仅 info；1 strict 且有 regression；2 环境缺失
"""
import argparse, datetime, json, os, sys
import xml.etree.ElementTree as ET

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def load(path, default=None):
    try:
        with open(path, encoding="utf-8-sig") as f:
            return json.load(f)
    except Exception:
        return default


def parse_junit(path):
    tree = ET.parse(path)
    tests = {}
    total = 0.0
    for tc in tree.iter("testcase"):
        name = "%s::%s" % (tc.get("classname", ""), tc.get("name", ""))
        try:
            t = float(tc.get("time", "0") or 0)
        except ValueError:
            t = 0.0
        tests[name] = round(t, 4)
        total += t
    return tests, round(total, 3)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--junit", required=True)
    ap.add_argument("--config", required=True)
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--update", action="store_true")
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    if not os.path.isfile(a.junit):
        print("[perf] 找不到 junit：%s（先跑 qc test / qc all）" % a.junit)
        return 2
    cfg = {"tolerance": 0.35, "mode": "info"}
    if os.path.isfile(a.config):
        cfg.update(load(a.config, {}))
    tests, total = parse_junit(a.junit)
    base = load(a.baseline, None)
    today = datetime.date.today().isoformat()

    if base is None or a.update:
        payload = {"updated": today, "total_s": total, "tests": tests}
        with open(a.baseline, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=1)
        print("[perf] 基线已写：total %.2fs · %d 用例 · %s" % (total, len(tests), a.baseline))
        if a.out:
            json.dump({"ok": True, "baseline_written": True, "total_s": total,
                       "counts": {"perf:total_s": total, "perf:cases": len(tests)}},
                      open(a.out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        return 0

    tol = float(cfg.get("tolerance", 0.35))
    base_total = float(base.get("total_s", 0) or 0)
    regressions, warns = [], []
    limit = base_total * (1 + tol)
    if base_total > 0 and total > limit:
        regressions.append("总耗时 %.2fs > 基线 %.2fs ×%.2f" % (total, base_total, 1 + tol))
    for name, t in tests.items():
        bt = float(base.get("tests", {}).get(name, 0) or 0)
        if bt > 0 and t > bt * (1 + 2 * tol):
            warns.append("%s %.3fs > 基线 %.3fs" % (name, t, bt))

    strict = str(cfg.get("mode", "info")).lower() == "strict"
    ok = not (strict and regressions)
    counts = {"perf:total_s": total, "perf:regressions": len(regressions), "perf:warns": len(warns)}
    print("[perf] 总耗时 %.2fs（基线 %.2fs，容差 %.0f%%，mode=%s）· regression %d · warn %d"
          % (total, base_total, tol * 100, cfg.get("mode", "info"), len(regressions), len(warns)))
    for r in regressions:
        print("  [%s] %s" % ("VIOLATION" if strict else "info", r))
    for w in warns[:8]:
        print("  [warn] " + w)
    if a.out:
        json.dump({"ok": ok, "counts": counts, "total_s": total, "baseline_total_s": base_total,
                   "regressions": regressions, "warns": warns},
                  open(a.out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
