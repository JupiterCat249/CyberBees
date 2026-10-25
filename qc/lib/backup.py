#!/usr/bin/env python3
"""backup —— 文档仓本地备份（G4 批次3 · 迭代170）

做法：git bundle create（含全部 refs）→ git bundle verify 校验 → 保留最近 N 份。
不联网；备份目录默认在仓库外（配置 qc/config/backup.json）。

用法：backup.py --docs-repo <文档仓> --config <json> [--out qc/out/backup.json]
退出码：0 成功；1 失败；2 环境缺失
"""
import argparse, datetime, json, os, subprocess, sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def run(args):
    try:
        p = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except Exception as e:
        return 2, str(e)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--docs-repo", required=True)
    ap.add_argument("--config", required=True)
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    cfg = {"dest": "", "keep": 7}
    if os.path.isfile(a.config):
        with open(a.config, encoding="utf-8-sig") as f:
            cfg.update(json.load(f))
    dest = cfg.get("dest") or ""
    keep = int(cfg.get("keep", 7))
    if not dest:
        print("[backup] 未配置 dest（qc/config/backup.json）")
        return 2
    os.makedirs(dest, exist_ok=True)
    day = datetime.date.today().isoformat()
    out = os.path.join(dest, "docs-%s.bundle" % day)

    rc, txt = run(["git", "-C", a.docs_repo, "bundle", "create", out, "--all"])
    if rc != 0:
        print("[backup] 创建失败：%s" % txt.strip()[:200])
        return 1
    rc2, txt2 = run(["git", "-C", a.docs_repo, "bundle", "verify", out])
    size = os.path.getsize(out) if os.path.isfile(out) else 0

    old = sorted([f for f in os.listdir(dest) if f.startswith("docs-") and f.endswith(".bundle")])
    removed = 0
    if keep > 0:
        for f in old[:-keep]:
            os.remove(os.path.join(dest, f))
            removed += 1

    ok = (rc2 == 0 and size > 0)
    counts = {"backup:bundles": len(old), "backup:keep": keep, "backup:bytes": size, "backup:removed": removed}
    print("[backup] %s · %.1f KB · verify=%s · 保留 %d 份（清理 %d）"
          % (os.path.basename(out), size / 1024.0, "OK" if ok else "FAIL", min(len(old), keep) if keep else len(old), removed))
    if not ok:
        print("  [VIOLATION] bundle 校验失败：%s" % txt2.strip()[:200])
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump({"ok": ok, "counts": counts, "path": out}, f, ensure_ascii=False, indent=1)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
