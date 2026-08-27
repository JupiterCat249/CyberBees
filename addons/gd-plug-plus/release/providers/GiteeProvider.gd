@tool
class_name GiteeProvider
extends ReleaseProvider

## Gitee Release API — query param auth.
## Source archive browser_download_url points to web pages → rewrite to API zipball.
## Uploaded attach_files → rewrite to API attach_files/download endpoint.

var _repo_url: String


func get_platform_key() -> String:
	return "gitee"


func build_releases_url(repo_url: String, page: int = 1, per_page: int = 30) -> String:
	_repo_url = repo_url
	var parts = _parse_owner_repo(repo_url)
	return (
		"https://gitee.com/api/v5/repos/%s/%s/releases?per_page=%d&page=%d"
		% [parts.owner, parts.repo, per_page, page]
	)


func get_api_headers(_token: String) -> Dictionary:
	return {"Accept": "application/json"}


func apply_token_to_url(url: String, token: String) -> String:
	if token.is_empty():
		return url
	var sep = "&" if "?" in url else "?"
	return url + sep + "access_token=" + token


func get_validate_url(token: String) -> String:
	var url := "https://gitee.com/api/v5/repos/dromara/hutool/releases?per_page=1&page=1"
	return apply_token_to_url(url, token)


func normalize_release(raw: Dictionary) -> Dictionary:
	var base = super.normalize_release(raw)
	base["_release_id"] = raw.get("id", 0)
	return base


func _normalize_assets(raw_assets: Array) -> Array:
	for a in raw_assets:
		if not a.has("size"):
			a["size"] = 0
		var dl_url: String = a.get("browser_download_url", "")
		var rewritten := _rewrite_archive_url(dl_url)
		if rewritten != dl_url:
			a["browser_download_url"] = rewritten
			a["type"] = "source_archive"
	return raw_assets


func supports_custom_assets() -> bool:
	return true


func needs_attach_files_fetch() -> bool:
	return true


func build_attach_files_url(repo_url: String, release_id: int) -> String:
	var parts = _parse_owner_repo(repo_url)
	return (
		"https://gitee.com/api/v5/repos/%s/%s/releases/%d/attach_files"
		% [parts.owner, parts.repo, release_id]
	)


func build_attach_download_url(
	repo_url: String, release_id: int, attach_file_id: int
) -> String:
	var parts = _parse_owner_repo(repo_url)
	return (
		"https://gitee.com/api/v5/repos/%s/%s/releases/%d/attach_files/%d/download"
		% [parts.owner, parts.repo, release_id, attach_file_id]
	)


func _rewrite_archive_url(url: String) -> String:
	# https://gitee.com/{owner}/{repo}/archive/refs/tags/{tag}.zip
	# → https://gitee.com/api/v5/repos/{owner}/{repo}/zipball?ref={tag}
	var idx := url.find("/archive/refs/tags/")
	if idx < 0:
		return url
	var base := url.left(idx)
	var rest := url.substr(idx + "/archive/refs/tags/".length())
	var tag := ""
	var endpoint := "zipball"
	if rest.ends_with(".tar.gz"):
		tag = rest.trim_suffix(".tar.gz")
		endpoint = "tarball"
	elif rest.ends_with(".zip"):
		tag = rest.trim_suffix(".zip")
	else:
		return url
	var owner_repo := base.trim_prefix("https://gitee.com/")
	return (
		"https://gitee.com/api/v5/repos/%s/%s?ref=%s"
		% [owner_repo, endpoint, tag]
	)
