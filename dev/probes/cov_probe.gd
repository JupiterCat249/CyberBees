extends Node
## **覆盖率探针**（迭代162 · 第三轮 S4/WS1）
##
## 只在"覆盖率运行"期间作为 autoload 临时注册（由 qc/lib/coverage_probe.py 注入/还原）。
## 被注入的每处函数入口调用 `CovProbe.touch("src/...gd:func")`；本节点按帧把命中集合刷到 res://qc/out/cov.json。
## 原则：**不改任何行为**，只记录"这个函数被执行过"。

const OUT_PATH := "res://qc/out/cov.json"
var _hits := {}
var _dirty := false
var _frames := 0


func touch(key: String) -> void:
	_hits[key] = int(_hits.get(key, 0)) + 1
	_dirty = true


func _process(_dt: float) -> void:
	_frames += 1
	if _dirty and _frames % 30 == 0:
		_flush()


func _flush() -> void:
	_dirty = false
	var dir := DirAccess.open("res://qc/out")
	if dir == null:
		return
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({ "hits": _hits }, "\t"))
	f.close()


func _exit_tree() -> void:
	_flush()
