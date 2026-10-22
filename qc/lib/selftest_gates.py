#!/usr/bin/env python3
"""门禁自检（迭代089）：给每个闸造一个**已知坏输入**，断言它真的会红。

为什么需要：本项目已发现三个「假绿」Bug，共同点是**失败路径从来没被执行过**。
本自检把失败路径变成每次 qc all 都会走的常规路径。

测的是「判定逻辑」这一层（Python 检查器），不启动 Godot：
  · 体积闸：新文件超限 → NEW_OVERSIZE；祖父文件生长 → GREW；达标 → 通过
  · 架构闸：禁止依赖 → layer_violations>0 且退出码 1；干净图 → 0

输出：每条 [PASS]/[FAIL] + 末尾汇总；有任何 FAIL 则退出码 1。
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SIZE_CHECK = os.path.join(HERE, "size_check.py")
ARCH_CHECK = os.path.join(HERE, "arch_check.py")

results = []


def record(name, ok, detail=""):
    results.append((name, ok, detail))
    print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, ("  " + detail) if detail and not ok else ""))


def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def test_size_gate(tmp, python):
    pol = os.path.join(tmp, "size_policy.json")
    with open(pol, "w", encoding="utf-8") as f:
        json.dump({"max_lines": 50, "max_bytes": 4096, "include_ext": [".gd"], "exclude_dirs": []}, f)

    # ① 新文件超限 → 必须红
    repo = os.path.join(tmp, "r1")
    os.makedirs(os.path.join(repo, "a"), exist_ok=True)
    with open(os.path.join(repo, "a", "big.gd"), "w", encoding="utf-8") as f:
        f.write("extends Node\n" + "var x := 0\n" * 80)
    base = os.path.join(tmp, "b_empty.json")
    with open(base, "w", encoding="utf-8") as f:
        json.dump({"exempt": {}}, f)
    out = os.path.join(tmp, "o1.json")
    rc, txt = run([python, SIZE_CHECK, "--repo", repo, "--policy", pol, "--baseline", base, "--out", out])
    has_kind = "NEW_OVERSIZE" in txt or (os.path.exists(out) and "NEW_OVERSIZE" in open(out, encoding="utf-8").read())
    record("体积闸：新文件超限必须红", rc == 1 and has_kind, "rc=%d %s" % (rc, txt[-120:]))

    # ② 祖父文件生长 → 必须红
    base2 = os.path.join(tmp, "b_grew.json")
    with open(base2, "w", encoding="utf-8") as f:
        json.dump({"exempt": {"a/big.gd": {"lines": 10, "bytes": 10}}}, f)
    out2 = os.path.join(tmp, "o2.json")
    rc2, txt2 = run([python, SIZE_CHECK, "--repo", repo, "--policy", pol, "--baseline", base2, "--out", out2])
    grew = os.path.exists(out2) and "GREW" in open(out2, encoding="utf-8").read()
    record("体积闸：祖父文件生长必须红", rc2 == 1 and grew, "rc=%d" % rc2)

    # ③ 达标 → 必须绿
    repo_ok = os.path.join(tmp, "r_ok")
    os.makedirs(repo_ok, exist_ok=True)
    with open(os.path.join(repo_ok, "small.gd"), "w", encoding="utf-8") as f:
        f.write("extends Node\nvar x := 0\n")
    out3 = os.path.join(tmp, "o3.json")
    rc3, _ = run([python, SIZE_CHECK, "--repo", repo_ok, "--policy", pol, "--baseline", base, "--out", out3])
    record("体积闸：达标文件必须绿", rc3 == 0, "rc=%d" % rc3)

    # ④ 豁免陈旧 → 必须红
    base4 = os.path.join(tmp, "b_stale.json")
    with open(base4, "w", encoding="utf-8") as f:
        json.dump({"exempt": {"small.gd": {"lines": 1, "bytes": 1}}}, f)
    out4 = os.path.join(tmp, "o4.json")
    rc4, _ = run([python, SIZE_CHECK, "--repo", repo_ok, "--policy", pol, "--baseline", base4, "--out", out4])
    stale = os.path.exists(out4) and "STALE_EXEMPT" in open(out4, encoding="utf-8").read()
    record("体积闸：陈旧豁免必须红", rc4 == 1 and stale, "rc=%d" % rc4)


def test_arch_gate(tmp, python):
    rules = os.path.join(tmp, "rules.json")
    with open(rules, "w", encoding="utf-8") as f:
        json.dump({
            "layers": {"ui_component": ["scenes/ui/view_"], "ui": ["scenes/ui/"], "battle": ["scripts/battle/"]},
            "forbid": [{"from": "ui_component", "to": ["ui"], "why": "测试用：子模块不得回指"}],
            "unresolved_must_be_zero": True,
        }, f, ensure_ascii=False)

    def graph(deps_map):
        # 必须与 gdcruiser 一致：{"graph": {"modules": {路径: {"dependencies": [...]}}}}
        return {"graph": {"modules": deps_map}, "cycles": []}

    bad = os.path.join(tmp, "g_bad.json")
    with open(bad, "w", encoding="utf-8") as f:
        json.dump(graph({
            "res://scenes/ui/view_fx.gd": {"dependencies": [
                {"target": "res://scenes/ui/arena_view.gd", "type": "preload", "line": 2, "resolved": True}
            ]},
            "res://scenes/ui/arena_view.gd": {"dependencies": []},
        }), f)
    out = os.path.join(tmp, "a_bad.json")
    rc, txt = run([python, ARCH_CHECK, "--graph", bad, "--rules", rules, "--out", out])
    v = 0
    if os.path.exists(out):
        v = json.load(open(out, encoding="utf-8")).get("layer_violations", 0)
    record("架构闸：禁止依赖必须红", rc == 1 and v > 0, "rc=%d violations=%s" % (rc, v))

    good = os.path.join(tmp, "g_good.json")
    with open(good, "w", encoding="utf-8") as f:
        json.dump(graph({"res://scenes/ui/view_fx.gd": {"dependencies": []}}), f)
    out2 = os.path.join(tmp, "a_good.json")
    rc2, _ = run([python, ARCH_CHECK, "--graph", good, "--rules", rules, "--out", out2])
    record("架构闸：干净图必须绿", rc2 == 0, "rc=%d" % rc2)


def main():
    python = sys.executable
    tmp = tempfile.mkdtemp(prefix="qc_selftest_")
    try:
        print("[qc] selftest 体积闸")
        test_size_gate(tmp, python)
        print("[qc] selftest 架构闸")
        test_arch_gate(tmp, python)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    failed = [r for r in results if not r[1]]
    print("[qc] selftest 合计 %d 项，失败 %d 项" % (len(results), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
