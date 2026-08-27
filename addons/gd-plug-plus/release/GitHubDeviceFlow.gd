@tool
class_name GitHubDeviceFlow
extends Node

## GitHub OAuth Device Authorization flow — fully async, signal-driven.
## Reference implementation lives in test_device_flow.py (kept in sync).
##
## Lifecycle:
##   start(client_id) -> emits `code_received(user_code, verification_uri, expires_in)`
##                       (UI shows the code; user opens browser, types it, confirms)
##                    -> polls /login/oauth/access_token every `interval` seconds
##                    -> emits `succeeded(token)` on user approval, OR
##                       `failed(error_key, message)` on denial / expiry / network
##
## All HTTP work is non-blocking via HTTPRequest; polling uses a one-shot Timer.
## Caller must add this Node to the scene tree BEFORE calling start().

signal code_received(user_code: String, verification_uri: String, expires_in: int)
signal succeeded(token: String)
signal failed(error_key: String, message: String)

const DEVICE_CODE_URL := "https://github.com/login/device/code"
const TOKEN_URL := "https://github.com/login/oauth/access_token"
const GRANT_TYPE := "urn:ietf:params:oauth:grant-type:device_code"

var _client_id: String = ""
var _device_code: String = ""
var _interval: float = 5.0
var _expires_at_msec: int = 0
var _http: HTTPRequest
var _poll_timer: Timer
var _running: bool = false


func _ready() -> void:
	_http = HTTPRequest.new()
	ProxyConfig.apply_to_http(_http)
	add_child(_http)
	_poll_timer = Timer.new()
	_poll_timer.one_shot = true
	_poll_timer.timeout.connect(_poll_token)
	add_child(_poll_timer)


func apply_proxy() -> void:
	if _http:
		ProxyConfig.apply_to_http(_http)


## Kick off Device Flow with the given OAuth Client ID. Subsequent state moves
## through the `code_received` → `succeeded` / `failed` signals. Calling start
## while a previous flow is in progress cancels the previous one.
func start(client_id: String) -> void:
	if _running:
		cancel()
	if client_id.is_empty():
		failed.emit("ERR_TOKEN_NO_CLIENT_ID", "Client ID is empty")
		return
	_client_id = client_id
	_running = true
	_request_device_code()


func cancel() -> void:
	_running = false
	if _http:
		_http.cancel_request()
	if _poll_timer:
		_poll_timer.stop()


# ---------------------------------------------------------------------------
# Step 1: request a device code
# ---------------------------------------------------------------------------


func _request_device_code() -> void:
	var body: String = "client_id=%s&scope=" % _client_id.uri_encode()
	var headers: PackedStringArray = [
		"Content-Type: application/x-www-form-urlencoded",
		"Accept: application/json",
	]
	if _http.request_completed.is_connected(_on_device_code_response):
		_http.request_completed.disconnect(_on_device_code_response)
	_http.request_completed.connect(_on_device_code_response, CONNECT_ONE_SHOT)
	var err = _http.request(DEVICE_CODE_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_running = false
		failed.emit("ERR_TOKEN_NETWORK", "device-code request failed: %d" % err)


func _on_device_code_response(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if not _running:
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_running = false
		failed.emit(
			"ERR_TOKEN_NETWORK",
			"device-code HTTP %d (result=%d)" % [response_code, result]
		)
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		_running = false
		failed.emit("ERR_TOKEN_BAD_RESPONSE", "non-JSON device-code response")
		return
	if parsed.has("error"):
		_running = false
		failed.emit(
			"ERR_TOKEN_DEVICE_CODE",
			"%s: %s" % [parsed.get("error", "?"), parsed.get("error_description", "")]
		)
		return

	_device_code = parsed.get("device_code", "")
	var user_code: String = parsed.get("user_code", "")
	var verify_uri: String = parsed.get("verification_uri", "https://github.com/login/device")
	_interval = float(parsed.get("interval", 5))
	var expires_in: int = int(parsed.get("expires_in", 900))
	_expires_at_msec = Time.get_ticks_msec() + expires_in * 1000

	if _device_code.is_empty() or user_code.is_empty():
		_running = false
		failed.emit("ERR_TOKEN_BAD_RESPONSE", "missing device_code or user_code")
		return

	code_received.emit(user_code, verify_uri, expires_in)
	_poll_timer.start(_interval)


# ---------------------------------------------------------------------------
# Step 2: poll for the access token until user approves / denies / expires
# ---------------------------------------------------------------------------


func _poll_token() -> void:
	if not _running:
		return
	if Time.get_ticks_msec() >= _expires_at_msec:
		_running = false
		failed.emit("ERR_TOKEN_EXPIRED", "device code expired")
		return
	var body: String = (
		"client_id=%s&device_code=%s&grant_type=%s"
		% [_client_id.uri_encode(), _device_code.uri_encode(), GRANT_TYPE.uri_encode()]
	)
	var headers: PackedStringArray = [
		"Content-Type: application/x-www-form-urlencoded",
		"Accept: application/json",
	]
	if _http.request_completed.is_connected(_on_token_response):
		_http.request_completed.disconnect(_on_token_response)
	_http.request_completed.connect(_on_token_response, CONNECT_ONE_SHOT)
	var err = _http.request(TOKEN_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		# Network glitch: back off and retry until expiry.
		_poll_timer.start(_interval)


func _on_token_response(
	result: int, _response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if not _running:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_poll_timer.start(_interval)
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		_poll_timer.start(_interval)
		return
	# GitHub returns 200 even for "authorization_pending" — must inspect body.
	if parsed.has("error"):
		var err: String = parsed.get("error", "")
		match err:
			"authorization_pending":
				_poll_timer.start(_interval)
			"slow_down":
				# Spec: bump interval by 5s per slow_down response.
				_interval += 5.0
				_poll_timer.start(_interval)
			"expired_token":
				_running = false
				failed.emit("ERR_TOKEN_EXPIRED", "device code expired")
			"access_denied":
				_running = false
				failed.emit("ERR_TOKEN_DENIED", "user denied authorization")
			_:
				_running = false
				failed.emit(
					"ERR_TOKEN_DEVICE_CODE",
					"%s: %s" % [err, parsed.get("error_description", "")]
				)
		return
	var token: String = parsed.get("access_token", "")
	if token.is_empty():
		_poll_timer.start(_interval)
		return
	_running = false
	succeeded.emit(token)
