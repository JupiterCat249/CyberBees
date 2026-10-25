#!/usr/bin/env python3
"""security —— 密钥/凭据扫描（G4 批次3 · 迭代170）

只做确定性正则扫描（不联网、不引重依赖）：
  · 私钥块 / AWS AccessKey / GitHub token / 通用 key=value 长串
配置文件 qc/config/security.json：exclude_globs 与 allow（每条必须写理由）。

用法：security.py --repo <仓根> --config <json> --out qc/out/security.json
退出码：0 无 finding；1 有；2 环境缺失
"""
import argparse, json, os, re, sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

PATTERNS = [
    ("private-key", r"-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----"),
    ("aws-access-key", r"AKIA[0-9A-Z]{16}"),
    ("github-token", r"gh[pousr]_[A-Za-z0-9]{36,}"),
    ("github-pat", r"github_pat_[A-Za-z0-9_]{20,}"),
    ("generic-secret", r"(?i)(api[_-]?key|secret|token|password)\s*[:=]\s*[\"'][A-Za-z0-9_\-]{16,}[\"']"),
]
EXTS = (".gd", ".py", ".json", ".cfg", ".ps1", ".tscn", ".tres", ".md", ".yml", ".yaml", ".ini")
SKIP_DIRS = {".git", "addons", ".venv", "node_modules", ".cov-backup", "out"}
DEFAULTS = {"exclude_globs": [], "allow": []}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--config", required=True)
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    cfg = dict(DEFAULTS)
    if os.path.isfile(a.config):
        with open(a.config, encoding="utf-8-sig") as f:
            cfg.update(json.load(f))
    allow = set()
    for w in cfg.get("allow", []):
        allow.add((w.get("id", ""), w.get("file", "")))

    findings = []
    files = 0
    for root, dirs, names in os.walk(a.repo):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for fn in names:
            if not fn.endswith(EXTS):
                continue
            full = os.path.join(root, fn)
            rel = os.path.relpath(full, a.repo).replace(os.sep, "/")
            if any(re.search(g, rel) for g in cfg.get("exclude_globs", [])):
                continue
            files += 1
            try:
                with open(full, encoding="utf-8-sig", errors="replace") as f:
                    text = f.read()
            except Exception:
                continue
            for pid, pat in PATTERNS:
                if (pid, rel) in allow:
                    continue
                for m in re.finditer(pat, text):
                    line_no = text[:m.start()].count("\n") + 1
                    findings.append("%s:%d [%s]" % (rel, line_no, pid))
                    break

    counts = {"security:files": files, "security:findings": len(findings)}
    print("[security] 扫描 %d 文件 · findings %d" % (files, len(findings)))
    for x in findings[:15]:
        print("  [VIOLATION] " + x)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump({"ok": not findings, "counts": counts, "findings": findings}, f, ensure_ascii=False, indent=1)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
