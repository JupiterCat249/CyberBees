#!/usr/bin/env python3
"""文档基线漂移检查（迭代116）：让《当前状态》里那行"基线快照"必须与实测一致。

为什么需要：本会话里那行数字是**手改的**，已经出现过一次漏改（lint 数字停留旧值）；
  而它是下个会话开工必读的"收尾状态"。手改必然漂移 ⇒ 用确定性检查把它钉住。

文档里的机器可读行（唯一格式，改动它要同步改本文件的正则）：
  > **基线快照**：lint=6 · tests=113/404 · selftest=23 · size=1720/995/721 · signals=24/0

判据：五项全部相等才绿；文件缺失 ⇒ 跳过（exit 0，打印 skip，便于在其他机器上运行）。
退出码：0 通过（含 skip）/ 1 漂移 / 2 参数或文档格式错误。
"""
import argparse, json, os, re, sys

## 控制台可能是 GBK（PS 5.1）⇒ 统一改成 UTF-8 并容错，否则勾号之类会抛 UnicodeEncodeError
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

PATTERNS = [
    ("lint", r"lint=(\d+)"),
    ("tests", r"tests=(\d+)/(\d+)"),
    ("selftest", r"selftest=(\d+)"),
    ("size", r"size=(\d+)/(\d+)/(\d+)"),
    ("signals", r"signals=(\d+)/(\d+)"),
]


def load_counts(path):
    with open(path, encoding="utf-8-sig") as f:
        return json.load(f)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--counts", required=True)
    ap.add_argument("--doc", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    if not os.path.isfile(a.doc):
        result = {"status": "skip", "why": "文档不存在：%s" % a.doc}
        os.makedirs(os.path.dirname(a.out), exist_ok=True)
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print("[docs] skip：%s" % result["why"])
        return 0

    lines = open(a.doc, encoding="utf-8-sig", errors="replace").read().splitlines()
    hit = None
    for ln in lines:
        if "基线快照" in ln:
            hit = ln
            break
    if hit is None:
        print("[docs] 文档里找不到「基线快照」行 —— 请按约定格式补一行")
        return 2

    counts = load_counts(a.counts)
    want = {
        "lint": counts.get("lint:total"),
        "tests": (counts.get("test:passing"), counts.get("test:asserts")),
        "selftest_failures": counts.get("qc:selftest_failures"),
        "size": (counts.get("size:arena_view"), counts.get("size:battle_engine"),
                 counts.get("size:net_diag_dump")),
        "signals": (counts.get("signals:declared"), counts.get("signals:problems")),
    }
    got = {}
    for key, rx in PATTERNS:
        m = re.search(rx, hit)
        if not m:
            print("[docs] 行里缺少 %s 字段（格式：%s）" % (key, rx))
            return 2
        got[key] = tuple(int(g) for g in m.groups()) if len(m.groups()) > 1 else int(m.group(1))

    drift = []
    if got["lint"] != want["lint"]:
        drift.append("lint: 文档 %s ≠ 实测 %s" % (got["lint"], want["lint"]))
    if got["tests"] != want["tests"]:
        drift.append("tests: 文档 %s/%s ≠ 实测 %s/%s" % (*got["tests"], *want["tests"]))
    if got["selftest"] != (0 if want["selftest_failures"] == 0 else want["selftest_failures"]):
        ## 文档记的是"自检失败数"（0 = 全绿），与 qc:selftest_failures 同口径
        drift.append("selftest: 文档 %s ≠ 实测失败数 %s" % (got["selftest"], want["selftest_failures"]))
    if got["size"] != want["size"]:
        drift.append("size: 文档 %s/%s/%s ≠ 实测 %s/%s/%s" % (*got["size"], *want["size"]))
    if got["signals"] != want["signals"]:
        drift.append("signals: 文档 %s/%s ≠ 实测 %s/%s" % (*got["signals"], *want["signals"]))

    result = {"status": "drift" if drift else "ok", "doc_line": hit.strip(), "drift": drift}
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    if drift:
        print("[docs] 文档基线漂移 %d 处：" % len(drift))
        for d in drift:
            print("  - " + d)
        print("  → 请更新《当前状态》的「基线快照」行（或跑 qc snapshot 后再改）")
        return 1
    print("[docs] 文档基线与实测一致 [OK]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
