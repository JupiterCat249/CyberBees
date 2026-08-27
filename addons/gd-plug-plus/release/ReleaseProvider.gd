@tool
class_name ReleaseProvider
extends RefCounted

## Strategy base class — encapsulates platform-specific Release API differences.
## Subclasses: GitHubProvider, CodebergProvider, GiteeProvider.


func get_platform_key() -> String:
	return ""


# --- API URL construction ---


func build_releases_url(_repo_url: String, _page: int = 1, _per_page: int = 30) -> String:
	return ""


func get_pagination_param() -> String:
	return "per_page"


# --- Authentication (validated via test_device_flow.py) ---


func get_api_headers(_token: String) -> Dictionary:
	return {"Accept": "application/json"}


func get_download_headers(token: String) -> Dictionary:
	var h = get_api_headers(token)
	h.erase("Accept")
	return h


func apply_token_to_url(_url: String, _token: String) -> String:
	return _url


# --- Token validation ---
# Returns a Release query URL for a well-known public repo on this platform.
# With a valid token the API returns 200; with an invalid token it returns 401.
# Used by the Settings tab "检测" button — validates via actual Release query
# so the result matches real-world plugin search behaviour.


func get_validate_url(_token: String) -> String:
	return ""


# --- Response normalization (unified output format) ---


func normalize_release(raw: Dictionary) -> Dictionary:
	return {
		"tag_name": raw.get("tag_name", ""),
		"name": raw.get("name", ""),
		"target_commitish": raw.get("target_commitish", ""),
		"prerelease": raw.get("prerelease", false),
		"created_at": raw.get("created_at", ""),
		"assets": _normalize_assets(raw.get("assets", [])),
	}


func _normalize_assets(raw_assets: Array) -> Array:
	return raw_assets


func supports_custom_assets() -> bool:
	return true


func needs_attach_files_fetch() -> bool:
	return false


func build_attach_files_url(_repo_url: String, _release_id: int) -> String:
	return ""


func build_attach_download_url(
	_repo_url: String, _release_id: int, _attach_file_id: int
) -> String:
	return ""


func get_asset_download_url(asset: Dictionary) -> String:
	return asset.get("browser_download_url", "")


# --- URL parsing helper ---


func _parse_owner_repo(repo_url: String) -> Dictionary:
	var s = repo_url.strip_edges().trim_suffix("/").trim_suffix(".git")
	if ":" in s and not "://" in s:
		s = s.get_slice(":", 1)
	var parts = s.split("/")
	if parts.size() >= 2:
		return {"owner": parts[-2], "repo": parts[-1]}
	return {"owner": "", "repo": s}
