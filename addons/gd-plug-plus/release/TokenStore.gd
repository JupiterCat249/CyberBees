@tool
class_name TokenStore
extends RefCounted

## Persists platform API tokens (and OAuth Client IDs for Device Flow) to a
## machine-wide encrypted file outside the project. Same file is read by every
## Godot project on the same machine — so users configure tokens once.
##
## Disk schema (encrypted JSON inside the .dat container):
##   {
##     "tokens":     { "github": "ghp_xxx", "codeberg": "...", "gitee": "..." },
##     "client_ids": { "github": "Ov23libsMl8RtkqojQaM" }   # not exposed in UI
##   }
##
## Migration rules:
## - If the new global encrypted file does not exist but the legacy plaintext
##   user://gd-plug-plus-tokens.json does → migrate once, then delete the
##   legacy file. Both the new wrapped schema and the older flat
##   {platform: token} form are accepted.

const LEGACY_PATH := "user://gd-plug-plus-tokens.json"
const GLOBAL_DIR_NAME := "gd-plug-plus"
const GLOBAL_FILE_NAME := "tokens.dat"
const _MAX_MASK_RUN := 12

## Static metadata describing each supported release platform: how the user is
## expected to obtain a token and which auth modes are available.
const PLATFORM_META: Dictionary = {
	"github":
	{
		"display_name": "GitHub",
		"settings_url": "https://github.com/settings/tokens",
		"apply_url": "https://github.com/settings/tokens/new",
		"oauth_app_url": "https://github.com/settings/developers",
		"auth_modes": ["device_flow", "pat"],
		"default_client_id": "Ov23libsMl8RtkqojQaM",
		"device_code_url": "https://github.com/login/device/code",
		"device_token_url": "https://github.com/login/oauth/access_token",
	},
	"codeberg":
	{
		"display_name": "Codeberg",
		"settings_url": "https://codeberg.org/user/settings/applications",
		"apply_url": "https://codeberg.org/user/settings/applications",
		"auth_modes": ["pat"],
	},
	"gitee":
	{
		"display_name": "Gitee",
		"settings_url": "https://gitee.com/profile/personal_access_tokens",
		"apply_url": "https://gitee.com/profile/personal_access_tokens/new",
		"auth_modes": ["pat"],
	},
}

var _tokens: Dictionary = {}
var _client_ids: Dictionary = {}


# ---------------------------------------------------------------------------
# Path & encryption
# ---------------------------------------------------------------------------


## Absolute path to the machine-shared encrypted tokens file.
## Lives under OS.get_config_dir() (e.g. %AppData% on Windows,
## ~/.config on Linux, ~/Library/... on macOS) so all Godot projects on
## the same machine read/write the same file.
static func get_global_config_path() -> String:
	return OS.get_config_dir().path_join(GLOBAL_DIR_NAME).path_join(GLOBAL_FILE_NAME)


## Derives a stable per-machine password for FileAccess.open_encrypted_with_pass.
## Reinstalling the OS or moving to a different machine will produce a different
## OS.get_unique_id() and the existing file will fail to decrypt — by design;
## the user must re-enter the tokens (logged via LOG_TOKEN_LOAD_FAILED).
static func _derive_password() -> String:
	return ("gd-plug-plus|v1|" + OS.get_unique_id()).sha256_text()


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------


func load_tokens() -> void:
	var new_path := get_global_config_path()
	if FileAccess.file_exists(new_path):
		var f := FileAccess.open_encrypted_with_pass(
			new_path, FileAccess.READ, _derive_password()
		)
		if f == null:
			PlugLogger.info(_safe_tr("LOG_TOKEN_LOAD_FAILED"))
			return
		var text := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			var t = parsed.get("tokens", {})
			_tokens = t if t is Dictionary else {}
			var c = parsed.get("client_ids", {})
			_client_ids = c if c is Dictionary else {}
		return
	if FileAccess.file_exists(LEGACY_PATH):
		_migrate_from_legacy()


