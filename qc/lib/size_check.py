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
    ap.add_argument("--warn-ratio", type=float, default=None,
                    help="预警比例（默认读 policy 的 warn_ratio，缺省 0.9）：未超限但已达上限该比例时**只提示不判红**")
    ap.add_argument("--tighten", action="store_true", help="把基线收紧到当前实测值（只降不升；已降到上限以下或消失的条目自动移除）")
    a = ap.parse_args()

    pol = load_json(a.policy, {})
    base = load_json(a.baseline, {"exempt": {}})
    max_lines = int(pol.get("max_lines", 1000))
    max_bytes = int(pol.get("max_bytes", 65536))
    exts = tuple(pol.get("include_ext", [".gd"]))
    exclude = set(pol.get("exclude_dirs", []))
    exempt = base.get("exempt", {}) or {}
    warn_ratio = float(a.warn_ratio if a.warn_ratio is not None else pol.get("warn_ratio", 0.9))

    files = walk(a.repo, exts, exclude)
    violations = []
    warnings = []
    used = {}
    max_seen_lines = 0
    max_code_lines = 0
    max_code_bytes = 0
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
        ## ⭐ 迭代144（人 2026-10-23 口径）：**注释单独归类** —— 审计只看生产代码；
        ##   注释行与空行不计入上限判定（仍计入 total_* 供报告参考）。
        text = raw.decode("utf-8", errors="replace")
        code_lines, code_bytes = 0, 0
        for ln in text.split("\n"):
            st = ln.strip()
            if st == "" or st.startswith("#"):
                continue
            code_lines += 1
            code_bytes += len(ln.encode("utf-8")) + 1
        max_seen_lines = max(max_seen_lines, nlines)
        max_seen_bytes = max(max_seen_bytes, nbytes)
        max_code_lines = max(max_code_lines, code_lines)
        max_code_bytes = max(max_code_bytes, code_bytes)
        over = code_lines > max_lines or code_bytes > max_bytes
        if over:
            over_cap += 1
        rec = exempt.get(rel)
        if over and rec is None:
            violations.append({"kind": "NEW_OVERSIZE", "file": rel, "lines": code_lines, "bytes": code_bytes,
                               "why": "超过上限且未登记祖父条款（新文件不允许一出生就超限）"})
        elif over and rec is not None:
            used[rel] = {"lines": code_lines, "bytes": code_bytes}
            allow_lines = int(rec.get("lines", 0))
            allow_bytes = int(rec.get("bytes", 0))
            if nlines > allow_lines or nbytes > allow_bytes:
                violations.append({"kind": "GREW", "file": rel,
                                   "lines": code_lines, "allow_lines": allow_lines,
                                   "bytes": code_bytes, "allow_bytes": allow_bytes,
                                   "why": "祖父条款只许变小：超限文件不得再生长"})
        elif (not over) and rec is not None:
            violations.append({"kind": "STALE_EXEMPT", "file": rel, "lines": code_lines,
                               "why": "已降到上限以下 —— 请从 size_baseline.json 移除该条"})
        if (not over):
            ## P3（迭代127）：**预警线** —— 只提示不判红，让"快撞线"提前可见。
            ##   exempt 里的文件本来就超限（由祖父条款管），不再重复预警以免噪声。
            lr = code_lines / float(max_lines) if max_lines else 0.0
            br = code_bytes / float(max_bytes) if max_bytes else 0.0
            if max(lr, br) >= warn_ratio:
                warnings.append({"file": rel, "lines": code_lines, "bytes": code_bytes,
                                 "lines_ratio": round(lr, 3), "bytes_ratio": round(br, 3),
                                 "why": "已达上限的 %.1f%%（soft 预警，不判红）" % (max(lr, br) * 100)})
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
        "max_code_lines": max_code_lines,
        "max_code_bytes": max_code_bytes,
        "max_bytes": max_seen_bytes,
        "exempt_count": len(exempt),
        "exempt_used": used,
        "violations": violations,
        "warnings": warnings,
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

    print("files=%d  over_cap=%d  max_code_lines=%d  max_code_bytes=%d  exempt=%d"
          % (len(files), over_cap, max_code_lines, max_code_bytes, len(exempt)))
    for w in warnings:
        print("  [预警] %s  %d 行 / %d 字节（%s）" % (w["file"], w["lines"], w["bytes"], w["why"]))
    for v in violations:
        print("  [%s] %s  (%s)" % (v["kind"], v["file"], v["why"]))
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
