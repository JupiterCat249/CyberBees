#!/usr/bin/env python3
"""lint 豁免清单对账（迭代125 · P5）：防止"新债伪装成豁免"与"豁免变陈旧"。

输入：qc/out/lint.log（gdlint 输出，格式：<绝对路径>:<行>: Error: <说明> (<rule>)）
      qc/config/lint_exemptions.json（豁免表：rule / file / symbol? ）
判据（双向，任一不满足 ⇒ 退出码 1）：
  ① 每条**实际**产出都必须被某条豁免命中（否则 = 新债未登记）；
  ② 每条**豁免**都必须命中至少一条实际产出（否则 = 豁免陈旧/过度登记）；
  ③ 实际产出条数必须等于日志末行 "Failure: N problems found" 的 N（防日志被截断）。

用法：lint_exempt_check.py --log qc/out/lint.log --exemptions qc/config/lint_exemptions.json --repo <仓根> --out qc/out/lint_exempt.json
退出码：0 通过 / 1 不一致 / 2 输入缺失
"""
import argparse, json, os, re, sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

LINE = re.compile(r"^(.*?):(\d+): (?:Error|Warning): (.*?)\((\w[\w-]*)\)\s*$")


def rel(path, repo):
    try:
        return os.path.relpath(path, repo).replace(os.sep, "/")
    except ValueError:
        return path.replace(os.sep, "/")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True)
    ap.add_argument("--exemptions", required=True)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    if not os.path.isfile(a.log) or not os.path.isfile(a.exemptions):
        print("[lint] 缺少 lint.log 或豁免清单")
        return 2

    findings = []
    declared_n = None
    for ln in open(a.log, encoding="utf-8", errors="replace").read().splitlines():
        ## ⚠️ gdlint 输出首行带 BOM（\ufeff）⇒ 必须先剥掉，否则第一条永远匹配不上
        m = LINE.match(ln.strip().lstrip("\ufeff"))
        if m:
            msg = m.group(3)
            symbol = ""
            ms = re.search(r'Function "([^"]+)"', msg)
            if ms:
                symbol = ms.group(1)
            findings.append({"rule": m.group(4), "file": rel(m.group(1), a.repo),
                             "line": int(m.group(2)), "symbol": symbol, "msg": msg.strip()[:160]})
            continue
        mf = re.match(r"Failure: (\d+) problems? found", ln.strip().lstrip("\ufeff"))
        if mf:
            declared_n = int(mf.group(1))

    doc = json.load(open(a.exemptions, encoding="utf-8-sig"))
    exemptions = doc.get("exemptions", [])
    used = [False] * len(exemptions)
    unregistered = []
    for f in findings:
        hit = False
        for i, e in enumerate(exemptions):
            if e.get("rule") != f["rule"] or e.get("file") != f["file"]:
                continue
            sym = e.get("symbol") or ""
            if sym and sym != f["symbol"]:
                continue
            hit = True
            used[i] = True
        if not hit:
            unregistered.append(f)

    stale = [e for i, e in enumerate(exemptions) if not used[i]]
    problems = []
    if unregistered:
        problems.append("有 %d 条实际产出未被登记（新债？）：" % len(unregistered))
    if stale:
        problems.append("有 %d 条豁免未命中任何实际产出（陈旧/过度登记）" % len(stale))
    if declared_n is not None and declared_n != len(findings):
        problems.append("日志声明 %d 条，实际解析 %d 条（日志被截断？）" % (declared_n, len(findings)))

    result = {"findings": len(findings), "exemptions": len(exemptions),
              "unregistered": unregistered, "stale": stale, "problems": problems}
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    if problems:
        print("[lint] 豁免对账不一致：")
        for p in problems:
            print("  - " + p)
        for f in unregistered[:6]:
            print("  ! 未登记: %s:%d %s (%s)" % (f["file"], f["line"], f["symbol"] or "-", f["rule"]))
        for e in stale[:6]:
            print("  ! 陈旧豁免: %s %s %s" % (e.get("rule"), e.get("file"), e.get("symbol") or ""))
        return 1
    print("[lint] 豁免对账一致：产出 %d 条 = 豁免 %d 条" % (len(findings), len(exemptions)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
