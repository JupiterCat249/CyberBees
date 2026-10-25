#!/usr/bin/env python3
"""aicheck —— AI 行为契约检查（G4 批次2 · 迭代169）

把人已明文写过的规则转成机器判红（不靠 AI 自述）：
  C1 提交信息符合 [type] 迭代NNN/G4/Mn/Sn ...（HEAD）
  C2 最近一个迭代记录必须有"验证"节，且提到 qc all / exit / 测试任一
  C3 最近一次提交的 .gd 改动不得触碰被禁字段（默认 font_size —— 人 2026-09-19 硬约束）

豁免：qc/config/ai_contract.json 的 waivers（每条须写理由与到期复核）。

用法：aicheck.py --repo <仓根> --docs-repo <文档仓> [--out qc/out/aicheck.json]
退出码：0 无 violation；1 有；2 环境缺失
"""
import argparse, json, os, re, subprocess, sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

DEFAULT = {
    "commit_regex": r"^\[[a-z]+\] (迭代\d{3}|G4|M\d|S\d|WS\d|reorg)",
    "record_glob": "实时开发记录/迭代记录/迭代{num}/记录.md",
    "record_require_any": ["验证", "qc all", "exit 0"],
    "forbidden": [
        {"id": "font-size", "glob": "*.gd", "pattern": r"font_size\s*=",
         "desc": "人 2026-09-19 硬约束：不得改字号字段（参数资源默认 0 = 沿用素材）"}
    ],
    "waivers": []
}


def run(args):
    try:
        r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")
        return r.stdout
    except Exception:
        return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--docs-repo", required=True)
    ap.add_argument("--config", required=True)
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    cfg = dict(DEFAULT)
    if os.path.isfile(a.config):
        with open(a.config, encoding="utf-8-sig") as f:
            cfg.update(json.load(f))
    waivers = {w.get("id") for w in cfg.get("waivers", []) if w.get("id")}
    violations, warnings = [], []

    subject = run(["git", "-C", a.repo, "log", "-1", "--pretty=%s"]).strip()
    if cfg.get("commit_regex") and not re.match(cfg["commit_regex"], subject):
        violations.append("C1 提交信息不合规：%s" % subject[:70])

    recs_root = os.path.join(a.docs_repo, "实时开发记录", "迭代记录")
    latest = ""
    if os.path.isdir(recs_root):
        items = [d for d in os.listdir(recs_root) if re.fullmatch(r"迭代\d{3}", d)]
        latest = max(items, key=lambda x: int(x[2:])) if items else ""
    if latest:
        rec = os.path.join(recs_root, latest, "记录.md")
        if not os.path.isfile(rec):
            violations.append("C2 最近迭代 %s 缺记录.md" % latest)
        else:
            with open(rec, encoding="utf-8-sig") as f:
                body = f.read()
            if not any(k in body for k in cfg.get("record_require_any", [])):
                violations.append("C2 %s 记录里没有验证性内容（%s）" % (latest, "/".join(cfg.get("record_require_any", []))))
    else:
        warnings.append("找不到迭代记录目录：%s" % recs_root)

    # C3：只看最近一次提交的 .gd 差异（新增行）
    diff = run(["git", "-C", a.repo, "diff", "HEAD~1", "HEAD", "--unified=0", "--", "*.gd"])
    changed = [ln[1:] for ln in diff.splitlines() if ln.startswith("+") and not ln.startswith("+++")]
    for item in cfg.get("forbidden", []):
        pat = re.compile(item.get("pattern", ""))
        hits = [ln for ln in changed if pat.search(ln)]
        if hits and item.get("id") not in waivers:
            violations.append("C3 触碰禁改字段 [%s]：%s" % (item.get("id"), hits[0].strip()[:70]))

    counts = {"aicheck:violations": len(violations), "aicheck:warnings": len(warnings),
              "aicheck:changed_gd_lines": len(changed)}
    print("[aicheck] 提交=%s · 最近迭代=%s · .gd 新增行=%d · violations=%d" % (subject[:40], latest or "?", len(changed), len(violations)))
    for v in violations:
        print("  [VIOLATION] " + v)
    for w in warnings:
        print("  [warn] " + w)

    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump({"ok": not violations, "counts": counts, "violations": violations,
                       "warnings": warnings, "subject": subject, "iteration": latest},
                      f, ensure_ascii=False, indent=1)
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
