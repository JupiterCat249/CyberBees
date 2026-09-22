class_name RelayClient
extends RefCounted
## 中继客户端（协议 v1）—— 只做「连接 + 收发 + 状态机」
## ---------------------------------------------------------------------------
## 不含规则、不碰视图；调用方每帧调一次 `poll()`（与项目的帧数驱动口径一致）
## 引擎依据（已核）：`WebSocketPeer`（Godot 4.7.2 ClassDB）
##   connect_to_url(url, TLSOptions) / poll() / get_ready_state() / send_text() / get_available_packet_count()
##   文档：class_websocketpeer · tutorials/networking/websocket
## 协议文档：系统维护/网络联机/扩展-001-中继协议v1.md
## ---------------------------------------------------------------------------
signal opened
signal welcomed(sid: String, proto: int, build: String)
signal room_state(code: String, seat: int, players: Array)
signal peer_joined(seat: int, name: String)
signal peer_left(seat: int, reason: String, ended: bool)
signal match_started(seed_value: int, first_side: int)
signal op_received(seat: int, seq: int, frame: int, payload: Variant, sseq: int)
signal op_acked(seq: int, sseq: int)
signal server_error(code: String, msg: String)
signal closed(code: int, reason: String)

enum St { IDLE, CONNECTING, OPEN, CLOSED, FAILED }

var url: String = ""
var proto: int = NetCodec.PROTO
var build: String = "godot-dev"
var state: St = St.IDLE
var last_error: String = ""

## 会话/房间
var sid: String = ""
var seat: int = -1
var room_code: String = ""
var players: Array = []
var seed_value: int = 0
var first_side: int = 0
var match_running: bool = false

## 统计（用于「只传操作」举证）
var sent_ops: int = 0
var recv_ops: int = 0
var sent_bytes: int = 0
var recv_bytes: int = 0
var unknown_msgs: int = 0

var _ws := WebSocketPeer.new()
var _seq: int = 0


func start(p_url: String, p_build: String = "") -> Error:
	url = p_url
	if p_build != "":
		build = p_build
	state = St.CONNECTING
	var err := _ws.connect_to_url(url)
	if err != OK:
		state = St.FAILED
		last_error = "connect_to_url err=%d" % err
		server_error.emit("CONNECT_FAIL", last_error)
	return err


## 每帧调一次（建议在 _process 里，与引擎帧数驱动对齐）
## ⚠️ **先抽干报文再处理状态**：服务器拒绝/结束时是「先发 err 再关闭」，
##    若先按 CLOSED 分支返回，最后一条报文会丢（迭代061 检查点2 实测踩到）
func poll() -> void:
	_ws.poll()
	var rs: int = _ws.get_ready_state()
	if rs == WebSocketPeer.STATE_OPEN or rs == WebSocketPeer.STATE_CLOSING or rs == WebSocketPeer.STATE_CLOSED:
		while _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet()
			recv_bytes += pkt.size()
			_handle(NetCodec.decode(pkt))
	match rs:
		WebSocketPeer.STATE_OPEN:
			if state != St.OPEN:
				state = St.OPEN
				opened.emit()
				_send(NetCodec.make("hello", {"proto": proto, "build": build}))
		WebSocketPeer.STATE_CLOSED:
			if state != St.CLOSED:
				state = St.CLOSED
				closed.emit(_ws.get_close_code(), _ws.get_close_reason())


func is_open() -> bool:
	return state == St.OPEN


# ---------------- 发送 ----------------
func create_room() -> void:
	_send(NetCodec.make("create"))


func join_room(code: String) -> void:
	_send(NetCodec.make("join", {"code": code.to_upper()}))


func start_match() -> void:
	_send(NetCodec.make("start"))


func leave() -> void:
	_send(NetCodec.make("leave"))


func ping(t: int = 0) -> void:
	_send(NetCodec.make("ping", {"t": t}))


## 发送一帧操作（**业务数据一律放在 payload 里**；服务器原样转发）
## 返回本消息的 seq（发送方递增，服务器不重排；两端按 seq 去重）
func send_op(frame: int, payload):
	_seq += 1
	_send(NetCodec.make("op", {"seq": _seq, "frame": frame, "payload": payload}))
	sent_ops += 1
	return _seq


func close(code: int = 1000, reason: String = "bye") -> void:
	_ws.close(code, reason)


func _send(msg: Dictionary) -> void:
	var bad: String = NetCodec.validate_outgoing(msg)
	if bad != "":
		last_error = bad
		server_error.emit("LOCAL_BAD_MSG", bad)
		return
	var txt: String = NetCodec.encode_text(msg)
	if state == St.OPEN:
		_ws.send_text(txt)
	sent_bytes += txt.to_utf8_buffer().size()


# ---------------- 接收 ----------------
func _handle(m: Dictionary) -> void:
	var t := String(m.get("t", ""))
	if t == "":
		unknown_msgs += 1
		server_error.emit("UNKNOWN_MSG", "empty")
		return
	if not NetCodec.S2C.has(t):
		unknown_msgs += 1
		server_error.emit("UNKNOWN_MSG", t)
		return
	match t:
		"welcome":
			sid = String(m.get("sid", ""))
			proto = int(m.get("proto", proto))
			welcomed.emit(sid, proto, String(m.get("build", "")))
		"room":
			room_code = String(m.get("code", ""))
			seat = int(m.get("seat", -1))
			players = m.get("players", [])
			room_state.emit(room_code, seat, players)
		"peer_joined":
			peer_joined.emit(int(m.get("seat", -1)), String(m.get("name", "")))
		"peer_left":
			match_running = false
			peer_left.emit(int(m.get("seat", -1)), String(m.get("reason", "")), bool(m.get("ended", false)))
		"start":
			seed_value = int(m.get("seed", 0))
			first_side = int(m.get("first_side", 0))
			match_running = true
			match_started.emit(seed_value, first_side)
		"op":
			recv_ops += 1
			op_received.emit(int(m.get("seat", -1)), int(m.get("seq", 0)), int(m.get("frame", 0)), m.get("payload", null), int(m.get("sseq", 0)))
		"op_ack":
			op_acked.emit(int(m.get("seq", 0)), int(m.get("sseq", 0)))
		"err":
			last_error = String(m.get("code", ""))
			server_error.emit(last_error, String(m.get("msg", "")))
		"left":
			pass
		"pong":
			pass
