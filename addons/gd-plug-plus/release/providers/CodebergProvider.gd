@tool
class_name CodebergProvider
extends ReleaseProvider

## Codeberg (Forgejo) Release API — token header authentication.


func get_platform_key() -> String:
	return "codeberg"


func build_releases_url(repo_url: String, page: int = 1, per_page: int = 30) -> String:
	var parts = _parse_owner_repo(repo_url)
	return (
		"https://codeberg.org/api/v1/repos/%s/%s/releases?limit=%d&page=%d"
		% [parts.owner, parts.repo, per_page, page]
	)


func get_pagination_param() -> String:
	return "limit"


func get_api_headers(token: String) -> Dictionary:
	var h := {"Accept": "application/json"}
	if not token.is_empty():
		h["Authorization"] = "token " + token
	return h


func get_validate_url(_token: String) -> String:
	return "https://codeberg.org/api/v1/repos/forgejo/forgejo/releases?limit=1&page=1"
