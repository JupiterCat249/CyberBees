#!/usr/bin/env python3
"""verify-head —— 证据链闭合检查（G4 批次2 · 迭代169）

问题：AI 可以口头说"我跑过 qc"，但没有任何机器证据。
做法：要求"当前 HEAD 有一份最近的证据"——receipt.json 或 nightly/latest.json 里记录了同一个 HEAD，
      且时间在 --max-age-hours 内。没有证据 = 红（说明改完没跑过）。

用法：verify_head.py --repo <仓根> [--max-age-hours 24] [--out qc/out/verify_head.json]
退出码：0 有证据；1 无证据/过期；2 环境缺失
"""
import argparse, datetime, json, os, subprocess, sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def run(args):
    try:
        r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")
        return r.stdout.strip()
    except Exception:
        return ""


def load(path, default=None):
    try:
        with open(path, encoding="utf-8-sig") as f:
            return json.load(f)
    except Exception:
        return default if default is not None else {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--max-age-hours", type=float, default=24.0)
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    head = run(["git", "-C", a.repo, "rev-parse", "--short=7", "HEAD"])
    if not head:
        print("[verify-head] 不是 git 仓库或无提交")
        return 2
    now = datetime.datetime.now()

    evidence = []
    rcpt = os.path.join(a.repo, "qc", "out", "receipt.json")
    if os.path.isfile(rcpt):
        r = load(rcpt)
        g = r.get("git") or {}
        if isinstance(g.get("game"), dict):
            h = str(g["game"].get("head_short") or g["game"].get("head", ""))[:7]
        else:
            h = str(g.get("head_short") or g.get("head", ""))[:7]
        ts = r.get("generated") or r.get("time") or ""
        evidence.append(("receipt", h, ts, os.path.getmtime(rcpt)))
    latest = os.path.join(a.repo, "qc", "out", "nightly", "latest.json")
    if os.path.isfile(latest):
        n = load(latest)
        h = str(n.get("head", ""))[:7]
        ts = n.get("date", "")
        evidence.append(("nightly", h, ts, os.path.getmtime(latest)))

    ok = False
    matched = ""
    for src, h, ts, mtime in evidence:
        age_h = (now - datetime.datetime.fromtimestamp(mtime)).total_seconds() / 3600.0
        if h and h == head and age_h <= a.max_age_hours:
            ok = True
            matched = src
            break

    counts = {"verify_head:evidence": len(evidence), "verify_head:stale": (0 if ok else 1),
              "verify_head:max_age_h": a.max_age_hours}
    if ok:
        print("[verify-head] HEAD %s 有证据（%s）" % (head, matched))
    else:
        print("[verify-head] HEAD %s 没有 %gh 内的证据 —— 改完请跑 qc receipt 或 qc nightly" % (head, a.max_age_hours))
        for src, h, ts, mtime in evidence:
            age_h = round((now - datetime.datetime.fromtimestamp(mtime)).total_seconds() / 3600.0, 1)
            print("  [证据] %-8s head=%-8s age=%.1fh ts=%s" % (src, h or "?", age_h, ts or "-"))

    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump({"ok": ok, "head": head, "matched": matched, "counts": counts,
                       "evidence": [{"src": s, "head": h, "ts": t} for s, h, t, _ in evidence]},
                      f, ensure_ascii=False, indent=1)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
