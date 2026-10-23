#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""源码布局闸（迭代155 · 源码组织方案-001 的 M6）。

判据（全部可红）：
  1. 顶层目录白名单 —— 新顶层目录必须显式登记（防止代码又长出"随手建"的目录）
  2. `scenes/**` 不得有 `*.gd`（场景目录只放场景；绑定脚本进 src/view/）
  3. `qc/**` 不得有 `*.gd`（质控目录只放 Python/PS/配置）
  4. 全仓不得有 `*.deprecated`（要废弃就删，Git 里可查）
  5. 生产代码（src/、scenes/、game_data/）不得引用 `res://dev/`（开发期工具不外泄）

退出码：0 绿 / 1 有违规 / 2 参数或环境错误。
"""
import argparse
import json
import os
import sys

ALLOWED_TOPS = {
    "addons", "archive", "assets", "design", "dev", "dsh_godot",
    "game_data", "net_config", "qc", "refs", "scenes", "src",
    "tests", "tools", "联机服务器",
}
PROD_DIRS = ("src", "scenes", "game_data")
SKIP_DIRS = {".git", ".godot", ".venv", "__pycache__", "node_modules", "qc"}


def walk(root, top):
    base = os.path.join(root, top)
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        rel = os.path.relpath(dirpath, root).replace(os.sep, "/")
        yield rel, filenames


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    root = os.path.abspath(a.repo)
    if not os.path.isdir(os.path.join(root, "src")):
        print("[layout] 找不到 src/ —— 传入的不是重排后的仓库根")
        return 2

    viol = []

    # 1) 顶层白名单
    tops = sorted(d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d)))
    unknown = [t for t in tops if not t.startswith(".") and t not in ALLOWED_TOPS]
    for t in unknown:
        viol.append({"rule": "TOP_NOT_ALLOWED", "path": t,
                     "why": "顶层目录必须登记在 layout_check.ALLOWED_TOPS（新目录先登记再放文件）"})

    # 2/3/4/5) 逐文件检查
    deprecated = []
    scene_gd = []
    qc_gd = []
    dev_refs = []
    for top in tops:
        if top.startswith("."):
            continue
        for rel, filenames in walk(root, top):
            for name in filenames:
                p = rel + "/" + name if rel != "." else name
                low = name.lower()
                ## archive/ 是**登记的归档区**：.deprecated 在那里是"历史留档"而非遗留垃圾，
                ## 故该规则对 archive/ 豁免（其它目录一律禁止）。
                if low.endswith(".deprecated") and not p.startswith("archive/"):
                    deprecated.append(p)
                if low.endswith(".gd"):
                    if p.startswith("scenes/"):
                        scene_gd.append(p)
                    if p.startswith("qc/"):
                        qc_gd.append(p)
                if any(p.startswith(d + "/") for d in PROD_DIRS) and low.endswith((".gd", ".tscn", ".tres", ".cfg", ".godot", ".json")):
                    try:
                        txt = open(os.path.join(root, p), encoding="utf-8", errors="replace").read()
                    except OSError:
                        continue
                    if "res://dev/" in txt:
                        dev_refs.append(p)

    for p in scene_gd:
        viol.append({"rule": "SCENE_HAS_GD", "path": p, "why": "scenes/ 只放 .tscn；脚本请放 src/view/"})
    for p in qc_gd:
        viol.append({"rule": "QC_HAS_GD", "path": p, "why": "qc/ 只放 Python/PS/配置；Godot 探针放 dev/probes/"})
    for p in deprecated:
        viol.append({"rule": "DEPRECATED_FILE", "path": p, "why": "不得保留 *.deprecated（要废弃就删，Git 可查）"})
    for p in dev_refs:
        viol.append({"rule": "PROD_REFERS_DEV", "path": p, "why": "生产代码不得引用 res://dev/（开发期工具不外泄）"})

    result = {
        "status": "ok" if not viol else "violations",
        "tops": tops,
        "unknown_tops": unknown,
        "violations": viol,
        "counts": {
            "unknown_tops": len(unknown),
            "scene_gd": len(scene_gd),
            "qc_gd": len(qc_gd),
            "deprecated": len(deprecated),
            "prod_refers_dev": len(dev_refs),
            "total": len(viol),
        },
    }
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    if viol:
        print("[layout] 布局违规 %d 处：" % len(viol))
        for v in viol[:20]:
            print("  - %-18s %s  (%s)" % (v["rule"], v["path"], v["why"]))
        return 1
    print("[layout] 布局合规：顶层 %d 个目录、无 scenes/qc 下的 .gd、无 .deprecated、生产不引 dev" % len([t for t in tops if not t.startswith(".")]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
