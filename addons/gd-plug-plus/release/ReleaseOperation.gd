@tool
class_name ReleaseOperation
extends RefCounted

## Template Method base — all Release API operations share the same skeleton:
## prepare → build URL → execute HTTP → parse → post-process.
## Subclasses override the hook methods.

var _provider: ReleaseProvider
var _token_store: TokenStore
var _http: HTTPRequest


func _init(provider: ReleaseProvider, token_store: TokenStore, http: HTTPRequest):
	_provider = provider
	_token_store = token_store
	_http = http


## Template method skeleton (do not override).
func execute(context: Dictionary) -> void:
	var token = _token_store.get_token(_provider.get_platform_key())
	var url = _build_url(context)
	if url.is_empty():
		PlugLogger.info("ReleaseOp.execute: URL is empty, aborting request")
		_on_response(HTTPRequest.RESULT_CONNECTION_ERROR, 0, PackedStringArray(), PackedByteArray())
		return
	url = _provider.apply_token_to_url(url, token)
	var headers = _get_headers(token)
	var has_tok := "yes" if not token.is_empty() else "no"
	PlugLogger.debug(
		"ReleaseOp.execute: GET %s (token=%s)" % [url, has_tok]
	)
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		PlugLogger.info(
			"ReleaseOp.execute: HTTPRequest busy (status=%d), cancelling previous"
			% _http.get_http_client_status()
		)
		_http.cancel_request()
	_http.request_completed.connect(_on_response, CONNECT_ONE_SHOT)
	var err = _http.request(url, _dict_to_headers(headers))
	if err != OK:
		PlugLogger.info("ReleaseOp.execute: HTTPRequest.request() failed err=%d url=%s" % [err, url])
		if _http.request_completed.is_connected(_on_response):
			_http.request_completed.disconnect(_on_response)
		_on_response(HTTPRequest.RESULT_CONNECTION_ERROR, 0, PackedStringArray(), PackedByteArray())


# --- Hook methods (subclasses override) ---


func _build_url(_context: Dictionary) -> String:
	return ""


func _get_headers(token: String) -> Dictionary:
	return _provider.get_api_headers(token)


func _on_response(
	_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray
) -> void:
	pass


func _dict_to_headers(d: Dictionary) -> PackedStringArray:
	var arr: PackedStringArray = []
	for k in d:
		arr.append("%s: %s" % [k, d[k]])
	return arr
