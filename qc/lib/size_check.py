#!/usr/bin/env python3
"""文件体积/行数门禁（迭代082）。

规则（由 qc/config/size_policy.json 定义）：
  R1 单文件不得超过 max_lines / max_bytes；
  R2 超限的历史文件必须登记在 size_baseline.json 的 exempt 里，且**只许变小**
     （当前行数 > 登记行数 ⇒ 红；字节同理）；
  R3 掉到上限以下后必须从 exempt 移除（挂着占位 ⇒ 红）。

输出 JSON：{ over_cap, max_lines, max_bytes, violations:[...], exempt_used:{...} }
退出码：0 通过 / 1 违规
"""
import argparse, json, os, sys


def load_json(path, default):
    if not os.path.isfile(path):
        return default
    with open(path, encoding="utf-8-sig") as f:
        return json.load(f)


def walk(repo, exts, exclude):
    out = []
    for dirpath, dirnames, filenames in os.walk(repo):
        dirnames[:] = [d for d in dirnames if d not in exclude]
        for fn in filenames:
            if any(fn.endswith(e) for e in exts):
                out.append(os.path.join(dirpath, fn))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--policy", required=True)
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--tighten", action="store_true", help="把基线收紧到当前实测值（只降不升；已降到上限以下或消失的条目自动移除）")
    a = ap.parse_args()

    pol = load_json(a.policy, {})
    base = load_json(a.baseline, {"exempt": {}})
    max_lines = int(pol.get("max_lines", 1000))
    max_bytes = int(pol.get("max_bytes", 65536))
    exts = tuple(pol.get("include_ext", [".gd"]))
    exclude = set(pol.get("exclude_dirs", []))
    exempt = base.get("exempt", {}) or {}

    files = walk(a.repo, exts, exclude)
    violations = []
    used = {}
    max_seen_lines = 0
    max_seen_bytes = 0
    over_cap = 0
    for path in files:
        rel = os.path.relpath(path, a.repo).replace(os.sep, "/")
        try:
            raw = open(path, "rb").read()
        except OSError:
            continue
        nbytes = len(raw)
        nlines = raw.count(b"\n") + (0 if raw.endswith(b"\n") or nbytes == 0 else 1)
        max_seen_lines = max(max_seen_lines, nlines)
        max_seen_bytes = max(max_seen_bytes, nbytes)
        over = nlines > max_lines or nbytes > max_bytes
        if over:
            over_cap += 1
        rec = exempt.get(rel)
        if over and rec is None:
            violations.append({"kind": "NEW_OVERSIZE", "file": rel, "lines": nlines, "bytes": nbytes,
                               "why": "超过上限且未登记祖父条款（新文件不允许一出生就超限）"})
        elif over and rec is not None:
            used[rel] = {"lines": nlines, "bytes": nbytes}
            allow_lines = int(rec.get("lines", 0))
            allow_bytes = int(rec.get("bytes", 0))
            if nlines > allow_lines or nbytes > allow_bytes:
                violations.append({"kind": "GREW", "file": rel,
                                   "lines": nlines, "allow_lines": allow_lines,
                                   "bytes": nbytes, "allow_bytes": allow_bytes,
                                   "why": "祖父条款只许变小：超限文件不得再生长"})
        elif (not over) and rec is not None:
            violations.append({"kind": "STALE_EXEMPT", "file": rel, "lines": nlines,
                               "why": "已降到上限以下 —— 请从 size_baseline.json 移除该条"})
    for rel in exempt:
        if rel not in used and not any(v.get("file") == rel for v in violations):
            p = os.path.join(a.repo, rel.replace("/", os.sep))
            if not os.path.isfile(p):
                violations.append({"kind": "MISSING_EXEMPT", "file": rel,
                                   "why": "登记了但文件不存在 → 请移除该条"})

    result = {
        "files": len(files),
        "over_cap": over_cap,
        "max_lines": max_seen_lines,
        "max_bytes": max_seen_bytes,
        "exempt_count": len(exempt),
        "exempt_used": used,
        "violations": violations,
        "policy": {"max_lines": max_lines, "max_bytes": max_bytes},
    }
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    if a.tighten:
        new_exempt = {}
        changed = []
        for rel, cur in used.items():
            prev = exempt.get(rel) or {}
            lines = min(int(prev.get("lines", cur["lines"])), cur["lines"])
            nbytes = min(int(prev.get("bytes", cur["bytes"])), cur["bytes"])
            new_exempt[rel] = {"lines": lines, "bytes": nbytes}
            if lines != int(prev.get("lines", lines)) or nbytes != int(prev.get("bytes", nbytes)):
                changed.append("%s %s->%s 行 / %s->%s 字节" % (rel, prev.get("lines"), lines, prev.get("bytes"), nbytes))
        dropped = [r for r in exempt if r not in new_exempt]
        doc = {"$comment": "祖父条款：历史上已超限的文件登记于此，只许变小（长一行/一字节即红）。snapshot 自动收紧登记值；降到上限以下或消失的条目自动移除。", "exempt": new_exempt}
        with open(a.baseline, "w", encoding="utf-8-sig") as f:   # 带 BOM：PS 5.1 的 Get-Content 才显示正常
            json.dump(doc, f, ensure_ascii=False, indent=2)
        if changed:
            print("  祖父条款收紧：" + "; ".join(changed))
        if dropped:
            print("  移出祖父条款（已达标/已消失）：" + ", ".join(dropped))
        if not changed and not dropped:
            print("  祖父条款无需调整")

    print("files=%d  over_cap=%d  max_lines=%d  max_bytes=%d  exempt=%d"
          % (len(files), over_cap, max_seen_lines, max_seen_bytes, len(exempt)))
    for v in violations:
        print("  [%s] %s  (%s)" % (v["kind"], v["file"], v["why"]))
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
