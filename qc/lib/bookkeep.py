#!/usr/bin/env python3
"""bookkeep —— 迭代记账校验（G4 批次1 · 迭代168）

只读，不改任何文件。查：
  1. 每个 迭代NNN/ 目录必须有 记录.md
  2. 索引.md 必须为每个目录有一行
  3. 索引里的相对链接必须存在（防重构后死链）
  4. git 应有 iter/NNN tag（缺失 = warning；早期迭代未打 tag）
  5. 最近 60 条提交格式（[type] 迭代NNN/Mn/Sn ...）不合规 = warning
  6. 夜检新鲜度（>2 天 = warning）
  7. 系统维护/项目规划蓝图下 md 的时间戳（缺失 = info）

退出码：0 无 violation；1 有 violation；2 环境缺失
"""
import argparse, datetime, json, os, re, subprocess, sys
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

SKIP_STAMP = ("模板", "归档", "迭代记录", "灵感池", "_INDEX")
TAG_MIN = 68   # 迭代068 起才有 iter/NNN tag
MIN_ENFORCED = 68  # 质控体系自迭代068 建立；更早的目录只作 legacy info


def run(args):
    try:
        r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")
        return r.stdout.strip()
    except Exception:
        return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--docs-repo", required=True)
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    it_root = os.path.join(a.docs_repo, "实时开发记录", "迭代记录")
    index_path = os.path.join(it_root, "索引.md")
    if not os.path.isdir(it_root):
        print("[bookkeep] 找不到迭代记录目录：%s" % it_root)
        return 2

    dirs = sorted([d for d in os.listdir(it_root) if re.fullmatch(r"迭代\d{3}", d)])
    violations, warnings, infos = [], [], []

    missing_records = [d for d in dirs if not os.path.isfile(os.path.join(it_root, d, "记录.md"))]
    legacy_records = [d for d in missing_records if int(d[2:]) < MIN_ENFORCED]
    violations += ["缺记录：%s/记录.md" % d for d in missing_records if int(d[2:]) >= MIN_ENFORCED]
    infos += ["legacy 缺记录（不计 violation）：%s" % d for d in legacy_records]

    index_text = ""
    if os.path.isfile(index_path):
        with open(index_path, encoding="utf-8-sig") as f:
            index_text = f.read()
    else:
        violations.append("缺索引：%s" % index_path)

    missing_rows = [d for d in dirs if ("| %s |" % d) not in index_text]
    legacy_rows = [d for d in missing_rows if int(d[2:]) < MIN_ENFORCED]
    violations += ["索引缺行：%s" % d for d in missing_rows if int(d[2:]) >= MIN_ENFORCED]
    infos += ["legacy 索引缺行（不计 violation）：%s" % d for d in legacy_rows]

    broken = []
    for m in re.finditer(r"\]\((?!https?:|#)([^)]+)\)", index_text):
        rel = m.group(1).strip().replace("/", os.sep)
        if not os.path.exists(os.path.join(it_root, rel)):
            broken.append(rel)
    violations += ["索引死链：%s" % x for x in broken]

    tags = set(x.strip() for x in run(["git", "-C", a.repo, "tag", "--list", "iter/*"]).splitlines() if x.strip())
    missing_tags = [d for d in dirs if int(d[2:]) >= TAG_MIN and ("iter/%03d" % int(d[2:])) not in tags]
    warnings += ["缺 tag：iter/%s" % d[2:] for d in missing_tags]

    subjects = [x for x in run(["git", "-C", a.repo, "log", "-60", "--pretty=format:%s"]).splitlines() if x.strip()]
    pat = re.compile(r"^\[[a-z]+\] (迭代\d{3}|M\d|S\d|G4|WS\d|reorg)")
    bad = [s for s in subjects if not pat.match(s)]
    warnings += ["提交格式：%s" % s[:60] for s in bad[:5]]

    latest = {}
    lp = os.path.join(a.repo, "qc", "out", "nightly", "latest.json")
    if os.path.isfile(lp):
        with open(lp, encoding="utf-8-sig") as f:
            latest = json.load(f)
    night_gap = None
    if latest.get("date"):
        try:
            night_gap = (datetime.date.today() - datetime.date.fromisoformat(str(latest["date"]))).days
            if night_gap > 2:
                warnings.append("夜检已 %d 天未跑（latest=%s）" % (night_gap, latest.get("date")))
        except ValueError:
            warnings.append("夜检日期不可解析：%s" % latest.get("date"))
    else:
        warnings.append("尚无夜检记录（qc nightly 未跑过）")

    no_stamp = 0
    for sub in ("系统维护", "项目规划蓝图"):
        base = os.path.join(a.docs_repo, sub)
        for root, _, files in os.walk(base):
            for fn in files:
                if not fn.endswith(".md"):
                    continue
                full = os.path.join(root, fn)
                rel = os.path.relpath(full, a.docs_repo)
                if any(k in rel for k in SKIP_STAMP):
                    continue
                try:
                    with open(full, encoding="utf-8-sig") as f:
                        head = "".join(f.readline() for _ in range(20))
                except Exception:
                    continue
                if not re.search(r"最后更新[：:]\s*\d{4}-\d{2}-\d{2}", head):
                    no_stamp += 1
    if no_stamp:
        infos.append("%d 份文档缺时间戳（白名单外）" % no_stamp)

    counts = {
        "bookkeep:iterations": len(dirs),
        "bookkeep:missing_records": len(missing_records),
        "bookkeep:missing_index": len(missing_rows),
        "bookkeep:broken_links": len(broken),
        "bookkeep:missing_tags": len(missing_tags),
        "bookkeep:bad_commits": len(bad),
        "bookkeep:no_stamp": no_stamp,
        "bookkeep:night_gap_days": (night_gap if night_gap is not None else -1),
        "bookkeep:violations": len(violations),
        "bookkeep:warnings": len(warnings),
    }

    print("[bookkeep] 迭代目录 %d · 缺记录 %d · 索引缺行 %d · 死链 %d · 缺 tag %d(w) · 提交格式 %d(w) · 夜检间隔 %s 天"
          % (len(dirs), len(missing_records), len(missing_rows), len(broken), len(missing_tags), len(bad), night_gap))
    for v in violations:
        print("  [VIOLATION] " + v)
    for w in warnings[:10]:
        print("  [warn] " + w)
    for i in infos:
        print("  [info] " + i)

    if a.out:
        payload = {"ok": not violations, "counts": counts, "violations": violations,
                   "warnings": warnings, "infos": infos}
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=1)
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
