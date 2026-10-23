#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""缺陷-用例绑定闸（迭代156 · 第三轮 S1 / WS5）。

人 2026-10-23 裁定：「缺陷绑定强度 = 硬措施，强制性实现质量保障」。

判据：
  1. 基线之后的每一个 `[fix]` 提交，都必须在 qc/config/bug_regressions.json 里登记；
  2. 每条登记必须指向**真实存在**的用例文件 + 真实存在的测试函数名；
  3. 登记里的 commit 必须是仓库里真实存在的提交（前缀匹配即可）。

退出码：0 绿 / 1 违规 / 2 参数或环境错误。
"""
import argparse
import json
import os
import re
import subprocess
import sys

FIX_RE = re.compile(r"^\[fix", re.IGNORECASE)


def git_commits(repo, since=None):
    args = ["git", "-C", repo, "log", "--format=%H%x09%s"]
    if since:
        args.append("%s..HEAD" % since)
    out = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if out.returncode != 0:
        raise RuntimeError("git log 失败：%s" % (out.stderr or "").strip()[:200])
    rows = []
    for ln in out.stdout.splitlines():
        if "\t" in ln:
            h, s = ln.split("\t", 1)
            rows.append((h, s))
    return rows


def read_commits_file(path):
    rows = []
    for ln in open(path, encoding="utf-8", errors="replace").read().splitlines():
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        parts = ln.split("\t")
        if len(parts) >= 2:
            rows.append((parts[0].strip(), parts[1].strip()))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--config", required=True)
    ap.add_argument("--out", required=True)
    ## 测试用：给定"提交列表"文件（TSV: sha\tsubject），避免自检里真的 git commit
    ap.add_argument("--commits", default="")
    a = ap.parse_args()

    repo = os.path.abspath(a.repo)
    cfg_path = a.config if os.path.isabs(a.config) else os.path.join(repo, a.config)
    if not os.path.isfile(cfg_path):
        print("[bugbind] 找不到配置：%s" % cfg_path)
        return 2
    cfg = json.load(open(cfg_path, encoding="utf-8-sig"))
    baseline = str(cfg.get("baseline_commit", "")).strip()
    entries = cfg.get("entries", []) or []

    if a.commits:
        commits = read_commits_file(a.commits)
    else:
        try:
            commits = git_commits(repo, baseline or None)
        except RuntimeError as e:
            print("[bugbind] %s" % e)
            return 2

    fix_commits = [(h, s) for h, s in commits if FIX_RE.match(s.strip())]
    if a.commits:
        all_shas = {h for h, _ in commits}
    else:
        ## 全量 sha（登记的历史修复可能早于基线 ⇒ 不能只在 baseline..HEAD 里找）
        full = subprocess.run(["git", "-C", repo, "log", "--format=%H"], capture_output=True, text=True,
                              encoding="utf-8", errors="replace")
        if full.returncode != 0:
            print("[bugbind] git log 全量失败：%s" % (full.stderr or "").strip()[:200])
            return 2
        all_shas = {x.strip() for x in full.stdout.splitlines() if x.strip()}

    viol = []
    bound = set()

    by_commit = {}
    for e in entries:
        by_commit[str(e.get("commit", "")).strip()] = e

    # ① 每个新 [fix] 提交必须有登记
    for h, s in fix_commits:
        hit = None
        for c in by_commit:
            if c and (h.startswith(c) or c.startswith(h)):
                hit = c
                break
        if hit is None:
            viol.append({"rule": "FIX_UNBOUND", "commit": h[:12], "subject": s.strip()[:100],
                         "why": "基线之后的 [fix] 提交必须在 qc/config/bug_regressions.json 登记（含用例）"})
        else:
            bound.add(hit)

    # ② 登记的用例必须真实存在
    for c, e in by_commit.items():
        if not c:
            viol.append({"rule": "ENTRY_NO_COMMIT", "why": "条目缺少 commit"})
            continue
        m = [h for h in all_shas if h.startswith(c)]
        if not m:
            viol.append({"rule": "ENTRY_UNKNOWN_COMMIT", "commit": c, "why": "登记的 commit 在仓库里不存在（前缀也不匹配）"})
        tests = e.get("tests", []) or []
        if not tests:
            viol.append({"rule": "ENTRY_NO_TESTS", "commit": c, "why": "登记必须给至少一条用例（file::test）"})
        for t in tests:
            if "::" not in str(t):
                viol.append({"rule": "BAD_TEST_REF", "commit": c, "test": str(t), "why": "用例引用格式应为 file::test_name"})
                continue
            f, name = str(t).split("::", 1)
            fp = os.path.join(repo, f.replace("/", os.sep))
            if not os.path.isfile(fp):
                viol.append({"rule": "TEST_FILE_MISSING", "commit": c, "test": str(t), "why": "用例文件不存在"})
                continue
            body = open(fp, encoding="utf-8", errors="replace").read()
            if not re.search(r"func\s+%s\s*\(" % re.escape(name), body):
                viol.append({"rule": "TEST_NAME_MISSING", "commit": c, "test": str(t), "why": "文件里找不到该测试函数"})

    result = {
        "status": "ok" if not viol else "violations",
        "baseline_commit": baseline,
        "fix_commits": len(fix_commits),
        "entries": len(entries),
        "bound": len(bound),
        "violations": viol,
        "counts": {
            "fix_commits": len(fix_commits),
            "entries": len(entries),
            "unbound": sum(1 for v in viol if v["rule"] == "FIX_UNBOUND"),
            "bad_tests": sum(1 for v in viol if v["rule"] in ("TEST_FILE_MISSING", "TEST_NAME_MISSING", "BAD_TEST_REF", "ENTRY_NO_TESTS")),
            "total": len(viol),
        },
    }
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    json.dump(result, open(a.out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

    if viol:
        print("[bugbind] 缺陷绑定违规 %d 处（[fix] 提交 %d 个 / 登记 %d 条）：" % (len(viol), len(fix_commits), len(entries)))
        for v in viol[:20]:
            print("  - %-20s %s" % (v["rule"], (v.get("commit", "") + " " + str(v.get("test", "")) + " " + v.get("subject", ""))[:110]))
        return 1
    print("[bugbind] 缺陷绑定合规：[fix] 提交 %d 个，全部有登记；登记 %d 条，用例均存在" % (len(fix_commits), len(entries)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
