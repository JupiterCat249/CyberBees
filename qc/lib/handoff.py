#!/usr/bin/env python3
"""handoff —— 生成《当前状态》的"事实块"（G4 批次1 · 迭代168）

定位：程序只写**可推导的事实**；判断性内容（本轮完成/下次可做/待人裁定）归人/AI，块外不动。
标记块：<!-- qc:handoff:begin --> ... <!-- qc:handoff:end -->

用法：
  handoff.py --repo <游戏仓> --docs-repo <文档仓> --counts qc/out/counts.json [--check] [--out qc/out/handoff.json]
退出码：0 一致或已写入；1 --check 漂移；2 环境/文件缺失
"""
import argparse, datetime, json, os, subprocess, sys
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

BEGIN = "<!-- qc:handoff:begin -->"
END = "<!-- qc:handoff:end -->"


def run(args):
    try:
        r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")
        return r.stdout.strip()
    except Exception:
        return ""


def load_json(path, default=None):
    try:
        with open(path, encoding="utf-8-sig") as f:
            return json.load(f)
    except Exception:
        return default if default is not None else {}


def latest_iteration(docs_repo):
    d = os.path.join(docs_repo, "实时开发记录", "迭代记录")
    if not os.path.isdir(d):
        return ""
    items = [x for x in os.listdir(d) if x.startswith("迭代") and len(x) == 5 and x[2:].isdigit()]
    return max(items, key=lambda x: int(x[2:])) if items else ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--docs-repo", required=True)
    ap.add_argument("--counts", required=True)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    counts = load_json(a.counts, {})
    c = counts.get("counts", counts)
    head = run(["git", "-C", a.repo, "rev-parse", "--short", "HEAD"]) or "?"
    subjects = [x for x in run(["git", "-C", a.repo, "log", "-3", "--pretty=format:%h %s"]).splitlines() if x.strip()]
    ahead = run(["git", "-C", a.repo, "rev-list", "--count", "origin/main..HEAD"])
    try:
        ahead_n = int(ahead) if ahead else 0
    except ValueError:
        ahead_n = -1

    latest = load_json(os.path.join(a.repo, "qc", "out", "nightly", "latest.json"), {})
    night_line = "无（`qc nightly` 尚未跑过）"
    if latest:
        d = str(latest.get("date", "?"))
        night_line = "%s exit %s（-Deep：%s）" % (d, latest.get("exit", "?"), "是" if latest.get("deep") else "否")
        try:
            gap = (datetime.date.today() - datetime.date.fromisoformat(d)).days
            if gap > 2:
                night_line += " · 警告：已 %d 天未跑" % gap
        except ValueError:
            pass

    today = datetime.date.today().isoformat()
    lines = [
        "> **事实快照（`qc handoff` 生成 · %s）**：HEAD `%s` · 测试 %s/%s · lint %s · 自检 %s/%s · 体积 %s/%s/%s · 信号 %s/%s"
        % (today, head,
           c.get("test:passing", "?"), c.get("test:asserts", "?"), c.get("lint:total", "?"),
           int(c.get("qc:selftest_total", 0)) - int(c.get("qc:selftest_failures", 0)),
           c.get("qc:selftest_total", "?"),
           c.get("size:arena_view", "?"), c.get("size:battle_engine", "?"), c.get("size:net_diag_dump", "?"),
           c.get("signals:declared", "?"), c.get("signals:problems", "?")),
        "> **最近夜检**：%s" % night_line,
        "> **最近提交**：%s" % ("；".join("`%s`" % s for s in subjects) if subjects else "（无）"),
        "> **最近迭代记录**：%s" % (latest_iteration(a.docs_repo) or "（无）"),
        "> **远端**：%s" % ("与 origin/main 一致" if ahead_n == 0 else ("%d 个提交未推送" % ahead_n if ahead_n > 0 else "无法判定（无远端或未 fetch）")),
    ]
    block = BEGIN + "\n" + "\n".join(lines) + "\n" + END

    page = os.path.join(a.docs_repo, "项目规划蓝图", "当前状态.md")
    if not os.path.isfile(page):
        print("[handoff] 找不到 %s" % page)
        return 2
    with open(page, encoding="utf-8-sig") as f:
        text = f.read()

    has = BEGIN in text and END in text
    old = text[text.index(BEGIN): text.index(END) + len(END)] if has else ""

    if a.check:
        if has and old == block:
            print("[handoff] 事实块一致（%d 行）" % len(lines))
            rc = 0
        else:
            print("[handoff] 事实块漂移：%s" % ("缺失" if not has else "内容不同"))
            for ln in lines:
                if ln not in old:
                    print("  缺: " + ln)
            rc = 1
    else:
        if has:
            text = text.replace(old, block)
        else:
            marker = "> **远端同步**"
            idx = text.find(marker)
            if idx >= 0:
                eol = text.find("\n", idx)
                text = text[:eol + 1] + block + "\n" + text[eol + 1:]
            else:
                eol = text.find("\n")
                text = text[:eol + 1] + "\n" + block + "\n" + text[eol + 1:]
        with open(page, "w", encoding="utf-8-sig", newline="") as f:
            f.write(text)
        print("[handoff] 已写入事实块（%d 行）" % len(lines))
        rc = 0

    if a.out:
        payload = {"ok": rc == 0, "check": bool(a.check), "drift": (1 if (a.check and rc == 1) else 0),
                   "lines": len(lines), "head": head, "nightly": latest.get("date", ""),
                   "counts": {"handoff:lines": len(lines), "handoff:drift": (1 if (a.check and rc == 1) else 0)}}
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=1)
    return rc


if __name__ == "__main__":
    sys.exit(main())
