class_name NetCodec
extends RefCounted
## 中继协议 v1 · **唯一编解码入口**
## ---------------------------------------------------------------------------
## 设计约束：将来若把编解码下沉到 GDExtension/C++，**只换本文件**，调用方（RelayClient）不动。
## 消息表与服务器 `联机服务器/server.js` **同源**；协议文档：`系统维护/网络联机/扩展-001-中继协议v1.md`
## 口径（《边界约束》T7 v1.12）：只传**操作数据**；服务器不解释 payload（客户端也不应依赖服务器理解）
## ---------------------------------------------------------------------------

const PROTO := 1

## 客户端 → 服务器
const C2S: Array[String] = ["hello", "create", "join", "leave", "start", "op", "ping"]
## 服务器 → 客户端（**白名单**：任何不在此表的类型都视为协议异常）
const S2C: Array[String] = [
	"welcome", "room", "peer_joined", "peer_left", "start", "left",
	"op", "op_ack", "pong", "err"
]


## 构造消息
static func make(type: String, fields: Dictionary = {}) -> Dictionary:
	var m: Dictionary = {"t": type}
	for k in fields:
		m[k] = fields[k]
	return m


## 编码为**文本**（服务器 proto 1 只接受文本帧，拒二进制）
static func encode_text(msg: Dictionary) -> String:
	return JSON.stringify(msg)


## 编码为字节（二进制路径预留；v1 不用）
static func encode(msg: Dictionary) -> PackedByteArray:
	return encode_text(msg).to_utf8_buffer()


## 解码：非法/非对象一律返回空字典（调用方当协议异常处理）
static func decode(bytes: PackedByteArray) -> Dictionary:
	return decode_text(bytes.get_string_from_utf8())


static func decode_text(txt: String) -> Dictionary:
	var v = JSON.parse_string(txt)
	return v if v is Dictionary else {}


static func is_known_type(t: String) -> bool:
	return C2S.has(t) or S2C.has(t)


## 客户端消息的**结构校验**（镜像服务器 SCHEMA；本地先挡掉明显错误，减少无效往返）
static func validate_outgoing(msg: Dictionary) -> String:
	var t := String(msg.get("t", ""))
	if t == "":
		return "missing t"
	if not C2S.has(t):
		return "not a client message: " + t
	match t:
		"hello":
			if not (msg.get("proto") is int or msg.get("proto") is float):
				return "hello.proto must be number"
		"join":
			if typeof(msg.get("code")) != TYPE_STRING:
				return "join.code must be string"
		"op":
			for f in ["seq", "frame"]:
				if typeof(msg.get(f)) != TYPE_FLOAT and typeof(msg.get(f)) != TYPE_INT:
					return "op.%s must be number" % f
			if not msg.has("payload"):
				return "op.payload missing"
	return ""
