#!/usr/bin/env python3
"""GUT 结果校验（迭代124 · P1）：把"静默不加载"变成红。

背景（本会话两次实测）：某个 tests/test_*.gd 里语法错（如 assert_ge 不存在、var := 类型推断失败）时，
  GUT **不会**让本次运行失败 —— 它只是少加载一个脚本，passing 数字变小、退出码仍 0。
  这正是项目三次"假绿"的同源形态：失败路径从未被执行。

判据（三条，任一不满足 ⇒ 退出码 1）：
  ① 日志里出现 Parse Error / Failed to load script ⇒ 红（附原文行）；
  ② 找不到 Run Summary / 没有 "Scripts <n>" 行 ⇒ 红（本次运行没跑到底）；
  ③ 磁盘上的 test_*.gd 数量 ≠ 日志里 Scripts 数 ⇒ 红（有文件没被加载 = 静默丢测试）。

用法：gut_check.py --log qc/out/gut.log --tests-dir tests --out qc/out/gutcheck.json
退出码：0 通过 / 1 判红 / 2 参数错误
"""
import argparse, json, os, re, sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

BAD_PATTERNS = [
    re.compile(r"Parse Error", re.I),
    re.compile(r"Failed to load script", re.I),
    re.compile(r"Script with errors", re.I),
]


def count_test_files(tests_dir):
    if not os.path.isdir(tests_dir):
        return 0
    n = 0
    for dirpath, _dirnames, filenames in os.walk(tests_dir):
        for fn in filenames:
            if fn.startswith("test_") and fn.endswith(".gd"):
                n += 1
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True)
    ap.add_argument("--tests-dir", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    if not os.path.isfile(a.log):
        print("[gut] 缺少日志文件：%s" % a.log)
        return 2
    lines = open(a.log, encoding="utf-8", errors="replace").read().splitlines()

    harness = []
    for i, ln in enumerate(lines, 1):
        for pat in BAD_PATTERNS:
            if pat.search(ln):
                harness.append({"line": i, "text": ln.strip()[:200]})
                break

    m_scripts = None
    for ln in lines:
        m = re.match(r"\s*Scripts\s+(\d+)\s*$", ln)
        if m:
            m_scripts = int(m.group(1))
    m_tests = re.search(r"^\s*Tests\s+(\d+)\s*$", "\n".join(lines), re.M)
    m_pass = re.search(r"^\s*Passing Tests\s+(\d+)\s*$", "\n".join(lines), re.M)
    m_fail = re.search(r"^\s*Failing Tests\s+(\d+)\s*$", "\n".join(lines), re.M)
    m_asserts = re.search(r"^\s*Asserts\s+(\d+)\s*$", "\n".join(lines), re.M)

    disk = count_test_files(a.tests_dir)
    problems = []
    if harness:
        problems.append("日志含 %d 处解析/加载错误（测试脚本可能被静默跳过）" % len(harness))
    if m_scripts is None:
        problems.append("日志里没有 Run Summary 的 Scripts 行（本次运行未跑到底）")
    elif disk != m_scripts:
        problems.append("磁盘测试文件 %d 个 ≠ 实际加载 %d 个（有文件没被加载）" % (disk, m_scripts))

    result = {
        "scripts_loaded": m_scripts,
        "scripts_on_disk": disk,
        "tests": int(m_tests.group(1)) if m_tests else None,
        "passing": int(m_pass.group(1)) if m_pass else None,
        "failing": int(m_fail.group(1)) if m_fail else None,
        "asserts": int(m_asserts.group(1)) if m_asserts else None,
        "harness_errors": harness,
        "problems": problems,
    }
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    if problems:
        print("[gut] 判红 %d 条：" % len(problems))
        for p in problems:
            print("  - " + p)
        for h in harness[:5]:
            print("  ! 行 %d: %s" % (h["line"], h["text"]))
        return 1
    print("[gut] 脚本 %d 个全部加载（磁盘 %d）· tests=%s passing=%s asserts=%s"
          % (m_scripts, disk, result["tests"], result["passing"], result["asserts"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
