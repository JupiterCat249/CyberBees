#!/usr/bin/env python3
"""架构闸：读取 gdcruiser 的依赖图 JSON，套用 qc/config/arch_rules.json 判定。

判据全部来自配置文件；本脚本不含任何"聪明"的逻辑，只做确定性计数。
输出 JSON：{"cycles":n,"layer_violations":n,"unresolved":n,"edges":n,"violations":[...]}
"""
import argparse, json, os, sys

def find_cycles(edges_map):
    """返回全部环（每条环为节点列表，首尾不重复）。仅用于「同类边」子图。"""
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {}
    stack = []
    out = []

    def dfs(node):
        color[node] = GRAY
        stack.append(node)
        for nxt in edges_map.get(node, []):
            c = color.get(nxt, WHITE)
            if c == GRAY:
                i = stack.index(nxt)
                out.append(stack[i:] + [nxt])
            elif c == WHITE:
                dfs(nxt)
        stack.pop()
        color[node] = BLACK

    for node in list(edges_map.keys()):
        if color.get(node, WHITE) == WHITE:
            dfs(node)
    return out


def layer_of(path, layers):
    # path 形如 res://src/battle/battle_engine.gd
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

    # 依赖分两类（实测教训 2026-10-22）：
    #   · preload/load 边 → 真有**加载顺序**风险，必须无环（排除自环：单例 idiom 就是自 load）
    #   · class_ref 边   → 仅是类型标注；GDScript 由全局类表解析，不存在加载顺序问题
    load_edges = {}
    type_edges = {}
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
            dtype = dep.get("type") or ""
            if dtype in ("preload", "load") and src_path != tgt:
                load_edges.setdefault(src_path, []).append(tgt)
            elif dtype == "class_ref" and src_path != tgt:
                type_edges.setdefault(src_path, []).append(tgt)
            tgt_layer = layer_of(tgt, layers)
            if tgt_layer is None:
                continue
            if tgt_layer in forbid.get(src_layer, ()):
                violations.append({
                    "from": src_path, "to": tgt,
                    "from_layer": src_layer, "to_layer": tgt_layer,
                    "line": dep.get("line"), "why": why.get((src_layer, tgt_layer), "")
                })

    ## ⭐ 第三轮 S1/WS4（迭代158）：层界按**可达性**判定 ——
    ##   边界是"最终能依赖到什么"，不是"直接 preload 了什么"（参照 dependency-cruiser 的 reachable 语义）。
    ##   仅用 load/preload 边（类型标注不构成加载风险），逐对 (from,to) 做 BFS 取**最短路径**。
    adjacency = {}
    for src, deps in list(load_edges.items()) + list(type_edges.items()):
        adjacency.setdefault(src, set()).update(deps)

    def shortest_path(start, pred):
        seen = {start: [start]}
        queue = [start]
        while queue:
            cur = queue.pop(0)
            if pred(cur) and cur != start:
                return seen[cur]
            for nxt in sorted(adjacency.get(cur, ())):
                if nxt not in seen:
                    seen[nxt] = seen[cur] + [nxt]
                    queue.append(nxt)
        return None

    reach_viol = []
    nodes = sorted(set(list(adjacency.keys()) + [t for ds in adjacency.values() for t in ds]))
    for node in nodes:
        src_layer = layer_of(node, layers)
        if src_layer is None:
            continue
        banned = forbid.get(src_layer, ())
        if not banned:
            continue
        for bl in banned:
            path = shortest_path(node, lambda n: layer_of(n, layers) == bl)
            if path:
                reach_viol.append({"from": node, "to": path[-1], "from_layer": src_layer,
                                   "to_layer": bl, "hops": len(path) - 1, "path": path,
                                   "why": why.get((src_layer, bl), "")})

    load_cycles = find_cycles(load_edges)
    type_cycles = find_cycles(type_edges)

    result = {
        "cycles": len(load_cycles),
        "cycle_detail": load_cycles,
        "type_cycles": len(type_cycles),
        "type_cycle_detail": type_cycles,
        "layer_violations": len(violations),
        "reach_violations": len(reach_viol),
        "violations": violations,
        "reach_violations_detail": reach_viol,
        "unresolved": unresolved if rules.get("unresolved_must_be_zero") else 0,
        "edges": edges,
        "modules": len(modules),
    }
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(json.dumps({k: v for k, v in result.items() if k not in ("cycle_detail", "type_cycle_detail", "violations", "reach_violations_detail")}, ensure_ascii=False))
    for c in load_cycles:
        print("  LOAD-CYCLE: " + " -> ".join(c))
    if type_cycles:
        print("  (info) 类型引用环 %d 处：GDScript 由全局类表解析，不构成加载顺序风险" % len(type_cycles))
    for v in reach_viol[:20]:
        print("  UNREACHABLE-OK?: %s (%s) -> %s (%s), hops=%d: %s" % (
            v["from"], v["from_layer"], v["to"], v["to_layer"], v["hops"], " -> ".join(v["path"])))
    for v in violations[:20]:
        print("  FORBIDDEN: %s -> %s (%s->%s line %s)" % (v["from"], v["to"], v["from_layer"], v["to_layer"], v["line"]))
    # 单独跑时退出码要诚实（此前恒 0 —— 违规只在 qc.ps1 里靠计数发现）
    bad = len(load_cycles) or len(violations) or len(reach_viol) or (unresolved if rules.get("unresolved_must_be_zero") else 0)
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
