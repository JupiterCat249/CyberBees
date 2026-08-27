@tool
class_name GitHubProvider
extends ReleaseProvider

## GitHub Release API — Bearer token + X-GitHub-Api-Version header.


func get_platform_key() -> String:
	return "github"


func build_releases_url(repo_url: String, page: int = 1, per_page: int = 30) -> String:
	var parts = _parse_owner_repo(repo_url)
	return (
		"https://api.github.com/repos/%s/%s/releases?per_page=%d&page=%d"
		% [parts.owner, parts.repo, per_page, page]
	)


func get_api_headers(token: String) -> Dictionary:
	var h := {"Accept": "application/json", "X-GitHub-Api-Version": "2026-03-10"}
	if not token.is_empty():
		h["Authorization"] = "Bearer " + token
	return h


func get_validate_url(_token: String) -> String:
	return "https://api.github.com/repos/godotengine/godot/releases?per_page=1&page=1"
