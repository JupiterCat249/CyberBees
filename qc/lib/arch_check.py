#!/usr/bin/env python3
"""架构闸：读取 gdcruiser 的依赖图 JSON，套用 qc/config/arch_rules.json 判定。

判据全部来自配置文件；本脚本不含任何"聪明"的逻辑，只做确定性计数。
输出 JSON：{"cycles":n,"layer_violations":n,"unresolved":n,"edges":n,"violations":[...]}
"""
import argparse, json, os, sys

def layer_of(path, layers):
    # path 形如 res://scripts/battle/battle_engine.gd
    p = path.replace("res://", "")
    best = None
    for name, prefixes in layers.items():
        for pre in prefixes:
            if p.startswith(pre):
                if best is None or len(pre) > len(best[1]):
                    best = (name, pre)
    return best[0] if best else None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--graph", required=True)
    ap.add_argument("--rules", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    with open(a.rules, "r", encoding="utf-8") as f:
        rules = json.load(f)
    with open(a.graph, "r", encoding="utf-8") as f:
        data = json.load(f)

    layers = rules["layers"]
    forbid = {}
    for r in rules.get("forbid", []):
        forbid.setdefault(r["from"], set()).update(r["to"])
    why = {(r["from"], t): r.get("why", "") for r in rules.get("forbid", []) for t in r["to"]}

    modules = data.get("graph", {}).get("modules", {}) or {}
    cycles = data.get("cycles", []) or []
    # cycles 结构兼容：list[list] 或 {"value":[...]}
    cycle_list = []
    for c in cycles if isinstance(cycles, list) else [cycles]:
        if isinstance(c, dict):
            cycle_list.append(c.get("value", []))
        elif isinstance(c, list):
            cycle_list.append(c)

    violations = []
    unresolved = 0
    edges = 0
    for src_path, mod in modules.items():
        src_layer = layer_of(src_path, layers)
        if src_layer is None:
            continue
        for dep in (mod.get("dependencies") or []):
            tgt = dep.get("target")
            if not tgt:
                continue
            if dep.get("resolved") is False:
                unresolved += 1
            edges += 1
            tgt_layer = layer_of(tgt, layers)
            if tgt_layer is None:
                continue
            if tgt_layer in forbid.get(src_layer, ()):
                violations.append({
                    "from": src_path, "to": tgt,
                    "from_layer": src_layer, "to_layer": tgt_layer,
                    "line": dep.get("line"), "why": why.get((src_layer, tgt_layer), "")
                })

    result = {
        "cycles": len(cycle_list),
        "cycle_detail": cycle_list,
        "layer_violations": len(violations),
        "violations": violations,
        "unresolved": unresolved if rules.get("unresolved_must_be_zero") else 0,
        "edges": edges,
        "modules": len(modules),
    }
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(json.dumps({k: v for k, v in result.items() if k not in ("cycle_detail", "violations")}, ensure_ascii=False))
    for c in cycle_list:
        print("  CYCLE: " + " -> ".join(c))
    for v in violations[:20]:
        print("  FORBIDDEN: %s -> %s (%s->%s line %s)" % (v["from"], v["to"], v["from_layer"], v["to_layer"], v["line"]))
    return 0

if __name__ == "__main__":
    sys.exit(main())
