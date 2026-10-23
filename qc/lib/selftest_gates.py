#!/usr/bin/env python3
"""门禁自检（迭代089）：给每个闸造一个**已知坏输入**，断言它真的会红。

为什么需要：本项目已发现三个「假绿」Bug，共同点是**失败路径从来没被执行过**。
本自检把失败路径变成每次 qc all 都会走的常规路径。

测的是「判定逻辑」这一层（Python 检查器），不启动 Godot：
  · 体积闸：新文件超限 → NEW_OVERSIZE；祖父文件生长 → GREW；达标 → 通过
  · 架构闸：禁止依赖 → layer_violations>0 且退出码 1；干净图 → 0
  · 信号闸：死信号 / 只发不收 → 退出码 1；@dead 豁免 → 0；动态发射 → 计入 undetectable 且不假绿；总线缺失 → 2
  · 棘轮：债务上升必红、持平/下降必绿、覆盖率下跌必红、info 类上升不算红、新指标不算红、有上升项时拒绝写回
  · 文档基线：与实测一致 → 0；漂移 → 1；文档缺失 → 0（skip）

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
SIGNALS_CHECK = os.path.join(HERE, "signals_check.py")
RATCHET = os.path.join(HERE, "ratchet.py")
DOCS_CHECK = os.path.join(HERE, "docs_check.py")

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

    # ③ 未解析依赖 → 必须红（resolved=false 且规则要求 unresolved_must_be_zero）
    unresolved = os.path.join(tmp, "g_unres.json")
    with open(unresolved, "w", encoding="utf-8") as f:
        json.dump(graph({"res://scenes/ui/view_fx.gd": {"dependencies": [
            {"target": "./missing.gd", "type": "preload", "line": 3, "resolved": False}
        ]}}), f)
    out_u = os.path.join(tmp, "a_unres.json")
    rc_u, _ = run([python, ARCH_CHECK, "--graph", unresolved, "--rules", rules, "--out", out_u])
    n_unres = 0
    if os.path.exists(out_u):
        n_unres = int(json.load(open(out_u, encoding="utf-8")).get("unresolved", 0))
    record("架构闸：未解析依赖必须红", rc_u == 1 and n_unres > 0, "rc=%d unresolved=%d" % (rc_u, n_unres))

    good = os.path.join(tmp, "g_good.json")
    with open(good, "w", encoding="utf-8") as f:
        json.dump(graph({"res://scenes/ui/view_fx.gd": {"dependencies": []}}), f)
    out2 = os.path.join(tmp, "a_good.json")
    rc2, _ = run([python, ARCH_CHECK, "--graph", good, "--rules", rules, "--out", out2])
    record("架构闸：干净图必须绿", rc2 == 0, "rc=%d" % rc2)


def test_signals_gate(tmp, python):
    """信号闸反例（迭代095）：判定逻辑必须真的红/真的豁免。"""
    def make_repo(name, bus_text, user_text=""):
        root = os.path.join(tmp, name)
        os.makedirs(os.path.join(root, "scripts", "battle"), exist_ok=True)
        with open(os.path.join(root, "scripts", "battle", "battle_signal_bus.gd"), "w", encoding="utf-8") as f:
            f.write(bus_text)
        if user_text:
            with open(os.path.join(root, "scripts", "battle", "user.gd"), "w", encoding="utf-8") as f:
                f.write(user_text)
        return root

    def run_sig(root, out_name):
        out = os.path.join(tmp, out_name)
        rc, txt = run([python, SIGNALS_CHECK, "--repo", root, "--out", out])
        data = json.load(open(out, encoding="utf-8")) if os.path.exists(out) else {}
        return rc, data, txt

    # ① 死信号（有声明、零发射零订阅）→ 必须红
    dead_bus = 'signal dead_one()\nconst SIG_DEAD := "dead_one"\n'
    rc1, d1, _ = run_sig(make_repo("s_dead", dead_bus), "s1.json")
    record("信号闸：死信号必须红", rc1 == 1 and len(d1.get("dead", [])) == 1,
           "rc=%d dead=%s" % (rc1, d1.get("dead")))

    # ② @dead 豁免 → 必须绿（豁免必须在代码里看得见）
    exempt_bus = 'signal dead_one()\nconst SIG_DEAD := "dead_one"  ## @dead 测试用：显式豁免\n'
    rc2, d2, _ = run_sig(make_repo("s_exempt", exempt_bus), "s2.json")
    record("信号闸：@dead 豁免必须绿", rc2 == 0 and int(d2.get("problems", -1)) == 0,
           "rc=%d problems=%s" % (rc2, d2.get("problems")))

    # ③ 只发不收 → 必须红（unsubscribed）
    emit_bus = 'signal ping()\nconst SIG_PING := "ping"\n'
    emit_user = 'func f(bus) -> void:\n\tbus.emit_signal(Bus.SIG_PING)\n'
    rc3, d3, _ = run_sig(make_repo("s_unsub", emit_bus, emit_user), "s3.json")
    record("信号闸：只发不收必须红", rc3 == 1 and len(d3.get("unsubscribed", [])) == 1,
           "rc=%d unsub=%s" % (rc3, d3.get("unsubscribed")))

    # ④ 动态发射 → 必须计入 undetectable（宁可报未知，不许假绿）
    dyn_bus = 'signal ok_sig()\nconst SIG_OK := "ok_sig"\n'
    dyn_user = ('func f(bus) -> void:\n\tbus.emit_signal(Bus.SIG_OK)\n'
                '\tbus.connect(Bus.SIG_OK, func() -> void: pass)\n'
                'func g(bus, name) -> void:\n\tbus.emit_signal(name)\n')
    rc4, d4, _ = run_sig(make_repo("s_dyn", dyn_bus, dyn_user), "s4.json")
    record("信号闸：动态发射计入 undetectable",
           rc4 == 0 and int(d4.get("problems", -1)) == 0 and int(d4.get("undetectable_emit", 0)) >= 1,
           "rc=%d undet=%s" % (rc4, d4.get("undetectable_emit")))

    # ⑤ 总线文件缺失 → 必须红（rc=2；这正是 qc.ps1 曾把 $null 当 0 判绿的那种情形）
    no_bus = os.path.join(tmp, "s_nobus")
    os.makedirs(no_bus, exist_ok=True)
    rc5, _d5, _ = run_sig(no_bus, "s5.json")
    record("信号闸：总线缺失必须红", rc5 == 2, "rc=%d" % rc5)


def test_ratchet(tmp, python):
    """棘轮反例（迭代106）：它是本会话抓出最多回归的机制，此前却**没有**任何自检。"""
    def write(name, obj):
        p = os.path.join(tmp, name)
        with open(p, "w", encoding="utf-8") as f:
            json.dump(obj, f)
        return p

    def run_ratchet(base, cur, update=False):
        cmd = [python, RATCHET, "--baseline", base, "--current", cur]
        if update:
            cmd.append("--update")
        return run(cmd)

    base = write("r_base.json", {"iteration": "t0", "counts": {"lint:total": 4, "test:passing": 5, "test:asserts": 10}})

    # ① 债务上升 → 必红
    cur = write("r_up.json", {"lint:total": 5, "test:passing": 5, "test:asserts": 10})
    rc, txt = run_ratchet(base, cur)
    record("棘轮：债务上升必红", rc == 1 and "FAIL" in txt, "rc=%d" % rc)

    # ② 持平 → 必绿
    cur = write("r_same.json", {"lint:total": 4, "test:passing": 5, "test:asserts": 10})
    rc, txt = run_ratchet(base, cur)
    record("棘轮：持平必绿", rc == 0 and "OK" in txt, "rc=%d" % rc)

    # ③ 下降 → 必绿且报改善
    cur = write("r_down.json", {"lint:total": 3, "test:passing": 5, "test:asserts": 10})
    rc, txt = run_ratchet(base, cur)
    record("棘轮：下降必绿（报改善）", rc == 0 and "改善" in txt, "rc=%d" % rc)

    # ④ 覆盖率类下跌 → 必红（test:passing 方向相反）
    cur = write("r_cov.json", {"lint:total": 4, "test:passing": 4, "test:asserts": 10})
    rc, txt = run_ratchet(base, cur)
    record("棘轮：覆盖率下跌必红", rc == 1 and "test:passing" in txt, "rc=%d" % rc)

    # ⑤ info 类上升 → 不算红
    cur = write("r_info.json", {"lint:total": 4, "test:passing": 5, "test:asserts": 99})
    rc, _ = run_ratchet(base, cur)
    record("棘轮：info 类上升不算红", rc == 0, "rc=%d" % rc)

    # ⑥ 新指标 → 记为 new，不算红
    cur = write("r_new.json", {"lint:total": 4, "test:passing": 5, "test:asserts": 10, "size:new_metric": 7})
    rc, txt = run_ratchet(base, cur)
    record("棘轮：新指标不算红", rc == 0 and "?" in txt, "rc=%d" % rc)

    # ⑦ 有上升项时 --update 必须**拒绝写回**（基线文件字节不变）
    cur = write("r_upd.json", {"lint:total": 9, "test:passing": 5, "test:asserts": 10})
    before = open(base, encoding="utf-8").read()
    rc, txt = run_ratchet(base, cur, update=True)
    after = open(base, encoding="utf-8").read()
    record("棘轮：上升时拒绝写回基线", rc == 1 and before == after and "skip" in txt, "rc=%d" % rc)


def test_size_tighten(tmp, python):
    """体积闸 --tighten 反例（迭代109）：它只在 snapshot 跑过，此前**从未被自检覆盖**。

    契约：① 变小则收紧；② 不带 --tighten 绝不改基线；③ 已达标/消失的条目被移除；
          ④ 只降不升（实际变大时不得把基线放大）。
    """
    pol = os.path.join(tmp, "t_policy.json")
    with open(pol, "w", encoding="utf-8") as f:
        json.dump({"max_lines": 50, "max_bytes": 4096, "include_ext": [".gd"], "exclude_dirs": []}, f)

    repo = os.path.join(tmp, "t_repo")
    os.makedirs(os.path.join(repo, "a"), exist_ok=True)
    big = os.path.join(repo, "a", "big.gd")
    with open(big, "w", encoding="utf-8") as f:
        f.write("extends Node\n" + "var x := 0\n" * 80)      # 81 行 → 超限

    def write_base(name, exempt):
        pth = os.path.join(tmp, name)
        with open(pth, "w", encoding="utf-8") as f:
            json.dump({"exempt": exempt}, f)
        return pth

    def read_base(pth):
        return json.load(open(pth, encoding="utf-8-sig")).get("exempt", {})

    def run_size(base, out, tighten=False):
        cmd = [python, SIZE_CHECK, "--repo", repo, "--policy", pol, "--baseline", base, "--out", os.path.join(tmp, out)]
        if tighten:
            cmd.append("--tighten")
        return run(cmd)

    # ① 变小 → 收紧
    base = write_base("t_b1.json", {"a/big.gd": {"lines": 200, "bytes": 99999}})
    rc, txt = run_size(base, "t_o1.json", tighten=True)
    ex = read_base(base)
    record("体积闸 --tighten：变小则收紧", rc == 0 and int(ex["a/big.gd"]["lines"]) == 81,
           "rc=%d lines=%s" % (rc, ex.get("a/big.gd")))

    # ② 不带 --tighten → 绝不改基线
    base2 = write_base("t_b2.json", {"a/big.gd": {"lines": 200, "bytes": 99999}})
    before = open(base2, encoding="utf-8-sig").read()
    run_size(base2, "t_o2.json", tighten=False)
    after = open(base2, encoding="utf-8-sig").read()
    record("体积闸 --tighten：不带开关时基线不变", before == after, "baseline changed")

    # ③ 已消失的条目 → 移除
    base3 = write_base("t_b3.json", {"a/gone.gd": {"lines": 200, "bytes": 99999}})
    rc, _ = run_size(base3, "t_o3.json", tighten=True)
    ex3 = read_base(base3)
    record("体积闸 --tighten：消失条目被移除", "a/gone.gd" not in ex3, "exempt=%s" % ex3)

    # ④ 只降不升：实际变大时不得放大基线
    base4 = write_base("t_b4.json", {"a/big.gd": {"lines": 10, "bytes": 10}})
    rc, _ = run_size(base4, "t_o4.json", tighten=True)
    ex4 = read_base(base4)
    record("体积闸 --tighten：只降不升", int(ex4["a/big.gd"]["lines"]) == 10 and rc == 1,
           "rc=%d lines=%s" % (rc, ex4.get("a/big.gd")))


def test_docs_check(tmp, python):
    """文档基线漂移反例（迭代116）：那行数字是手改的，必须被对账钉住。"""
    counts = {
        "lint:total": 6, "test:passing": 113, "test:asserts": 404,
        "qc:selftest_failures": 0,
        "size:arena_view": 1720, "size:battle_engine": 995, "size:net_diag_dump": 721,
        "signals:declared": 24, "signals:problems": 0,
    }
    cpath = os.path.join(tmp, "d_counts.json")
    with open(cpath, "w", encoding="utf-8") as f:
        json.dump(counts, f)

    def write_doc(name, line):
        p = os.path.join(tmp, name)
        with open(p, "w", encoding="utf-8") as f:
            f.write("# 状态\n\n" + line + "\n")
        return p

    def run_docs(doc, out):
        return run([python, DOCS_CHECK, "--counts", cpath, "--doc", doc, "--out", os.path.join(tmp, out)])

    ok_doc = write_doc("d_ok.md",
        "> **基线快照**：lint=6 · tests=113/404 · selftest=0 · size=1720/995/721 · signals=24/0")
    rc, txt = run_docs(ok_doc, "d_o1.json")
    record("文档基线：一致必须绿", rc == 0 and "一致" in txt, "rc=%d" % rc)

    bad_doc = write_doc("d_bad.md",
        "> **基线快照**：lint=99 · tests=113/404 · selftest=0 · size=1720/995/721 · signals=24/0")
    rc, txt = run_docs(bad_doc, "d_o2.json")
    record("文档基线：漂移必须红", rc == 1 and "lint" in txt, "rc=%d" % rc)

    missing = os.path.join(tmp, "d_missing.md")
    rc, txt = run_docs(missing, "d_o3.json")
    record("文档基线：文档缺失应 skip", rc == 0 and "skip" in txt, "rc=%d" % rc)


def main():
    python = sys.executable
    tmp = tempfile.mkdtemp(prefix="qc_selftest_")
    try:
        print("[qc] selftest 体积闸")
        test_size_gate(tmp, python)
        print("[qc] selftest 架构闸")
        test_arch_gate(tmp, python)
        print("[qc] selftest 信号闸")
        test_signals_gate(tmp, python)
        print("[qc] selftest 棘轮")
        test_ratchet(tmp, python)
        print("[qc] selftest 体积收紧")
        test_size_tighten(tmp, python)
        print("[qc] selftest 文档基线")
        test_docs_check(tmp, python)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    failed = [r for r in results if not r[1]]
    print("[qc] selftest 合计 %d 项，失败 %d 项" % (len(results), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
