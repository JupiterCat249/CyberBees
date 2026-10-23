#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""变异测试（迭代163 · 第三轮 S4 / WS2）。

回答一个断言数量回答不了的问题：**这些断言真的能抓错吗？**

做法（全部由本脚本完成，跑完**必定还原**）：
  1. 在核心模块里定点变异一处（比较符 / 布尔 / 加减 / 返回常量）；
  2. 跑回归；若回归变红 -> 该变异被"杀死"（说明有断言能抓到这个错）；
  3. 若全绿 -> "存活"（说明这段逻辑没有被有效断言覆盖）—— 记入 survivors；
  4. 分数 = 杀死数 / 总数，与 config 的 min_score 比较（默认 60%，只升）。

不进 `qc all`（耗时 ~20s × 变异数），由人/批次显式触发。
退出码：0 达标 / 1 未达标 / 2 环境错误。
"""
import argparse, json, os, re, subprocess, sys, time

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

OPS = [
    ("==", "!="), ("!=", "=="), (">=", ">"), ("<=", "<"),
    ("true", "false"), ("false", "true"),
    (" + ", " - "), (" - ", " + "),
    ("return 0", "return 1"), ("return 1", "return 0"), ("return true", "return false"),
]
SKIP = re.compile(r"^\s*(#|##|@|\[)")


def gen_mutants(repo, targets, cap):
    out = []
    for rel in targets:
        p = os.path.join(repo, rel)
        if not os.path.isfile(p):
            continue
        lines = open(p, encoding="utf-8").read().split("\n")
        for i, ln in enumerate(lines):
            if SKIP.match(ln) or not ln.strip():
                continue
            for old, new in OPS:
                if old in ln:
                    out.append({"file": rel, "line": i, "old": old, "new": new,
                                "text": ln.strip()[:100]})
                    break
            if len(out) >= cap:
                return out
    return out


def run_suite(repo, godot):
    r = subprocess.run([godot, "--headless", "--path", repo,
                        "-s", "addons/gut/gut_cmdln.gd", "-gdir=res://tests", "-gexit"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    txt = (r.stdout or "") + (r.stderr or "")
    m = re.search(r"Failing Tests\s+(\d+)", txt)
    failing = int(m.group(1)) if m else -1
    p = re.search(r"Passing Tests\s+(\d+)", txt)
    passing = int(p.group(1)) if p else -1
    return {"rc": r.returncode, "failing": failing, "passing": passing}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--config", required=True)
    ap.add_argument("--godot", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-mutants", type=int, default=0)
    ap.add_argument("--dry-run", action="store_true", help="只列出变异体，不跑回归")
    ap.add_argument("--simulate", default="", help="测试用：JSON 数组模拟 results，只做打分")
    a = ap.parse_args()
    repo = os.path.abspath(a.repo)
    cfg = {"targets": ["src/battle/rules_combat.gd", "src/data/unit_instance.gd"],
           "max_mutants": 8, "min_score": 60}
    if os.path.isfile(a.config):
        cfg.update(json.load(open(a.config, encoding="utf-8-sig")))
    cap = a.max_mutants or int(cfg.get("max_mutants", 8))

    if a.simulate:
        results = json.loads(a.simulate)
        mutants = [{"file": "sim", "line": 0, "old": "", "new": "", "text": "sim"}] * len(results)
    else:
        mutants = gen_mutants(repo, cfg.get("targets", []), cap)
        if not mutants:
            print("[mut] 没有可变异点（检查 targets）")
            return 2

    if a.dry_run:
        for m in mutants:
            print("  %s:%d  %s -> %s   | %s" % (m["file"], m["line"] + 1, m["old"], m["new"], m["text"]))
        print("[mut] 共 %d 个变异体（dry-run，未执行）" % len(mutants))
        return 0

    results = []
    t0 = time.time()
    for idx, m in enumerate(mutants):
        if a.simulate:
            r = results_sim = json.loads(a.simulate)[idx]
            killed = bool(r.get("killed"))
            results.append({"mutant": m, "killed": killed, "detail": r})
            continue
        p = os.path.join(repo, m["file"])
        raw = open(p, "rb").read()
        text = raw.decode("utf-8")
        lines = text.split("\n")
        original_line = lines[m["line"]]
        lines[m["line"]] = original_line.replace(m["old"], m["new"], 1)
        open(p, "wb").write("\n".join(lines).encode("utf-8"))
        try:
            res = run_suite(repo, a.godot)
        finally:
            open(p, "wb").write(raw)
        killed = res["failing"] != 0
        results.append({"mutant": m, "killed": killed, "detail": res})
        print("[mut] %d/%d %s:%d %s->%s -> %s" % (idx + 1, len(mutants), m["file"], m["line"] + 1,
                                                   m["old"], m["new"], "KILLED" if killed else "SURVIVED"))

    total = len(results)
    killed_n = sum(1 for r in results if r["killed"])
    score = round(100.0 * killed_n / max(1, total), 1)
    survivors = [r["mutant"] for r in results if not r["killed"]]
    out = {"total": total, "killed": killed_n, "score": score,
           "min_score": cfg.get("min_score", 60), "elapsed_s": round(time.time() - t0, 1),
           "targets": cfg.get("targets", []), "survivors": survivors}
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    json.dump(out, open(a.out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("[mut] 变异分数 %d/%d = %.1f%%（下限 %s%%），存活 %d 个" % (
        killed_n, total, score, cfg.get("min_score", 60), len(survivors)))
    for s in survivors[:10]:
        print("  - SURVIVED %s:%d %s->%s" % (s["file"], s["line"] + 1, s["old"], s["new"]))
    return 0 if score >= float(cfg.get("min_score", 60)) else 1


if __name__ == "__main__":
    sys.exit(main())
