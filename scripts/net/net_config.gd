class_name NetConfig
extends RefCounted
## 联机参数（**与代码分离** —— 准生产口径：test/prod 只换参数，不动代码）
## ---------------------------------------------------------------------------
## 配置位置：`res://net_config/net.<profile>.json`
## 切换方式：① 命令行 `--net-profile=prod`（编辑器 F6 时在「调试 → 自定义参数」里加）
##           ② 代码 `NetConfig.load_profile("prod")`
##           ③ 环境变量 `SB_NET_PROFILE`（仅桌面导出有效）
## ---------------------------------------------------------------------------

const DIR := "res://net_config"
const DEFAULT_PROFILE := "test"


## 枚举可用配置
static func profiles() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		var n := String(f)
		if n.begins_with("net.") and n.ends_with(".json"):
			out.append(n.substr(4, n.length() - 9))
	out.sort()
	return out


## 当前应使用的 profile（命令行 > 环境变量 > 默认）
static func default_profile() -> String:
	var args := OS.get_cmdline_user_args()
	for a in args:
		var s := String(a)
		if s.begins_with("--net-profile="):
			return s.substr(14)
	var env := OS.get_environment("SB_NET_PROFILE")
	if env != "":
		return env
	return DEFAULT_PROFILE


## 读取配置（返回空字典 = 失败）
static func load_profile(name: String) -> Dictionary:
	var p := "%s/net.%s.json" % [DIR, name]
	if not FileAccess.file_exists(p):
		push_error("[NET] 缺配置：" + p)
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (d is Dictionary):
		push_error("[NET] 配置不是 JSON 对象：" + p)
		return {}
	d["_profile"] = name
	d["_path"] = p
	return d


## 临时覆盖（优先级最高）：命令行 `--net-url=ws://ip:port/relay` 或环境变量 `SB_NET_URL`
## 用途：不改任何文件即可切换目标（联机排查、直连/域名切换、指到别人的测试服）
static func url_override() -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--net-url="):
			return s.substr(10)
	return OS.get_environment("SB_NET_URL")


## 组装 ws(s)://host:port/path（url_override() 非空时优先）
static func resolve_url(cfg: Dictionary) -> String:
	var forced := url_override()
	if forced != "":
		return forced
	if cfg.is_empty():
		return ""
	var scheme := "wss" if bool(cfg.get("wss", false)) else "ws"
	var host := String(cfg.get("host", "127.0.0.1"))
	var port := int(cfg.get("port", 80))
	var p := String(cfg.get("path", "/relay"))
	if not p.begins_with("/"):
		p = "/" + p
	return "%s://%s:%d%s" % [scheme, host, port, p]


## 客户端 build 标识（用于服务器日志/展示；**不参与规则判定**）
static func build_tag(cfg: Dictionary) -> String:
	return String(cfg.get("build", "godot-dev"))
