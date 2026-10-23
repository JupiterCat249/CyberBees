#!/usr/bin/env python3
"""信号契约闸：三向对账（声明 / 发射 / 订阅）。

背景：本项目信号走字符串中介 —— emit_signal(Bus.SIG_X) 与 .connect(Bus.SIG_X)，
而 const SIG_X := "x" 与 signal x(...) 分处两行。gdcruiser 与 gdlint 都看不见收发关系，
所以这一闸必须自研。

判据：
  · 每条 SIG_* 必须「有发射 + 至少一个订阅」，否则计入问题；
  · 确属保留不用者，在总线文件该行加 @dead 注释显式豁免（豁免必须在代码里看得见）；
  · 无法静态判定的动态用法（emit_signal(变量)）计入 undetectable —— 宁可报未知，不许假绿。

★ 只扫产品代码：tests/ 与 verification/ 不参与计数（否则一条测试里的 connect 会让死信号看着是活的）。
"""
import argparse, json, os, re, sys

EXCLUDE_DIRS = {"addons", ".godot", "archive", "verification", "tools", ".git", "qc", "tests", ".venv"}

def classify_arg(arg):
    """信号名实参能否静态解析：
       literal   "x"            -> 可（字符串字面量）
       constant  Bus.SIG_X      -> 可（常量表对账已覆盖）
       handler   _on_xxx        -> 可（signal.connect(方法) 惯用法，无需解析信号名）
       lambda    func(          -> 可
       unknown   其余            -> 无法判定（宁可报未知，不许假绿）
    """
    a = arg.strip()
    if not a:
        return "unknown"
    if a.startswith('"'):
        return "unknown" if ("+" in a or "%" in a) else "literal"
    if a.startswith("SIG_") or ".SIG_" in a:
        return "constant"
    if a.startswith("_") or a.startswith("self.") or a.startswith("func(") or a.startswith("Callable("):
        return "handler"
    return "unknown"