func save() -> void:
	var path := get_global_config_path()
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open_encrypted_with_pass(
		path, FileAccess.WRITE, _derive_password()
	)
	if f == null:
		PlugLogger.info(_safe_tr("LOG_TOKEN_SAVE_FAILED"))
		push_error("[gd-plug-plus] " + _safe_tr("LOG_TOKEN_SAVE_FAILED"))
		return
	var blob: Dictionary = {"tokens": _tokens, "client_ids": _client_ids}
	f.store_string(JSON.stringify(blob, "\t"))
	f.close()


func _migrate_from_legacy() -> void:
	var f := FileAccess.open(LEGACY_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		if parsed.has("tokens") and parsed["tokens"] is Dictionary:
			_tokens = parsed["tokens"]
			var c = parsed.get("client_ids", {})
			_client_ids = c if c is Dictionary else {}
		else:
			_tokens = parsed
			_client_ids = {}
	save()
	# Best-effort cleanup of the legacy plaintext file.
	var abs_legacy := ProjectSettings.globalize_path(LEGACY_PATH)
	DirAccess.remove_absolute(abs_legacy)
	PlugLogger.info(_safe_tr("LOG_TOKEN_MIGRATED"))


# ---------------------------------------------------------------------------
# Token CRUD
# ---------------------------------------------------------------------------


func get_token(platform: String) -> String:
	return _tokens.get(platform, "")


func set_token(platform: String, token: String) -> void:
	_tokens[platform] = token
	save()


func clear_token(platform: String) -> void:
	_tokens.erase(platform)
	save()


## True iff a non-empty token is stored for the given platform key.
func has_token(platform: String) -> bool:
	return not get_token(platform).is_empty()


# ---------------------------------------------------------------------------
# Mask helpers (for status display in the Settings tab)
# ---------------------------------------------------------------------------


## Returns a privacy-preserving display form of `token`:
## - 0 chars       → "" (empty in / empty out)
## - 1..8 chars    → all '*' of the same length
## - >=9 chars     → first 4 + capped run of '*' (≤ _MAX_MASK_RUN) + last 4
static func mask_token(token: String) -> String:
	var n := token.length()
	if n == 0:
		return ""
	if n <= 8:
		return "*".repeat(n)
	var mid_len: int = mini(n - 8, _MAX_MASK_RUN)
	return token.substr(0, 4) + "*".repeat(mid_len) + token.substr(n - 4, 4)


func get_masked_token(platform: String) -> String:
	return mask_token(get_token(platform))


# ---------------------------------------------------------------------------
# OAuth Client ID (Device Flow). Backend only — UI does not expose this.
# ---------------------------------------------------------------------------


## Returns the user-overridden Client ID if set, otherwise the built-in default
## from PLATFORM_META, otherwise empty.
func get_client_id(platform: String) -> String:
	var override: String = _client_ids.get(platform, "")
	if not override.is_empty():
		return override
	var meta: Dictionary = PLATFORM_META.get(platform, {})
	return meta.get("default_client_id", "")


func set_client_id(platform: String, client_id: String) -> void:
	if client_id.is_empty():
		_client_ids.erase(platform)
	else:
		_client_ids[platform] = client_id
	save()


## True iff the user has explicitly overridden the default client ID.
func has_custom_client_id(platform: String) -> bool:
	return not _client_ids.get(platform, "").is_empty()


# ---------------------------------------------------------------------------
# Platform metadata helpers
# ---------------------------------------------------------------------------


static func get_platform_keys() -> Array:
	return PLATFORM_META.keys()


static func get_platform_meta(platform: String) -> Dictionary:
	return PLATFORM_META.get(platform, {})


static func supports_device_flow(platform: String) -> bool:
	var meta: Dictionary = PLATFORM_META.get(platform, {})
	return "device_flow" in meta.get("auth_modes", [])


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


## tr() requires a Node, but TokenStore is a RefCounted. Use TranslationServer
## directly — falls back to the key itself when no translation exists.
static func _safe_tr(key: String) -> String:
	return TranslationServer.translate(key)
