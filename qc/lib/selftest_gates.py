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
  · GUT 校验：全部加载 → 0；日志含解析错误 → 1；磁盘数 ≠ 加载数 → 1
  · lint 豁免：双向一致 → 0；新债未登记 → 1；豁免陈旧 → 1
  · 体积预警：达 91% 有预警但**不判红**；50% 无预警
  · 体积口径：注释行不计入（注释多代码少必须绿）；代码超限必须红
  · 信号登记：全登记 → 0；新出现未登记 → 1；登记陈旧 → 1

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
GUT_CHECK = os.path.join(HERE, "gut_check.py")
LINT_EXEMPT = os.path.join(HERE, "lint_exempt_check.py")

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
            "layers": {"ui_component": ["src/view/view_"], "ui": ["src/view/"], "battle": ["src/battle/"]},
            "forbid": [{"from": "ui_component", "to": ["ui"], "why": "测试用：子模块不得回指"}],
            "unresolved_must_be_zero": True,
        }, f, ensure_ascii=False)

    def graph(deps_map):
        # 必须与 gdcruiser 一致：{"graph": {"modules": {路径: {"dependencies": [...]}}}}
        return {"graph": {"modules": deps_map}, "cycles": []}

    bad = os.path.join(tmp, "g_bad.json")
    with open(bad, "w", encoding="utf-8") as f:
        json.dump(graph({
            "res://src/view/view_fx.gd": {"dependencies": [
                {"target": "res://src/view/arena_view.gd", "type": "preload", "line": 2, "resolved": True}
            ]},
            "res://src/view/arena_view.gd": {"dependencies": []},
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
        json.dump(graph({"res://src/view/view_fx.gd": {"dependencies": [
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
        json.dump(graph({"res://src/view/view_fx.gd": {"dependencies": []}}), f)
    out2 = os.path.join(tmp, "a_good.json")
    rc2, _ = run([python, ARCH_CHECK, "--graph", good, "--rules", rules, "--out", out2])
    record("架构闸：干净图必须绿", rc2 == 0, "rc=%d" % rc2)


def test_signals_gate(tmp, python):
    """信号闸反例（迭代095）：判定逻辑必须真的红/真的豁免。"""
    def make_repo(name, bus_text, user_text=""):
        root = os.path.join(tmp, name)
        os.makedirs(os.path.join(root, "src", "battle"), exist_ok=True)
        with open(os.path.join(root, "src", "battle", "battle_signal_bus.gd"), "w", encoding="utf-8") as f:
            f.write(bus_text)
        if user_text:
            with open(os.path.join(root, "src", "battle", "user.gd"), "w", encoding="utf-8") as f:
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
        "lint:total": 6, "test:passing": 133, "test:asserts": 650,
        "qc:selftest_failures": 0,
        "size:arena_view": 1635, "size:battle_engine": 995, "size:net_diag_dump": 721,
        "signals:declared": 24, "signals:problems": 0,
        "qc:selftest_total": 37,
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
        "> **基线快照**：lint=6 · tests=133/650 · selftest=0 · size=1635/995/721 · signals=24/0")
    rc, txt = run_docs(ok_doc, "d_o1.json")
    record("文档基线：一致必须绿", rc == 0 and "一致" in txt, "rc=%d" % rc)

    bad_doc = write_doc("d_bad.md",
        "> **基线快照**：lint=99 · tests=133/650 · selftest=0 · size=1635/995/721 · signals=24/0")
    rc, txt = run_docs(bad_doc, "d_o2.json")
    record("文档基线：漂移必须红", rc == 1 and "lint" in txt, "rc=%d" % rc)

    missing = os.path.join(tmp, "d_missing.md")
    ## 迭代139：**收尾状态行**也要对账（此前只有基线快照一行被覆盖 ⇒ 该行曾漂 17 批）
    def write_status_doc(name, self_ok: bool):
        st = ("> **收尾状态**（iter137）：自检 **37/37** · lint **6**（= 豁免 6）· 体积 **1635 / 995 / 721** · "
              "回归 **133 测试 / 650 断言**")
        if not self_ok:
            st = st.replace("自检 **37/37**", "自检 **26/26**")
        ## ⚠️ 必须同时带「基线快照」行（缺它会返回 rc=2，掩盖本用例要测的判据）
        base = ("> **基线快照**：lint=6 · tests=133/650 · selftest=0 · "
                "size=1635/995/721 · signals=24/0")
        pth = os.path.join(tmp, name)
        with open(pth, "w", encoding="utf-8") as f:
            f.write("# 状态\n\n" + base + "\n\n" + st + "\n")
        return pth

    ok_st = write_status_doc("d_st_ok.md", True)
    rc, txt = run_docs(ok_st, "d_o4.json")
    record("收尾状态行：一致必须绿", rc == 0, "rc=%d" % rc)

    bad_st = write_status_doc("d_st_bad.md", False)
    rc, txt = run_docs(bad_st, "d_o5.json")
    record("收尾状态行：漂移必须红", rc == 1 and "收尾状态" in txt, "rc=%d" % rc)

    rc, txt = run_docs(missing, "d_o3.json")
    record("文档基线：文档缺失应 skip", rc == 0 and "skip" in txt, "rc=%d" % rc)


def test_gut_check(tmp, python):
    """GUT 结果校验反例（迭代124 · P1）：测试文件语法错时 GUT 只是少加载，必须由本闸判红。"""
    tdir = os.path.join(tmp, "g_tests")
    os.makedirs(tdir, exist_ok=True)

    def write_test(name):
        with open(os.path.join(tdir, name), "w", encoding="utf-8") as f:
            f.write("extends GutTest\n")

    def write_log(name, scripts, extra=""):
        p = os.path.join(tmp, name)
        with open(p, "w", encoding="utf-8") as f:
            f.write("Godot Engine\n" + extra +
                    "\n= Run Summary\n\nTotals\n------\n\nScripts              %d\n"
                    "Tests                3\nPassing Tests        3\nAsserts              7\n" % scripts)
        return p

    def run_check(log, out):
        return run([python, GUT_CHECK, "--log", log, "--tests-dir", tdir, "--out", os.path.join(tmp, out)])

    write_test("test_a.gd")
    ok = write_log("g_ok.log", 1)
    rc, txt = run_check(ok, "g_o1.json")
    record("GUT 校验：全部加载必须绿", rc == 0 and "全部加载" in txt, "rc=%d" % rc)

    bad = write_log("g_bad.log", 1, "SCRIPT ERROR: Parse Error: No constructor matches\n")
    rc, txt = run_check(bad, "g_o2.json")
    record("GUT 校验：解析错误必须红", rc == 1 and "解析" in txt, "rc=%d" % rc)

    write_test("test_b.gd")          # 磁盘 2 个，但日志只说加载 1 个
    rc, txt = run_check(ok, "g_o3.json")
    record("GUT 校验：少加载必须红", rc == 1, "rc=%d" % rc)


def test_lint_exempt(tmp, python):
    """lint 豁免清单反例（迭代125 · P5）：新债必须红、陈旧豁免也必须红。"""
    repo = os.path.join(tmp, "le_repo")
    os.makedirs(os.path.join(repo, "scenes", "ui"), exist_ok=True)
    target = os.path.join(repo, "scenes", "ui", "a.gd")
    open(target, "w").close()

    def write_log(name, extra_line=""):
        p = os.path.join(tmp, name)
        with open(p, "w", encoding="utf-8") as f:
            f.write("\ufeff%s:10: Error: Max allowed file lines num (1000) exceeded (max-file-lines)\n" % target)
            if extra_line:
                f.write(extra_line + "\n")
            else:
                f.write("Failure: 1 problems found\n")
        return p

    def write_ex(name, items):
        p = os.path.join(tmp, name)
        with open(p, "w", encoding="utf-8") as f:
            json.dump({"exemptions": items}, f)
        return p

    one = [{"rule": "max-file-lines", "file": "scenes/ui/a.gd", "symbol": ""}]
    ex_ok = write_ex("le_ok.json", one)
    log_ok = write_log("le_ok.log")

    def run_check(log, ex, out):
        return run([python, LINT_EXEMPT, "--log", log, "--exemptions", ex, "--repo", repo,
                    "--out", os.path.join(tmp, out)])

    rc, txt = run_check(log_ok, ex_ok, "le_o1.json")
    record("lint 豁免：一致必须绿", rc == 0, "rc=%d" % rc)

    log_new = write_log("le_new.log",
        "%s:20: Error: Function \"bad_fn\" has more than 6 return statements (max-returns)" % target)
    rc, txt = run_check(log_new, ex_ok, "le_o2.json")
    record("lint 豁免：新债未登记必须红", rc == 1 and "未登记" in txt, "rc=%d" % rc)

    ex_stale = write_ex("le_stale.json", one + [{"rule": "max-returns", "file": "scenes/ui/gone.gd", "symbol": ""}])
    rc, txt = run_check(log_ok, ex_stale, "le_o3.json")
    record("lint 豁免：陈旧豁免必须红", rc == 1 and "陈旧" in txt, "rc=%d" % rc)


def test_size_warn(tmp, python):
    """体积预警线反例（迭代127 · P3）：接近上限要"看得见"，但**不得**变成失败（避免噪声红）。"""
    pol = os.path.join(tmp, "w_policy.json")
    with open(pol, "w", encoding="utf-8") as f:
        json.dump({"max_lines": 100, "max_bytes": 100000, "include_ext": [".gd"],
                   "exclude_dirs": [], "warn_ratio": 0.9}, f)
    base = os.path.join(tmp, "w_base.json")
    with open(base, "w", encoding="utf-8") as f:
        json.dump({"exempt": {}}, f)

    repo = os.path.join(tmp, "w_repo")
    os.makedirs(repo, exist_ok=True)
    near = os.path.join(repo, "near.gd")
    with open(near, "w", encoding="utf-8") as f:
        f.write("extends Node\n" + "var a := 1\n" * 90)      # 91 行 / 上限 100

    def run_size(out):
        return run([python, SIZE_CHECK, "--repo", repo, "--policy", pol,
                    "--baseline", base, "--out", os.path.join(tmp, out)])

    rc, txt = run_size("w_o1.json")
    record("体积预警：达 91% 有预警且不判红", rc == 0 and "预警" in txt, "rc=%d" % rc)

    with open(near, "w", encoding="utf-8") as f:
        f.write("extends Node\n" + "var a := 1\n" * 49)      # 50 行
    rc, txt = run_size("w_o2.json")
    record("体积预警：50% 不应有预警", rc == 0 and "预警" not in txt, "rc=%d" % rc)


def test_signals_accept(tmp, python):
    """undetectable 登记表反例（迭代128 · P4）：名单与登记**双向**必须一致。"""
    repo = os.path.join(tmp, "sa_repo")
    os.makedirs(os.path.join(repo, "scenes", "ui"), exist_ok=True)
    os.makedirs(os.path.join(repo, "src", "battle"), exist_ok=True)

    bus = os.path.join(repo, "src", "battle", "battle_signal_bus.gd")
    with open(bus, "w", encoding="utf-8") as f:
        f.write('extends Node\nconst SIG_X := "x_changed"\nsignal x_changed\n')

    app = os.path.join(repo, "scenes", "ui", "a.gd")
    with open(app, "w", encoding="utf-8") as f:
        ## ⚠️ 必须用**无法静态判定**的实参（classify_arg 对 _on_x 判为 handler）⇒ 用变量 cb；
        ##   同时要有 emit，否则会因"无发射点"判别的红（与本用例无关）
        f.write('extends Control\nfunc _ready():\n\tvar cb = Callable(self, "_on_x")\n'
                '\tbus.x_changed.connect(cb)\n\tbus.emit_signal(SIG_X)\n')

    def write_accept(name, entries):
        p = os.path.join(tmp, name)
        with open(p, "w", encoding="utf-8") as f:
            json.dump({"entries": entries}, f)
        return p

    one = [{"kind": "connect", "file": os.path.join("scenes", "ui", "a.gd"), "arg": "cb"}]

    def run_sig(accept, out):
        return run([python, SIGNALS_CHECK, "--repo", repo, "--bus",
                    "src/battle/battle_signal_bus.gd", "--out", os.path.join(tmp, out),
                    "--accept", accept])

    rc, txt = run_sig(write_accept("sa_ok.json", one), "sa_o1.json")
    record("信号登记：全登记必须绿", rc == 0, "rc=%d" % rc)

    rc, txt = run_sig(write_accept("sa_empty.json", []), "sa_o2.json")
    record("信号登记：未登记必须红", rc == 1 and "NOT-ACCEPTED" in txt, "rc=%d" % rc)

    two = one + [{"kind": "connect", "file": os.path.join("scenes", "ui", "gone.gd"), "arg": "_on_gone"}]
    rc, txt = run_sig(write_accept("sa_stale.json", two), "sa_o3.json")
    record("信号登记：陈旧登记必须红", rc == 1 and "STALE" in txt, "rc=%d" % rc)



def test_size_measure_code(tmp, python):
    """体积口径反例（迭代144 · 人 2026-10-23）：**只看生产代码** —— 注释/空行不计入上限。"""
    pol = os.path.join(tmp, "m_policy.json")
    with open(pol, "w", encoding="utf-8") as f:
        json.dump({"max_lines": 100, "max_bytes": 100000, "include_ext": [".gd"],
                   "exclude_dirs": [], "warn_ratio": 0.9, "measure": "code"}, f)
    base = os.path.join(tmp, "m_base.json")
    with open(base, "w", encoding="utf-8") as f:
        json.dump({"exempt": {}}, f)
    repo = os.path.join(tmp, "m_repo")
    os.makedirs(repo, exist_ok=True)

    def run_size(out, name="m_o.json"):
        return run([python, SIZE_CHECK, "--repo", repo, "--policy", pol,
                    "--baseline", base, "--out", os.path.join(tmp, out)])

    heavy = os.path.join(repo, "heavy_comments.gd")
    with open(heavy, "w", encoding="utf-8") as f:
        # 10 行代码 + 500 行注释（含空行）⇒ 按"只看代码"口径必须绿
        f.write("extends Node\n" + "var a := 1\n" * 9)
        f.write("\n" + "# 注释\n" * 250 + "\n")
    rc, txt = run_size("m_o1.json")
    record("体积口径：注释不计入（注释多代码少必须绿）", rc == 0, "rc=%d" % rc)

    with open(heavy, "w", encoding="utf-8") as f:
        f.write("extends Node\n" + "var a := 1\n" * 101)   # 102 行代码 ⇒ 超限
    rc, txt = run_size("m_o2.json")
    record("体积口径：代码超限必须红", rc == 1, "rc=%d" % rc)


def test_layout_gate(tmp, python):
    """布局闸反例（迭代155 · M6）：四条禁止规则都必须真的红。"""
    CHECK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "layout_check.py")

    def make_repo(name):
        root = os.path.join(tmp, name)
        os.makedirs(os.path.join(root, "src", "battle"), exist_ok=True)
        os.makedirs(os.path.join(root, "scenes"), exist_ok=True)
        os.makedirs(os.path.join(root, "qc"), exist_ok=True)
        os.makedirs(os.path.join(root, "tests"), exist_ok=True)
        with open(os.path.join(root, "src", "battle", "a.gd"), "w", encoding="utf-8") as f:
            f.write("extends Node\n")
        return root

    def run_lay(root, out):
        return run([python, CHECK, "--repo", root, "--out", os.path.join(tmp, out)])

    # ① 干净仓库 ⇒ 绿
    clean = make_repo("l_clean")
    rc, txt = run_lay(clean, "l_o0.json")
    record("布局闸：干净仓库必须绿", rc == 0, "rc=%d" % rc)

    # ② scenes/ 下放 .gd ⇒ 红
    scene_gd = make_repo("l_scene")
    with open(os.path.join(scene_gd, "scenes", "bad.gd"), "w", encoding="utf-8") as f:
        f.write("extends Node\n")
    rc, txt = run_lay(scene_gd, "l_o1.json")
    record("布局闸：scenes 下的 .gd 必须红", rc == 1 and "SCENE_HAS_GD" in txt, "rc=%d" % rc)

    # ③ qc/ 下放 .gd ⇒ 红
    qc_gd = make_repo("l_qc")
    with open(os.path.join(qc_gd, "qc", "probe.gd"), "w", encoding="utf-8") as f:
        f.write("extends SceneTree\n")
    rc, txt = run_lay(qc_gd, "l_o2.json")
    record("布局闸：qc 下的 .gd 必须红", rc == 1 and "QC_HAS_GD" in txt, "rc=%d" % rc)

    # ④ *.deprecated ⇒ 红（archive/ 豁免）
    dep = make_repo("l_dep")
    with open(os.path.join(dep, "src", "battle", "old.gd.deprecated"), "w", encoding="utf-8") as f:
        f.write("extends Node\n")
    rc, txt = run_lay(dep, "l_o3.json")
    record("布局闸：.deprecated 必须红", rc == 1 and "DEPRECATED_FILE" in txt, "rc=%d" % rc)

    # ⑤ 生产代码引用 res://dev/ ⇒ 红
    devref = make_repo("l_devref")
    with open(os.path.join(devref, "src", "battle", "b.gd"), "w", encoding="utf-8") as f:
        f.write('const P := preload("res://dev/probes/p.gd")\n')
    rc, txt = run_lay(devref, "l_o4.json")
    record("布局闸：生产引 dev 必须红", rc == 1 and "PROD_REFERS_DEV" in txt, "rc=%d" % rc)


def test_bug_binding(tmp, python):
    """缺陷绑定闸反例（迭代156 · 第三轮 S1/WS5）：硬措施必须真红。"""
    CHECK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bug_binding_check.py")
    repo = os.path.join(tmp, "bb_repo")
    os.makedirs(os.path.join(repo, "tests"), exist_ok=True)
    test_file = os.path.join(repo, "tests", "test_demo.gd")
    with open(test_file, "w", encoding="utf-8") as f:
        f.write("extends GutTest\n\nfunc test_bugfix_keeps_state() -> void:\n\tassert_true(true)\n")

    cfg = os.path.join(repo, "bug_regressions.json")
    commits = os.path.join(repo, "commits.tsv")
    with open(commits, "w", encoding="utf-8") as f:
        f.write("aaaa1111\t[fix] 修复甲\nbbbb2222\t[feat] 新功能\n")

    def run_bb(cfg_path, out):
        return run([python, CHECK, "--repo", repo, "--config", cfg_path,
                    "--commits", commits, "--out", os.path.join(tmp, out)])

    # ① 未登记 ⇒ 红
    json.dump({"entries": []}, open(cfg, "w", encoding="utf-8"))
    rc, txt = run_bb(cfg, "bb_o1.json")
    record("缺陷绑定：未登记的 [fix] 必须红", rc == 1 and "FIX_UNBOUND" in txt, "rc=%d" % rc)

    # ② 已登记且用例存在 ⇒ 绿
    json.dump({"entries": [{"commit": "aaaa1111", "tests": ["tests/test_demo.gd::test_bugfix_keeps_state"]}]},
              open(cfg, "w", encoding="utf-8"))
    rc, txt = run_bb(cfg, "bb_o2.json")
    record("缺陷绑定：登记且用例存在必须绿", rc == 0, "rc=%d" % rc)

    # ③ 登记的用例名不存在 ⇒ 红
    json.dump({"entries": [{"commit": "aaaa1111", "tests": ["tests/test_demo.gd::test_does_not_exist"]}]},
              open(cfg, "w", encoding="utf-8"))
    rc, txt = run_bb(cfg, "bb_o3.json")
    record("缺陷绑定：用例名不存在必须红", rc == 1 and "TEST_NAME_MISSING" in txt, "rc=%d" % rc)


def test_sync_docs(tmp, python):
    """数字单一来源反例（迭代157 · 第三轮 S1/WS6）：check 必须能发现手写差异，write 必须修好。"""
    CHECK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sync_docs.py")
    counts = os.path.join(tmp, "sd_counts.json")
    json.dump({"lint:total": 5, "test:passing": 147, "test:asserts": 705,
               "qc:selftest_failures": 0, "qc:selftest_total": 49,
               "size:arena_view": 1656, "size:battle_engine": 995, "size:net_diag_dump": 721,
               "signals:declared": 24, "signals:problems": 0, "signals:undetectable": 5},
              open(counts, "w", encoding="utf-8"))

    def write_doc(name, status_line):
        p = os.path.join(tmp, name)
        with open(p, "w", encoding="utf-8") as f:
            f.write("# 状态\n\n"
                    "> **基线快照**（机器可读）：lint=99 · tests=1/2 · selftest=9 · size=1/2/3 · signals=1/1\n\n"
                    + status_line + "\n")
        return p

    stale = write_doc("sd_stale.md", "> **收尾状态**（iter0）：自检 **1/1** · lint **9** · 体积 **1 / 2 / 3** · 回归 **1 测试 / 2 断言**")
    rc, txt = run([python, CHECK, "--counts", counts, "--doc", stale, "--iteration", "iterT", "--check"])
    record("数字单一来源：手写差异必须被 check 发现", rc == 1, "rc=%d" % rc)

    rc2, _ = run([python, CHECK, "--counts", counts, "--doc", stale, "--iteration", "iterT", "--exemptions", "5"])
    rc3, _ = run([python, CHECK, "--counts", counts, "--doc", stale, "--iteration", "iterT", "--check"])
    body = open(stale, encoding="utf-8").read()
    ok = (rc2 == 0 and rc3 == 0 and "lint=5" in body and "tests=147/705" in body
          and "自检 **49/49**" in body and "豁免 5" in body)
    record("数字单一来源：write 后必须与 counts 一致", ok, "rc2=%d rc3=%d" % (rc2, rc3))


def test_arch_reachability(tmp, python):
    """可达层界反例（迭代158 · 第三轮 S1/WS4）：间接越界必须红，并报最短路径。"""
    CHECK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "arch_check.py")
    rules = os.path.join(tmp, "r_rules.json")
    json.dump({"layers": {"battle": ["src/battle/"], "net": ["src/net/"], "ui": ["src/view/"]},
               "forbid": [{"from": "battle", "to": ["ui"], "why": "规则层不得最终依赖视图"}],
               "unresolved_must_be_zero": True}, open(rules, "w", encoding="utf-8"))

    def graph(deps_map, name):
        p = os.path.join(tmp, name)
        json.dump({"graph": {"modules": deps_map}, "cycles": []}, open(p, "w", encoding="utf-8"))
        return p

    # ① battle → net → view（间接越界）⇒ 必须红且带路径
    g_bad = graph({
        "res://src/battle/a.gd": {"dependencies": [{"target": "res://src/net/b.gd", "type": "preload", "line": 1, "resolved": True}]},
        "res://src/net/b.gd": {"dependencies": [{"target": "res://src/view/c.gd", "type": "preload", "line": 2, "resolved": True}]},
        "res://src/view/c.gd": {"dependencies": []},
    }, "r_bad.json")
    out = os.path.join(tmp, "r_o1.json")
    rc, txt = run([python, CHECK, "--graph", g_bad, "--rules", rules, "--out", out])
    rj = json.load(open(out, encoding="utf-8")) if os.path.exists(out) else {}
    path = (rj.get("reach_violations_detail") or [{}])[0].get("path", [])
    ok = rc == 1 and rj.get("reach_violations", 0) == 1 and len(path) == 3
    record("可达层界：间接越界必须红并报路径", ok, "rc=%d reach=%s path=%s" % (rc, rj.get("reach_violations"), path))

    # ② battle → net（无越界）⇒ 绿
    g_ok = graph({
        "res://src/battle/a.gd": {"dependencies": [{"target": "res://src/net/b.gd", "type": "preload", "line": 1, "resolved": True}]},
        "res://src/net/b.gd": {"dependencies": []},
    }, "r_ok.json")
    out2 = os.path.join(tmp, "r_o2.json")
    rc2, _ = run([python, CHECK, "--graph", g_ok, "--rules", rules, "--out", out2])
    record("可达层界：无越界必须绿", rc2 == 0, "rc=%d" % rc2)


def test_test_health(tmp, python):
    """测试健康闸反例（迭代159 · 第三轮 S2/WS7）。"""
    CHECK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test_health.py")
    junit = os.path.join(tmp, "h_junit.xml")
    with open(junit, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write('<testsuites name="GutTests" tests="2">\n')
        f.write('  <testsuite name="tests/test_demo.gd" tests="2">\n')
        f.write('    <testcase name="test_fast" classname="tests/test_demo.gd" status="pass" time="0.01"/>\n')
        f.write('    <testcase name="test_slow" classname="tests/test_demo.gd" status="pass" time="5.0"/>\n')
        f.write("  </testsuite>\n</testsuites>\n")

    def run_h(cfg_obj, out):
        cfg = os.path.join(tmp, out.replace(".json", "_cfg.json"))
        json.dump(cfg_obj, open(cfg, "w", encoding="utf-8"))
        return run([python, CHECK, "--junit", junit, "--config", cfg, "--out", os.path.join(tmp, out)])

    rc, txt = run_h({"slow_budget_ms": 1000, "total_budget_ms": 180000, "quarantine": []}, "h_o1.json")
    record("测试健康：慢用例超预算必须红", rc == 1 and "SLOW_TEST" in txt, "rc=%d" % rc)

    rc2, txt2 = run_h({"slow_budget_ms": 10000, "total_budget_ms": 180000,
                       "quarantine": [{"file": "tests/test_demo.gd", "test": "test_fast", "reason": ""}]}, "h_o2.json")
    record("测试健康：隔离缺 reason 必须红", rc2 == 1 and "QUARANTINE_NO_REASON" in txt2, "rc=%d" % rc2)

    rc3, txt3 = run_h({"slow_budget_ms": 10000, "total_budget_ms": 180000,
                       "quarantine": [{"file": "tests/test_demo.gd", "test": "test_missing", "reason": "x"}]}, "h_o3.json")
    record("测试健康：隔离指向不存在必须红", rc3 == 1 and "QUARANTINE_UNKNOWN" in txt3, "rc=%d" % rc3)


def test_receipt(tmp, python):
    """交付证据链反例（迭代160 · 第三轮 S2/WS8）：交付后再改文件/改数字必须被发现。"""
    CHECK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "receipt.py")
    repo = os.path.join(tmp, "rc_repo")
    os.makedirs(os.path.join(repo, "tests"), exist_ok=True)
    os.makedirs(os.path.join(repo, "qc", "lib"), exist_ok=True)
    with open(os.path.join(repo, "tests", "test_a.gd"), "w", encoding="utf-8") as f:
        f.write("extends GutTest\n")
    with open(os.path.join(repo, "qc", "lib", "x.py"), "w", encoding="utf-8") as f:
        f.write("print(1)\n")
    counts = os.path.join(tmp, "rc_counts.json")
    json.dump({"test:passing": 1, "lint:total": 0}, open(counts, "w", encoding="utf-8"))
    rec = os.path.join(tmp, "rc_receipt.json")

    def write_rec():
        return run([python, CHECK, "--repo", repo, "--counts", counts, "--out", rec, "--iteration", "iterT"])

    def verify():
        return run([python, CHECK, "--repo", repo, "--counts", counts, "--out", rec, "--verify", rec])

    rc, _ = write_rec()
    rc_ok, _ = verify()
    record("交付证据链：清单与文件一致必须绿", rc == 0 and rc_ok == 0, "write=%d verify=%d" % (rc, rc_ok))

    with open(os.path.join(repo, "tests", "test_a.gd"), "a", encoding="utf-8") as f:
        f.write("# tampered\n")
    rc2, txt2 = verify()
    record("交付证据链：交付后改文件必须红", rc2 == 1 and "CHANGED" in txt2, "rc=%d" % rc2)

    with open(os.path.join(repo, "tests", "test_a.gd"), "w", encoding="utf-8") as f:
        f.write("extends GutTest\n")
    json.dump({"test:passing": 99, "lint:total": 0}, open(counts, "w", encoding="utf-8"))
    rc3, txt3 = verify()
    record("交付证据链：改 counts 必须红", rc3 == 1 and "COUNTS" in txt3, "rc=%d" % rc3)


def test_coverage_probe(tmp, python):
    """覆盖率注入/还原往返（迭代162 · 第三轮 S4/WS1）：必须能注入，也必须**逐字节还原**。"""
    CHECK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "coverage_probe.py")
    repo = os.path.join(tmp, "cov_repo")
    os.makedirs(os.path.join(repo, "src", "battle"), exist_ok=True)
    src = os.path.join(repo, "src", "battle", "demo.gd")
    body = "extends RefCounted\n\n\nfunc add(a: int, b: int) -> int:\n\treturn a + b\n"
    open(src, "w", encoding="utf-8").write(body)
    proj = os.path.join(repo, "project.godot")
    prow = "[application]\n\nconfig/name=\"demo\"\n"
    open(proj, "w", encoding="utf-8").write(prow)

    rc1, _ = run([python, CHECK, "--repo", repo, "inject"])
    injected = open(src, encoding="utf-8").read()
    proj_after = open(proj, encoding="utf-8").read()
    ok_inject = rc1 == 0 and "CovProbe.touch" in injected and "CovProbe=" in proj_after
    record("覆盖率探针：注入必须生效", ok_inject, "rc=%d has_touch=%s has_autoload=%s" % (
           rc1, "CovProbe.touch" in injected, "CovProbe=" in proj_after))

    rc2, _ = run([python, CHECK, "--repo", repo, "restore"])
    same = open(src, encoding="utf-8").read() == body and open(proj, encoding="utf-8").read() == prow
    record("覆盖率探针：还原必须逐字节一致", rc2 == 0 and same, "rc=%d same=%s" % (rc2, same))


def test_mutation_score(tmp, python):
    """变异分数判定（迭代163 · S4/WS2）：分数与 min_score 的比较必须真的红/绿。"""
    CHECK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mutation_probe.py")
    cfg = os.path.join(tmp, "mut_cfg.json")
    json.dump({"targets": [], "max_mutants": 2, "min_score": 60}, open(cfg, "w", encoding="utf-8"))
    out = os.path.join(tmp, "mut_out.json")

    def run_sim(results):
        return run([python, CHECK, "--repo", tmp, "--config", cfg, "--godot", "x", "--out", out,
                    "--simulate", json.dumps(results)])

    rc1, _ = run_sim([{"killed": True}, {"killed": True}])
    record("变异分数：全部杀死（100%）必须绿", rc1 == 0, "rc=%d" % rc1)

    rc2, txt2 = run_sim([{"killed": False}, {"killed": False}])
    data = json.load(open(out, encoding="utf-8"))
    record("变异分数：全部存活（0%）必须红", rc2 == 1 and data.get("score") == 0, "rc=%d score=%s" % (rc2, data.get("score")))

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
        print("[qc] selftest GUT 校验")
        test_gut_check(tmp, python)
        print("[qc] selftest lint 豁免")
        test_lint_exempt(tmp, python)
        print("[qc] selftest 体积预警")
        test_size_warn(tmp, python)
        print("[qc] selftest 体积口径")
        test_size_measure_code(tmp, python)
        print("[qc] selftest 布局闸")
        test_layout_gate(tmp, python)
        print("[qc] selftest 缺陷绑定")
        test_bug_binding(tmp, python)
        print("[qc] selftest 数字单一来源")
        test_sync_docs(tmp, python)
        print("[qc] selftest 可达层界")
        test_arch_reachability(tmp, python)
        print("[qc] selftest 测试健康")
        test_test_health(tmp, python)
        print("[qc] selftest 交付证据链")
        test_receipt(tmp, python)
        print("[qc] selftest 覆盖率探针")
        test_coverage_probe(tmp, python)
        print("[qc] selftest 变异分数")
        test_mutation_score(tmp, python)
        print("[qc] selftest 信号登记")
        test_signals_accept(tmp, python)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    failed = [r for r in results if not r[1]]
    print("[qc] selftest 合计 %d 项，失败 %d 项" % (len(results), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
