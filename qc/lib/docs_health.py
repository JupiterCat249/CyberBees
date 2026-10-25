#!/usr/bin/env python3
"""docs-health —— 文档健康闸（G4 批次2 · 迭代169）

查三件（只读）：
  1. 相对链接死链：]（路径） 指向的文件不存在（跳过 http/#/mailto、代码块与行内代码）
  2. 时间戳：系统维护 / 项目规划蓝图 下的 md 前 20 行必须有"最后更新：YYYY-MM-DD"（白名单/豁免除外）
  3. 变更记录陈旧：文档有"变更记录"表时，表内最新日期不得早于"最后更新"日期（warn）

配置：qc/config/docs_health.json（stamp_dirs / stamp_skip / stamp_exempt / dead_link_exempt）
用法：docs_health.py --docs-repo <文档仓> --config <json> --out qc/out/docs_health.json
退出码：0 无 violation；1 有；2 环境缺失
"""
import argparse, json, os, re, sys, urllib.parse

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

FENCE = re.compile(r"(?s)\x60\x60\x60.*?\x60\x60\x60")
INLINE = re.compile(r"\x60[^\x60]*\x60")
LINK = re.compile(r"\]\(([^)\s]+)")
STAMP = re.compile(r"最后更新[：:]\s*(\d{4}-\d{2}-\d{2})")
DATE = re.compile(r"\d{4}-\d{2}-\d{2}")

DEFAULTS = {"stamp_dirs": ["系统维护", "项目规划蓝图"],
            "stamp_skip": ["模板", "归档", "迭代记录", "灵感池", "_INDEX"],
            "stamp_exempt": [], "dead_link_exempt": []}


def walk_md(base):
    for root, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if d not in (".git", "node_modules", "addons", ".venv")]
        for fn in files:
            if fn.endswith(".md"):
                yield os.path.join(root, fn)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--docs-repo", required=True)
    ap.add_argument("--config", required=True)
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    if not os.path.isdir(a.docs_repo):
        print("[docs-health] 文档仓不存在：%s" % a.docs_repo)
        return 2
    cfg = dict(DEFAULTS)
    if os.path.isfile(a.config):
        with open(a.config, encoding="utf-8-sig") as f:
            cfg.update(json.load(f))
    dead_exempt = set(cfg.get("dead_link_exempt") or [])
    stamp_exempt = set(cfg.get("stamp_exempt") or [])

    files = list(walk_md(a.docs_repo))
    dead, no_stamp, stale_changelog = [], [], []
    links_total = 0
    for full in files:
        rel = os.path.relpath(full, a.docs_repo).replace(os.sep, "/")
        with open(full, encoding="utf-8-sig", errors="replace") as f:
            body = f.read()
        clean = INLINE.sub("", FENCE.sub("", body))
        for m in LINK.finditer(clean):
            tgt = m.group(1).strip()
            if tgt.startswith(("http://", "https://", "#", "mailto:", "tel:", "data:")):
                continue
            tgt = tgt.split("#")[0].split("?")[0]
            if not tgt:
                continue
            links_total += 1
            cand = urllib.parse.unquote(tgt)
            p1 = os.path.normpath(os.path.join(os.path.dirname(full), cand))
            p2 = os.path.normpath(os.path.join(a.docs_repo, cand.lstrip("/")))
            if not (os.path.exists(p1) or os.path.exists(p2)):
                key = rel + " -> " + tgt
                if key not in dead_exempt:
                    dead.append(key)
        if any(rel == x or rel.startswith(x + "/") for x in cfg["stamp_dirs"]):
            if any(k in rel for k in cfg["stamp_skip"]):
                continue
            if rel in stamp_exempt:
                continue
            head = "\n".join(body.splitlines()[:20])
            if not STAMP.search(head):
                no_stamp.append(rel)
                continue
        if "变更记录" in body and STAMP.search(body):
            head_dates = STAMP.findall("\n".join(body.splitlines()[:20]))
            stamp_date = head_dates[0] if head_dates else ""
            tail = body[body.index("变更记录"):]
            dates = DATE.findall(tail)
            if stamp_date and dates and max(dates) < stamp_date:
                stale_changelog.append("%s (最后更新 %s > 变更记录最新 %s)" % (rel, stamp_date, max(dates)))

    counts = {"docs_health:files": len(files), "docs_health:links": links_total,
              "docs_health:dead": len(dead), "docs_health:no_stamp": len(no_stamp),
              "docs_health:changelog_stale": len(stale_changelog)}
    print("[docs-health] 文件 %d · 相对链接 %d · 死链 %d · 缺时间戳 %d · 变更记录陈旧 %d(w)"
          % (len(files), links_total, len(dead), len(no_stamp), len(stale_changelog)))
    for d in dead[:10]:
        print("  [VIOLATION] 死链: " + d)
    for s in no_stamp[:10]:
        print("  [VIOLATION] 缺时间戳: " + s)
    for s in stale_changelog[:5]:
        print("  [warn] " + s)

    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump({"ok": (not dead and not no_stamp), "counts": counts,
                       "dead": dead, "no_stamp": no_stamp, "changelog_stale": stale_changelog},
                      f, ensure_ascii=False, indent=1)
    return 1 if (dead or no_stamp) else 0


if __name__ == "__main__":
    sys.exit(main())
