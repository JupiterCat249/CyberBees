@tool
class_name AssetMatcher
extends RefCounted

## Matches release assets against a pattern or default heuristics.
## Translated from Python test_device_flow.py match_assets logic.

const ARCHIVE_EXTS: Array[String] = [".zip", ".tar.gz", ".tgz", ".tar.bz2", ".tar.xz", ".7z"]
const SOURCE_CODE_NAMES: Array[String] = ["source code", "source_code", "源代码"]


static func match_assets(assets: Array, pattern: String, _repo_url: String) -> Array:
	var local: Array = []
	var fallback: Array = []
	for asset in assets:
		var asset_name: String = asset.get("name", "")
		if pattern.is_empty():
			if not is_archive(asset_name) or is_source_code(asset_name):
				continue
		else:
			if not asset_name.matchn(pattern):
				continue
		var atype: String = asset.get("type", "attachment")
		if atype == "external" or atype == "source_archive":
			fallback.append(asset)
		else:
			local.append(asset)
	local.append_array(fallback)
	return local


static func is_archive(filename: String) -> bool:
	var lower = filename.to_lower()
	for ext in ARCHIVE_EXTS:
		if lower.ends_with(ext):
			return true
	return false


static func is_source_code(name: String) -> bool:
	var lower = name.to_lower()
	for kw in SOURCE_CODE_NAMES:
		if kw in lower:
			return true
	return false
