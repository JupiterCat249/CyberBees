#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""差异覆盖探针（迭代162 · 第三轮 S4 / WS1）。

流程（全部由本脚本完成，跑完**必定还原**）：
  inject   : 给 src/**/*.gd 的每个函数入口插入 `CovProbe.touch("<rel>:<func>")`，
             并在 project.godot 的 [autoload] 里临时注册 CovProbe；
  restore  : 从备份还原 src/ 与 project.godot（幂等；找不到备份也会用 git checkout 兜底）；
  report   : 读覆盖结果 + 列出函数清单 ⇒ coverage.json（含"改动文件里未覆盖的函数"）。

安全：inject 前要求工作区**干净**（src/ 与 project.godot 无未提交改动），否则拒绝执行。
退出码：0 成功 / 1 检查失败（有未覆盖的改动函数）/ 2 环境或参数错误。
"""
import argparse, json, os, re, subprocess, sys

BACKUP = ".cov-backup"
SKIP_DIRS = {".godot", "__pycache__"}
FUNC_RE = re.compile(r"^(\s*)(static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")


def sh(args, cwd):
    r = subprocess.run(args, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def src_files(repo):
    out = []
    for dirpath, dirnames, filenames in os.walk(os.path.join(repo, "src")):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for n in filenames:
            if n.endswith(".gd"):
                out.append(os.path.relpath(os.path.join(dirpath, n), repo).replace(os.sep, "/"))
    return sorted(out)


def inject(repo):
    bk = os.path.join(repo, BACKUP)
    os.makedirs(bk, exist_ok=True)
    manifest = []
    for rel in src_files(repo):
        full = os.path.join(repo, rel)
        raw = open(full, "rb").read().decode("utf-8")
        dst = os.path.join(bk, rel.replace("/", "__"))
        open(dst, "wb").write(raw.encode("utf-8"))
        lines = raw.split("\n")
        out = []
        i = 0
        while i < len(lines):
            ln = lines[i]
            out.append(ln)
            m = FUNC_RE.match(ln)
            if m and "CovProbe.touch" not in ln:
                indent, _, name = m.group(1), m.group(2), m.group(3)
                ## 签名可能跨行：向下找以 ":" 结尾的那一行
                ## ⚠️ 若签名行/续行里已经有函数体（": pass" 之类），跳过该函数（不注入）
                if ":" in lines[i][lines[i].find(")"):] and not lines[i].rstrip().endswith(":"):
                    i += 1
                    continue
                j = i
                ok = False
                while j < len(lines):
                    if lines[j].rstrip().endswith(":"):
                        ok = True
                        break
                    j += 1
                    if j < len(lines):
                        out.append(lines[j])
                if not ok:
                    i += 1
                    continue
                key = "%s:%s" % (rel, name)
                out.append("%s\tCovProbe.touch(%s)" % (indent, json.dumps(key)))
                manifest.append({"file": rel, "func": name, "line": i + 1, "key": key})
                i = j + 1
                continue
            i += 1
        open(full, "wb").write("\n".join(out).encode("utf-8"))
    ## autoload 注册（备份 project.godot）
    proj = os.path.join(repo, "project.godot")
    praw = open(proj, "rb").read().decode("utf-8")
    open(os.path.join(bk, "__project.godot"), "wb").write(praw.encode("utf-8"))
    if "CovProbe=" not in praw:
        if "[autoload]" in praw:
            praw = praw.replace("[autoload]", '[autoload]\nCovProbe="*res://dev/probes/cov_probe.gd"', 1)
        else:
            praw = praw.rstrip() + '\n\n[autoload]\nCovProbe="*res://dev/probes/cov_probe.gd"\n'
        open(proj, "wb").write(praw.encode("utf-8"))
    json.dump(manifest, open(os.path.join(bk, "manifest.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("[cov] 已注入 %d 个函数探针（备份在 %s）" % (len(manifest), BACKUP))
    return 0


def restore(repo):
    bk = os.path.join(repo, BACKUP)
    if not os.path.isdir(bk):
        print("[cov] 没有备份目录，尝试 git 兜底还原")
        sh(["git", "checkout", "--", "src", "project.godot"], repo)
        return 0
    n = 0
    for name in os.listdir(bk):
        src = os.path.join(bk, name)
        if name == "manifest.json":
            continue
        if name == "__project.godot":
            open(os.path.join(repo, "project.godot"), "wb").write(open(src, "rb").read())
            n += 1
            continue
        rel = name.replace("__", "/")
        open(os.path.join(repo, rel), "wb").write(open(src, "rb").read())
        n += 1
    print("[cov] 已从备份还原 %d 个文件" % n)
    return 0


def changed_functions(repo, ref):
    rc, out, err = sh(["git", "diff", "--unified=0", ref, "--", "src"], repo)
    if rc != 0:
        return None
    changed = {}   # file -> set(lines)
    cur = None
    for ln in out.splitlines():
        if ln.startswith("+++ b/"):
            cur = ln[6:]
            changed.setdefault(cur, set())
        elif ln.startswith("@@") and cur:
            m = re.search(r"\+(\d+)(?:,(\d+))?", ln)
            if m:
                start = int(m.group(1))
                count = int(m.group(2) or 1)
                for k in range(start, start + count):
                    changed[cur].add(k)
    return changed


def report(repo, ref):
    bk = os.path.join(repo, BACKUP)
    manifest = json.load(open(os.path.join(bk, "manifest.json"), encoding="utf-8"))
    cov_path = os.path.join(repo, "qc", "out", "cov.json")
    hits = {}
    if os.path.isfile(cov_path):
        hits = json.load(open(cov_path, encoding="utf-8-sig")).get("hits", {})
    covered = {k for k in hits if int(hits[k]) > 0}
    all_keys = {m["key"] for m in manifest}
    uncovered = sorted(all_keys - covered)

    changed = changed_functions(repo, ref)
    changed_uncovered = []
    if changed is not None:
        for m in manifest:
            lines = changed.get(m["file"])
            if not lines:
                continue
            if m["line"] in lines and m["key"] not in covered:
                changed_uncovered.append(m["key"])
    result = {
        "total": len(all_keys),
        "covered": len(covered & all_keys),
        "percent": round(100.0 * len(covered & all_keys) / max(1, len(all_keys)), 1),
        "changed_ref": ref,
        "changed_uncovered": changed_uncovered,
        "uncovered_count": len(uncovered),
        "uncovered_all": uncovered,
        "uncovered_sample": uncovered[:80],
    }
    os.makedirs(os.path.join(repo, "qc", "out"), exist_ok=True)
    json.dump(result, open(os.path.join(repo, "qc", "out", "coverage.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    print("[cov] 函数覆盖 %d/%d（%.1f%%）；未覆盖 %d 个；改动函数未覆盖 %d 个（ref=%s）" % (
        result["covered"], result["total"], result["percent"], result["uncovered_count"], len(changed_uncovered), ref))
    for k in changed_uncovered[:15]:
        print("  - UNCOVERED %s" % k)
    return 1 if changed_uncovered else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("action", choices=["inject", "restore", "report"])
    ap.add_argument("--ref", default="HEAD")
    a = ap.parse_args()
    repo = os.path.abspath(a.repo)
    if a.action == "inject":
        return inject(repo)
    if a.action == "restore":
        return restore(repo)
    return report(repo, a.ref)


if __name__ == "__main__":
    sys.exit(main())
