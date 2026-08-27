@tool
class_name ProviderFactory
extends RefCounted

## Factory Method — auto-selects the right ReleaseProvider based on URL.

static func create(url: String) -> ReleaseProvider:
	if "github.com" in url:
		return GitHubProvider.new()
	if "codeberg.org" in url:
		return CodebergProvider.new()
	if "gitee.com" in url:
		return GiteeProvider.new()
	push_warning("ProviderFactory: unsupported platform for URL: " + url)
	return null


static func detect_platform_key(url: String) -> String:
	var provider = create(url)
	if provider:
		return provider.get_platform_key()
	return ""


static func create_by_key(platform_key: String) -> ReleaseProvider:
	match platform_key:
		"github":
			return GitHubProvider.new()
		"codeberg":
			return CodebergProvider.new()
		"gitee":
			return GiteeProvider.new()
		_:
			push_warning("ProviderFactory: unknown platform key: " + platform_key)
			return null
