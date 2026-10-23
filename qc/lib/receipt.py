#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""交付证据链（迭代160 · 第三轮 S2 / WS8）。

产出 receipt.json：把"这次交付**测的到底是什么**"绑定成可校验的清单 ——
  · git：游戏仓 head/脏否/tag，文档仓 head/脏否；
  · counts：本轮的机器计数快照；
  · manifest：被测输入（tests/**、src/**、qc/lib/**、qc/config/**）的 sha256 + 字节数。

校验（--verify）：重算 manifest 哈希 + 对比 counts ⇒ 任何"交付后又改过文件/改过数字"都会被发现。
退出码：0 绿 / 1 不一致 / 2 参数错误。
"""
import argparse, hashlib, json, os, subprocess, sys

MANIFEST_GLOBS = ("tests", "src", "qc/lib", "qc/config")
SKIP_NAMES = {"local.json"}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def walk_files(root, rel_top):
    base = os.path.join(root, rel_top.replace("/", os.sep))
    if not os.path.isdir(base):
        return
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in (".godot", "__pycache__", "out")]
        for name in sorted(filenames):
            if name in SKIP_NAMES or name.endswith(".uid"):
                continue
            full = os.path.join(dirpath, name)
            yield os.path.relpath(full, root).replace(os.sep, "/"), full


def manifest(root):
    out = []
    for top in MANIFEST_GLOBS:
        for rel, full in walk_files(root, top):
            try:
                out.append({"path": rel, "sha256": sha256(full), "bytes": os.path.getsize(full)})
            except OSError:
                pass
    return sorted(out, key=lambda x: x["path"])


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return r.stdout.strip() if r.returncode == 0 else ""


def git_info(repo):
    return {
        "head": git(repo, "rev-parse", "HEAD"),
        "head_short": git(repo, "rev-parse", "--short", "HEAD"),
        "subject": git(repo, "log", "-1", "--format=%s"),
        "dirty": bool(git(repo, "status", "--porcelain")),
        "tags_at_head": git(repo, "tag", "--points-at", "HEAD").split(),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--docs-repo", default="")
    ap.add_argument("--counts", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--iteration", default="")
    ap.add_argument("--verify", default="", help="给定既有 receipt 做校验，不写新文件")
    a = ap.parse_args()
    repo = os.path.abspath(a.repo)

    if not os.path.isfile(a.counts):
        print("[receipt] 找不到 counts：%s（先跑 qc all）" % a.counts)
        return 2
    counts = json.load(open(a.counts, encoding="utf-8-sig"))

    if a.verify:
        want = json.load(open(a.verify, encoding="utf-8-sig"))
        cur = {m["path"]: m["sha256"] for m in manifest(repo)}
        old = {m["path"]: m["sha256"] for m in want.get("manifest", [])}
        bad = []
        for p, h in old.items():
            if p not in cur:
                bad.append(("MISSING", p))
            elif cur[p] != h:
                bad.append(("CHANGED", p))
        for p in cur:
            if p not in old:
                bad.append(("NEW", p))
        if want.get("counts") != counts:
            diff = {k: (want.get("counts", {}).get(k), counts.get(k))
                    for k in set(list(want.get("counts", {})) + list(counts))
                    if want.get("counts", {}).get(k) != counts.get(k)}
            bad.append(("COUNTS", str(diff)[:200]))
        if bad:
            print("[receipt] 校验失败 %d 处：" % len(bad))
            for kind, p in bad[:20]:
                print("  - %-8s %s" % (kind, p))
            return 1
        print("[receipt] 校验通过：manifest %d 个文件 + counts 与交付时一致" % len(cur))
        return 0

    rec = {
        "iteration": a.iteration,
        "counts": counts,
        "git": {"game": git_info(repo)},
        "manifest": manifest(repo),
    }
    if a.docs_repo and os.path.isdir(a.docs_repo):
        rec["git"]["docs"] = git_info(os.path.abspath(a.docs_repo))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    json.dump(rec, open(a.out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("[receipt] 已写：%s（manifest %d 文件 · game %s%s%s）" % (
        os.path.basename(a.out), len(rec["manifest"]),
        rec["git"]["game"]["head_short"], "" if a.iteration == "" else " · " + a.iteration,
        "" if not rec["git"]["game"]["dirty"] else " · **脏工作区**"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
