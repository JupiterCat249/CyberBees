class_name NetConfig
extends RefCounted
## 联机参数（**与代码分离** —— 准生产口径：test/prod 只换参数，不动代码）
## ---------------------------------------------------------------------------
## 配置位置：`res://net_config/net.<profile>.json`
## 切换方式（优先级从高到低）：
##           ① 命令行 `--net-profile=prod`（编辑器 F6 时在「调试 → 自定义参数」里加）
##           ② 环境变量 `SB_NET_PROFILE`（仅桌面导出有效）
##           ③ **编辑器内「联机档位」面板**（推荐）：写 `项目设置 net/profile`，见 `addons/net_profile_panel/`
##              —— 同一键也能在「项目设置 → 常规」里直接改，随项目持久化到 `project.godot`
##           ④ 开关文件 `res://net_config/profile.flag`（旧机制，保留兼容）
##           ⑤ 默认 `DEFAULT_PROFILE`
## ---------------------------------------------------------------------------

const DIR := "res://net_config"
const DEFAULT_PROFILE := "test"
## 编辑器面板（`addons/net_profile_panel/`）与「项目设置」共用的键 —— **优先级高于开关文件**，
## 且在编辑器里**可见可改**（引擎自带持久化：随项目写进 `project.godot`）。空串 = 未设置，回落开关文件。
const SETTING := "net/profile"


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


## 当前应使用的 profile（命令行 > 环境变量 > **项目设置 net/profile** > profile.flag > 默认）
static func default_profile() -> String:
	var args := OS.get_cmdline_user_args()
	for a in args:
		var s := String(a)
		if s.begins_with("--net-profile="):
			return s.substr(14)
	var env := OS.get_environment("SB_NET_PROFILE")
	if env != "":
		return env
	## **项目设置**（编辑器「联机档位」面板 / 项目设置面板改的就是它；随项目持久化）
	var from_setting := String(ProjectSettings.get_setting(SETTING, "")).strip_edges()
	if from_setting != "":
		return from_setting
	## dev 档位开关文件：给**编辑器内**运行的实例切档用（编辑器进程传不了 user args，环境变量也可能拿不到）
	if FileAccess.file_exists(DIR + "/profile.flag"):
		var f := FileAccess.open(DIR + "/profile.flag", FileAccess.READ)
		if f != null:
			var name := f.get_as_text().strip_edges()
			f.close()
			if name != "":
				return name
	return DEFAULT_PROFILE


## 当前档位的**来源**（供编辑器面板显示；与 default_profile() 同一套优先级）
static func profile_source() -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--net-profile="):
			return "命令行"
	if OS.get_environment("SB_NET_PROFILE") != "":
		return "环境变量"
	if String(ProjectSettings.get_setting(SETTING, "")).strip_edges() != "":
		return "项目设置 net/profile"
	if FileAccess.file_exists(DIR + "/profile.flag"):
		var f := FileAccess.open(DIR + "/profile.flag", FileAccess.READ)
		if f != null:
			var name := f.get_as_text().strip_edges()
			f.close()
			if name != "":
				return "开关文件 profile.flag"
	return "默认值"


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