def iter_gd(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        for fn in filenames:
            if fn.endswith(".gd"):
                yield os.path.join(dirpath, fn)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--bus", default="")   ## 空 = 自动探测（src/battle 优先，兼容旧 scripts/battle）
    ap.add_argument("--out", required=True)
    ap.add_argument("--accept", default="", help="undetectable 登记表（JSON）：与实际名单**双向**对账，不一致即判红")
    a = ap.parse_args()

    ## 总线路径：显式给了就用；否则自动探测（迭代152 目录重排：src/battle 为新位置）
    if not a.bus:
        for cand in ("src/battle/battle_signal_bus.gd", "scripts/battle/battle_signal_bus.gd"):
            if os.path.isfile(os.path.join(a.repo, cand.replace("/", os.sep))):
                a.bus = cand
                break
        if not a.bus:
            print("[signals] 找不到 battle_signal_bus.gd（src/battle 与 scripts/battle 均无）")
            return 2

    bus_path = os.path.join(a.repo, a.bus.replace("/", os.sep))
    if not os.path.isfile(bus_path):
        print("BUS NOT FOUND: " + bus_path)
        return 2
    bus_lines = open(bus_path, encoding="utf-8").read().splitlines()

    consts = {}
    for i, line in enumerate(bus_lines, 1):
        m = re.match(r'\s*const\s+(SIG_\w+)\s*:=\s*"([\w]+)"', line)
        if m:
            consts[m.group(1)] = {"signal": m.group(2), "exempt": "@dead" in line, "line": i}
    decls = {}
    for i, line in enumerate(bus_lines, 1):
        m = re.match(r'\s*signal\s+(\w+)', line)
        if m:
            decls[m.group(1)] = {"exempt": "@dead" in line, "line": i}

    sources = []
    for p in iter_gd(a.repo):
        try:
            sources.append((p, open(p, encoding="utf-8", errors="replace").read()))
        except OSError:
            pass

    dead, unsub, unemit, unknown = [], [], [], []
    undetect_emit = undetect_connect = 0
    for cname, meta in sorted(consts.items()):
        sig = meta["signal"]
        emit_pat = re.compile(r'emit_signal\(\s*(?:[A-Za-z_]\w*\s*\.\s*)?' + cname + r'\b')
        emit_pat2 = re.compile(r'\b' + sig + r'\s*\.\s*emit\(')
        conn_pat = re.compile(r'\.connect\(\s*(?:[A-Za-z_]\w*\s*\.\s*)?' + cname + r'\b')
        conn_pat2 = re.compile(r'\.connect\(\s*"' + sig + r'"')
        conn_pat3 = re.compile(r'\b' + sig + r'\s*\.\s*connect\(')
        emits = subs = 0
        for _, src in sources:
            emits += len(emit_pat.findall(src)) + len(emit_pat2.findall(src))
            subs += len(conn_pat.findall(src)) + len(conn_pat2.findall(src)) + len(conn_pat3.findall(src))
        rec = {"const": cname, "signal": sig, "emit": emits, "subscribe": subs, "line": meta["line"]}
        if meta["exempt"] or decls.get(sig, {}).get("exempt"):
            continue
        if emits == 0 and subs == 0:
            dead.append(rec)
        else:
            if subs == 0:
                unsub.append(rec)
            if emits == 0:
                unemit.append(rec)

    # 「无法判定」只统计**真正无法解析**的用法；按实参形状分类，方式见 classify_arg()。
    emit_call = re.compile(r'emit_signal\(\s*([^)\n]*)')
    conn_call = re.compile(r'\.connect\(\s*([^)\n]*)')
    for p, src in sources:
        for m in emit_call.finditer(src):
            if classify_arg(m.group(1)) == "unknown":
                undetect_emit += 1
                unknown.append({"file": os.path.relpath(p, a.repo), "kind": "emit", "arg": m.group(1).strip()[:60]})
        for m in conn_call.finditer(src):
            if classify_arg(m.group(1)) == "unknown":
                undetect_connect += 1
                unknown.append({"file": os.path.relpath(p, a.repo), "kind": "connect", "arg": m.group(1).strip()[:60]})

    missing_const = sorted(set(decls) - {m["signal"] for m in consts.values()})
    missing_decl = sorted({m["signal"] for m in consts.values()} - set(decls))

    result = {
        "declared_signals": len(decls),
        "declared_consts": len(consts),
        "dead": dead,
        "unsubscribed": unsub,
        "unemitted": unemit,
        "problems": len(dead) + len(unsub) + len(unemit),
        "undetectable_emit": undetect_emit,
        "undetectable_connect": undetect_connect,
        ## P4（迭代128）：undetectable 的**名单**（不只是计数）—— 文档与输出要能对账
        "undetectable_list": unknown,
        "signal_without_const": missing_const,
        "const_without_signal": missing_decl,
    }
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    print("signals=%d  problems=%d (dead=%d unsubscribed=%d unemitted=%d)  undetectable=%d/%d"
          % (len(decls), result["problems"], len(dead), len(unsub), len(unemit), undetect_emit, undetect_connect))
    for u in unknown:
        print("  UNDETECTABLE  %-8s %s  arg=%s" % (u["kind"], u["file"], u["arg"]))
    for r in dead:
        print("  DEAD          %-28s (bus line %d)" % (r["signal"], r["line"]))
    for r in unsub:
        print("  NO-SUBSCRIBER %-28s emit=%d" % (r["signal"], r["emit"]))
    for r in unemit:
        print("  NO-EMITTER    %-28s subs=%d" % (r["signal"], r["subscribe"]))
    if missing_const:
        print("  SIGNAL-WITHOUT-CONST: " + ", ".join(missing_const))
    if missing_decl:
        print("  CONST-WITHOUT-SIGNAL: " + ", ".join(missing_decl))
    ## ⭐ 迭代095：**退出码必须反映判定** —— 此前恒 return 0，单跑 `qc signals` 永远绿（与迭代082 修掉的
    ##   "单闸恒 0" 属同一类假绿）。problems 现基线为 0 ⇒ 零容忍：任何死信号/单向信号/结构不配对都判红。
    bad = result["problems"] + len(missing_const) + len(missing_decl)

    ## P4（迭代128）：undetectable 名单与登记表**双向**对账
    ##   ① 实际出现但未登记 ⇒ 新出现的"静态不可判定"用法（要人看一眼）；
    ##   ② 登记了但实际没出现 ⇒ 登记表陈旧（应删，否则它会掩盖将来同类问题）。
    if a.accept and os.path.isfile(a.accept):
        try:
            doc = json.load(open(a.accept, encoding="utf-8-sig"))
            accepted = {(e.get("kind"), e.get("file"), e.get("arg")) for e in doc.get("entries", [])}
        except Exception as ex:
            print("  ACCEPT-READ-ERROR: %s" % ex)
            accepted = None
        if accepted is not None:
            actual = {(u["kind"], u["file"], u["arg"]) for u in unknown}
            new_ones = sorted(actual - accepted)
            stale = sorted(accepted - actual)
            if new_ones:
                print("  UNDETECTABLE-NOT-ACCEPTED %d 条（新出现，未登记）：" % len(new_ones))
                for k, f, arg in new_ones:
                    print("    + %s %s arg=%s" % (k, f, arg))
                bad += len(new_ones)
            if stale:
                print("  ACCEPT-STALE %d 条（登记但未出现）：" % len(stale))
                for k, f, arg in stale:
                    print("    - %s %s arg=%s" % (k, f, arg))
                bad += len(stale)

    return 1 if bad > 0 else 0

if __name__ == "__main__":
    sys.exit(main())
