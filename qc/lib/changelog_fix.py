#!/usr/bin/env python3
"""changelog_fix —— 变更记录审计与补齐（迭代172 · 收尾合规）

对 docs-health 报出的"变更记录陈旧"文档：
  1. 取该文件的最后一次 git 提交（日期 + hash + 标题）；
  2. 把「最后更新」的日期校正为提交日期（可核对的事实）；
  3. 若「变更记录」表的最新日期仍早于该日期，补一行（写明依据 git 提交）。
只处理干净文件（有未提交改动则跳过）。

用法：changelog_fix.py --docs-repo <文档仓> --list qc/out/docs_health.json [--dry-run]
"""
import argparse, json, os, re, subprocess, sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return r.stdout.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--docs-repo", required=True)
    ap.add_argument("--list", required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if not os.path.isfile(a.list):
        print("[changelog] 找不到 %s（先跑 qc docs-health）" % a.list)
        return 2
    data = json.load(open(a.list, encoding="utf-8-sig"))
    items = [x.split(" (")[0] for x in data.get("changelog_stale", [])]
    fixed, skipped = 0, 0
    for rel in items:
        full = os.path.join(a.docs_repo, rel)
        if not os.path.isfile(full):
            skipped += 1
            continue
        if git(a.docs_repo, "status", "--porcelain", "--", rel):
            print("  [skip] 有未提交改动：%s" % rel)
            skipped += 1
            continue
        last = git(a.docs_repo, "log", "-1", "--format=%ad|%h|%s", "--date=short", "--", rel)
        if not last:
            print("  [skip] 无提交记录：%s" % rel)
            skipped += 1
            continue
        date, h, subj = last.split("|", 2)
        raw = open(full, "rb").read()
        bom = raw.startswith(b"\xef\xbb\xbf")
        text = raw.decode("utf-8-sig")
        lines = text.split("\n")

        upd = -1
        for i, ln in enumerate(lines[:20]):
            if "最后更新" in ln:
                upd = i
                break
        if upd >= 0:
            lines[upd] = re.sub(r"\d{4}-\d{2}-\d{2}", date, lines[upd], count=1)

        heading = -1
        for i, ln in enumerate(lines):
            if re.match(r"^#{1,6}\s*.*变更记录", ln):
                heading = i
        if heading < 0:
            print("  [skip] 无变更记录章节：%s" % rel)
            skipped += 1
            continue
        last_row = -1
        newest = None
        for i in range(heading + 1, len(lines)):
            m = re.match(r"^\|\s*(\d{4}-\d{2}-\d{2})\s*\|", lines[i])
            if m:
                last_row = i
                newest = m.group(1)
        if newest and newest < date:
            new_row = "| %s | 补齐：该日修订此前未登记（依据 git `%s`：%s） |" % (date, h, subj.replace("|", "/")[:80])
            lines.insert(last_row + 1, new_row)
            print("  [fix] %s：最后更新→%s，补记一行（git %s）" % (rel, date, h))
        else:
            print("  [fix] %s：最后更新→%s（变更记录已覆盖）" % (rel, date))
        fixed += 1
        text = "\n".join(lines)
        if not a.dry_run:
            with open(full, "wb") as f:
                f.write((b"\xef\xbb\xbf" if bom else b"") + text.encode("utf-8"))
    print("[changelog] 处理 %d 条（修复 %d · 跳过 %d）%s" % (len(items), fixed, skipped, "（dry-run）" if a.dry_run else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
