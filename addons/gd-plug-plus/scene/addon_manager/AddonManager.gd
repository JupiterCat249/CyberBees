# gdlint:disable=max-file-lines
@tool
extends Control

signal updated

enum VersionState { UNKNOWN, CHECKING, UP_TO_DATE, BEHIND, UPDATING, UPDATED }

enum TreeMode { AVAILABLE, SEARCHING, SEARCHED }

const PLUG_GD_PATH = "res://plug.gd"
const PLUG_BASE_PATH = "res://addons/gd-plug-plus/plug.gd"
const ADDON_INDEX_PATH = "res://addons/gd-plug-plus/addon_index.json"
const COLOR_UNKNOWN = PlugUIConstants.COLOR_UNKNOWN
const COLOR_CHECKING = PlugUIConstants.COLOR_CHECKING
const COLOR_UP_TO_DATE = PlugUIConstants.COLOR_UP_TO_DATE
const COLOR_BEHIND = PlugUIConstants.COLOR_BEHIND
const COLOR_UPDATING = PlugUIConstants.COLOR_UPDATING
const COLOR_UPDATED = PlugUIConstants.COLOR_UPDATED
const COLOR_ACTION = PlugUIConstants.COLOR_ACTION
const COLOR_COMMIT = PlugUIConstants.COLOR_COMMIT
const COLOR_URL = PlugUIConstants.COLOR_URL
const COLOR_CONFLICT = PlugUIConstants.COLOR_CONFLICT

const SELF_REPO_NAME = "huzz-open/gd-plug-plus"
const SELF_REPO_URL = "https://github.com/huzz-open/gd-plug-plus"
const SELF_ADDON_DIR = "addons/gd-plug-plus"

var addon_data: AddonData = AddonData.new()
var loading_spinner: TextureRect
var release_manager: ReleaseManager
var _download_progress_bar: ProgressBar
var _overlay_base_text: String = ""

var _is_executing: bool = false
var _version_info_task_id: int = -1
var _addon_index: Array = []
var _version_cache: Dictionary = {}
var _version_state: Dictionary = {}
var _installing_repos: Dictionary = {}
## repo_name -> error i18n key; tracks per-batch install failures so that
## `_on_install_completed` can distinguish partial/total failures from full success.
var _install_failures: Dictionary = {}
## repo_name -> deep snapshot of the repo dict captured BEFORE the batch mutated
## addon_data, or `null` if the repo did not exist pre-batch. Used by
## `_rollback_repo_to_snapshot` so that aborted installs leave addons.json in
## exactly its pre-batch state (no ghost "Installing"/"Installed" rows in the
## installed tree).
var _install_pre_snapshots: Dictionary = {}
var _local_info_task_id: int = -1
var _local_info_done: bool = false
var _local_info_active: bool = false
var _search_task_id: int = -1
var _search_done: bool = false
var _search_active: bool = false
var _search_result: Dictionary = {}
var _search_url: String = ""
var _search_branches: PackedStringArray = []
var _search_tags: PackedStringArray = []
var _search_default_branch: String = ""
var _search_head_commit: String = ""
var _search_cancelled: bool = false
var _install_task_id: int = -1
var _install_done: bool = false
var _install_active: bool = false
var _update_task_id: int = -1
var _update_done: bool = false
var _update_active: bool = false
var _version_info_task_id_active: bool = false
var _version_info_done: bool = false
var _tree_mode: int = TreeMode.AVAILABLE
var _search_btn: Button
var _search_ref_commits: Dictionary = {}
var _search_overlay: CenterContainer
var _search_spinner: TextureRect
var _search_overlay_label: Label
var _console_collapsed: bool = true
var _console_panel: PanelContainer
var _console_toggle_btn: Button
var _console_log: RichTextLabel
var _console_clear_btn: Button
var _last_log_count: int = 0
var _installed_filter_input: LineEdit
var _selector_popup: SelectorPopup
var _selector_target_item: TreeItem
var _selector_context: String = ""
var _selector_repo_name: String = ""
var _popup_loading: bool = false
var _popup_task_id: int = -1
var _popup_done: bool = false
var _popup_active: bool = false
var _popup_result: Dictionary = {}
var _remote_ref_cache: Dictionary = {}
var _commit_cache: Dictionary = {}
var _pending_changes: Dictionary = {}
var _is_version_switch: bool = false
var _update_cancelled: bool = false
var _install_cancelled: bool = false
var _release_checkbox: CheckBox
var _search_coordinator: SearchCoordinator = SearchCoordinator.new()
var _release_search_pending: bool = false
## platform_key -> outer MarginContainer wrapping the platform PanelContainer
## (used by _focus_settings_tab to flash + ensure_control_visible).
var _settings_platform_panels: Dictionary = {}
## category_key -> { "button": Button, "content": Control } for the sidebar
## navigation. Switching categories toggles `content.visible` only — every
## category panel is built once on _setup_settings_tab.
var _settings_categories: Dictionary = {}
## Currently active category key in the Settings tab; also persists which
## panel _focus_settings_tab should reveal when called from pre-check.
var _settings_active_category: String = ""
## platform_key -> {
##   "name_link": LinkButton, "pat_input": LineEdit,
##   "save_btn": Button, "clear_btn": Button, "validate_btn": Button,
##   "status_icon": Label, "validation_state": String,   # UNKNOWN / PENDING / OK / FAIL
##   "validate_http": HTTPRequest,                       # lazy-created per row
##   # GitHub-only:
##   "device_btn": Button,
##   "device_dialog": AcceptDialog,                      # null when not active
##   "device_uri": String,
## }
var _settings_platform_rows: Dictionary = {}
var _device_flow: GitHubDeviceFlow
var _settings_flash_tween: Tween
var _settings_refreshing: bool = false
var _settings_header_rtl: RichTextLabel
var _about_labels: Array[Dictionary] = []
var _cache_labels: Array[Dictionary] = []
var _cache_repo_path_label: Label
var _cache_release_path_label: Label
var _cache_clear_repo_btn: Button
var _cache_clear_release_btn: Button
var _proxy_enable_cb: CheckBox
var _proxy_host_input: LineEdit
var _proxy_port_spin: SpinBox
var _console_header_height: int = PlugUIConstants.CONSOLE_HEADER_HEIGHT
var _console_expanded_height: int = PlugUIConstants.CONSOLE_EXPANDED_HEIGHT

@onready var tab_container: TabContainer = $TabContainer
@onready var installed_tree: Tree = %InstalledTree
@onready var search_input: LineEdit = %SearchInput
@onready var check_version_btn: Button = %CheckVersionBtn
@onready var update_all_btn: Button = %UpdateAllBtn
@onready var loading_overlay: PanelContainer = %LoadingOverlay
@onready var loading_label: Label = %LoadingLabel
@onready var cancel_update_btn: Button = %CancelUpdateBtn
@onready var search_result_panel: VBoxContainer = %SearchResultPanel
@onready var search_status_label: Label = %SearchStatusLabel
@onready var search_tree: Tree = %SearchTree
@onready var install_selected_btn: Button = %InstallSelectedBtn

# ===========================================================================
# Shared helpers (used by both tabs)
# ===========================================================================


static func _get_editor_scale() -> float:
	if Engine.is_editor_hint():
		return EditorInterface.get_editor_scale()
	return 1.0


static func _scaled(value: float) -> int:
	return int(value * _get_editor_scale())


static func _tr(key: String) -> String:
	return TranslationServer.get_or_add_domain("gd-plug-plus").translate(key)


static func _short_commit(hash: String) -> String:
	return (
		hash.left(PlugUIConstants.SHORT_COMMIT_LENGTH)
		if hash.length() > PlugUIConstants.SHORT_COMMIT_LENGTH
		else hash
	)


static func _format_branch_tag(branch: String, tag: String) -> String:
	if not tag.is_empty():
		return tag + " [tag]"
	if not branch.is_empty():
		return branch
	return "--"


func _build_branch_tag_groups(branches: PackedStringArray, tags: PackedStringArray) -> Array:
	var groups: Array = []
	if not branches.is_empty():
		var items: Array = []
		for b in branches:
			items.append({"columns": [b], "meta": {"type": "branch", "name": b}})
		groups.append({"header": tr("BRANCH_HEADER") % branches.size(), "items": items})
	if not tags.is_empty():
		var items: Array = []
		for t in tags:
			items.append({"columns": [t], "meta": {"type": "tag", "name": t}})
		groups.append({"header": tr("TAG_HEADER") % tags.size(), "items": items})
	return groups


func _build_commit_groups(commits: Array) -> Array:
	var groups: Array = []
	var items: Array = []
	for c in commits:
		var hs = c.get("hash_short", _short_commit(c.get("hash", "")))
		(
			items
			. append(
				{
					"columns": [hs, c.get("message", "")],
					"meta": {"type": "commit", "hash": c.get("hash", ""), "hash_short": hs},
				}
			)
		)
	if not items.is_empty():
		groups.append({"header": "", "items": items})
	return groups


# ===========================================================================
# Lifecycle
# ===========================================================================


func _ready():
	PlugLogger.debug("AddonManager._ready() start")
	PlugLogger.info(_tr("LOG_PLUGGED_DIR") % GitManager.get_plugged_dir())
	_console_header_height = _scaled(PlugUIConstants.CONSOLE_HEADER_HEIGHT)
	_console_expanded_height = _scaled(PlugUIConstants.CONSOLE_EXPANDED_HEIGHT)
	loading_spinner = loading_overlay.get_node(
		"CenterContainer/VBoxContainer/HBoxContainer/TextureRect"
	)
	release_manager = ReleaseManager.new()
	release_manager.name = "ReleaseManager"
	add_child(release_manager)
	_search_coordinator.all_completed.connect(_on_coordinator_search_completed)
	_load_addon_index()
	_init_data()

	var bottom_panel: MarginContainer = $"TabContainer/Installed/BottomPanel"
	bottom_panel.add_theme_constant_override(
		"margin_left", _scaled(PlugUIConstants.MARGIN_STANDARD)
	)
	bottom_panel.add_theme_constant_override("margin_top", _scaled(PlugUIConstants.MARGIN_COMPACT))
	bottom_panel.add_theme_constant_override(
		"margin_right", _scaled(PlugUIConstants.MARGIN_STANDARD)
	)
	bottom_panel.add_theme_constant_override(
		"margin_bottom", _scaled(PlugUIConstants.MARGIN_COMPACT)
	)
	var bottom_hbox: HBoxContainer = bottom_panel.get_node("HBoxContainer")
	bottom_hbox.add_theme_constant_override(
		"separation", _scaled(PlugUIConstants.SEPARATION_STANDARD)
	)
	var search_bar: MarginContainer = $"TabContainer/InstallNew/SearchBar"
	search_bar.add_theme_constant_override("margin_left", _scaled(PlugUIConstants.MARGIN_STANDARD))
	search_bar.add_theme_constant_override("margin_top", _scaled(PlugUIConstants.MARGIN_STANDARD))
	search_bar.add_theme_constant_override("margin_right", _scaled(PlugUIConstants.MARGIN_STANDARD))
	search_tree.custom_minimum_size = Vector2(0, _scaled(PlugUIConstants.SEARCH_TREE_MIN_HEIGHT))
	var overlay_vbox: VBoxContainer = loading_overlay.get_node("CenterContainer/VBoxContainer")
	overlay_vbox.add_theme_constant_override(
		"separation", _scaled(PlugUIConstants.SEPARATION_LARGE)
	)
	_download_progress_bar = ProgressBar.new()
	_download_progress_bar.custom_minimum_size = Vector2(_scaled(300), 0)
	_download_progress_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_download_progress_bar.visible = false
	_download_progress_bar.show_percentage = true
	var cancel_btn_idx := cancel_update_btn.get_index() if cancel_update_btn else -1
	if cancel_btn_idx >= 0:
		overlay_vbox.add_child(_download_progress_bar)
		overlay_vbox.move_child(_download_progress_bar, cancel_btn_idx)
	else:
		overlay_vbox.add_child(_download_progress_bar)
	release_manager.download_progress.connect(_on_download_progress)

	installed_tree.columns = PlugUIConstants.INSTALLED_COL_WIDTHS.size()
	installed_tree.column_titles_visible = true
	installed_tree.hide_root = true
	for ci in range(installed_tree.columns):
		installed_tree.set_column_expand(ci, PlugUIConstants.INSTALLED_COL_EXPAND[ci])
		installed_tree.set_column_custom_minimum_width(
			ci, _scaled(PlugUIConstants.INSTALLED_COL_WIDTHS[ci])
		)
	for ci in range(installed_tree.columns):
		installed_tree.set_column_clip_content(ci, true)
	installed_tree.item_mouse_selected.connect(_on_installed_tree_mouse_selected)

	search_result_panel.visible = true
	search_status_label.visible = false
	install_selected_btn.disabled = true

	search_tree.columns = PlugUIConstants.SEARCH_COL_WIDTHS.size()
	search_tree.column_titles_visible = true
	search_tree.hide_root = true
	for ci in range(search_tree.columns):
		search_tree.set_column_expand(ci, PlugUIConstants.SEARCH_COL_EXPAND[ci])
		search_tree.set_column_custom_minimum_width(
			ci, _scaled(PlugUIConstants.SEARCH_COL_WIDTHS[ci])
		)
	for ci in range(search_tree.columns):
		search_tree.set_column_clip_content(ci, true)
	search_tree.item_edited.connect(_on_search_tree_item_edited)
	search_tree.item_mouse_selected.connect(_on_search_tree_mouse_selected)

	_setup_search_bar()
	_setup_installed_filter()
	_setup_search_overlay()
	_setup_settings_tab()
	_setup_console()
	_apply_translations()

	_refresh_installed_tree()
	_refresh_unified_tree()
	connect("visibility_changed", _on_visibility_changed)
	tab_container.tab_changed.connect(_on_tab_changed)
	_local_info_done = false
	_local_info_active = true
	_local_info_task_id = WorkerThreadPool.add_task(_load_local_version_info)


func _init_data():
	var err = addon_data.load_data()
	if err == ERR_FILE_NOT_FOUND:
		_try_migrate_legacy()
	_ensure_self_tracked()
	check_version_btn.show()
	update_all_btn.show()
	addon_data.check_consistency()


func _ensure_self_tracked():
	if addon_data.has_repo(SELF_REPO_NAME):
		return
	var cfg = ConfigFile.new()
	if cfg.load("res://addons/gd-plug-plus/plugin.cfg") != OK:
		return
	var pname = cfg.get_value("plugin", "name", "gd-plug-plus")
	var pdesc = cfg.get_value("plugin", "description", "")
	var pver = cfg.get_value("plugin", "version", "")
	var pauthor = cfg.get_value("plugin", "author", "")
	var found_addons: Array = [
		{
			"name": pname,
			"description": pdesc,
			"type": "plugin",
			"addon_dir": SELF_ADDON_DIR,
			"version": pver,
			"author": pauthor,
		}
	]
	addon_data.add_repo_from_search(SELF_REPO_NAME, SELF_REPO_URL, found_addons, "main")
	addon_data.set_addon_installed(SELF_REPO_NAME, SELF_ADDON_DIR, true)
	addon_data.save_data()
	PlugLogger.info("Self-tracked gd-plug-plus in addons.json")


func _try_migrate_legacy():
	if not FileAccess.file_exists(PLUG_GD_PATH) and not FileAccess.file_exists(PLUG_BASE_PATH):
		return
	var base_path = PLUG_GD_PATH if FileAccess.file_exists(PLUG_GD_PATH) else PLUG_BASE_PATH
	var gd_plug_script = load(base_path)
	if gd_plug_script == null:
		return
	var gd_plug = gd_plug_script.new()
	gd_plug._plug_start()
	if FileAccess.file_exists(PLUG_GD_PATH):
		gd_plug._plugging()
	var plugged = gd_plug._plugged_plugins if gd_plug._plugged_plugins else {}
	var installed = gd_plug.installation_config.get_value("plugin", "installed", {})
	gd_plug.free()
	if plugged.is_empty() and installed.is_empty():
		return
	addon_data.migrate_from_legacy(plugged, installed)
	addon_data.save_data()


func _process(_delta):
	if _search_overlay != null and _search_overlay.visible and _search_spinner != null:
		_search_spinner.pivot_offset = _search_spinner.size * 0.5
		_search_spinner.rotation += _delta * TAU * PlugUIConstants.SPINNER_SPEED
	if loading_overlay.visible and loading_spinner != null:
		loading_spinner.pivot_offset = loading_spinner.size * 0.5
		loading_spinner.rotation += _delta * TAU * PlugUIConstants.SPINNER_SPEED
	_update_console()
	if _local_info_done:
		_local_info_done = false
		if _local_info_active:
			WorkerThreadPool.wait_for_task_completion(_local_info_task_id)
			_local_info_task_id = -1
			_local_info_active = false
		_refresh_installed_tree()
	if _search_done:
		_search_done = false
		PlugLogger.debug("search task completed, waiting for thread...")
		if _search_active:
			WorkerThreadPool.wait_for_task_completion(_search_task_id)
			_search_task_id = -1
			_search_active = false
		PlugLogger.debug("calling _on_search_completed")
		_on_search_completed()
	if _version_info_done:
		_version_info_done = false
		if _version_info_task_id_active:
			WorkerThreadPool.wait_for_task_completion(_version_info_task_id)
			_version_info_task_id = -1
			_version_info_task_id_active = false
		_refresh_installed_tree()
		show_overlay(false)
		disable_ui(false)
	if _install_done:
		_install_done = false
		if _install_active:
			WorkerThreadPool.wait_for_task_completion(_install_task_id)
			_install_task_id = -1
			_install_active = false
		_on_install_completed()
	if _update_done:
		_update_done = false
		if _update_active:
			WorkerThreadPool.wait_for_task_completion(_update_task_id)
			_update_task_id = -1
			_update_active = false
		_on_update_completed()
	if _popup_done:
		_popup_done = false
		if _popup_active:
			WorkerThreadPool.wait_for_task_completion(_popup_task_id)
			_popup_task_id = -1
			_popup_active = false
		_on_popup_data_loaded()


func _notification(what):
	match what:
		NOTIFICATION_PREDELETE:
			PlugLogger.debug("PREDELETE — node about to be destroyed")
			_wait_and_cleanup_tasks()
			PlugLogger.debug("PREDELETE — thread cleanup done")
			if is_instance_valid(_selector_popup):
				_selector_popup.queue_free()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			if not _is_executing:
				addon_data.load_data()
				_refresh_installed_tree()
		NOTIFICATION_TRANSLATION_CHANGED:
			if is_node_ready():
				_apply_translations()
				_refresh_installed_tree()
				if _tree_mode == TreeMode.SEARCHED:
					_update_search_tree_install_status()
					_update_install_selected_count()
				else:
					_refresh_unified_tree(search_input.text if search_input else "")


func _wait_and_cleanup_tasks():
	PlugLogger.debug("request_cancel + waiting for all threads...")
	GitManager.request_cancel()
	if is_instance_valid(release_manager):
		release_manager.cancel()
	if not _installing_repos.is_empty():
		PlugLogger.debug("rolling back %d in-progress installs..." % _installing_repos.size())
		for repo_name in _installing_repos.keys():
			_rollback_repo_to_snapshot(repo_name)
		_installing_repos.clear()
		_install_pre_snapshots.clear()
		addon_data.save_data()
	var names = ["search", "local_info", "version_info", "install", "update", "popup"]
	var ids = [
		_search_task_id,
		_local_info_task_id,
		_version_info_task_id,
		_install_task_id,
		_update_task_id,
		_popup_task_id
	]
	var actives = [
		_search_active,
		_local_info_active,
		_version_info_task_id_active,
		_install_active,
		_update_active,
		_popup_active
	]
	for i in range(ids.size()):
		if actives[i] and ids[i] >= 0:
			PlugLogger.debug("waiting for %s (tid=%d)..." % [names[i], ids[i]])
			WorkerThreadPool.wait_for_task_completion(ids[i])
			PlugLogger.debug("%s completed" % names[i])
	_search_task_id = -1
	_search_done = false
	_search_active = false
	_local_info_task_id = -1
	_local_info_done = false
	_local_info_active = false
	_version_info_task_id = -1
	_version_info_done = false
	_version_info_task_id_active = false
	_install_task_id = -1
	_install_done = false
	_install_active = false
	_update_task_id = -1
	_update_done = false
	_update_active = false
	_popup_task_id = -1
	_popup_done = false
	_popup_active = false
	GitManager.reset_cancel()
	PlugLogger.debug("all threads cleaned up")


# ===========================================================================
# i18n
# ===========================================================================


func _apply_translations():
	if not is_node_ready():
		return
	tab_container.set_tab_title(0, tr("TAB_INSTALLED"))
	tab_container.set_tab_title(1, tr("TAB_INSTALL_NEW"))
	if tab_container.get_tab_count() > 2:
		tab_container.set_tab_title(2, tr("TAB_SETTINGS"))
	check_version_btn.text = tr("BTN_CHECK_UPDATE")
	update_all_btn.text = tr("BTN_UPDATE_ALL")

	installed_tree.set_column_title(0, tr("COL_NAME"))
	installed_tree.set_column_title(1, tr("COL_DESCRIPTION"))
	installed_tree.set_column_title(2, tr("COL_VERSION"))
	installed_tree.set_column_title(3, tr("COL_BRANCH_TAG"))
	installed_tree.set_column_title(4, tr("COL_COMMIT"))
	installed_tree.set_column_title(5, tr("COL_UPDATE_TIME"))
	installed_tree.set_column_title(6, tr("COL_ACTIONS"))
	installed_tree.set_column_title(7, "")
	installed_tree.set_column_title(8, "")
	installed_tree.set_column_title(9, "")

	search_tree.set_column_title(1, tr("COL_STATUS"))
	search_tree.set_column_title(2, tr("COL_NAME"))
	search_tree.set_column_title(3, tr("COL_VERSION"))
	search_tree.set_column_title(4, tr("COL_TYPE"))
	search_tree.set_column_title(5, tr("COL_BRANCH_TAG"))
	search_tree.set_column_title(6, tr("COL_COMMIT"))
	search_tree.set_column_title(7, tr("COL_REPO_PATH"))
	search_tree.set_column_title(8, tr("COL_AUTHOR"))

	if _search_btn:
		_search_btn.text = tr("BTN_SEARCH")
	if search_input:
		search_input.placeholder_text = tr("SEARCH_PLACEHOLDER")
	if _search_overlay_label:
		_search_overlay_label.text = tr("SEARCHING")
	if _release_checkbox:
		_release_checkbox.text = tr("SEARCH_RELEASE_CHECKBOX")
	_retranslate_settings_tab()
	if _console_toggle_btn:
		_console_toggle_btn.text = (
			tr("CONSOLE_COLLAPSED") if _console_collapsed else tr("CONSOLE_EXPANDED")
		)
	if _console_clear_btn:
		_console_clear_btn.text = tr("CONSOLE_CLEAR")
	if _installed_filter_input:
		_installed_filter_input.placeholder_text = tr("INSTALLED_FILTER_PLACEHOLDER")


# ===========================================================================
# Plugin Index
# ===========================================================================


func _load_addon_index():
	_addon_index.clear()
	if not FileAccess.file_exists(ADDON_INDEX_PATH):
		return
	var file = FileAccess.open(ADDON_INDEX_PATH, FileAccess.READ)
	if file == null:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data = json.data
		if data is Array:
			_addon_index = data
	file.close()


func _get_index_description(repo_url: String) -> String:
	var repo_name = GitManager.repo_name_from_url(repo_url)
	for entry in _addon_index:
		if not entry is Dictionary:
			continue
		var entry_repo = GitManager.repo_name_from_url(entry.get("url", ""))
		if entry_repo == repo_name:
			var addons_arr: Array = entry.get("addons", [])
			if addons_arr.size() > 0 and addons_arr[0] is Dictionary:
				return addons_arr[0].get("description", "")
	return ""


func _refresh_unified_tree(filter_text: String = ""):
	if not is_node_ready():
		return
	if _tree_mode != TreeMode.AVAILABLE:
		return
	search_tree.clear()
	search_tree.create_item()
	install_selected_btn.disabled = true
	var btn_tpl = tr("BTN_INSTALL_SELECTED")
	install_selected_btn.text = btn_tpl % 0 if "%d" in btn_tpl else btn_tpl
	var filter_lower = filter_text.to_lower()
	var existing_addons = _get_existing_addons()

	for entry in _addon_index:
		if not entry is Dictionary:
			continue
		var url: String = entry.get("url", "")
		if url.is_empty():
			continue
		var addons_arr: Array = entry.get("addons", [])
		if addons_arr.is_empty():
			continue

		var repo_name = GitManager.repo_name_from_url(url)
		var already_installed = addon_data.has_repo(repo_name)

		for addon in addons_arr:
			if not addon is Dictionary:
				continue
			var pname: String = addon.get("name", "")
			var desc: String = addon.get("description", "")
			var addon_dir: String = addon.get("addon_dir", "")
			var author: String = addon.get("author", "")
			var branch: String = addon.get("branch", "main")
			var type_raw: String = addon.get("type", "plugin")
			if pname.is_empty():
				continue

			if not filter_lower.is_empty():
				var match_text = (pname + " " + desc + " " + author + " " + url).to_lower()
				if filter_lower not in match_text:
					continue

			var has_conflict := false
			if not addon_dir.is_empty() and not already_installed:
				has_conflict = not (
					addon_data.check_dir_conflicts([addon_dir], existing_addons).is_empty()
				)

			var item = search_tree.create_item(search_tree.get_root())

			item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			item.set_checked(0, false)
			item.set_editable(0, not already_installed)

			if already_installed:
				item.set_text(1, tr("STATUS_INSTALLED"))
				item.set_custom_color(1, COLOR_UP_TO_DATE)
			else:
				item.set_text(1, tr("STATUS_NOT_INSTALLED"))
				item.set_custom_color(1, COLOR_UNKNOWN)
			item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)

			item.set_text(2, pname)
			if has_conflict and not already_installed:
				item.set_custom_color(2, COLOR_CONFLICT)
				item.set_tooltip_text(2, url + "\n" + tr("CONFLICT_DIR_EXISTS") % addon_dir)
			else:
				item.set_tooltip_text(2, url)

			item.set_text(3, "--")
			item.set_text_alignment(3, HORIZONTAL_ALIGNMENT_CENTER)

			var type_text = "Plugin" if type_raw in ["editor_plugin", "plugin"] else "Extension"
			item.set_text(4, type_text)

			item.set_text(5, branch)
			item.set_custom_color(5, COLOR_UPDATED)
			item.set_text_alignment(5, HORIZONTAL_ALIGNMENT_CENTER)
			item.set_tooltip_text(5, tr("BRANCH_CLICK_HINT"))

			item.set_text(6, "--")
			item.set_text_alignment(6, HORIZONTAL_ALIGNMENT_CENTER)

			item.set_text(7, addon_dir)
			item.set_text(8, author)

			item.set_meta("addon_info", addon)
			item.set_meta("repo", url)
			item.set_meta("is_available", true)
			item.set_meta("selected_branch", branch)
			item.set_meta("selected_tag", "")
			item.set_meta("selected_commit", "")
			item.set_meta("has_conflict", has_conflict)

	_update_install_selected_count()


# ===========================================================================
# Installed tree rendering
# ===========================================================================


func _get_installed_filter_text() -> String:
	if _installed_filter_input and is_instance_valid(_installed_filter_input):
		return _installed_filter_input.text
	return ""


func _refresh_installed_tree(filter_text: String = ""):
	if not is_node_ready():
		return
	if filter_text.is_empty():
		filter_text = _get_installed_filter_text()
	installed_tree.clear()
	installed_tree.create_item()

	var repos = addon_data.get_all_repos_for_ui()
	var filter_lower = filter_text.to_lower()

	for repo_entry in repos:
		var repo_name: String = repo_entry["repo_name"]
		var url: String = repo_entry["url"]
		var addons: Array = repo_entry["addons"]
		var is_multi = addons.size() > 1

		# Hide rows that are currently mid-install. `_execute_install` /
		# `_install_repo_manual` write `installed=true` BEFORE the actual
		# download/extract starts (so the install loop has a working entry to
		# operate on), but the user shouldn't see a half-baked row in the
		# Installed tab until it's truly done. Progress is visible in the
		# Search tab (`STATUS_INSTALLING`) and the install button text.
		if repo_name in _installing_repos:
			continue

		if not filter_lower.is_empty():
			var match_text = (repo_name + " " + url).to_lower()
			var any_addon_match = false
			for a in addons:
				if filter_lower in (a.get("name", "") + " " + a.get("description", "")).to_lower():
					any_addon_match = true
					break
			if filter_lower not in match_text and not any_addon_match:
				continue

		var first_addon = _first_installed_or_first(addons)
		var child = installed_tree.create_item(installed_tree.get_root())
		var is_locked = addon_data.is_repo_locked(repo_name)
		var has_pending = _pending_changes.has(repo_name)
		var pending = _pending_changes.get(repo_name, {}) as Dictionary
		var vstate = _version_state.get(repo_name, VersionState.UNKNOWN)
		var is_release_installed = first_addon.get("installed_from", "") == "release"
		var installed_asset: String = first_addon.get("installed_asset_filename", "")

		var plugin_name = first_addon.get("name", "")
		if is_release_installed and not plugin_name.is_empty() and not installed_asset.is_empty():
			if plugin_name == installed_asset.get_basename():
				plugin_name = ""
		var display_name = plugin_name if not plugin_name.is_empty() else repo_name
		if is_multi:
			display_name = tr("MULTI_ADDONS_COUNT") % [display_name, addons.size()]
		child.set_text(0, display_name)
		child.set_tooltip_text(0, url)

		var desc_text = first_addon.get("description", "")
		if desc_text.is_empty() and is_release_installed and not installed_asset.is_empty():
			desc_text = "Release " + installed_asset
		elif desc_text.is_empty():
			desc_text = _get_index_description(url)
		child.set_text(1, desc_text)
		child.set_custom_color(1, COLOR_URL)

		var ver = first_addon.get("version", "")
		child.set_text(2, _format_version(ver))
		child.set_text_alignment(2, HORIZONTAL_ALIGNMENT_CENTER)

		# Col 3: branch/tag
		var bt_text: String
		var bt_color: Color
		if is_release_installed and has_pending and pending.has("tag"):
			var p_tag: String = pending["tag"]
			var cur_itag = first_addon.get("installed_tag", "")
			bt_text = (p_tag + " [R]") if not p_tag.is_empty() else "[R]"
			bt_color = COLOR_CHECKING if p_tag != cur_itag else COLOR_UPDATED
		elif is_release_installed:
			var itag = first_addon.get("installed_tag", "")
			bt_text = (itag + " [R]") if not itag.is_empty() else "[R]"
			bt_color = COLOR_UPDATED
		elif has_pending:
			var cur_branch = first_addon.get("branch", "")
			var cur_tag = first_addon.get("tag", "")
			var p_tag = pending.get("tag", "") if pending.has("tag") else cur_tag
			var p_branch = pending.get("branch", "") if pending.has("branch") else cur_branch
			if pending.has("tag"):
				p_branch = ""
			elif pending.has("branch"):
				p_tag = ""
			bt_text = _format_branch_tag(p_branch, p_tag)
			var bt_changed = (p_branch != cur_branch) or (p_tag != cur_tag)
			bt_color = COLOR_CHECKING if bt_changed else COLOR_UPDATED
		else:
			var cur_branch = first_addon.get("branch", "")
			var cur_tag = first_addon.get("tag", "")
			bt_text = _format_branch_tag(cur_branch, cur_tag)
			bt_color = COLOR_UPDATED if not is_locked else COLOR_UNKNOWN
		child.set_text(3, bt_text)
		child.set_custom_color(3, bt_color)
		child.set_text_alignment(3, HORIZONTAL_ALIGNMENT_CENTER)

		# Col 4: commit
		var cached = _version_cache.get(repo_name, {})
		var commit_text = ""
		var commit_color: Color
		if is_release_installed:
			commit_text = "--"
			commit_color = COLOR_CHECKING if has_pending else COLOR_UNKNOWN
		elif has_pending and not pending.get("commit_preview", "").is_empty():
			commit_text = pending["commit_preview"]
			commit_color = COLOR_CHECKING
		else:
			if cached.has("current_commit") and not cached["current_commit"].is_empty():
				commit_text = _short_commit(cached["current_commit"])
			elif not first_addon.is_empty():
				commit_text = _short_commit(first_addon.get("commit", ""))
			commit_color = _commit_color(vstate != VersionState.BEHIND)
			if is_locked and not has_pending and vstate != VersionState.BEHIND:
				commit_color = COLOR_UNKNOWN
		child.set_text(4, commit_text)
		child.set_custom_color(4, commit_color)
		child.set_text_alignment(4, HORIZONTAL_ALIGNMENT_CENTER)

		child.set_text(5, cached.get("commit_date", ""))

		# Col 6: detail
		child.set_text(6, tr("ACTION_DETAIL"))
		child.set_custom_color(6, COLOR_ACTION)
		child.set_text_alignment(6, HORIZONTAL_ALIGNMENT_CENTER)

		# Col 7: lock/unlock
		if is_locked:
			child.set_text(7, tr("BTN_UNLOCK"))
			child.set_custom_color(7, COLOR_CHECKING)
		else:
			child.set_text(7, tr("BTN_LOCK"))
			child.set_custom_color(7, COLOR_ACTION)
		child.set_text_alignment(7, HORIZONTAL_ALIGNMENT_CENTER)

		# Col 8: update/apply/locked
		if is_locked:
			child.set_text(8, tr("STATUS_LOCKED"))
			child.set_custom_color(8, COLOR_UNKNOWN)
		elif has_pending:
			child.set_text(8, tr("BTN_APPLY"))
			child.set_custom_color(8, COLOR_BEHIND)
		else:
			var action_text = _get_update_action_text(repo_name, first_addon)
			var action_color = _get_update_action_color(repo_name, first_addon)
			child.set_text(8, action_text)
			child.set_custom_color(8, action_color)
		child.set_text_alignment(8, HORIZONTAL_ALIGNMENT_CENTER)

		# Col 9: uninstall (self plugin excluded)
		if repo_name != SELF_REPO_NAME:
			child.set_text(9, tr("ACTION_UNINSTALL"))
			child.set_custom_color(9, COLOR_ACTION)
			child.set_text_alignment(9, HORIZONTAL_ALIGNMENT_CENTER)

		child.set_meta("repo_name", repo_name)

		if is_multi:
			child.set_collapsed(true)
			for sp in addons:
				var sub_item = installed_tree.create_item(child)
				sub_item.set_text(0, sp.get("name", ""))
				sub_item.set_custom_color(
					0, COLOR_URL if sp.get("installed", false) else COLOR_UNKNOWN
				)
				sub_item.set_text(1, sp.get("description", ""))
				sub_item.set_custom_color(1, COLOR_URL)
				var sp_ver = sp.get("version", "")
				sub_item.set_text(2, _format_version(sp_ver))
				sub_item.set_text(
					5,
					tr("SUB_INSTALLED") if sp.get("installed", false) else tr("SUB_NOT_INSTALLED")
				)
				sub_item.set_custom_color(
					5, COLOR_UP_TO_DATE if sp.get("installed", false) else COLOR_UNKNOWN
				)
				sub_item.set_text(6, tr("ACTION_DETAIL"))
				sub_item.set_custom_color(6, COLOR_ACTION)
				sub_item.set_text_alignment(6, HORIZONTAL_ALIGNMENT_CENTER)
				sub_item.set_meta("repo_name", repo_name)
				sub_item.set_meta("addon_dir", sp.get("addon_dir", ""))
				for sci in [3, 4, 7, 8, 9]:
					sub_item.set_selectable(sci, false)


func _first_installed_or_first(addons: Array) -> Dictionary:
	for p in addons:
		if p.get("installed", false):
			return p
	return addons[0] if addons.size() > 0 else {}


# ===========================================================================
# Display helpers
# ===========================================================================


## Commit color: latest=blue, behind=red, unknown=gray.
## Both Installed and Search tabs use this for consistency.
static func _commit_color(is_latest: bool) -> Color:
	return COLOR_UPDATED if is_latest else COLOR_BEHIND


func _get_update_action_text(repo_name: String, addon: Dictionary) -> String:
	if repo_name in _installing_repos:
		return tr("STATUS_INSTALLING")
	var result: String
	var vstate = _version_state.get(repo_name, VersionState.UNKNOWN)
	match vstate:
		VersionState.CHECKING:
			result = tr("STATUS_CHECKING")
		VersionState.UPDATING:
			result = tr("STATUS_UPDATING")
		VersionState.UP_TO_DATE, VersionState.UPDATED:
			result = tr("STATUS_LATEST")
		VersionState.BEHIND:
			result = tr("STATUS_UPDATE")
		_:
			if not AddonData.is_updatable(addon):
				result = tr("STATUS_LOCKED")
			else:
				result = tr("STATUS_UPDATE")
	return result


func _get_update_action_color(repo_name: String, addon: Dictionary) -> Color:
	if repo_name in _installing_repos:
		return COLOR_CHECKING
	var result: Color
	var vstate = _version_state.get(repo_name, VersionState.UNKNOWN)
	match vstate:
		VersionState.CHECKING, VersionState.UPDATING:
			result = COLOR_CHECKING
		VersionState.UP_TO_DATE:
			result = COLOR_UP_TO_DATE
		VersionState.UPDATED:
			result = COLOR_UPDATED
		VersionState.BEHIND:
			result = COLOR_BEHIND
		_:
			if not AddonData.is_updatable(addon):
				result = COLOR_UNKNOWN
			else:
				result = COLOR_ACTION
	return result


# ===========================================================================
# Version info
# ===========================================================================


func _fetch_all_version_info():
	for repo_name in addon_data.get_repos():
		_version_state[repo_name] = VersionState.CHECKING
	_refresh_installed_tree()
	show_overlay(true, tr("OVERLAY_CHECKING_VERSION"))
	disable_ui(true)
	_remote_ref_cache.clear()
	_commit_cache.clear()
	_version_info_done = false
	_version_info_task_id_active = true
	_version_info_task_id = WorkerThreadPool.add_task(_collect_version_info)


func _collect_version_info():
	for repo_name in addon_data.get_repos():
		var is_release_repo = addon_data.get_repo_install_from(repo_name) == "release"
		if is_release_repo:
			_version_state[repo_name] = VersionState.UP_TO_DATE
			var installed = addon_data.get_installed_addons(repo_name)
			if not installed.is_empty():
				_version_cache[repo_name] = {
					"current_branch": "",
					"current_commit": "",
					"current_tag": installed[0].get("installed_tag", ""),
					"commit_date": "",
					"behind": 0,
					"installed_from": "release",
				}
			continue
		var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
		if not DirAccess.dir_exists_absolute(plug_dir.path_join(".git")):
			if not _ensure_repo_cloned(repo_name):
				_version_state[repo_name] = VersionState.UNKNOWN
				continue
		var info = GitManager.get_current_info(plug_dir)
		var result: Dictionary = {
			"current_branch": info.get("branch", ""),
			"current_commit": info.get("commit_short", ""),
			"current_tag": info.get("tag", ""),
			"commit_date": info.get("date", ""),
		}
		var plugins = addon_data.get_installed_addons(repo_name)
		var max_behind := 0
		for p in plugins:
			if not AddonData.is_updatable(p):
				continue
			var branch = p.get("branch", "")
			if branch.is_empty():
				branch = GitManager.get_remote_default_branch(plug_dir)
			var compare_result = GitManager.fetch_and_compare(plug_dir, branch)
			var behind = compare_result.get("behind", 0)
			if behind > max_behind:
				max_behind = behind
		result["behind"] = max_behind
		_version_cache[repo_name] = result
		_version_state[repo_name] = (
			VersionState.BEHIND if max_behind > 0 else VersionState.UP_TO_DATE
		)
	_version_info_done = true


func _load_local_version_info():
	for repo_name in addon_data.get_repos():
		if _version_cache.has(repo_name):
			continue
		var is_release_repo = addon_data.get_repo_install_from(repo_name) == "release"
		if is_release_repo:
			var installed = addon_data.get_installed_addons(repo_name)
			if not installed.is_empty():
				var first = installed[0]
				_version_cache[repo_name] = {
					"current_branch": "",
					"current_commit": "",
					"current_tag": first.get("installed_tag", ""),
					"commit_date": "",
					"behind": 0,
					"installed_from": "release",
				}
			continue
		var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
		var info = GitManager.get_current_info(plug_dir)
		if info.get("commit_short", "").is_empty():
			continue
		var branch: String = info.get("branch", "")
		var behind := GitManager.local_behind_count(plug_dir, branch)
		_version_cache[repo_name] = {
			"current_branch": branch,
			"current_commit": info.get("commit_short", ""),
			"current_tag": info.get("tag", ""),
			"commit_date": info.get("date", ""),
			"behind": behind,
		}
		if not _version_state.has(repo_name) or _version_state[repo_name] == VersionState.UNKNOWN:
			_version_state[repo_name] = (
				VersionState.BEHIND if behind > 0 else VersionState.UP_TO_DATE
			)
	_local_info_done = true


# ===========================================================================
# UI helpers
# ===========================================================================


func disable_ui(disabled: bool = true):
	check_version_btn.disabled = disabled
	update_all_btn.disabled = disabled
	if _search_btn:
		_search_btn.disabled = disabled


func show_overlay(show: bool = true, text: String = ""):
	loading_overlay.visible = show
	loading_label.text = text
	_overlay_base_text = text
	if _download_progress_bar:
		_download_progress_bar.visible = false
		_download_progress_bar.value = 0
	if cancel_update_btn:
		cancel_update_btn.visible = show
		cancel_update_btn.disabled = false
		cancel_update_btn.text = tr("BTN_CANCEL")


func _on_download_progress(downloaded_bytes: int, total_bytes: int) -> void:
	if loading_overlay.visible and _download_progress_bar:
		_download_progress_bar.visible = true
		if total_bytes > 0:
			_download_progress_bar.max_value = total_bytes
			_download_progress_bar.value = downloaded_bytes
			var pct := int(float(downloaded_bytes) / float(total_bytes) * 100.0)
			loading_label.text = "%s  (%s / %s  %d%%)" % [
				_overlay_base_text,
				String.humanize_size(downloaded_bytes),
				String.humanize_size(total_bytes),
				pct,
			]
		else:
			_download_progress_bar.max_value = 100
			_download_progress_bar.value = 0
			loading_label.text = "%s  (%s)" % [
				_overlay_base_text,
				String.humanize_size(downloaded_bytes),
			]
	if not loading_overlay.visible and _is_executing:
		var tip := _format_download_tooltip(downloaded_bytes, total_bytes)
		_set_checked_items_status(_format_download_status(downloaded_bytes, total_bytes), COLOR_CHECKING, tip)


func _format_download_status(downloaded_bytes: int, total_bytes: int) -> String:
	var base := tr("STATUS_DOWNLOADING")
	if total_bytes > 0:
		var pct := int(float(downloaded_bytes) / float(total_bytes) * 100.0)
		return "%s%d%%" % [base, pct]
	return base


func _format_download_tooltip(downloaded_bytes: int, total_bytes: int) -> String:
	if total_bytes > 0:
		var pct := int(float(downloaded_bytes) / float(total_bytes) * 100.0)
		return "%s / %s (%d%%)" % [
			String.humanize_size(downloaded_bytes),
			String.humanize_size(total_bytes),
			pct,
		]
	if downloaded_bytes > 0:
		return String.humanize_size(downloaded_bytes)
	return ""


func _format_version(ver: String, fallback: String = "") -> String:
	if ver.is_empty():
		return fallback
	return ver


func _ensure_repo_cloned(repo_name: String, fallback_url: String = "") -> bool:
	if repo_name.strip_edges().is_empty():
		return false
	var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
	if DirAccess.dir_exists_absolute(plug_dir.path_join(".git")):
		return true
	var url: String = fallback_url
	if url.is_empty():
		var repo = addon_data.get_repo(repo_name)
		url = repo.get("url", "")
	if url.is_empty():
		return false
	if DirAccess.dir_exists_absolute(plug_dir):
		GitManager.delete_directory(plug_dir)
	var exit = GitManager.shallow_clone(url, plug_dir)
	return exit == OK


# ===========================================================================
# Search flow
# ===========================================================================


func _on_SearchUrlBtn_pressed():
	var url = search_input.text.strip_edges()
	PlugLogger.debug("search button pressed, raw input='%s'" % url)
	if url.is_empty():
		return
	if (
		not url.begins_with("http://")
		and not url.begins_with("https://")
		and not url.begins_with("git@")
	):
		if "/" in url:
			url = "https://github.com/" + url
			PlugLogger.debug("expanded to GitHub URL: %s" % url)
		else:
			return

	_start_search(url)


func _show_repo_exists_dialog(repo_name: String, url: String):
	var dialog = ConfirmationDialog.new()
	dialog.title = tr("TOAST_INFO")
	dialog.dialog_text = tr("TOAST_REPO_EXISTS") % repo_name
	dialog.ok_button_text = tr("BTN_VIEW_INSTALLED")
	dialog.get_cancel_button().text = tr("BTN_SEARCH_ANYWAY")
	dialog.confirmed.connect(
		func():
			_jump_to_installed_tab(repo_name)
			dialog.queue_free()
	)
	dialog.canceled.connect(
		func():
			_start_search(url)
			dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered()


func _jump_to_installed_tab(repo_name: String):
	tab_container.current_tab = 0
	if _installed_filter_input:
		_installed_filter_input.text = repo_name
	_refresh_installed_tree(repo_name)


func _start_search(url: String):
	# Pre-check: when the user requests a Release search but the platform's
	# API token is missing, abort and pop a confirm dialog with a "Configure
	# Now" path that re-runs the search after the user saves a token. This
	# prevents the silent rate-limit / 401 failures users would otherwise see.
	var pre_with_release = _release_checkbox.button_pressed and _is_url_like(url)
	if pre_with_release and not _ensure_token_for_release(url):
		return
	_start_search_unchecked(url)


## Internal: actually kicks off the search. Always go through `_start_search`
## (or `_retry_search_after_token_set`) which runs the token pre-check first.
func _start_search_unchecked(url: String) -> void:
	_search_url = url
	_search_cancelled = false
	_search_head_commit = ""
	_tree_mode = TreeMode.SEARCHING
	search_tree.clear()
	search_tree.create_item()
	install_selected_btn.disabled = true
	_search_btn.text = tr("BTN_CANCEL")
	_search_overlay.visible = true
	PlugLogger.info(_tr("LOG_SEARCH_START") % url)
	var with_release = _release_checkbox.button_pressed and _is_url_like(url)
	_search_coordinator.reset(with_release)
	_release_search_pending = with_release
	_search_done = false
	_search_active = true
	_search_task_id = WorkerThreadPool.add_task(_run_search_task)
	if with_release:
		PlugLogger.debug("_start_search: with_release=true, calling _start_release_search")
		_start_release_search(url)
	else:
		PlugLogger.debug("_start_search: with_release=false, no release search")


func _run_search_task():
	PlugLogger.debug("search thread started, url=%s" % _search_url)
	GitManager.reset_cancel()
	var url = _search_url
	var repo_name = GitManager.repo_name_from_url(url)
	if repo_name.strip_edges().is_empty():
		_search_result = {"error": "Invalid URL"}
		_search_done = true
		return
	var cache_dir = GitManager.get_plugged_dir().path_join(repo_name)
	var has_local = DirAccess.dir_exists_absolute(cache_dir.path_join(".git"))

	# 1) Local cache
	if has_local:
		PlugLogger.debug("local repo cache hit: %s" % cache_dir)
		var local_refs = GitManager.get_local_refs(cache_dir)
		_search_branches = local_refs.get("branches", PackedStringArray())
		_search_tags = local_refs.get("tags", PackedStringArray())
		_search_default_branch = local_refs.get("default_branch", "main")
		_search_ref_commits = local_refs.get("ref_commits", {})
		var head_commit = GitManager.rev_parse_head(cache_dir)
		_search_head_commit = _short_commit(head_commit)
		_search_result = GitManager.scan_addons_in_dir(cache_dir)
		PlugLogger.info(_tr("LOG_SOURCE_SCAN_DONE"))
		_search_done = true
		return

	# 2) addon_index.json lookup
	var index_match = _find_index_entry(url)
	if not index_match.is_empty():
		PlugLogger.debug("addon_index hit for: %s" % url)
		var addons_arr: Array = index_match.get("addons", [])
		var found: Array = []
		for a in addons_arr:
			if not a is Dictionary:
				continue
			(
				found
				. append(
					{
						"name": a.get("name", ""),
						"description": a.get("description", ""),
						"addon_dir": a.get("addon_dir", ""),
						"author": a.get("author", ""),
						"type": a.get("type", "plugin"),
						"version": "",
					}
				)
			)
		var branch: String = ""
		if not addons_arr.is_empty() and addons_arr[0] is Dictionary:
			branch = addons_arr[0].get("branch", "main")
		if branch.is_empty():
			branch = "main"
		_search_branches = PackedStringArray([branch])
		_search_tags = PackedStringArray()
		_search_default_branch = branch
		_search_ref_commits = {}
		_search_head_commit = ""
		_search_result = {"addons": found, "warnings": []}
		PlugLogger.info(_tr("LOG_SOURCE_SCAN_DONE"))
		_search_done = true
		return

	# 3) Remote clone
	var remote_info = GitManager.ls_remote(url)
	if remote_info.get("cancelled", false) or remote_info.has("error"):
		if remote_info.has("error"):
			_search_result = {"error": remote_info["error"]}
		else:
			PlugLogger.info(_tr("LOG_SEARCH_CANCELLED"))
		_search_done = true
		return
	_search_branches = remote_info.get("branches", PackedStringArray())
	_search_tags = remote_info.get("tags", PackedStringArray())
	_search_default_branch = remote_info.get("default_branch", "main")
	_search_ref_commits = remote_info.get("ref_commits", {})

	if _search_cancelled:
		_search_done = true
		return

	if DirAccess.dir_exists_absolute(cache_dir):
		GitManager.delete_directory(cache_dir)
	PlugLogger.debug("shallow_clone -> %s" % cache_dir)
	var clone_exit = GitManager.shallow_clone(url, cache_dir)
	if clone_exit != OK:
		if clone_exit != GitManager.ERR_CANCELLED:
			var detail = GitManager.last_error
			if detail.is_empty():
				detail = tr("ERR_REMOTE_READ").replace("{SEP}", ",")
			_search_result = {"error": detail}
		_search_done = true
		return

	var head_commit = GitManager.rev_parse_head(cache_dir)
	_search_head_commit = _short_commit(head_commit)
	_search_result = GitManager.scan_addons_in_dir(cache_dir)
	PlugLogger.info(_tr("LOG_SOURCE_SCAN_DONE"))
	_search_done = true


func _find_index_entry(search_url: String) -> Dictionary:
	var search_repo = GitManager.repo_name_from_url(search_url)
	for entry in _addon_index:
		if not entry is Dictionary:
			continue
		var entry_repo = GitManager.repo_name_from_url(entry.get("url", ""))
		if entry_repo == search_repo:
			return entry
	return {}


func _on_search_completed():
	PlugLogger.debug(
		(
			"_on_search_completed: cancelled=%s has_error=%s release_pending=%s"
			% [_search_cancelled, _search_result.has("error"), _release_search_pending]
		)
	)
	if _search_cancelled:
		_search_btn.disabled = false
		_search_btn.text = tr("BTN_SEARCH")
		_search_overlay.visible = false
		_search_cancelled = false
		_tree_mode = TreeMode.AVAILABLE
		_refresh_unified_tree(search_input.text)
		return

	if _search_result.has("error"):
		if _release_search_pending:
			PlugLogger.debug("_on_search_completed: source error but release pending, waiting")
			_search_coordinator.on_source_completed(_search_result)
		else:
			_search_btn.disabled = false
			_search_btn.text = tr("BTN_SEARCH")
			_search_overlay.visible = false
			_tree_mode = TreeMode.AVAILABLE
			_refresh_unified_tree(search_input.text)
			_show_toast(_search_result["error"], true)
		return

	var source_count = _search_result.get("addons", []).size()
	PlugLogger.debug(
		"_on_search_completed: source found %d addons, forwarding to coordinator" % source_count
	)
	if _release_search_pending:
		PlugLogger.info(_tr("LOG_RELEASE_SEARCH_START"))
	_search_coordinator.on_source_completed(_search_result)


func _on_coordinator_search_completed(source_result: Dictionary, release_result: Array):
	PlugLogger.debug(
		(
			"coordinator completed: source_addons=%d release_addons=%d"
			% [source_result.get("addons", []).size(), release_result.size()]
		)
	)
	var found_addons: Array = source_result.get("addons", []).duplicate()
	for r in release_result:
		found_addons.append(r)
	_finalize_search_display(found_addons)


func _start_release_search(url: String):
	PlugLogger.debug("_start_release_search: %s" % url)
	var index_entry = _find_index_entry(url)
	var skip = not index_entry.is_empty() and index_entry.get("with_release", true) == false
	if skip:
		PlugLogger.debug("_start_release_search: skipped by index entry")
		_search_coordinator.on_release_completed([])
		return
	var pattern: String = (
		index_entry.get("release_asset_pattern", "") if not index_entry.is_empty() else ""
	)
	PlugLogger.debug("_start_release_search: calling fetch_releases, pattern='%s'" % pattern)
	_disconnect_release_signals()
	release_manager.releases_fetched.connect(
		func(releases: Array):
			PlugLogger.debug("_start_release_search: got %d releases" % releases.size())
			var release_addons = _build_release_addons(releases, pattern, url)
			PlugLogger.info(_tr("LOG_RELEASE_SEARCH_DONE") % releases.size())
			_search_coordinator.on_release_completed(release_addons),
		CONNECT_ONE_SHOT
	)
	release_manager.fetch_releases(url)


func _disconnect_release_signals():
	for conn in release_manager.releases_fetched.get_connections():
		release_manager.releases_fetched.disconnect(conn.callable)


func _build_release_addons(releases: Array, pattern: String, url: String) -> Array:
	var source_addons: Array = _search_result.get("addons", [])
	var release_addons: Array = []
	var all_release_tags: PackedStringArray = []
	var tag_asset_map: Dictionary = {}
	var first_found := true

	PlugLogger.debug(
		"_build_release_addons: %d releases, pattern='%s', source_addons=%d"
		% [releases.size(), pattern, source_addons.size()]
	)

	for release_data in releases:
		var tag: String = release_data.get("tag_name", "")
		var assets: Array = release_data.get("assets", [])
		PlugLogger.debug("_build_release_addons: tag=%s assets_count=%d" % [tag, assets.size()])
		var matched = AssetMatcher.match_assets(assets, pattern, url)
		if matched.is_empty():
			PlugLogger.debug("_build_release_addons: tag=%s — no matching assets" % tag)
			continue
		var matched_entries: Array = []
		for m in matched:
			var m_filename: String = m.get("name", "")
			matched_entries.append(
				{
					"url": m.get("browser_download_url", ""),
					"name": m_filename.get_basename(),
					"filename": m_filename,
					"size": int(m.get("size", 0)),
				}
			)
		var default_asset: Dictionary = matched_entries[0]
		var download_url: String = default_asset.get("url", "")
		var asset_filename: String = default_asset.get("filename", "")
		var asset_basename: String = default_asset.get("name", "")
		PlugLogger.debug(
			(
				"_build_release_addons: tag=%s matched_count=%d default=%s url=%s"
				% [tag, matched_entries.size(), asset_filename, download_url]
			)
		)
		all_release_tags.append(tag)
		tag_asset_map[tag] = matched_entries
		if not first_found:
			continue
		first_found = false
		if not source_addons.is_empty():
			for sa in source_addons:
				var r = sa.duplicate()
				r["_from_release"] = true
				r["_release_tag"] = tag
				r["_release_asset_url"] = download_url
				r["_release_asset_filename"] = asset_filename
				PlugLogger.debug(
					"_build_release_addons: release addon from source: name=%s dir=%s tag=%s"
					% [r.get("name", ""), r.get("addon_dir", ""), tag]
				)
				release_addons.append(r)
		else:
			PlugLogger.debug("_build_release_addons: no source addons, creating stub entry")
			(
				release_addons
				. append(
					{
						"_from_release": true,
						"_release_tag": tag,
						"_release_asset_url": download_url,
						"_release_asset_filename": asset_filename,
						"_release_is_stub": true,
						"name": asset_basename,
						"addon_dir": "",
						"type": "",
						"description": "Release: " + tag,
					}
				)
			)

	if not all_release_tags.is_empty():
		var repo_name = GitManager.repo_name_from_url(url)
		var cached = _remote_ref_cache.get(repo_name, {})
		cached["release_tags"] = all_release_tags
		cached["release_tag_assets"] = tag_asset_map
		_remote_ref_cache[repo_name] = cached
		PlugLogger.debug(
			(
				"_build_release_addons: repo=%s %d release tags cached, first=%s"
				% [
					repo_name,
					all_release_tags.size(),
					all_release_tags[0] if all_release_tags.size() > 0 else ""
				]
			)
		)
	else:
		PlugLogger.debug("_build_release_addons: no release tags found for %s" % url)

	return release_addons


func _finalize_search_display(found_addons: Array):
	PlugLogger.info(_tr("LOG_SEARCH_DONE"))
	_search_btn.disabled = false
	_search_btn.text = tr("BTN_SEARCH")
	_search_overlay.visible = false
	_release_search_pending = false

	_tree_mode = TreeMode.SEARCHED

	var sr_name = GitManager.repo_name_from_url(_search_url)
	if not _search_branches.is_empty() or not _search_tags.is_empty():
		var cached = _remote_ref_cache.get(sr_name, {})
		cached["branches"] = _search_branches
		cached["tags"] = _search_tags
		cached["ref_commits"] = _search_ref_commits
		_remote_ref_cache[sr_name] = cached
		PlugLogger.debug(
			"_finalize_search_display: cache merged for %s, keys=%s" % [sr_name, cached.keys()]
		)

	var warnings: Array = _search_result.get("warnings", [])

	if found_addons.is_empty():
		var msg = tr("TOAST_NO_ADDON_FOUND")
		if not warnings.is_empty():
			msg += "\n" + "\n".join(warnings)
		install_selected_btn.disabled = false
		install_selected_btn.text = tr("BTN_MANUAL_INSTALL")
		# When the user searched a URL but didn't tick "Search Releases", the
		# repo might publish only via GitHub Releases (no source plugin.cfg /
		# .gdextension in tree). Offer a one-click retry instead of forcing
		# them to tick the box manually.
		if (
			_release_checkbox != null
			and not _release_checkbox.button_pressed
			and _is_url_like(_search_url)
		):
			_prompt_retry_with_release(msg)
		else:
			_show_toast(msg, true)
		return

	var addon_dirs: Array = []
	for p in found_addons:
		addon_dirs.append(p.get("addon_dir", ""))
	var existing_addons = _get_existing_addons()
	var conflicts = addon_data.check_dir_conflicts(addon_dirs, existing_addons)

	var default_commit_raw = _search_ref_commits.get(_search_default_branch, _search_head_commit)
	var default_commit = _short_commit(default_commit_raw)
	var search_repo_name = GitManager.repo_name_from_url(_search_url)
	var already_installed = addon_data.has_repo(search_repo_name)

	search_tree.clear()
	search_tree.create_item()
	for p in found_addons:
		var item = search_tree.create_item(search_tree.get_root())
		var pdir = p.get("addon_dir", "")
		var has_conflict = pdir in conflicts

		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_checked(0, not has_conflict and not already_installed)
		item.set_editable(0, not already_installed)

		if already_installed:
			item.set_text(1, tr("STATUS_INSTALLED"))
			item.set_custom_color(1, COLOR_UP_TO_DATE)
		else:
			item.set_text(1, tr("STATUS_NOT_INSTALLED"))
			item.set_custom_color(1, COLOR_UNKNOWN)
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)

		var name_text = p.get("name", "Unknown")
		item.set_text(2, name_text)
		if has_conflict and not already_installed:
			item.set_custom_color(2, COLOR_CONFLICT)
			item.set_tooltip_text(2, _search_url + "\n" + tr("CONFLICT_DIR_EXISTS") % pdir)
		else:
			item.set_tooltip_text(2, _search_url)

		var ver = p.get("version", "")
		item.set_text(3, _format_version(ver))

		var is_from_release = p.get("_from_release", false)
		var type_raw = p.get("type", "")
		var type_text: String
		if type_raw.is_empty():
			type_text = "--"
		elif type_raw in ["editor_plugin", "plugin"]:
			type_text = "Plugin"
		else:
			type_text = "Extension"
		if is_from_release:
			type_text += " [R]"
		item.set_text(4, type_text)

		var release_asset_filename: String = ""
		if is_from_release:
			var rtag = p.get("_release_tag", "")
			release_asset_filename = p.get("_release_asset_filename", "")
			item.set_text(5, rtag)
			item.set_custom_color(5, COLOR_UPDATED)
			item.set_text_alignment(5, HORIZONTAL_ALIGNMENT_CENTER)
			item.set_tooltip_text(5, tr("BRANCH_CLICK_HINT"))
			item.set_text(6, "--")
			item.set_text_alignment(6, HORIZONTAL_ALIGNMENT_CENTER)
			item.set_meta("from_release", true)
			item.set_meta("selected_branch", "")
			item.set_meta("selected_tag", rtag)
			item.set_meta("selected_commit", "")
			item.set_meta("release_asset_filename", release_asset_filename)
			var release_cache = _remote_ref_cache.get(search_repo_name, {})
			var meta_tags = release_cache.get("release_tags", PackedStringArray())
			var meta_assets = release_cache.get("release_tag_assets", {})
			if not meta_tags.is_empty():
				item.set_meta("release_tags", meta_tags)
			if not meta_assets.is_empty():
				item.set_meta("release_tag_assets", meta_assets)
		else:
			item.set_text(5, _search_default_branch)
			item.set_custom_color(5, COLOR_UPDATED)
			item.set_text_alignment(5, HORIZONTAL_ALIGNMENT_CENTER)
			item.set_tooltip_text(5, tr("BRANCH_CLICK_HINT"))
			item.set_text(6, default_commit)
			item.set_custom_color(6, _commit_color(true))
			item.set_text_alignment(6, HORIZONTAL_ALIGNMENT_CENTER)
			item.set_meta("selected_branch", _search_default_branch)
			item.set_meta("selected_tag", "")
			item.set_meta("selected_commit", "")

		var is_stub: bool = p.get("_release_is_stub", false)
		if is_from_release:
			if is_stub:
				item.set_text(7, release_asset_filename)
				var stub_tip = _tr("RELEASE_ASSET_CLICK_HINT")
				if not release_asset_filename.is_empty():
					stub_tip = release_asset_filename + "\n" + stub_tip
				item.set_tooltip_text(7, stub_tip)
			else:
				item.set_text(7, pdir)
				var src_tip = _tr("RELEASE_ASSET_CLICK_HINT")
				if not release_asset_filename.is_empty():
					src_tip = release_asset_filename + "\n" + src_tip
				elif not pdir.is_empty():
					src_tip = pdir
				item.set_tooltip_text(7, src_tip)
		else:
			item.set_text(7, pdir)
		item.set_text(8, p.get("author", ""))

		item.set_meta("addon_info", p)
		item.set_meta("has_conflict", has_conflict)

	_update_install_selected_count()


func _get_existing_addons() -> PackedStringArray:
	var result: PackedStringArray = []
	var addons_path = ProjectSettings.globalize_path("res://addons")
	if not DirAccess.dir_exists_absolute(addons_path):
		return result
	var dir = DirAccess.open(addons_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname = dir.get_next()
	while not fname.is_empty():
		if dir.current_is_dir():
			result.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return result


func _on_search_tree_item_edited():
	_update_install_selected_count()


func _update_install_selected_count():
	if _is_executing or not _installing_repos.is_empty():
		install_selected_btn.disabled = false
		install_selected_btn.text = tr("BTN_CANCEL_INSTALL")
		return
	var count = 0
	var root = search_tree.get_root()
	if root:
		var child = root.get_first_child()
		while child:
			if child.is_checked(0):
				count += 1
			child = child.get_next()
	install_selected_btn.disabled = count == 0
	var sel_tpl = tr("BTN_INSTALL_SELECTED")
	install_selected_btn.text = sel_tpl % count if "%d" in sel_tpl else sel_tpl


# ===========================================================================
# Install flow
# ===========================================================================


func _on_InstallSelectedBtn_pressed():
	if _is_executing and not _installing_repos.is_empty():
		_cancel_install()
		return

	if _tree_mode == TreeMode.AVAILABLE:
		_install_from_available()
		return

	var selected: Array[Dictionary] = []
	var root = search_tree.get_root()
	if root:
		var child = root.get_first_child()
		while child:
			if child.is_checked(0):
				var info = child.get_meta("addon_info")
				if info:
					var entry = info.duplicate()
					entry["_branch"] = child.get_meta("selected_branch")
					entry["_tag"] = child.get_meta("selected_tag")
					entry["_commit"] = (
						child.get_meta("selected_commit")
						if child.has_meta("selected_commit")
						else ""
					)
					# Defensive: release rows must carry the *currently displayed*
					# tag into _release_tag, in case the asset/tag selection chain
					# left info["_release_tag"] stale (legacy data path).
					if entry.get("_from_release", false):
						var sel_tag: String = entry.get("_tag", "")
						if not sel_tag.is_empty():
							entry["_release_tag"] = sel_tag
					selected.append(entry)
			child = child.get_next()

	if selected.is_empty():
		var found: Array = _search_result.get("addons", [])
		if found.is_empty():
			install_selected_btn.disabled = false
			install_selected_btn.text = tr("BTN_CANCEL_INSTALL")
			_install_repo_manual(_search_url)
		return

	var selected_dirs: Array = []
	for s in selected:
		selected_dirs.append(s.get("addon_dir", ""))
	var fresh_conflicts = addon_data.check_dir_conflicts(selected_dirs, _get_existing_addons())

	var conflicts_in_selected: Array[Dictionary] = []
	for s in selected:
		if s.get("addon_dir", "") in fresh_conflicts:
			conflicts_in_selected.append(s)
	if not conflicts_in_selected.is_empty():
		_show_conflict_dialog(conflicts_in_selected, selected)
		return
	_execute_install(selected)


func _install_from_available():
	var by_url: Dictionary = {}
	var root = search_tree.get_root()
	if root:
		var child = root.get_first_child()
		while child:
			if child.is_checked(0) and child.has_meta("is_available"):
				var url: String = child.get_meta("repo", "")
				var info: Dictionary = child.get_meta("addon_info", {})
				if not url.is_empty() and not info.is_empty():
					var entry = info.duplicate()
					entry["_branch"] = child.get_meta("selected_branch", "main")
					entry["_tag"] = child.get_meta("selected_tag", "")
					entry["_commit"] = child.get_meta("selected_commit", "")
					if entry.get("_from_release", false):
						var sel_tag: String = entry.get("_tag", "")
						if not sel_tag.is_empty():
							entry["_release_tag"] = sel_tag
					if not by_url.has(url):
						by_url[url] = []
					by_url[url].append(entry)
			child = child.get_next()

	if by_url.is_empty():
		return

	var selected_dirs: Array = []
	for url in by_url:
		for s in by_url[url]:
			selected_dirs.append(s.get("addon_dir", ""))
	var fresh_conflicts = addon_data.check_dir_conflicts(selected_dirs, _get_existing_addons())
	var has_conflict := false
	for d in selected_dirs:
		if d in fresh_conflicts:
			has_conflict = true
			break
	if has_conflict:
		var all_selected: Array[Dictionary] = []
		for url in by_url:
			for s in by_url[url]:
				all_selected.append(s)
		var conflicts_in_selected: Array[Dictionary] = []
		for s in all_selected:
			if s.get("addon_dir", "") in fresh_conflicts:
				conflicts_in_selected.append(s)
		_show_conflict_dialog(conflicts_in_selected, all_selected)
		return

	install_selected_btn.disabled = false
	install_selected_btn.text = tr("BTN_CANCEL_INSTALL")
	_is_executing = true
	disable_ui(true)
	_install_done = false
	_install_active = true
	_install_task_id = WorkerThreadPool.add_task(_run_available_install.bind(by_url))


func _run_available_install(by_url: Dictionary):
	var project_root = ProjectSettings.globalize_path("res://")
	for url in by_url:
		var repo_name = GitManager.repo_name_from_url(url)
		var addons_list: Array = by_url[url]
		var default_branch: String = addons_list[0].get("_branch", "main")

		for s in addons_list:
			var tag_val: String = s.get("_tag", "")
			var commit_val: String = s.get("_commit", "")
			var branch_val: String = s.get("_branch", s.get("branch", "main"))
			if not tag_val.is_empty():
				s["tag"] = tag_val
				s.erase("branch")
			elif not commit_val.is_empty():
				s["commit"] = commit_val
			elif not branch_val.is_empty():
				s["branch"] = branch_val

		addon_data.add_repo_from_search(repo_name, url, addons_list, default_branch)
		for s in addons_list:
			addon_data.set_addon_installed(repo_name, s.get("addon_dir", ""), true)
			var tag_val: String = s.get("_tag", "")
			var commit_val: String = s.get("_commit", "")
			var branch_val: String = s.get("_branch", "")
			if not commit_val.is_empty():
				addon_data.set_addon_commit_lock(repo_name, s.get("addon_dir", ""), commit_val)
			elif not tag_val.is_empty():
				addon_data.set_addon_tag(repo_name, s.get("addon_dir", ""), tag_val)
			elif not branch_val.is_empty():
				addon_data.set_addon_branch(repo_name, s.get("addon_dir", ""), branch_val)

		var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
		if not _ensure_repo_cloned(repo_name, url):
			continue

		var groups = AddonData.group_addons_by_version(addons_list)
		for ref in groups:
			if ref == "__release__":
				continue
			if ref != "__default__":
				GitManager.fetch_ref(plug_dir, ref)
				GitManager.checkout(plug_dir, ref)
			var commit_hash = GitManager.rev_parse_head(plug_dir)
			for p in groups[ref]:
				var pdir: String = p.get("addon_dir", "")
				if pdir.is_empty():
					continue
				GitManager.copy_addon_dir(plug_dir, pdir, project_root)
				addon_data.set_addon_commit(repo_name, pdir, commit_hash)

		var scanned = GitManager.scan_local_addons(plug_dir)
		for sp in scanned:
			sp["type"] = AddonData._normalize_type(sp.get("type", ""))
		addon_data.merge_scan_results(repo_name, scanned)

	addon_data.save_data()
	_install_done = true


func _execute_install(selected: Array[Dictionary]):
	var url = _search_url
	var repo_name = GitManager.repo_name_from_url(url)
	var all_found: Array = _search_result.get("addons", []).duplicate()
	for s in selected:
		if s.get("_from_release", false):
			var s_dir: String = s.get("addon_dir", "")
			var has_source_entry := false
			for f in all_found:
				if f.get("addon_dir", "") == s_dir:
					has_source_entry = true
					break
			if not has_source_entry:
				all_found.append(s)
				PlugLogger.debug(
					"_execute_install: added release addon "
					+ "(no source entry for dir='%s')" % s_dir
				)

	# Snapshot every repo this batch is about to touch, BEFORE we mutate
	# addon_data. `_abort_release_install` uses these to undo the early
	# `set_addon_installed(true)` writes when an install fails.
	var touched_repos: Dictionary = {repo_name: true}
	for s in selected:
		var pdir_pre: String = s.get("addon_dir", "")
		if pdir_pre.is_empty():
			continue
		var old_owner_pre: String = addon_data.find_owner_repo(pdir_pre)
		if not old_owner_pre.is_empty() and old_owner_pre != repo_name:
			touched_repos[old_owner_pre] = true
	_install_pre_snapshots.clear()
	for rn in touched_repos.keys():
		if addon_data.has_repo(rn):
			_install_pre_snapshots[rn] = addon_data.get_repo(rn).duplicate(true)
		else:
			_install_pre_snapshots[rn] = null

	addon_data.add_repo_from_search(repo_name, url, all_found, _search_default_branch)

	var repos_to_cleanup: Dictionary = {}
	for s in selected:
		var pdir = s.get("addon_dir", "")
		var old_owner = addon_data.find_owner_repo(pdir)
		if not old_owner.is_empty() and old_owner != repo_name:
			addon_data.set_addon_installed(old_owner, pdir, false)
			repos_to_cleanup[old_owner] = true
		addon_data.set_addon_installed(repo_name, pdir, true)
		if s.get("_from_release", false):
			addon_data.set_addon_installed_from(repo_name, pdir, "release")
			addon_data.set_addon_installed_tag(repo_name, pdir, s.get("_release_tag", ""))
			addon_data.set_addon_installed_asset(
				repo_name, pdir, s.get("_release_asset_filename", "")
			)
		else:
			var commit_val: String = s.get("_commit", "")
			var tag_val: String = s.get("_tag", "")
			var branch_val: String = s.get("_branch", _search_default_branch)
			if not commit_val.is_empty():
				addon_data.set_addon_commit_lock(repo_name, pdir, commit_val)
			elif not tag_val.is_empty():
				addon_data.set_addon_tag(repo_name, pdir, tag_val)
			elif not branch_val.is_empty():
				addon_data.set_addon_branch(repo_name, pdir, branch_val)

	for old_repo in repos_to_cleanup:
		if addon_data.get_installed_addons(old_repo).is_empty():
			addon_data.remove_repo(old_repo)

	addon_data.save_data()
	_installing_repos[repo_name] = true
	_install_failures.clear()
	_refresh_installed_tree()
	_set_checked_items_status(tr("STATUS_INSTALLING"), COLOR_CHECKING)
	install_selected_btn.disabled = false
	install_selected_btn.text = tr("BTN_CANCEL_INSTALL")
	_is_executing = true
	disable_ui(true)
	PlugLogger.info(_tr("LOG_INSTALL_START") % repo_name)
	_install_done = false

	var has_release := false
	var has_source := false
	var release_addon: Dictionary = {}
	for s in selected:
		if s.get("_from_release", false):
			has_release = true
			if release_addon.is_empty():
				release_addon = s
		else:
			has_source = true

	PlugLogger.debug(
		"_execute_install: has_release=%s has_source=%s selected_count=%d"
		% [str(has_release), str(has_source), selected.size()]
	)
	if has_release:
		PlugLogger.debug(
			"_execute_install: release_addon keys=%s tag=%s asset_url=%s addon_dir=%s"
			% [
				str(release_addon.keys()),
				release_addon.get("_release_tag", ""),
				release_addon.get("_release_asset_url", ""),
				release_addon.get("addon_dir", ""),
			]
		)
		_install_active = false
		_start_release_install(repo_name, url, release_addon, has_source)
	else:
		_install_active = true
		_install_task_id = WorkerThreadPool.add_task(_run_install.bind(repo_name))


func _start_release_install(
	repo_name: String, url: String, release_addon: Dictionary, also_run_source: bool
):
	var tag: String = release_addon.get("_release_tag", "")
	var asset_url: String = release_addon.get("_release_asset_url", "")
	var addon_dir: String = release_addon.get("addon_dir", "")

	PlugLogger.info("Installing from release: %s tag=%s addon_dir=%s" % [repo_name, tag, addon_dir])
	PlugLogger.debug(
		"_start_release_install: asset_url=%s also_run_source=%s" % [asset_url, str(also_run_source)]
	)

	if tag.is_empty():
		PlugLogger.info("Release install aborted: tag is empty for %s" % repo_name)
		_install_done = true
		return

	if asset_url.is_empty():
		PlugLogger.info("Release install aborted: asset_url is empty for %s %s" % [repo_name, tag])
		_install_done = true
		return

	if release_manager.is_tag_cached(repo_name, tag):
		PlugLogger.info("Release cache hit for %s %s, applying directly" % [repo_name, tag])
		_run_release_install_task(repo_name, tag, addon_dir, also_run_source)
		return

	PlugLogger.info("Downloading release %s %s..." % [repo_name, tag])
	_set_checked_items_status(tr("STATUS_DOWNLOADING"), COLOR_CHECKING)
	release_manager.download_completed.connect(
		func(ok: bool, _cache_dir: String):
			if ok:
				PlugLogger.debug("_start_release_install: download OK, applying install")
				_set_checked_items_status(tr("STATUS_INSTALLING"), COLOR_CHECKING)
				_run_release_install_task(repo_name, tag, addon_dir, also_run_source)
			else:
				var err_key = release_manager.get_last_error()
				_abort_release_install(repo_name, tag, err_key),
		CONNECT_ONE_SHOT
	)
	release_manager.download_asset(url, repo_name, tag, asset_url, addon_dir)


func _cancel_install() -> void:
	_install_cancelled = true
	GitManager.request_cancel()
	if release_manager:
		release_manager.cancel()
	install_selected_btn.disabled = true
	install_selected_btn.text = tr("BTN_CANCELLING")
	PlugLogger.info("Install cancel requested")
	for repo_name in _installing_repos.keys():
		_rollback_repo_to_snapshot(repo_name)
	_install_done = true


## Rolls back an aborted release install using the pre-batch snapshot, registers
## the failure for the batch summary, and signals the install loop. Actual
## toast/log/button copy decisions are made by `_on_install_completed`.
##
## Key invariant: `_execute_install` ALWAYS marks the addon as installed=true
## before the actual download/extract starts (so the installed tree shows the
## row immediately with a "Installing" status). On failure we MUST undo that
## write — otherwise the failed addon stays as a ghost "Installed" row.
func _abort_release_install(repo_name: String, tag: String, error_key: String) -> void:
	var key: String = error_key if not error_key.is_empty() else "ERR_RELEASE_DOWNLOAD_FAILED"
	PlugLogger.info(
		"Release install aborted: repo=%s tag=%s reason=%s" % [repo_name, tag, key]
	)
	_rollback_repo_to_snapshot(repo_name)
	_install_failures[repo_name] = key
	_installing_repos.erase(repo_name)
	_install_done = true


## Restore a single repo to its pre-batch state using `_install_pre_snapshots`.
##  - snapshot is `null` (or missing) → repo did not exist pre-batch → remove it
##  - snapshot is a dict             → repo existed pre-batch → replace whole repo
func _rollback_repo_to_snapshot(repo_name: String) -> void:
	if not _install_pre_snapshots.has(repo_name):
		# No snapshot recorded — fall back to a defensive remove only if the
		# repo currently has zero installed addons (protects pre-existing user
		# data from being clobbered by a stray rollback).
		var repo_installed = addon_data.get_installed_addons(repo_name)
		if repo_installed.is_empty() and addon_data.has_repo(repo_name):
			PlugLogger.debug(
				"_rollback_repo_to_snapshot: no snapshot, removing empty repo %s" % repo_name
			)
			addon_data.remove_repo(repo_name)
			addon_data.save_data()
		return
	var snap = _install_pre_snapshots[repo_name]
	if snap == null:
		PlugLogger.debug(
			"_rollback_repo_to_snapshot: snapshot=null, removing %s (was new in batch)" % repo_name
		)
		addon_data.remove_repo(repo_name)
	else:
		PlugLogger.debug(
			"_rollback_repo_to_snapshot: restoring %s to pre-batch state" % repo_name
		)
		addon_data.set_repo(repo_name, snap)
	addon_data.save_data()


func _run_release_install_task(
	repo_name: String, tag: String, addon_dir: String, also_run_source: bool
):
	_install_active = true
	_install_task_id = WorkerThreadPool.add_task(
		func():
			_apply_release_install(repo_name, tag, addon_dir)
			if also_run_source:
				_run_install(repo_name)
			else:
				_install_done = true
	)


func _apply_release_install(repo_name: String, tag: String, addon_dir: String):
	var project_root = ProjectSettings.globalize_path("res://")
	var cache_dir = release_manager.get_cache_dir(repo_name, tag)
	PlugLogger.debug(
		"_apply_release_install: repo=%s tag=%s addon_dir=%s cache_dir=%s project_root=%s"
		% [repo_name, tag, addon_dir, cache_dir, project_root]
	)

	if not DirAccess.dir_exists_absolute(cache_dir):
		PlugLogger.info("Release install failed: cache dir does not exist: %s" % cache_dir)
		return

	if addon_dir.is_empty():
		PlugLogger.debug("_apply_release_install: addon_dir empty, using auto-detect")
		_copy_release_auto_detect(cache_dir, project_root, repo_name, tag)
	else:
		var src = cache_dir.path_join("addons").path_join(addon_dir.get_file())
		PlugLogger.debug(
			"_apply_release_install: trying src=%s exists=%s"
			% [src, str(DirAccess.dir_exists_absolute(src))]
		)
		if not DirAccess.dir_exists_absolute(src):
			src = cache_dir.path_join(addon_dir)
			PlugLogger.debug(
				"_apply_release_install: fallback src=%s exists=%s"
				% [src, str(DirAccess.dir_exists_absolute(src))]
			)
		if not DirAccess.dir_exists_absolute(src):
			src = cache_dir
			PlugLogger.debug("_apply_release_install: last resort src=cache_dir=%s" % src)
		var dst = project_root.path_join(addon_dir)
		PlugLogger.info("Copying release: %s → %s" % [src, dst])
		DirAccess.make_dir_recursive_absolute(dst)
		var copied = GitManager._copy_dir_recursive(src, dst)
		PlugLogger.debug("_apply_release_install: copied %d files" % copied)
		if copied == 0:
			PlugLogger.info(
				"Release install failed: 0 files copied, "
				+ "clearing stale cache %s" % cache_dir
			)
			release_manager.clear_tag_cache(repo_name, tag)
			return
		addon_data.set_addon_installed_tag(repo_name, addon_dir, tag)
	_backfill_release_addon_metadata(repo_name, cache_dir)
	PlugLogger.info("Release installed: %s %s" % [repo_name, tag])
	addon_data.save_data()


## After a successful release extract, reads the detected addon type (and scans
## plugin.cfg for richer metadata) and updates addon_data so the UI no longer
## shows "-- [R]" or a wrong type placeholder.
##
## `force_overwrite=true` is used by the tag-switch path: name/description/
## version/author are tag-specific and should refresh to the new tag's values
## (instead of the install-time "fill only when empty" behavior).
func _backfill_release_addon_metadata(
	repo_name: String, cache_dir: String, force_overwrite: bool = false
) -> void:
	var detected_type: String = release_manager.get_last_detected_type()
	PlugLogger.debug(
		(
			"_backfill_release_addon_metadata: repo=%s detected_type=%s force=%s"
			% [repo_name, detected_type, str(force_overwrite)]
		)
	)
	var scanned: Array = GitManager.scan_local_addons(cache_dir)
	if detected_type.is_empty() and scanned.is_empty():
		return
	var scan_by_dir: Dictionary = {}
	for a in scanned:
		var atype: String = a.get("type", "")
		var norm: String = AddonData._normalize_type(atype)
		var dir_key: String = a.get("addon_dir", "")
		scan_by_dir[dir_key] = {
			"name": a.get("name", ""),
			"description": a.get("description", ""),
			"version": a.get("version", ""),
			"author": a.get("author", ""),
			"type": norm,
		}
	for p in addon_data.get_addons(repo_name):
		if p.get("installed_from", "") != "release":
			continue
		var pdir: String = p.get("addon_dir", "")
		var md: Dictionary = {}
		if scan_by_dir.has(pdir):
			md = scan_by_dir[pdir]
		else:
			var pdir_tail: String = pdir.trim_prefix("addons/")
			if scan_by_dir.has(pdir_tail):
				md = scan_by_dir[pdir_tail]
		if md.is_empty():
			var fallback_patch: Dictionary = {}
			if p.get("type", "") == "" and not detected_type.is_empty():
				fallback_patch["type"] = detected_type
			var tag_fb: String = p.get("installed_tag", "")
			if not tag_fb.is_empty() and (force_overwrite or p.get("version", "") == ""):
				fallback_patch["version"] = tag_fb
			if not fallback_patch.is_empty():
				addon_data.update_addon_metadata(repo_name, pdir, fallback_patch)
			continue
		var patch: Dictionary = {"type": md.get("type", detected_type)}
		var current_name: String = p.get("name", "")
		var md_name: String = md.get("name", "")
		var name_should_overwrite: bool = (
			not md_name.is_empty()
			and (force_overwrite or current_name.is_empty() or current_name.ends_with(".zip"))
		)
		if name_should_overwrite:
			patch["name"] = md_name
		for k in ["description", "version", "author"]:
			if md.get(k, "") != "" and (force_overwrite or p.get(k, "") == ""):
				patch[k] = md[k]
		if not patch.has("version") or patch["version"] == "":
			var tag_fallback: String = p.get("installed_tag", "")
			if not tag_fallback.is_empty() and (force_overwrite or p.get("version", "") == ""):
				patch["version"] = tag_fallback
		addon_data.update_addon_metadata(repo_name, pdir, patch)


func _install_repo_manual(url: String):
	var repo_name = GitManager.repo_name_from_url(url)
	addon_data.add_repo_from_search(repo_name, url, [], _search_default_branch)
	addon_data.save_data()
	_installing_repos[repo_name] = true
	_refresh_installed_tree()
	_is_executing = true
	disable_ui(true)
	_install_done = false
	_install_active = true
	_install_task_id = WorkerThreadPool.add_task(_run_install.bind(repo_name))


func _run_install(repo_name: String):
	if repo_name.strip_edges().is_empty():
		_install_done = true
		return
	var repo = addon_data.get_repo(repo_name)
	var url: String = repo.get("url", "")
	var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
	var project_root = ProjectSettings.globalize_path("res://")

	if not DirAccess.dir_exists_absolute(plug_dir.path_join(".git")):
		if DirAccess.dir_exists_absolute(plug_dir):
			GitManager.delete_directory(plug_dir)
		var exit = GitManager.shallow_clone(url, plug_dir)
		if exit != OK:
			_install_done = true
			return

	var installed_plugins = addon_data.get_installed_addons(repo_name)
	var groups = AddonData.group_addons_by_version(installed_plugins)

	for ref in groups:
		if ref == "__release__":
			continue
		if ref != "__default__":
			GitManager.fetch_ref(plug_dir, ref)
			GitManager.checkout(plug_dir, ref)
		var commit_hash = GitManager.rev_parse_head(plug_dir)
		for p in groups[ref]:
			var pdir: String = p.get("addon_dir", "")
			if pdir.is_empty():
				continue
			GitManager.copy_addon_dir(plug_dir, pdir, project_root)
			addon_data.set_addon_commit(repo_name, pdir, commit_hash)

	addon_data.save_data()
	_install_done = true


func _on_install_completed():
	var was_cancelled = _install_cancelled
	_install_cancelled = false
	_installing_repos.clear()
	_is_executing = false
	disable_ui(false)
	GitManager.reset_cancel()
	_version_cache.clear()
	_remote_ref_cache.clear()
	_commit_cache.clear()
	_pending_changes.clear()
	_local_info_done = false
	_local_info_active = true
	_local_info_task_id = WorkerThreadPool.add_task(_load_local_version_info)
	_refresh_installed_tree()
	_update_search_tree_install_status()

	var failures: Dictionary = _install_failures.duplicate()
	_install_failures.clear()
	_install_pre_snapshots.clear()

	if was_cancelled:
		_restore_checked_items_status()
		install_selected_btn.text = tr("BTN_INSTALL_CANCELLED")
		PlugLogger.info(_tr("LOG_INSTALL_CANCELLED"))
		return

	_apply_install_final_row_status(failures)

	if failures.is_empty():
		install_selected_btn.text = tr("BTN_INSTALL_DONE")
		PlugLogger.info(_tr("LOG_INSTALL_DONE"))
	else:
		var success_present := _has_any_successful_checked_row(failures)
		if success_present:
			install_selected_btn.text = tr("BTN_INSTALL_PARTIAL")
			PlugLogger.info(_tr("LOG_INSTALL_PARTIAL") % failures.size())
		else:
			install_selected_btn.text = tr("BTN_INSTALL_FAILED")
			PlugLogger.info(_tr("LOG_INSTALL_FAILED") % failures.size())
		_show_install_failure_toast(failures)

	_check_csharp_compatibility()
	emit_signal("updated")


## Paints the final per-row status based on the batch failure map.
## Checked rows whose repo appears in `failures` get STATUS_FAILED + red;
## other checked rows get STATUS_INSTALLED + green (matches the success case).
func _apply_install_final_row_status(failures: Dictionary) -> void:
	var root = search_tree.get_root()
	if root == null:
		return
	var child = root.get_first_child()
	while child:
		if child.is_checked(0):
			var repo_url: String = child.get_meta("repo", "")
			var repo_name: String = (
				GitManager.repo_name_from_url(repo_url) if not repo_url.is_empty() else ""
			)
			if not repo_name.is_empty() and failures.has(repo_name):
				child.set_text(1, tr("STATUS_FAILED"))
				child.set_custom_color(1, COLOR_CONFLICT)
			else:
				child.set_text(1, tr("STATUS_INSTALLED"))
				child.set_custom_color(1, COLOR_UP_TO_DATE)
			child.set_editable(0, false)
		child = child.get_next()


## Returns true if at least one checked row's repo is NOT in the failure map.
func _has_any_successful_checked_row(failures: Dictionary) -> bool:
	var root = search_tree.get_root()
	if root == null:
		return false
	var child = root.get_first_child()
	while child:
		if child.is_checked(0):
			var repo_url: String = child.get_meta("repo", "")
			var repo_name: String = (
				GitManager.repo_name_from_url(repo_url) if not repo_url.is_empty() else ""
			)
			if repo_name.is_empty() or not failures.has(repo_name):
				return true
		child = child.get_next()
	return false


## Summarizes install failures into a single toast so users see every failed
## repo + its i18n-translated reason in one place.
func _show_install_failure_toast(failures: Dictionary) -> void:
	if failures.is_empty():
		return
	var lines: Array[String] = []
	for repo_name in failures.keys():
		var key: String = failures[repo_name]
		lines.append("• %s — %s" % [repo_name, tr(key)])
	var body: String = "\n".join(lines)
	_show_toast("%s\n%s" % [tr("TOAST_INSTALL_FAILED_HEADER"), body], true)


func _check_csharp_compatibility():
	for repo_name in addon_data.get_repos():
		for p in addon_data.get_installed_addons(repo_name):
			if p.get("language", "") == "csharp" and not OS.has_feature("dotnet"):
				_show_toast(tr("WARN_CSHARP_NO_DOTNET"))
				return


# ===========================================================================
# Conflict dialog
# ===========================================================================


func _show_conflict_dialog(conflicts: Array[Dictionary], all_selected: Array[Dictionary]):
	var dialog = ConfirmationDialog.new()
	dialog.title = tr("CONFLICT_TITLE")
	dialog.ok_button_text = tr("CONFLICT_OVERWRITE")
	dialog.get_cancel_button().text = tr("BTN_CANCEL")
	var vbox = VBoxContainer.new()
	for c in conflicts:
		var pdir = c.get("addon_dir", "")
		var owner = addon_data.find_owner_repo(pdir)
		var label = Label.new()
		if not owner.is_empty():
			label.text = tr("CONFLICT_DIR_OWNED") % [pdir, owner]
		else:
			label.text = tr("CONFLICT_DIR_EXISTS") % pdir
		label.add_theme_color_override("font_color", COLOR_CONFLICT)
		vbox.add_child(label)
	dialog.add_child(vbox)
	dialog.confirmed.connect(
		func():
			_execute_install(all_selected)
			dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


# ===========================================================================
# Update operations
# ===========================================================================


func _on_CheckVersionBtn_pressed():
	_version_cache.clear()
	_version_state.clear()
	_remote_ref_cache.clear()
	_commit_cache.clear()
	_pending_changes.clear()
	_fetch_all_version_info()


func _on_UpdateAllBtn_pressed():
	var updatable_repos: Array[String] = []
	for repo_name in addon_data.get_repos():
		if addon_data.is_repo_locked(repo_name):
			continue
		if addon_data.get_repo_install_from(repo_name) == "release":
			continue
		var plugins = addon_data.get_installed_addons(repo_name)
		for p in plugins:
			if AddonData.is_updatable(p):
				updatable_repos.append(repo_name)
				break
	if updatable_repos.is_empty():
		return
	for rn in updatable_repos:
		_version_state[rn] = VersionState.UPDATING
	_refresh_installed_tree()
	show_overlay(true, tr("OVERLAY_UPDATING_ALL"))
	_is_executing = true
	disable_ui(true)
	_update_done = false
	_update_active = true
	_update_task_id = WorkerThreadPool.add_task(_run_update_repos.bind(updatable_repos))


func _update_single_repo(repo_name: String):
	if _is_executing:
		return
	_version_state[repo_name] = VersionState.UPDATING
	call_deferred("_refresh_installed_tree", "")
	show_overlay(true, tr("OVERLAY_UPDATING_ONE") % repo_name)
	_is_executing = true
	disable_ui(true)
	_update_done = false
	_update_active = true
	_update_task_id = WorkerThreadPool.add_task(_run_update_repos.bind([repo_name]))


func _run_update_repos(repo_names: Array):
	var project_root = ProjectSettings.globalize_path("res://")
	for repo_name in repo_names:
		if addon_data.get_repo_install_from(repo_name) == "release":
			continue
		var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
		if not DirAccess.dir_exists_absolute(plug_dir.path_join(".git")):
			continue
		var installed = addon_data.get_installed_addons(repo_name)
		var groups = AddonData.group_addons_by_version(installed)
		for ref in groups:
			if ref == "__release__":
				continue
			var plugins_in_group = groups[ref]
			var first_p = plugins_in_group[0]
			if not AddonData.is_updatable(first_p):
				continue
			var branch = first_p.get("branch", "")
			if branch.is_empty():
				branch = GitManager.get_remote_default_branch(plug_dir)
			GitManager.git(plug_dir, ["fetch", "origin", branch])
			GitManager.checkout(plug_dir, branch)
			GitManager.pull_current(plug_dir)
			var commit_hash = GitManager.rev_parse_head(plug_dir)
			var scanned = GitManager.scan_local_addons(plug_dir)
			for sp in scanned:
				sp["type"] = AddonData._normalize_type(sp.get("type", ""))
			for p in plugins_in_group:
				var pdir = p.get("addon_dir", "")
				for sp in scanned:
					if sp.get("addon_dir", "") == pdir:
						addon_data.update_addon_metadata(repo_name, pdir, sp)
						break
				GitManager.copy_addon_dir(plug_dir, pdir, project_root)
				addon_data.set_addon_commit(repo_name, pdir, commit_hash)
	addon_data.save_data()
	_update_done = true


func _on_update_completed():
	_is_executing = false
	disable_ui(false)
	show_overlay(false)
	var was_cancelled = _update_cancelled
	_update_cancelled = false
	var keys_to_clear: Array = []
	for repo_name in _version_state:
		if _version_state[repo_name] == VersionState.UPDATING:
			keys_to_clear.append(repo_name)
	if was_cancelled or _is_version_switch:
		for rn in keys_to_clear:
			_version_state.erase(rn)
		_is_version_switch = false
		if was_cancelled:
			PlugLogger.info(_tr("LOG_UPDATE_CANCELLED"))
	else:
		for rn in keys_to_clear:
			_version_state[rn] = VersionState.UPDATED
	_version_cache.clear()
	_remote_ref_cache.clear()
	_commit_cache.clear()
	_pending_changes.clear()
	_local_info_done = false
	_local_info_active = true
	_local_info_task_id = WorkerThreadPool.add_task(_load_local_version_info)
	_refresh_installed_tree()
	if not was_cancelled:
		if SELF_REPO_NAME in keys_to_clear:
			_load_addon_index()
			if _tree_mode == TreeMode.AVAILABLE:
				_refresh_unified_tree()
			_show_toast(tr("TOAST_SELF_UPDATED"))
		emit_signal("updated")


func _on_CancelUpdateBtn_pressed():
	GitManager.request_cancel()
	if release_manager:
		release_manager.cancel()
	show_overlay(false)
	if _is_executing:
		_update_cancelled = true
		if not _update_active:
			_update_done = true
		PlugLogger.info(_tr("LOG_UPDATE_CANCELLED"))
	elif _version_info_task_id_active:
		var check_keys: Array = []
		for repo_name in _version_state:
			if _version_state[repo_name] == VersionState.CHECKING:
				check_keys.append(repo_name)
		for rn in check_keys:
			_version_state.erase(rn)
		disable_ui(false)
		_refresh_installed_tree()
		PlugLogger.info(_tr("LOG_CHECK_CANCELLED"))


# ===========================================================================
# Uninstall
# ===========================================================================


func _confirm_remove_repo(repo_name: String):
	if _is_executing:
		return
	var confirm = ConfirmationDialog.new()
	confirm.dialog_text = tr("UNINSTALL_CONFIRM") % repo_name
	confirm.ok_button_text = tr("BTN_CONFIRM")
	confirm.get_cancel_button().text = tr("BTN_CANCEL")
	confirm.confirmed.connect(
		func():
			_uninstall_repo(repo_name)
			confirm.queue_free()
	)
	confirm.canceled.connect(func(): confirm.queue_free())
	add_child(confirm)
	confirm.popup_centered()


func _uninstall_repo(repo_name: String):
	var installed = addon_data.get_installed_addons(repo_name).duplicate(true)
	addon_data.remove_repo(repo_name)
	addon_data.save_data()
	_version_cache.erase(repo_name)
	_version_state.erase(repo_name)
	_remote_ref_cache.erase(repo_name)
	_pending_changes.erase(repo_name)
	_erase_commit_cache_for_repo(repo_name)
	_refresh_installed_tree()
	_update_search_tree_install_status()
	WorkerThreadPool.add_task(
		func():
			for p in installed:
				var dest: String = p.get("addon_dir", "")
				GitManager.delete_installed_dir(dest)
	)


# ===========================================================================
# Version switching
# ===========================================================================


func _switch_repo_version(
	repo_name: String, version_type: String, version_value: String, extra_commit: String = ""
):
	if _is_executing:
		return
	var install_from = addon_data.get_repo_install_from(repo_name)
	if install_from == "release" and version_type == "tag":
		_switch_release_version(repo_name, version_value)
		return
	_version_state[repo_name] = VersionState.UPDATING
	call_deferred("_refresh_installed_tree", "")
	show_overlay(true, tr("OVERLAY_SWITCHING") % [repo_name, version_type, version_value])
	_is_executing = true
	disable_ui(true)
	_update_done = false
	_update_active = true
	_update_task_id = WorkerThreadPool.add_task(
		func():
			var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
			var project_root = ProjectSettings.globalize_path("res://")
			if not DirAccess.dir_exists_absolute(plug_dir.path_join(".git")):
				_update_done = true
				return
			match version_type:
				"branch":
					GitManager.fetch_ref(plug_dir, version_value)
					GitManager.checkout(plug_dir, version_value)
					GitManager.pull_current(plug_dir)
					if not extra_commit.is_empty():
						GitManager.checkout(plug_dir, extra_commit)
				"tag":
					GitManager.fetch_ref(plug_dir, "tag " + version_value)
					GitManager.checkout(plug_dir, version_value)
				"commit":
					GitManager.git(plug_dir, ["fetch", "origin"])
					GitManager.checkout(plug_dir, version_value)
			var commit_hash = GitManager.rev_parse_head(plug_dir)
			var installed_addons = addon_data.get_installed_addons(repo_name)
			for p in installed_addons:
				var pdir = p.get("addon_dir", "")
				match version_type:
					"branch":
						addon_data.set_addon_branch(repo_name, pdir, version_value, commit_hash)
					"tag":
						addon_data.set_addon_tag(repo_name, pdir, version_value, commit_hash)
					"commit":
						addon_data.set_addon_commit_lock(repo_name, pdir, version_value)
				GitManager.copy_addon_dir(plug_dir, pdir, project_root)
			var scanned = GitManager.scan_local_addons(plug_dir)
			for sp in scanned:
				sp["type"] = AddonData._normalize_type(sp.get("type", ""))
			addon_data.merge_scan_results(repo_name, scanned)
			addon_data.save_data()
			_remote_ref_cache.erase(repo_name)
			_erase_commit_cache_for_repo(repo_name)
			_update_done = true
	)


func _erase_commit_cache_for_repo(repo_name: String):
	var keys_to_erase: Array = []
	for key in _commit_cache:
		if (key as String).begins_with(repo_name + ":"):
			keys_to_erase.append(key)
	for key in keys_to_erase:
		_commit_cache.erase(key)


func _switch_release_version(repo_name: String, new_tag: String):
	PlugLogger.info("Switching release version: %s → %s" % [repo_name, new_tag])
	_version_state[repo_name] = VersionState.UPDATING
	call_deferred("_refresh_installed_tree", "")
	show_overlay(true, tr("OVERLAY_SWITCHING") % [repo_name, "tag", new_tag])
	_is_executing = true
	_is_version_switch = true
	disable_ui(true)
	_update_done = false
	if release_manager.is_tag_cached(repo_name, new_tag):
		PlugLogger.debug("_switch_release_version: cache hit, applying directly")
		_run_release_switch_task(repo_name, new_tag)
	else:
		PlugLogger.debug("_switch_release_version: cache miss, downloading")
		var url = addon_data.get_repo(repo_name).get("url", "")
		var pattern = addon_data.get_release_asset_pattern(repo_name)
		var installed = addon_data.get_installed_addons(repo_name)
		var addon_dir = installed[0].get("addon_dir", "") if not installed.is_empty() else ""
		release_manager.releases_fetched.connect(
			func(releases: Array):
				var target_release: Dictionary = {}
				for rel in releases:
					if rel.get("tag_name", "") == new_tag:
						target_release = rel
						break
				if target_release.is_empty():
					_show_toast(tr("ERR_RELEASE_NOT_FOUND"), true)
					_is_executing = false
					show_overlay(false)
					disable_ui(false)
					return
				var matched_assets = AssetMatcher.match_assets(
					target_release.get("assets", []), pattern, url
				)
				if matched_assets.is_empty():
					_show_toast(tr("ERR_RELEASE_NOT_FOUND"), true)
					_is_executing = false
					show_overlay(false)
					disable_ui(false)
					return
				var asset_url = matched_assets[0].get("browser_download_url", "")
				release_manager.download_completed.connect(
					func(ok: bool, _cache_dir: String):
						if ok:
							_run_release_switch_task(repo_name, new_tag)
						else:
							_show_toast(tr("ERR_RELEASE_DOWNLOAD"), true)
							_is_executing = false
							show_overlay(false)
							disable_ui(false),
					CONNECT_ONE_SHOT
				)
				release_manager.download_asset(url, repo_name, new_tag, asset_url, addon_dir),
			CONNECT_ONE_SHOT
		)
		release_manager.fetch_releases(url)


func _run_release_switch_task(repo_name: String, new_tag: String):
	_update_active = true
	_update_task_id = WorkerThreadPool.add_task(
		func():
			_apply_release_from_cache(repo_name, new_tag)
			_update_done = true
	)


func _apply_release_from_cache(repo_name: String, new_tag: String):
	var project_root = ProjectSettings.globalize_path("res://")
	var cache_dir = release_manager.get_cache_dir(repo_name, new_tag)
	PlugLogger.debug(
		"_apply_release_from_cache: repo=%s tag=%s cache=%s"
		% [repo_name, new_tag, cache_dir]
	)
	var installed = addon_data.get_installed_addons(repo_name)

	# --- Phase 1: Backup old addon directories ---
	var backed_up := _backup_installed_addons(repo_name, installed, project_root)

	# --- Phase 2: Copy new version from cache ---
	var success := true
	var installed_tags: Array[Dictionary] = []
	for p in installed:
		var addon_dir_rel: String = p.get("addon_dir", "")
		if addon_dir_rel.is_empty():
			PlugLogger.debug("_apply_release_from_cache: addon_dir empty, using auto-detect")
			_copy_release_auto_detect(cache_dir, project_root, repo_name, new_tag)
			continue
		var src = cache_dir.path_join("addons").path_join(addon_dir_rel.get_file())
		PlugLogger.debug(
			"_apply_release_from_cache: src=%s exists=%s"
			% [src, str(DirAccess.dir_exists_absolute(src))]
		)
		if not DirAccess.dir_exists_absolute(src):
			src = cache_dir.path_join(addon_dir_rel)
			PlugLogger.debug(
				"_apply_release_from_cache: fallback src=%s exists=%s"
				% [src, str(DirAccess.dir_exists_absolute(src))]
			)
		if not DirAccess.dir_exists_absolute(src):
			src = cache_dir
			PlugLogger.debug("_apply_release_from_cache: last resort src=cache_dir")
		var dst = project_root.path_join(addon_dir_rel)
		PlugLogger.info("Copying release: %s → %s" % [src, dst])
		DirAccess.make_dir_recursive_absolute(dst)
		var copied = GitManager._copy_dir_recursive(src, dst)
		PlugLogger.debug("_apply_release_from_cache: copied %d files" % copied)
		if copied == 0:
			PlugLogger.info("Release cache stale: 0 files copied, clearing cache %s" % cache_dir)
			release_manager.clear_tag_cache(repo_name, new_tag)
			success = false
			continue
		installed_tags.append({"dir": addon_dir_rel, "tag": new_tag})

	# --- Phase 3: Check cancel / failure and handle ---
	if _update_cancelled or not success:
		PlugLogger.info("Version switch rolled back for %s" % repo_name)
		_rollback_release_switch(backed_up, project_root, repo_name)
		return

	for entry in installed_tags:
		addon_data.set_addon_installed_tag(repo_name, entry["dir"], entry["tag"])
	release_manager.inspect_cache_dir(cache_dir)
	_backfill_release_addon_metadata(repo_name, cache_dir, true)
	addon_data.save_data()
	_cleanup_upgrade_backup(repo_name)
	PlugLogger.info(_tr("LOG_RELEASE_CACHED") % new_tag)


## Backup all currently installed addon directories for a repo before switching.
## Returns an array of {addon_dir_rel, backup_path} for later restore.
func _backup_installed_addons(
	repo_name: String, installed: Array, project_root: String
) -> Array:
	var backup_root := _get_upgrade_backup_dir(repo_name)
	var backed_up: Array = []
	for p in installed:
		var addon_dir_rel: String = p.get("addon_dir", "")
		if addon_dir_rel.is_empty():
			continue
		var full_path := project_root.path_join(addon_dir_rel)
		if not DirAccess.dir_exists_absolute(full_path):
			continue
		var backup_path := backup_root.path_join(addon_dir_rel.get_file())
		DirAccess.make_dir_recursive_absolute(backup_root)
		PlugLogger.debug("Backing up %s → %s" % [full_path, backup_path])
		GitManager._copy_dir_recursive(full_path, backup_path)
		GitManager.delete_installed_dir(addon_dir_rel)
		backed_up.append({"addon_dir_rel": addon_dir_rel, "backup_path": backup_path})
	return backed_up


## Restore addon directories from backup and clean up.
func _rollback_release_switch(
	backed_up: Array, project_root: String, repo_name: String
) -> void:
	for b in backed_up:
		var dst := project_root.path_join(b["addon_dir_rel"])
		var src: String = b["backup_path"]
		if DirAccess.dir_exists_absolute(dst):
			GitManager.delete_directory(dst)
		PlugLogger.debug("Restoring backup %s → %s" % [src, dst])
		DirAccess.make_dir_recursive_absolute(dst)
		GitManager._copy_dir_recursive(src, dst)
	_cleanup_upgrade_backup(repo_name)


func _get_upgrade_backup_dir(repo_name: String) -> String:
	var safe_name := repo_name.replace("/", "_")
	return OS.get_cache_dir().path_join("gd-plug-plus").path_join(
		"_upgrade_backup"
	).path_join(safe_name)


func _cleanup_upgrade_backup(repo_name: String) -> void:
	var backup_dir := _get_upgrade_backup_dir(repo_name)
	if DirAccess.dir_exists_absolute(backup_dir):
		GitManager.delete_directory(backup_dir)


func _copy_release_auto_detect(
	cache_dir: String, project_root: String, repo_name: String, tag: String
):
	PlugLogger.debug(
		"_copy_release_auto_detect: cache=%s project=%s repo=%s"
		% [cache_dir, project_root, repo_name]
	)
	var addons_path = cache_dir.path_join("addons")
	if DirAccess.dir_exists_absolute(addons_path):
		PlugLogger.debug("_copy_release_auto_detect: found addons/ in cache, scanning subdirs")
		var dir = DirAccess.open(addons_path)
		if dir:
			dir.list_dir_begin()
			var fname = dir.get_next()
			while not fname.is_empty():
				if dir.current_is_dir() and not fname.begins_with("."):
					var src = addons_path.path_join(fname)
					var dst = project_root.path_join("addons").path_join(fname)
					PlugLogger.info("Copying addon: %s → %s" % [src, dst])
					DirAccess.make_dir_recursive_absolute(dst)
					var copied = GitManager._copy_dir_recursive(src, dst)
					PlugLogger.debug("_copy_release_auto_detect: copied %d files for %s" % [copied, fname])
					var new_dir = "addons/" + fname
					for p in addon_data.get_addons(repo_name):
						if p.get("addon_dir", "") == "":
							p["addon_dir"] = new_dir
							break
					addon_data.set_addon_installed_tag(repo_name, new_dir, tag)
				fname = dir.get_next()
			dir.list_dir_end()
	else:
		PlugLogger.debug("_copy_release_auto_detect: no addons/ dir, copying entire cache to addons/")
		var repo_short = repo_name.get_file()
		var dst = project_root.path_join("addons").path_join(repo_short)
		PlugLogger.info("Copying release (flat): %s → %s" % [cache_dir, dst])
		DirAccess.make_dir_recursive_absolute(dst)
		var copied = GitManager._copy_dir_recursive(cache_dir, dst)
		PlugLogger.debug("_copy_release_auto_detect: copied %d files" % copied)
		if copied == 0:
			PlugLogger.info(
				"Release install failed: 0 files copied, "
				+ "clearing stale cache %s" % cache_dir
			)
			release_manager.clear_tag_cache(repo_name, tag)
			return
		var new_dir = "addons/" + repo_short
		for p in addon_data.get_addons(repo_name):
			if p.get("addon_dir", "") == "":
				p["addon_dir"] = new_dir
				break
		addon_data.set_addon_installed_tag(repo_name, new_dir, tag)


# ===========================================================================
# Shared SelectorPopup (branch/tag + commit, both tabs)
# ===========================================================================


func _get_or_create_selector_popup() -> SelectorPopup:
	if not is_instance_valid(_selector_popup):
		_selector_popup = SelectorPopup.new()
		add_child(_selector_popup)
	return _selector_popup


func _open_branch_tag_popup(branches: PackedStringArray, tags: PackedStringArray):
	var groups = _build_branch_tag_groups(branches, tags)
	var popup = _get_or_create_selector_popup()
	if popup.item_selected.is_connected(_on_selector_item_selected):
		popup.item_selected.disconnect(_on_selector_item_selected)
	(
		popup
		. setup(
			{
				"title": tr("BRANCH_POPUP_TITLE"),
				"size":
				Vector2i(
					_scaled(PlugUIConstants.BRANCH_POPUP_SIZE.x),
					_scaled(PlugUIConstants.BRANCH_POPUP_SIZE.y)
				),
				"filter_placeholder": tr("BRANCH_POPUP_FILTER"),
				"columns": 1,
				"show_column_titles": false,
				"groups": groups,
			}
		)
	)
	popup.item_selected.connect(_on_selector_item_selected, CONNECT_ONE_SHOT)
	popup.popup_centered()


func _open_commit_popup(commits: Array):
	var groups = _build_commit_groups(commits)
	var popup = _get_or_create_selector_popup()
	if popup.item_selected.is_connected(_on_selector_item_selected):
		popup.item_selected.disconnect(_on_selector_item_selected)
	(
		popup
		. setup(
			{
				"title": tr("COL_COMMIT"),
				"size":
				Vector2i(
					_scaled(PlugUIConstants.COMMIT_POPUP_SIZE.x),
					_scaled(PlugUIConstants.COMMIT_POPUP_SIZE.y)
				),
				"filter_placeholder": tr("BRANCH_POPUP_FILTER"),
				"columns": 2,
				"column_widths": [_scaled(PlugUIConstants.COMMIT_POPUP_HASH_COL_WIDTH), 0],
				"show_column_titles": false,
				"groups": groups,
			}
		)
	)
	popup.item_selected.connect(_on_selector_item_selected, CONNECT_ONE_SHOT)
	popup.popup_centered()


# --- Branch/tag selector (both tabs) ---


func _show_branch_tag_selector(repo_name: String, context: String):
	if _popup_loading:
		return
	if (
		context.begins_with("installed")
		and addon_data.get_repo_install_from(repo_name) == "release"
	):
		_show_release_tag_selector(repo_name, context)
		return
	_selector_context = context
	_selector_repo_name = repo_name

	if _remote_ref_cache.has(repo_name):
		var cached = _remote_ref_cache[repo_name]
		_open_branch_tag_popup(cached["branches"], cached["tags"])
		return

	var popup = _get_or_create_selector_popup()
	popup.show_loading(tr("BRANCH_POPUP_TITLE"), tr("SELECTOR_LOADING"))
	popup.popup_centered()
	_popup_loading = true

	var url = ""
	if context == "search_branch":
		url = _search_url
	elif context.begins_with("available_"):
		if _selector_target_item != null and _selector_target_item.has_meta("repo"):
			url = _selector_target_item.get_meta("repo")
	else:
		url = addon_data.get_repo(repo_name).get("url", "")

	_popup_done = false
	_popup_active = true
	_popup_task_id = WorkerThreadPool.add_task(
		func():
			GitManager.reset_cancel()
			var remote_info = GitManager.ls_remote(url)
			_popup_result = {
				"type": "branch_tag",
				"branches": remote_info.get("branches", PackedStringArray()),
				"tags": remote_info.get("tags", PackedStringArray()),
				"ref_commits": remote_info.get("ref_commits", {}),
				"error": remote_info.get("error", ""),
			}
			_popup_done = true
	)


func _get_release_tags_cached(repo_name: String, item: TreeItem) -> PackedStringArray:
	var tags: PackedStringArray = _remote_ref_cache.get(repo_name, {}).get(
		"release_tags", PackedStringArray()
	)
	if tags.is_empty() and item != null and item.has_meta("release_tags"):
		var meta_tags = item.get_meta("release_tags")
		if meta_tags is PackedStringArray:
			tags = meta_tags
		elif meta_tags is Array:
			tags = PackedStringArray(meta_tags)
	return tags


func _get_release_tag_assets(repo_name: String, item: TreeItem) -> Dictionary:
	var assets: Dictionary = _remote_ref_cache.get(repo_name, {}).get("release_tag_assets", {})
	if assets.is_empty() and item != null and item.has_meta("release_tag_assets"):
		var meta_assets = item.get_meta("release_tag_assets")
		if meta_assets is Dictionary:
			assets = meta_assets
	return assets


func _show_search_release_tag_selector(repo_name: String):
	_selector_context = "search_release_tag"
	_selector_repo_name = repo_name
	var cached = _remote_ref_cache.get(repo_name, {})
	var cache_keys = cached.keys() if not cached.is_empty() else []
	var release_tags: PackedStringArray = _get_release_tags_cached(
		repo_name, _selector_target_item
	)
	PlugLogger.debug(
		(
			"_show_search_release_tag_selector: repo=%s cache_keys=%s release_tags_count=%d"
			% [repo_name, cache_keys, release_tags.size()]
		)
	)
	if release_tags.is_empty():
		PlugLogger.debug("_show_search_release_tag_selector: release_tags empty, aborting")
		return
	var groups: Array = []
	var items: Array = []
	for t in release_tags:
		items.append({"columns": [t], "meta": {"type": "tag", "name": t}})
	groups.append({"header": tr("TAG_HEADER") % items.size(), "items": items})
	var popup = _get_or_create_selector_popup()
	if popup.item_selected.is_connected(_on_selector_item_selected):
		popup.item_selected.disconnect(_on_selector_item_selected)
	(
		popup
		. setup(
			{
				"title": tr("BRANCH_POPUP_TITLE"),
				"size":
				Vector2i(
					_scaled(PlugUIConstants.BRANCH_POPUP_SIZE.x),
					_scaled(PlugUIConstants.BRANCH_POPUP_SIZE.y)
				),
				"filter_placeholder": tr("BRANCH_POPUP_FILTER"),
				"columns": 1,
				"show_column_titles": false,
				"groups": groups,
			}
		)
	)
	popup.item_selected.connect(_on_selector_item_selected, CONNECT_ONE_SHOT)
	popup.popup_centered()


func _resolve_tag_asset(tag_entry, preferred_filename: String) -> Dictionary:
	# Accepts either the legacy single-dict format or the new Array-of-Dict format.
	var assets: Array = []
	if tag_entry is Array:
		assets = tag_entry
	elif tag_entry is Dictionary:
		assets = [tag_entry]
	if assets.is_empty():
		return {}
	if not preferred_filename.is_empty():
		for a in assets:
			if a is Dictionary and a.get("filename", "") == preferred_filename:
				return a
	var first = assets[0]
	return first if first is Dictionary else {}


func _format_asset_size(size: int) -> String:
	if size <= 0:
		return "--"
	var fsize: float = float(size)
	if fsize >= 1024.0 * 1024.0:
		return "%.2f MB" % (fsize / (1024.0 * 1024.0))
	if fsize >= 1024.0:
		return "%.1f KB" % (fsize / 1024.0)
	return "%d B" % size


func _show_release_asset_selector(item: TreeItem):
	if item == null:
		return
	if not item.has_meta("from_release") or not item.get_meta("from_release"):
		PlugLogger.debug("_show_release_asset_selector: item is not a release row, aborting")
		return
	var url: String = ""
	if item.has_meta("repo"):
		url = item.get_meta("repo")
	if url.is_empty():
		url = _search_url
	var repo_name: String = GitManager.repo_name_from_url(url)
	var tag_name: String = item.get_meta("selected_tag", "")
	if tag_name.is_empty():
		var info_tmp: Dictionary = item.get_meta("addon_info", {})
		tag_name = info_tmp.get("_release_tag", "")
	var asset_map: Dictionary = _get_release_tag_assets(repo_name, item)
	var assets_raw = asset_map.get(tag_name, [])
	var assets: Array = []
	if assets_raw is Array:
		assets = assets_raw
	elif assets_raw is Dictionary:
		assets = [assets_raw]
	if assets.is_empty():
		PlugLogger.debug(
			"_show_release_asset_selector: no cached assets for tag=%s repo=%s" % [tag_name, repo_name]
		)
		return

	_selector_context = "search_release_asset"
	_selector_repo_name = repo_name
	_selector_target_item = item

	var popup_items: Array = []
	for a in assets:
		if not (a is Dictionary):
			continue
		var fname: String = a.get("filename", "")
		var size_int: int = int(a.get("size", 0))
		var size_str: String = _format_asset_size(size_int)
		(
			popup_items
			. append(
				{
					"columns": [fname, size_str],
					"meta":
					{
						"type": "release_asset",
						"url": a.get("url", ""),
						"filename": fname,
						"name": a.get("name", fname.get_basename()),
						"size": size_int,
					},
				}
			)
		)

	var header_text: String = _tr("RELEASE_ASSET_HEADER") % popup_items.size()
	var groups: Array = [{"header": header_text, "items": popup_items}]

	var popup = _get_or_create_selector_popup()
	if popup.item_selected.is_connected(_on_selector_item_selected):
		popup.item_selected.disconnect(_on_selector_item_selected)
	(
		popup
		. setup(
			{
				"title": _tr("RELEASE_ASSET_POPUP_TITLE"),
				"size":
				Vector2i(
					_scaled(PlugUIConstants.COMMIT_POPUP_SIZE.x),
					_scaled(PlugUIConstants.COMMIT_POPUP_SIZE.y)
				),
				"filter_placeholder": _tr("BRANCH_POPUP_FILTER"),
				"columns": 2,
				"show_column_titles": false,
				"groups": groups,
			}
		)
	)
	popup.item_selected.connect(_on_selector_item_selected, CONNECT_ONE_SHOT)
	popup.popup_centered()


func _apply_release_asset_selection(item: TreeItem, asset: Dictionary) -> void:
	if item == null or asset.is_empty():
		return
	var info: Dictionary = item.get_meta("addon_info", {})
	var asset_url: String = asset.get("url", "")
	var asset_filename: String = asset.get("filename", "")
	var asset_basename: String = asset.get("name", "")
	if asset_basename.is_empty() and not asset_filename.is_empty():
		asset_basename = asset_filename.get_basename()
	# Sync _release_tag from the row's currently displayed tag so that
	# downstream install code paths read the same tag the user picked.
	# Without this, info["_release_tag"] stays at the original search-time tag
	# while the asset URL/filename point to the freshly chosen tag — the
	# install would then download newer asset bytes into an older tag's
	# cache dir and report "tag=v1.3.6" while fetching "?ref=v1.8.0".
	var current_tag: String = item.get_meta("selected_tag", "")
	if not current_tag.is_empty():
		info["_release_tag"] = current_tag
	info["_release_asset_url"] = asset_url
	info["_release_asset_filename"] = asset_filename
	var is_stub: bool = info.get("_release_is_stub", false)
	if is_stub:
		if not asset_basename.is_empty():
			info["name"] = asset_basename
			item.set_text(2, asset_basename)
		item.set_text(7, asset_filename)
		var stub_tip: String = _tr("RELEASE_ASSET_CLICK_HINT")
		if not asset_filename.is_empty():
			stub_tip = asset_filename + "\n" + stub_tip
		item.set_tooltip_text(7, stub_tip)
	else:
		var pdir: String = info.get("addon_dir", "")
		item.set_text(7, pdir)
		var src_tip: String = _tr("RELEASE_ASSET_CLICK_HINT")
		if not asset_filename.is_empty():
			src_tip = asset_filename + "\n" + src_tip
		elif not pdir.is_empty():
			src_tip = pdir
		item.set_tooltip_text(7, src_tip)
	item.set_meta("addon_info", info)
	item.set_meta("release_asset_filename", asset_filename)


func _show_release_tag_selector(repo_name: String, context: String):
	_selector_context = context
	_selector_repo_name = repo_name
	var popup = _get_or_create_selector_popup()
	popup.show_loading(tr("BRANCH_POPUP_TITLE"), tr("SELECTOR_LOADING"))
	popup.popup_centered()
	var url = addon_data.get_repo(repo_name).get("url", "")
	release_manager.get_tags(url)
	release_manager.tags_fetched.connect(
		func(tags: Array):
			var groups: Array = []
			var items: Array = []
			for t in tags:
				(
					items
					. append(
						{
							"columns": [t.get("tag_name", "")],
							"meta": {"type": "tag", "name": t.get("tag_name", "")},
						}
					)
				)
			if not items.is_empty():
				groups.append({"header": tr("TAG_HEADER") % items.size(), "items": items})
			if popup.item_selected.is_connected(_on_selector_item_selected):
				popup.item_selected.disconnect(_on_selector_item_selected)
			(
				popup
				. setup(
					{
						"title": tr("BRANCH_POPUP_TITLE"),
						"size":
						Vector2i(
							_scaled(PlugUIConstants.BRANCH_POPUP_SIZE.x),
							_scaled(PlugUIConstants.BRANCH_POPUP_SIZE.y)
						),
						"filter_placeholder": tr("BRANCH_POPUP_FILTER"),
						"columns": 1,
						"show_column_titles": false,
						"groups": groups,
					}
				)
			)
			popup.item_selected.connect(_on_selector_item_selected, CONNECT_ONE_SHOT),
		CONNECT_ONE_SHOT
	)


func _show_search_branch_popup(item: TreeItem):
	_selector_target_item = item
	var repo_name = GitManager.repo_name_from_url(_search_url)
	if not _search_branches.is_empty() or not _search_tags.is_empty():
		_selector_context = "search_branch"
		_selector_repo_name = repo_name
		_open_branch_tag_popup(_search_branches, _search_tags)
	else:
		_show_branch_tag_selector(repo_name, "search_branch")


# --- Commit selector (both tabs) ---


func _get_effective_ref(repo_name: String) -> Dictionary:
	if _pending_changes.has(repo_name):
		var p = _pending_changes[repo_name]
		if not p.get("tag", "").is_empty():
			return {"type": "tag", "ref": p["tag"]}
		if not p.get("branch", "").is_empty():
			return {"type": "branch", "ref": p["branch"]}
	var first = _first_installed_or_first(addon_data.get_installed_addons(repo_name))
	if not first.get("tag", "").is_empty():
		return {"type": "tag", "ref": first["tag"]}
	var br = first.get("branch", "")
	if br.is_empty():
		var cached_info = _version_cache.get(repo_name, {})
		br = cached_info.get("current_branch", "")
	return {"type": "branch", "ref": br}


func _show_commit_selector(repo_name: String, context: String):
	if _popup_loading:
		return
	_selector_context = context
	_selector_repo_name = repo_name

	var eff: Dictionary
	if context == "available_commit" and _selector_target_item != null:
		var branch: String = _selector_target_item.get_meta("selected_branch", "main")
		eff = {"type": "branch", "ref": branch}
	else:
		eff = _get_effective_ref(repo_name)
	var eff_type: String = eff.get("type", "branch")
	var eff_ref: String = eff.get("ref", "")

	if eff_type == "tag" and not eff_ref.is_empty():
		var ref_commits_dict = _remote_ref_cache.get(repo_name, {}).get(
			"ref_commits", _search_ref_commits
		)
		var tag_hash = ref_commits_dict.get(eff_ref, "")
		if tag_hash.is_empty():
			tag_hash = eff_ref
		var single = [
			{"hash": tag_hash, "hash_short": _short_commit(tag_hash), "message": "Tag: " + eff_ref}
		]
		_open_commit_popup(single)
		return

	var cache_key = repo_name + ":" + eff_ref
	if _commit_cache.has(cache_key):
		_open_commit_popup(_commit_cache[cache_key])
		return

	var popup = _get_or_create_selector_popup()
	popup.show_loading(tr("COL_COMMIT"), tr("SELECTOR_LOADING"))
	popup.popup_centered()
	_popup_loading = true

	var clone_url = ""
	if context.begins_with("available_") and _selector_target_item != null:
		clone_url = _selector_target_item.get_meta("repo", "")

	_popup_done = false
	_popup_active = true
	_popup_task_id = WorkerThreadPool.add_task(
		func():
			GitManager.reset_cancel()
			if not _ensure_repo_cloned(repo_name, clone_url):
				_popup_result = {
					"type": "commit",
					"error":
					(
						GitManager.last_error
						if not GitManager.last_error.is_empty()
						else "Clone failed"
					),
					"commits": [],
					"cache_key": cache_key
				}
				_popup_done = true
				return
			var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
			GitManager.git(
				plug_dir, ["fetch", "origin", "--deepen=%d" % PlugUIConstants.FETCH_DEEPEN_COUNT]
			)
			var commits: Array[Dictionary] = []
			if not eff_ref.is_empty():
				commits = GitManager.get_commit_log(
					plug_dir, "origin/" + eff_ref, PlugUIConstants.COMMIT_LOG_LIMIT
				)
			if commits.is_empty():
				var info = GitManager.get_current_info(plug_dir)
				var branch = info.get("branch", "")
				if not branch.is_empty():
					commits = GitManager.get_commit_log(
						plug_dir, "origin/" + branch, PlugUIConstants.COMMIT_LOG_LIMIT
					)
			if commits.is_empty():
				commits = GitManager.get_commit_log(
					plug_dir, "--all", PlugUIConstants.COMMIT_LOG_LIMIT
				)
			if commits.is_empty():
				commits = GitManager.get_commit_log(
					plug_dir, "HEAD", PlugUIConstants.COMMIT_LOG_LIMIT
				)
			_popup_result = {
				"type": "commit", "commits": commits, "error": "", "cache_key": cache_key
			}
			_popup_done = true
	)


func _on_popup_data_loaded():
	_popup_loading = false
	var popup = _get_or_create_selector_popup()
	var err: String = _popup_result.get("error", "")
	if not err.is_empty():
		popup.show_error(err)
		return
	var ptype: String = _popup_result.get("type", "")
	if ptype == "branch_tag":
		var branches: PackedStringArray = _popup_result.get("branches", PackedStringArray())
		var tags: PackedStringArray = _popup_result.get("tags", PackedStringArray())
		var ref_commits: Dictionary = _popup_result.get("ref_commits", {})
		_remote_ref_cache[_selector_repo_name] = {
			"branches": branches, "tags": tags, "ref_commits": ref_commits
		}
		_open_branch_tag_popup(branches, tags)
	elif ptype == "commit":
		var commits: Array = _popup_result.get("commits", [])
		var ck: String = _popup_result.get("cache_key", _selector_repo_name)
		_commit_cache[ck] = commits
		_open_commit_popup(commits)


# --- Unified selection handler ---


func _on_selector_item_selected(meta: Dictionary):
	var version_type: String = meta.get("type", "")

	# Search / Available tab: release tag selection → update item display
	if _selector_context == "search_release_tag":
		if _selector_target_item != null and version_type == "tag":
			var tag_name = meta.get("name", "")
			_selector_target_item.set_text(5, tag_name)
			_selector_target_item.set_meta("selected_tag", tag_name)
			var asset_map: Dictionary = _get_release_tag_assets(
				_selector_repo_name, _selector_target_item
			)
			if asset_map.has(tag_name):
				var chosen: Dictionary = _resolve_tag_asset(
					asset_map[tag_name], _selector_target_item.get_meta("release_asset_filename", "")
				)
				if not chosen.is_empty():
					_apply_release_asset_selection(_selector_target_item, chosen)
					PlugLogger.debug(
						(
							"_on_selector: release tag changed to '%s' asset=%s url=%s"
							% [tag_name, chosen.get("filename", ""), chosen.get("url", "")]
						)
					)
				else:
					PlugLogger.debug(
						"_on_selector: release tag '%s' has empty asset list" % tag_name
					)
			else:
				PlugLogger.debug(
					"_on_selector: release tag '%s' has no cached asset, keeping previous URL"
					% tag_name
				)
		return

	# Search / Available tab: release asset selection → switch asset of current tag
	if _selector_context == "search_release_asset":
		if _selector_target_item != null and version_type == "release_asset":
			var asset_url: String = meta.get("url", "")
			var asset_filename: String = meta.get("filename", "")
			var asset_basename: String = meta.get("name", "")
			var asset_size: int = int(meta.get("size", 0))
			_apply_release_asset_selection(
				_selector_target_item,
				{
					"url": asset_url,
					"filename": asset_filename,
					"name": asset_basename,
					"size": asset_size,
				}
			)
			PlugLogger.debug(
				(
					"_on_selector: release asset changed to filename=%s url=%s"
					% [asset_filename, asset_url]
				)
			)
		return

	# Search / Available tab: branch/tag selection → update item display
	if _selector_context in ["search_branch", "available_branch"]:
		_apply_search_ref_selection(meta)
		return

	# Search / Available tab: commit selection → update item display + store for install
	if _selector_context in ["search_commit", "available_commit"]:
		_apply_search_commit_selection(meta)
		return

	# Installed tab: branch/tag/commit → store as pending
	if _selector_context in ["installed_branch", "installed_commit"]:
		var rn = _selector_repo_name
		var pending = _pending_changes.get(rn, {}).duplicate() as Dictionary

		match version_type:
			"branch":
				var branch_name = meta.get("name", "")
				if not branch_name.is_empty():
					pending["branch"] = branch_name
					pending.erase("tag")
					var ref_commits = _remote_ref_cache.get(rn, {}).get("ref_commits", {})
					var latest_hash = ref_commits.get(branch_name, "")
					pending["commit"] = latest_hash
					pending["commit_preview"] = (
						_short_commit(latest_hash) if not latest_hash.is_empty() else ""
					)
			"tag":
				var tag_name = meta.get("name", "")
				if not tag_name.is_empty():
					pending["tag"] = tag_name
					pending.erase("branch")
					var ref_commits = _remote_ref_cache.get(rn, {}).get("ref_commits", {})
					var tag_hash = ref_commits.get(tag_name, "")
					pending["commit"] = tag_hash
					pending["commit_preview"] = (
						_short_commit(tag_hash) if not tag_hash.is_empty() else ""
					)
			"commit":
				var hash_full = meta.get("hash", "")
				if not hash_full.is_empty():
					pending["commit"] = hash_full
					pending["commit_preview"] = meta.get("hash_short", _short_commit(hash_full))

		_pending_changes[rn] = pending
		if _pending_matches_current(rn, pending):
			_pending_changes.erase(rn)
		_refresh_installed_tree()


func _pending_matches_current(repo_name: String, pending: Dictionary) -> bool:
	var first = _first_installed_or_first(addon_data.get_installed_addons(repo_name))
	var cur_branch = first.get("branch", "")
	var cur_tag = first.get("tag", "")
	if first.get("installed_from", "") == "release":
		cur_tag = first.get("installed_tag", "")
	var cur_commit = first.get("commit", "")
	var cached = _version_cache.get(repo_name, {})
	if cached.has("current_commit") and not cached["current_commit"].is_empty():
		cur_commit = cached["current_commit"]

	var eff_branch = pending.get("branch", "") if pending.has("branch") else cur_branch
	var eff_tag = pending.get("tag", "") if pending.has("tag") else cur_tag
	if pending.has("tag"):
		eff_branch = ""
	elif pending.has("branch"):
		eff_tag = ""
	var eff_commit = pending.get("commit", "")

	if eff_branch != cur_branch or eff_tag != cur_tag:
		return false
	if not eff_commit.is_empty() and not cur_commit.is_empty():
		var len_cmp = mini(eff_commit.length(), cur_commit.length())
		if eff_commit.left(len_cmp) != cur_commit.left(len_cmp):
			return false
	return true


func _apply_search_ref_selection(meta: Dictionary):
	var item = _selector_target_item
	if item == null:
		return
	var ref_name: String = meta.get("name", "")
	var is_tag: bool = meta.get("type", "") == "tag"
	if is_tag:
		item.set_text(5, ref_name + " [tag]")
		item.set_meta("selected_branch", "")
		item.set_meta("selected_tag", ref_name)
	else:
		item.set_text(5, ref_name)
		item.set_meta("selected_branch", ref_name)
		item.set_meta("selected_tag", "")
	var commit = _search_ref_commits.get(ref_name, _search_head_commit)
	item.set_text(6, _short_commit(commit))
	item.set_custom_color(6, _commit_color(true))
	item.set_meta("selected_commit", "")


func _apply_search_commit_selection(meta: Dictionary):
	var item = _selector_target_item
	if item == null:
		return
	var hash_full: String = meta.get("hash", "")
	var hash_short: String = meta.get("hash_short", _short_commit(hash_full))
	item.set_text(6, hash_short)
	item.set_meta("selected_commit", hash_full)
	var branch: String = item.get_meta("selected_branch", "")
	var tag: String = item.get_meta("selected_tag", "")
	var ref = tag if not tag.is_empty() else branch
	var head = _search_ref_commits.get(ref, _search_head_commit)
	item.set_custom_color(6, _commit_color(hash_full == head))


# ===========================================================================
# Signal callbacks
# ===========================================================================


func _on_visibility_changed():
	if visible and not _is_executing:
		addon_data.load_data()
		_remote_ref_cache.clear()
		_commit_cache.clear()
		_refresh_installed_tree()


func _on_tab_changed(tab: int):
	if tab == 1:
		_update_search_tree_install_status()
		_update_install_selected_count()
	elif tab == 2:
		_refresh_all_platform_rows()


func _on_installed_tree_mouse_selected(position: Vector2, mouse_button_index: int):
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	var item = installed_tree.get_selected()
	if item == null or not item.has_meta("repo_name"):
		return
	var col = installed_tree.get_column_at_position(position)
	var repo_name: String = item.get_meta("repo_name")
	if repo_name.is_empty():
		return

	var is_locked = addon_data.is_repo_locked(repo_name)

	match col:
		3:
			if not is_locked:
				_show_branch_tag_selector(repo_name, "installed_branch")
		4:
			if not is_locked:
				_show_commit_selector(repo_name, "installed_commit")
		6:
			_show_detail_dialog(repo_name)
		7:
			_toggle_repo_lock(repo_name)
		8:
			if is_locked:
				return
			if _pending_changes.has(repo_name):
				_apply_pending_changes(repo_name)
			else:
				var action = item.get_text(8)
				if (
					action != tr("STATUS_LATEST")
					and action != tr("STATUS_INSTALLING")
					and action != tr("STATUS_CHECKING")
					and action != tr("STATUS_UPDATING")
				):
					_update_single_repo(repo_name)
		9:
			if repo_name != SELF_REPO_NAME:
				_confirm_remove_repo(repo_name)


func _toggle_repo_lock(repo_name: String):
	var is_locked = addon_data.is_repo_locked(repo_name)
	if is_locked:
		addon_data.set_repo_locked(repo_name, false)
	else:
		_pending_changes.erase(repo_name)
		addon_data.set_repo_locked(repo_name, true)
	addon_data.save_data()
	call_deferred("_refresh_installed_tree", "")


func _apply_pending_changes(repo_name: String):
	if not _pending_changes.has(repo_name):
		return
	var pending = _pending_changes[repo_name] as Dictionary
	var has_tag = not pending.get("tag", "").is_empty()
	var has_branch = not pending.get("branch", "").is_empty()
	var commit = pending.get("commit", "")
	_pending_changes.erase(repo_name)
	_is_version_switch = true

	if has_tag:
		_switch_repo_version(repo_name, "tag", pending["tag"])
	elif has_branch:
		_switch_repo_version(repo_name, "branch", pending["branch"], commit)
	elif not commit.is_empty():
		var first = _first_installed_or_first(addon_data.get_installed_addons(repo_name))
		var cur_branch = first.get("branch", "")
		if not cur_branch.is_empty():
			_switch_repo_version(repo_name, "branch", cur_branch, commit)
		else:
			_switch_repo_version(repo_name, "commit", commit)


func _on_search_tree_mouse_selected(position: Vector2, mouse_button_index: int):
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return

	if _tree_mode == TreeMode.SEARCHED:
		var col = search_tree.get_column_at_position(position)
		var item = search_tree.get_item_at_position(position)
		if item and item.has_meta("addon_info"):
			if col == 1 and item.get_text(1) == tr("STATUS_INSTALLED"):
				var repo_name = GitManager.repo_name_from_url(_search_url)
				_jump_to_installed_tab(repo_name)
			elif col == 5:
				_selector_target_item = item
				var repo_name = GitManager.repo_name_from_url(_search_url)
				var is_release = item.has_meta("from_release") and item.get_meta("from_release")
				PlugLogger.debug(
					"SEARCHED col5 click: repo=%s from_release=%s" % [repo_name, is_release]
				)
				if is_release:
					_show_search_release_tag_selector(repo_name)
				else:
					_show_search_branch_popup(item)
			elif col == 6:
				if item.has_meta("from_release") and item.get_meta("from_release"):
					PlugLogger.debug("SEARCHED col6 click: release row, skipping commit selector")
					return
				_selector_target_item = item
				var repo_name = GitManager.repo_name_from_url(_search_url)
				_show_commit_selector(repo_name, "search_commit")
			elif col == 7:
				if item.has_meta("from_release") and item.get_meta("from_release"):
					PlugLogger.debug("SEARCHED col7 click: release row, opening asset selector")
					_selector_target_item = item
					_show_release_asset_selector(item)
		return

	if _tree_mode != TreeMode.AVAILABLE:
		return
	var col = search_tree.get_column_at_position(position)
	var item = search_tree.get_item_at_position(position)
	if item == null or not item.has_meta("is_available"):
		return
	if col == 1 and item.get_text(1) == tr("STATUS_INSTALLED"):
		var repo_name = GitManager.repo_name_from_url(item.get_meta("repo"))
		_jump_to_installed_tab(repo_name)
	elif col == 5:
		_selector_target_item = item
		var url: String = item.get_meta("repo")
		var repo_name = GitManager.repo_name_from_url(url)
		if item.has_meta("from_release") and item.get_meta("from_release"):
			_show_search_release_tag_selector(repo_name)
		else:
			_show_branch_tag_selector(repo_name, "available_branch")
	elif col == 6:
		_selector_target_item = item
		var url: String = item.get_meta("repo")
		var repo_name = GitManager.repo_name_from_url(url)
		_show_commit_selector(repo_name, "available_commit")
	elif col == 7:
		if item.has_meta("from_release") and item.get_meta("from_release"):
			PlugLogger.debug("AVAILABLE col7 click: release row, opening asset selector")
			_selector_target_item = item
			_show_release_asset_selector(item)


func _on_SearchInput_text_changed(new_text: String):
	if _tree_mode != TreeMode.AVAILABLE:
		_tree_mode = TreeMode.AVAILABLE
	_refresh_unified_tree(new_text)


# ===========================================================================
# Search bar setup
# ===========================================================================


func _setup_search_bar():
	var search_bar_margin = search_input.get_parent()
	search_bar_margin.set(
		"theme_override_constants/margin_top", _scaled(PlugUIConstants.MARGIN_COMPACT)
	)
	search_bar_margin.set("theme_override_constants/margin_bottom", 0)
	var search_hbox = HBoxContainer.new()
	search_hbox.add_theme_constant_override(
		"separation", _scaled(PlugUIConstants.SEPARATION_STANDARD)
	)
	search_bar_margin.remove_child(search_input)
	search_hbox.add_child(search_input)
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.text_submitted.connect(_on_SearchInput_submitted)
	_release_checkbox = CheckBox.new()
	_release_checkbox.text = tr("SEARCH_RELEASE_CHECKBOX")
	_release_checkbox.button_pressed = false
	search_hbox.add_child(_release_checkbox)
	_search_btn = Button.new()
	_search_btn.pressed.connect(_on_SearchBtn_pressed)
	search_hbox.add_child(_search_btn)
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(_scaled(PlugUIConstants.SEARCH_BAR_SPACER_WIDTH), 0)
	search_hbox.add_child(spacer)
	install_selected_btn.get_parent().remove_child(install_selected_btn)
	search_hbox.add_child(install_selected_btn)
	search_bar_margin.add_child(search_hbox)


func _setup_installed_filter():
	var installed_vbox = installed_tree.get_parent()
	_installed_filter_input = LineEdit.new()
	_installed_filter_input.placeholder_text = tr("INSTALLED_FILTER_PLACEHOLDER")
	_installed_filter_input.clear_button_enabled = true
	_installed_filter_input.text_changed.connect(_on_installed_filter_changed)
	var margin = MarginContainer.new()
	margin.set("theme_override_constants/margin_left", _scaled(PlugUIConstants.MARGIN_STANDARD))
	margin.set("theme_override_constants/margin_top", _scaled(PlugUIConstants.MARGIN_COMPACT))
	margin.set("theme_override_constants/margin_right", _scaled(PlugUIConstants.MARGIN_STANDARD))
	margin.set("theme_override_constants/margin_bottom", 0)
	margin.add_child(_installed_filter_input)
	installed_vbox.add_child(margin)
	installed_vbox.move_child(margin, 0)


func _on_installed_filter_changed(new_text: String):
	_refresh_installed_tree(new_text)


func _setup_settings_tab():
	var sidebar: PanelContainer = $"TabContainer/Settings/SettingsSidebar"
	var sidebar_style := sidebar.get_theme_stylebox("panel").duplicate()
	sidebar_style.content_margin_top = _scaled(6)
	sidebar_style.content_margin_left = _scaled(6)
	sidebar_style.content_margin_right = _scaled(6)
	sidebar_style.content_margin_bottom = _scaled(6)
	sidebar.add_theme_stylebox_override("panel", sidebar_style)
	var settings_hbox: HBoxContainer = $"TabContainer/Settings"
	var vsep := VSeparator.new()
	settings_hbox.add_child(vsep)
	settings_hbox.move_child(vsep, 1)
	var sidebar_vbox: VBoxContainer = $"TabContainer/Settings/SettingsSidebar/SettingsSidebarVBox"
	var content_vbox: VBoxContainer = (
		$"TabContainer/Settings/SettingsContentScroll/SettingsContent"
	)
	var margin := _scaled(PlugUIConstants.MARGIN_STANDARD)
	content_vbox.add_theme_constant_override(
		"separation", _scaled(PlugUIConstants.SEPARATION_LARGE)
	)
	_device_flow = GitHubDeviceFlow.new()
	add_child(_device_flow)
	_device_flow.code_received.connect(_on_device_flow_code_received)
	_device_flow.succeeded.connect(_on_device_flow_succeeded)
	_device_flow.failed.connect(_on_device_flow_failed)
	var auth_panel := _build_auth_category_panel(margin)
	content_vbox.add_child(auth_panel)
	_register_settings_category("auth", sidebar_vbox, "SETTINGS_CATEGORY_AUTH", auth_panel)
	var network_panel := _build_network_category_panel()
	content_vbox.add_child(network_panel)
	_register_settings_category(
		"network", sidebar_vbox, "SETTINGS_CATEGORY_NETWORK", network_panel
	)
	var cache_panel := _build_cache_category_panel()
	content_vbox.add_child(cache_panel)
	_register_settings_category(
		"cache", sidebar_vbox, "SETTINGS_CATEGORY_CACHE", cache_panel
	)
	var about_panel := _build_about_category_panel()
	content_vbox.add_child(about_panel)
	_register_settings_category("about", sidebar_vbox, "SETTINGS_CATEGORY_ABOUT", about_panel)
	_select_settings_category("auth")
	for key in TokenStore.get_platform_keys():
		_refresh_platform_row(key)


## Builds a sidebar entry for a settings category and wires it to switch
## visibility on press. The sidebar button uses a flat toggle look reminiscent
## of Godot's own Editor Settings navigator. `i18n_key` is passed through `tr`
## both at construction and (potentially in the future) on locale change.
func _register_settings_category(
	key: String, sidebar: VBoxContainer, i18n_key: String, panel: Control
) -> void:
	var btn := Button.new()
	btn.text = tr(i18n_key)
	btn.toggle_mode = true
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = _scaled(28)
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(1, 1, 1, 0.12)
	pressed_style.corner_radius_top_left = _scaled(3)
	pressed_style.corner_radius_top_right = _scaled(3)
	pressed_style.corner_radius_bottom_left = _scaled(3)
	pressed_style.corner_radius_bottom_right = _scaled(3)
	pressed_style.content_margin_left = _scaled(8)
	pressed_style.content_margin_right = _scaled(8)
	pressed_style.content_margin_top = _scaled(4)
	pressed_style.content_margin_bottom = _scaled(4)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	var hover_style := pressed_style.duplicate()
	hover_style.bg_color = Color(1, 1, 1, 0.06)
	btn.add_theme_stylebox_override("hover", hover_style)
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0, 0, 0, 0)
	normal_style.content_margin_left = pressed_style.content_margin_left
	normal_style.content_margin_right = pressed_style.content_margin_right
	normal_style.content_margin_top = pressed_style.content_margin_top
	normal_style.content_margin_bottom = pressed_style.content_margin_bottom
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color(0.85, 0.85, 0.85))
	btn.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	btn.pressed.connect(func(): _select_settings_category(key))
	sidebar.add_child(btn)
	_settings_categories[key] = {"button": btn, "content": panel, "i18n_key": i18n_key}


func _select_settings_category(key: String) -> void:
	_settings_active_category = key
	for cat_key in _settings_categories.keys():
		var entry: Dictionary = _settings_categories[cat_key]
		var is_active: bool = cat_key == key
		(entry["content"] as Control).visible = is_active
		(entry["button"] as Button).button_pressed = is_active


## The "Authentication" settings page: header + one PanelContainer per release
## platform. All sections use the same outer→PanelContainer→inner_margin
## structure so their content is guaranteed to be left-aligned.
func _build_auth_category_panel(_margin: int) -> Control:
	var page = VBoxContainer.new()
	page.add_theme_constant_override(
		"separation", _scaled(PlugUIConstants.SEPARATION_LARGE)
	)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_settings_header(page)
	for key in TokenStore.get_platform_keys():
		var outer := _build_platform_panel(key)
		page.add_child(outer)
		_settings_platform_panels[key] = outer
	return page


func _build_network_category_panel() -> Control:
	var page = VBoxContainer.new()
	page.add_theme_constant_override(
		"separation", _scaled(PlugUIConstants.SEPARATION_LARGE)
	)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var outer = MarginContainer.new()
	var panel = PanelContainer.new()
	outer.add_child(panel)
	var inner = MarginContainer.new()
	var pad := _scaled(8)
	inner.add_theme_constant_override("margin_left", pad)
	inner.add_theme_constant_override("margin_right", pad)
	inner.add_theme_constant_override("margin_top", pad)
	inner.add_theme_constant_override("margin_bottom", pad)
	panel.add_child(inner)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override(
		"separation", _scaled(PlugUIConstants.SEPARATION_STANDARD)
	)

	_proxy_enable_cb = CheckBox.new()
	_proxy_enable_cb.text = tr("SETTINGS_PROXY_ENABLE")
	vbox.add_child(_proxy_enable_cb)

	var addr_hbox = HBoxContainer.new()
	addr_hbox.add_theme_constant_override("separation", _scaled(4))
	var host_label = Label.new()
	host_label.text = tr("SETTINGS_PROXY_HOST")
	addr_hbox.add_child(host_label)
	_proxy_host_input = LineEdit.new()
	_proxy_host_input.placeholder_text = ProxyConfig.DEFAULT_HOST
	_proxy_host_input.custom_minimum_size = Vector2(_scaled(200), 0)
	addr_hbox.add_child(_proxy_host_input)
	var port_label = Label.new()
	port_label.text = tr("SETTINGS_PROXY_PORT")
	addr_hbox.add_child(port_label)
	_proxy_port_spin = SpinBox.new()
	_proxy_port_spin.min_value = 1
	_proxy_port_spin.max_value = 65535
	_proxy_port_spin.value = ProxyConfig.DEFAULT_PORT
	_proxy_port_spin.custom_minimum_size = Vector2(_scaled(90), 0)
	addr_hbox.add_child(_proxy_port_spin)
	var save_btn = Button.new()
	save_btn.text = tr("BTN_SAVE")
	save_btn.pressed.connect(_on_save_proxy)
	addr_hbox.add_child(save_btn)
	vbox.add_child(addr_hbox)

	inner.add_child(vbox)
	page.add_child(outer)

	var cfg := ProxyConfig.load_config()
	_proxy_enable_cb.button_pressed = cfg.get("enabled", false)
	_proxy_host_input.text = cfg.get("host", ProxyConfig.DEFAULT_HOST)
	_proxy_port_spin.value = int(cfg.get("port", ProxyConfig.DEFAULT_PORT))

	return page


func _on_save_proxy() -> void:
	var cfg := {
		"enabled": _proxy_enable_cb.button_pressed,
		"host": _proxy_host_input.text.strip_edges(),
		"port": int(_proxy_port_spin.value),
	}
	if cfg["host"].is_empty():
		cfg["host"] = ProxyConfig.DEFAULT_HOST
	ProxyConfig.save_config(cfg)
	_apply_proxy_to_all()
	_show_toast(tr("TOAST_PROXY_SAVED"))


func _apply_proxy_to_all() -> void:
	release_manager.apply_proxy()
	if _device_flow and is_instance_valid(_device_flow):
		_device_flow.apply_proxy()
	for key in _settings_platform_rows:
		var row: Dictionary = _settings_platform_rows[key]
		var http: HTTPRequest = row.get("validate_http", null)
		if http != null and is_instance_valid(http):
			ProxyConfig.apply_to_http(http)


func _build_cache_category_panel() -> Control:
	var page = VBoxContainer.new()
	page.add_theme_constant_override(
		"separation", _scaled(PlugUIConstants.SEPARATION_LARGE)
	)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cache_labels.clear()
	var repo_path := GitManager.get_plugged_dir()
	var release_path := ReleaseCache.get_cache_root()
	var sections: Array[Dictionary] = [
		{
			"title_key": "CACHE_SECTION_REPO",
			"path": repo_path,
			"btn_key": "BTN_CLEAR_CACHE",
			"callback": _on_clear_repo_cache,
			"path_ref": "repo",
		},
		{
			"title_key": "CACHE_SECTION_RELEASE",
			"path": release_path,
			"btn_key": "BTN_CLEAR_CACHE",
			"callback": _on_clear_release_cache,
			"path_ref": "release",
		},
	]
	for sec in sections:
		var outer = MarginContainer.new()
		var panel = PanelContainer.new()
		outer.add_child(panel)
		var inner = MarginContainer.new()
		var pad := _scaled(8)
		inner.add_theme_constant_override("margin_left", pad)
		inner.add_theme_constant_override("margin_right", pad)
		inner.add_theme_constant_override("margin_top", pad)
		inner.add_theme_constant_override("margin_bottom", pad)
		panel.add_child(inner)
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override(
			"separation",
			_scaled(PlugUIConstants.SEPARATION_STANDARD),
		)
		var title_hbox = HBoxContainer.new()
		title_hbox.add_theme_constant_override(
			"separation",
			_scaled(PlugUIConstants.SEPARATION_STANDARD),
		)
		var title = Label.new()
		title.text = tr(sec["title_key"])
		title.add_theme_color_override("font_color", COLOR_URL)
		title_hbox.add_child(title)
		_cache_labels.append(
			{"label": title, "i18n_key": sec["title_key"]}
		)
		var btn = Button.new()
		btn.text = tr(sec["btn_key"])
		btn.pressed.connect(sec["callback"])
		if sec["path_ref"] == "repo":
			_cache_clear_repo_btn = btn
		else:
			_cache_clear_release_btn = btn
		title_hbox.add_child(btn)
		vbox.add_child(title_hbox)
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override(
			"separation",
			_scaled(PlugUIConstants.SEPARATION_STANDARD),
		)
		var path_key = Label.new()
		path_key.text = tr("CACHE_PATH")
		path_key.add_theme_color_override(
			"font_color", COLOR_UNKNOWN
		)
		hbox.add_child(path_key)
		_cache_labels.append(
			{"label": path_key, "i18n_key": "CACHE_PATH"}
		)
		var path_val = Label.new()
		path_val.text = sec["path"]
		path_val.clip_text = true
		path_val.text_overrun_behavior = (
			TextServer.OVERRUN_TRIM_ELLIPSIS
		)
		path_val.tooltip_text = sec["path"]
		path_val.size_flags_horizontal = (
			Control.SIZE_EXPAND_FILL
		)
		path_val.mouse_filter = Control.MOUSE_FILTER_STOP
		path_val.mouse_default_cursor_shape = (
			Control.CURSOR_POINTING_HAND
		)
		var open_path: String = sec["path"]
		path_val.gui_input.connect(
			func(event: InputEvent):
				if (
					event is InputEventMouseButton
					and event.pressed
					and event.button_index == MOUSE_BUTTON_LEFT
				):
					OS.shell_open(open_path)
		)
		hbox.add_child(path_val)
		if sec["path_ref"] == "repo":
			_cache_repo_path_label = path_val
		else:
			_cache_release_path_label = path_val
		vbox.add_child(hbox)
		inner.add_child(vbox)
		page.add_child(outer)
	return page


func _on_clear_repo_cache() -> void:
	_clear_cache_async(
		GitManager.get_plugged_dir(), _cache_clear_repo_btn
	)


func _on_clear_release_cache() -> void:
	_clear_cache_async(
		ReleaseCache.get_cache_root(), _cache_clear_release_btn
	)


func _clear_cache_async(path: String, btn: Button) -> void:
	if btn:
		btn.disabled = true
		btn.text = tr("BTN_CLEARING_CACHE")
	WorkerThreadPool.add_task(
		func():
			if DirAccess.dir_exists_absolute(path):
				GitManager.delete_directory(path)
				DirAccess.make_dir_recursive_absolute(path)
			call_deferred("_on_cache_cleared", btn)
	)


func _on_cache_cleared(btn: Button) -> void:
	if btn:
		btn.disabled = false
		btn.text = tr("BTN_CLEAR_CACHE")
	_show_toast(tr("TOAST_CACHE_CLEARED"))


func _build_about_category_panel() -> Control:
	var page = VBoxContainer.new()
	page.add_theme_constant_override(
		"separation", _scaled(PlugUIConstants.SEPARATION_LARGE)
	)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var outer = MarginContainer.new()
	var panel = PanelContainer.new()
	outer.add_child(panel)
	var inner_margin = MarginContainer.new()
	var pad := _scaled(8)
	inner_margin.add_theme_constant_override("margin_left", pad)
	inner_margin.add_theme_constant_override("margin_right", pad)
	inner_margin.add_theme_constant_override("margin_top", pad)
	inner_margin.add_theme_constant_override("margin_bottom", pad)
	panel.add_child(inner_margin)
	var cfg := ConfigFile.new()
	cfg.load("res://addons/gd-plug-plus/plugin.cfg")
	var plugin_name: String = cfg.get_value("plugin", "name", "gd-plug-plus")
	var plugin_ver: String = cfg.get_value("plugin", "version", "--")
	var plugin_author: String = cfg.get_value("plugin", "author", "--")
	var plugin_desc: String = cfg.get_value("plugin", "description", "--")
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", _scaled(PlugUIConstants.DETAIL_H_SEPARATION))
	grid.add_theme_constant_override("v_separation", _scaled(PlugUIConstants.DETAIL_V_SEPARATION))
	var field_keys: Array[String] = [
		"ABOUT_PLUGIN_NAME", "ABOUT_VERSION", "ABOUT_AUTHOR", "ABOUT_DESCRIPTION",
	]
	var field_vals: Array[String] = [plugin_name, plugin_ver, plugin_author, plugin_desc]
	_about_labels.clear()
	for i in range(field_keys.size()):
		var key_label = Label.new()
		key_label.text = tr(field_keys[i])
		key_label.add_theme_color_override("font_color", COLOR_UNKNOWN)
		grid.add_child(key_label)
		_about_labels.append({"label": key_label, "i18n_key": field_keys[i]})
		var val_label = Label.new()
		val_label.text = field_vals[i]
		val_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		val_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(val_label)
	var homepage := "https://github.com/huzz-open/gd-plug-plus"
	var home_key_label = Label.new()
	home_key_label.text = tr("ABOUT_HOMEPAGE")
	home_key_label.add_theme_color_override("font_color", COLOR_UNKNOWN)
	grid.add_child(home_key_label)
	_about_labels.append({"label": home_key_label, "i18n_key": "ABOUT_HOMEPAGE"})
	var home_val = Label.new()
	home_val.text = homepage
	home_val.add_theme_color_override("font_color", Color(0.45, 0.65, 1.0))
	home_val.mouse_filter = Control.MOUSE_FILTER_STOP
	home_val.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	home_val.gui_input.connect(
		func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				OS.shell_open(homepage)
	)
	grid.add_child(home_val)
	inner_margin.add_child(grid)
	page.add_child(outer)
	return page


func _build_settings_header(parent: VBoxContainer) -> void:
	var outer = MarginContainer.new()
	var panel = PanelContainer.new()
	outer.add_child(panel)
	var inner_margin = MarginContainer.new()
	var pad := _scaled(8)
	inner_margin.add_theme_constant_override("margin_left", pad)
	inner_margin.add_theme_constant_override("margin_right", pad)
	inner_margin.add_theme_constant_override("margin_top", pad)
	inner_margin.add_theme_constant_override("margin_bottom", pad)
	panel.add_child(inner_margin)
	var token_dir := TokenStore.get_global_config_path().get_base_dir()
	var desc_rtl = RichTextLabel.new()
	desc_rtl.bbcode_enabled = true
	desc_rtl.fit_content = true
	desc_rtl.scroll_active = false
	desc_rtl.text = _build_header_bbcode(token_dir)
	desc_rtl.meta_clicked.connect(func(meta): OS.shell_open(str(meta)))
	inner_margin.add_child(desc_rtl)
	_settings_header_rtl = desc_rtl
	parent.add_child(outer)


func _build_header_bbcode(token_dir: String) -> String:
	return (
		"%s [url=%s][u]%s[/u][/url]"
		% [tr("SETTINGS_DESC_TOKENS"), token_dir, tr("SETTINGS_LINK_VIEW")]
	)


## Returns the OUTER MarginContainer wrapping the platform PanelContainer. The
## wrapper exists so flash modulate (in `_focus_settings_tab`) animates only the
## panel area, not the surrounding settings_content separation. The dictionary
## `_settings_platform_panels` stores this outer wrapper for use by both
## `ensure_control_visible` and the tween target.
func _build_platform_panel(key: String) -> Control:
	var meta := TokenStore.get_platform_meta(key)
	var outer = MarginContainer.new()
	var panel = PanelContainer.new()
	outer.add_child(panel)
	var inner_margin = MarginContainer.new()
	var pad := _scaled(8)
	inner_margin.add_theme_constant_override("margin_left", pad)
	inner_margin.add_theme_constant_override("margin_right", pad)
	inner_margin.add_theme_constant_override("margin_top", pad)
	inner_margin.add_theme_constant_override("margin_bottom", pad)
	panel.add_child(inner_margin)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _scaled(6))
	inner_margin.add_child(vbox)
	var row_state_device: Dictionary = {}

	# Header: clickable platform name (apply URL) + device login + status icon + Validate.
	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", _scaled(8))
	var apply_url: String = meta.get("apply_url", meta.get("settings_url", ""))
	var name_link = LinkButton.new()
	name_link.text = meta.get("display_name", key.capitalize())
	name_link.tooltip_text = tr("PLATFORM_LINK_TOOLTIP")
	name_link.add_theme_font_size_override("font_size", _scaled(14))
	name_link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	name_link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_link.pressed.connect(func(): OS.shell_open(apply_url))
	head.add_child(name_link)
	if TokenStore.supports_device_flow(key):
		var login_btn = Button.new()
		login_btn.text = tr("BTN_DEVICE_FLOW_LOGIN")
		login_btn.pressed.connect(_on_device_flow_login.bind(key))
		head.add_child(login_btn)
		row_state_device = {"device_btn": login_btn, "device_dialog": null, "device_uri": ""}
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var status_icon = Label.new()
	status_icon.add_theme_font_size_override("font_size", _scaled(14))
	head.add_child(status_icon)
	var validate_btn = Button.new()
	validate_btn.text = tr("BTN_VALIDATE")
	validate_btn.pressed.connect(_on_pat_validate.bind(key))
	head.add_child(validate_btn)
	vbox.add_child(head)

	# Token row: secret LineEdit pre-filled with current token (any non-empty
	# value implies "configured"); Save / Clear act on the input contents.
	var pat_row = HBoxContainer.new()
	pat_row.add_theme_constant_override(
		"separation", _scaled(PlugUIConstants.SEPARATION_STANDARD)
	)
	var pat_input = LineEdit.new()
	pat_input.placeholder_text = tr("TOKEN_PAT_PLACEHOLDER")
	pat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pat_input.text_changed.connect(_on_pat_input_changed.bind(key))
	pat_input.focus_entered.connect(_on_pat_input_focus_entered.bind(key))
	pat_input.focus_exited.connect(_on_pat_input_focus_exited.bind(key))
	pat_row.add_child(pat_input)
	var save_btn = Button.new()
	save_btn.text = tr("BTN_SAVE")
	save_btn.pressed.connect(_on_pat_save.bind(key))
	pat_row.add_child(save_btn)
	var clear_btn = Button.new()
	clear_btn.text = tr("BTN_CLEAR")
	clear_btn.pressed.connect(_on_pat_clear.bind(key))
	pat_row.add_child(clear_btn)
	vbox.add_child(pat_row)

	var row_state: Dictionary = {
		"name_link": name_link,
		"pat_input": pat_input,
		"save_btn": save_btn,
		"clear_btn": clear_btn,
		"validate_btn": validate_btn,
		"status_icon": status_icon,
		"validation_state": "UNKNOWN",
		"validate_http": null,
		"user_edited": false,
	}

	if not row_state_device.is_empty():
		row_state.merge(row_state_device)
	_settings_platform_rows[key] = row_state
	return outer


## Repaints status_icon + token input for `key`. When the input does NOT have
## focus the masked form (head/tail visible) is shown; while focused the field
## is cleared so the user can paste a new token directly.
func _refresh_platform_row(key: String) -> void:
	if not release_manager:
		return
	var row: Dictionary = _settings_platform_rows.get(key, {})
	if row.is_empty():
		return
	var ts: TokenStore = release_manager.get_token_store()
	var stored: String = ts.get_token(key)
	var input: LineEdit = row["pat_input"]
	if not input.has_focus():
		_settings_refreshing = true
		input.text = ts.get_masked_token(key) if not stored.is_empty() else ""
		_settings_refreshing = false
		row["user_edited"] = false
	var has_token: bool = not stored.is_empty()
	(row["validate_btn"] as Button).disabled = not has_token
	_paint_status_icon(row, has_token)


## Pure UI helper. Reads `validation_state` and `has_token` from `row` and
## writes the icon glyph + colour + tooltip. Kept separate from
## `_refresh_platform_row` so validation callbacks can repaint without
## re-touching the input field (which the user may be editing).
func _paint_status_icon(row: Dictionary, has_token: bool) -> void:
	var icon: Label = row["status_icon"]
	var state: String = row.get("validation_state", "UNKNOWN")
	if not has_token:
		icon.text = tr("STATUS_VALIDATE_NONE")
		icon.tooltip_text = tr("STATUS_VALIDATE_NONE_TOOLTIP")
		icon.add_theme_color_override("font_color", COLOR_UNKNOWN)
		return
	match state:
		"OK":
			icon.text = tr("STATUS_VALIDATE_OK")
			icon.tooltip_text = tr("STATUS_VALIDATE_OK_TOOLTIP")
			icon.add_theme_color_override("font_color", COLOR_UP_TO_DATE)
		"FAIL":
			icon.text = tr("STATUS_VALIDATE_FAIL")
			icon.tooltip_text = row.get(
				"validation_error_tooltip", tr("STATUS_VALIDATE_FAIL_TOOLTIP")
			)
			icon.add_theme_color_override("font_color", COLOR_CONFLICT)
		"PENDING":
			icon.text = tr("STATUS_VALIDATE_PENDING")
			icon.tooltip_text = tr("STATUS_VALIDATE_PENDING_TOOLTIP")
			icon.add_theme_color_override("font_color", COLOR_CHECKING)
		_:  # UNKNOWN
			icon.text = tr("STATUS_VALIDATE_UNKNOWN")
			icon.tooltip_text = tr("STATUS_VALIDATE_UNKNOWN_TOOLTIP")
			icon.add_theme_color_override("font_color", COLOR_UNKNOWN)


func _refresh_all_platform_rows() -> void:
	for key in _settings_platform_rows.keys():
		_refresh_platform_row(key)


## Re-applies tr() to every dynamically built widget in the Settings tab. Called
## from _apply_translations on locale change. Validation state strings (OK/FAIL/
## UNKNOWN) are repainted via _refresh_all_platform_rows() at the bottom so the
## tooltip text follows the new locale even mid-session.
func _retranslate_settings_tab() -> void:
	for cat_key in _settings_categories.keys():
		var entry: Dictionary = _settings_categories[cat_key]
		(entry["button"] as Button).text = tr(entry["i18n_key"])
	for plat_key in _settings_platform_rows.keys():
		var row: Dictionary = _settings_platform_rows[plat_key]
		if row.has("name_link"):
			(row["name_link"] as LinkButton).tooltip_text = tr("PLATFORM_LINK_TOOLTIP")
		if row.has("pat_input"):
			(row["pat_input"] as LineEdit).placeholder_text = tr("TOKEN_PAT_PLACEHOLDER")
		if row.has("save_btn"):
			(row["save_btn"] as Button).text = tr("BTN_SAVE")
		if row.has("clear_btn"):
			(row["clear_btn"] as Button).text = tr("BTN_CLEAR")
		if row.has("validate_btn"):
			(row["validate_btn"] as Button).text = tr("BTN_VALIDATE")
		if row.has("device_btn"):
			(row["device_btn"] as Button).text = tr("BTN_DEVICE_FLOW_LOGIN")
	if _settings_header_rtl:
		var token_dir := TokenStore.get_global_config_path().get_base_dir()
		_settings_header_rtl.text = _build_header_bbcode(token_dir)
	for entry in _about_labels:
		(entry["label"] as Label).text = tr(entry["i18n_key"])
	for entry in _cache_labels:
		(entry["label"] as Label).text = tr(entry["i18n_key"])
	if _cache_clear_repo_btn:
		_cache_clear_repo_btn.text = tr("BTN_CLEAR_CACHE")
	if _cache_clear_release_btn:
		_cache_clear_release_btn.text = tr("BTN_CLEAR_CACHE")
	_refresh_all_platform_rows()


## When the input gains focus, clear the masked display so the user can
## directly paste a new token without having to manually select-all first.
func _on_pat_input_focus_entered(key: String) -> void:
	var row: Dictionary = _settings_platform_rows.get(key, {})
	if row.is_empty():
		return
	var input: LineEdit = row["pat_input"]
	_settings_refreshing = true
	input.text = ""
	_settings_refreshing = false
	input.placeholder_text = tr("TOKEN_PAT_PLACEHOLDER")


## When the input loses focus and is still empty, restore the masked display
## of the currently stored token (if any).
func _on_pat_input_focus_exited(key: String) -> void:
	var row: Dictionary = _settings_platform_rows.get(key, {})
	if row.is_empty():
		return
	var input: LineEdit = row["pat_input"]
	if input.text.strip_edges().is_empty():
		row["user_edited"] = false
		_refresh_platform_row(key)


## Editing the token in the LineEdit invalidates the previous validation
## verdict — we don't know whether the *new* string is valid until the user
## clicks Validate, so revert the icon to UNKNOWN.
func _on_pat_input_changed(_new_text: String, key: String) -> void:
	if _settings_refreshing:
		return
	var row: Dictionary = _settings_platform_rows.get(key, {})
	if row.is_empty():
		return
	row["user_edited"] = true
	row["validation_state"] = "UNKNOWN"
	row.erase("validation_error_tooltip")
	_paint_status_icon(row, not _new_text.strip_edges().is_empty())


func _on_pat_save(platform_key: String) -> void:
	var row: Dictionary = _settings_platform_rows.get(platform_key, {})
	if row.is_empty():
		return
	var input: LineEdit = row["pat_input"]
	var token: String = input.text.strip_edges()
	if token.is_empty():
		_show_toast(tr("TOAST_TOKEN_EMPTY"))
		return
	if not row.get("user_edited", false):
		return
	release_manager.get_token_store().set_token(platform_key, token)
	row["validation_state"] = "UNKNOWN"
	row.erase("validation_error_tooltip")
	_refresh_platform_row(platform_key)
	_show_toast(tr("TOAST_TOKEN_SAVED"))


func _on_pat_clear(platform_key: String) -> void:
	release_manager.get_token_store().clear_token(platform_key)
	var row: Dictionary = _settings_platform_rows.get(platform_key, {})
	if not row.is_empty():
		(row["pat_input"] as LineEdit).text = ""
		row["validation_state"] = "UNKNOWN"
		row.erase("validation_error_tooltip")
	_refresh_platform_row(platform_key)
	_show_toast(tr("TOAST_TOKEN_CLEARED"))


# ===========================================================================
# Token validation (Settings tab "检测" button)
# ===========================================================================


## Issues a single API call to a permission-free endpoint (provider-defined,
## see ReleaseProvider.get_validate_url) and updates the row's status icon
## based on the HTTP response. Runs entirely on a per-row HTTPRequest so
## validating multiple platforms in parallel never crosses signals.
func _on_pat_validate(key: String) -> void:
	var row: Dictionary = _settings_platform_rows.get(key, {})
	if row.is_empty():
		return
	var ts: TokenStore = release_manager.get_token_store()
	var token: String = ts.get_token(key)
	if token.is_empty():
		_show_toast(tr("TOAST_TOKEN_EMPTY"))
		return
	var provider: ReleaseProvider = ProviderFactory.create_by_key(key)
	if provider == null:
		_show_toast(tr("ERR_TOKEN_VALIDATE_NETWORK"), true)
		return
	var url: String = provider.get_validate_url(token)
	if url.is_empty():
		_show_toast(tr("ERR_TOKEN_VALIDATE_NETWORK"), true)
		return
	var headers_dict: Dictionary = provider.get_api_headers(token)
	var headers: PackedStringArray = []
	for h_key in headers_dict.keys():
		headers.append("%s: %s" % [h_key, headers_dict[h_key]])

	var http: HTTPRequest = row.get("validate_http", null)
	if http == null or not is_instance_valid(http):
		http = HTTPRequest.new()
		ProxyConfig.apply_to_http(http)
		add_child(http)
		row["validate_http"] = http
	http.cancel_request()
	# CONNECT_ONE_SHOT prevents stale callbacks if the user spams Validate
	# while a previous request is still in flight (cancel_request above
	# guarantees the previous handler is detached anyway).
	if http.request_completed.is_connected(_on_pat_validate_response):
		http.request_completed.disconnect(_on_pat_validate_response)
	http.request_completed.connect(_on_pat_validate_response.bind(key), CONNECT_ONE_SHOT)
	row["validation_state"] = "PENDING"
	row.erase("validation_error_tooltip")
	_paint_status_icon(row, true)
	(row["validate_btn"] as Button).disabled = true
	PlugLogger.debug(
		"[TokenValidate] platform=%s url=%s headers=%s" % [key, url, str(headers)]
	)
	var err := http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		row["validation_state"] = "FAIL"
		row["validation_error_tooltip"] = (
			tr("STATUS_VALIDATE_FAIL_TOOLTIP")
			+ "\n"
			+ tr("ERR_TOKEN_VALIDATE_NETWORK")
		)
		(row["validate_btn"] as Button).disabled = false
		_paint_status_icon(row, true)


func _on_pat_validate_response(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	key: String
) -> void:
	var row: Dictionary = _settings_platform_rows.get(key, {})
	if row.is_empty():
		return
	var body_str: String = body.get_string_from_utf8().left(512)
	PlugLogger.debug(
		"[TokenValidate] platform=%s result=%d http=%d body=%s"
		% [key, result, response_code, body_str]
	)
	(row["validate_btn"] as Button).disabled = false
	if result != HTTPRequest.RESULT_SUCCESS:
		row["validation_state"] = "FAIL"
		row["validation_error_tooltip"] = (
			tr("STATUS_VALIDATE_FAIL_TOOLTIP")
			+ "\n"
			+ tr("ERR_TOKEN_VALIDATE_NETWORK")
		)
		_paint_status_icon(row, true)
		return
	if response_code >= 200 and response_code < 300:
		row["validation_state"] = "OK"
		row.erase("validation_error_tooltip")
		_paint_status_icon(row, true)
		return
	row["validation_state"] = "FAIL"
	row["validation_error_tooltip"] = (
		tr("STATUS_VALIDATE_FAIL_TOOLTIP")
		+ "\n"
		+ tr("ERR_TOKEN_VALIDATE_HTTP").format({"code": response_code})
	)
	_paint_status_icon(row, true)


# ===========================================================================
# GitHub Device Flow integration (Settings tab only)
# ===========================================================================


## Click handler for "使用 GitHub 登录". Builds a modal AcceptDialog *first*
## (so the UI shows immediate feedback) and then kicks off the device-code
## request. The dialog is filled with user_code/uri once
## `_on_device_flow_code_received` fires; closing the dialog by any means
## (X button, ESC, OK button) cancels the in-flight flow.
func _on_device_flow_login(key: String) -> void:
	if key != "github":
		return
	var ts: TokenStore = release_manager.get_token_store()
	var client_id: String = ts.get_client_id(key)
	if client_id.is_empty():
		_show_toast(tr("ERR_TOKEN_NO_CLIENT_ID"), true)
		return
	# Tear down any leftover dialog from a previous flow.
	_close_device_dialog()
	var dialog := _build_device_flow_dialog()
	var row: Dictionary = _settings_platform_rows.get(key, {})
	row["device_dialog"] = dialog
	(row["device_btn"] as Button).disabled = true
	add_child(dialog)
	dialog.popup_centered()
	_set_device_dialog_status(tr("DEVICE_FLOW_STATUS_REQUESTING"))
	_device_flow.start(client_id)


## Builds the modal dialog skeleton. Content (user_code, verification_uri) is
## populated on `_on_device_flow_code_received`. Layout:
##
##   AcceptDialog "GitHub Device Flow Login"
##     VBox (margins)
##       Label   tr(DEVICE_FLOW_DLG_INSTRUCT)
##       LinkButton verification_uri  ← live, opens shell on click
##       HBox  [ user_code (large)        ] [Copy]
##       HBox  [Open Browser]              [        spacer        ]
##       Label tr(DEVICE_FLOW_STATUS_*)   ← live status line
##     ok_button.text = "Cancel"
##
## Both `confirmed` (OK button) and `close_requested` (X / ESC) are wired to
## `_on_device_dialog_dismissed` — so closing the dialog by any means is
## treated as "user cancelled the flow".
func _build_device_flow_dialog() -> AcceptDialog:
	var dlg_w := _scaled(400)
	var dialog := AcceptDialog.new()
	dialog.title = tr("DEVICE_FLOW_DLG_TITLE")
	dialog.get_ok_button().text = tr("BTN_DEVICE_FLOW_CANCEL")

	var margin := MarginContainer.new()
	var pad := _scaled(6)
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	dialog.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _scaled(4))
	margin.add_child(vbox)

	var instruct := Label.new()
	instruct.text = tr("DEVICE_FLOW_DLG_INSTRUCT")
	instruct.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruct.custom_minimum_size.x = dlg_w - pad * 2
	vbox.add_child(instruct)

	var uri_link := LinkButton.new()
	uri_link.text = ""
	uri_link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	uri_link.pressed.connect(_open_device_uri)
	vbox.add_child(uri_link)

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", _scaled(4))
	var code_label := Label.new()
	code_label.text = ""
	code_label.add_theme_font_size_override("font_size", _scaled(20))
	code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_row.add_child(code_label)
	var copy_btn := Button.new()
	copy_btn.text = tr("BTN_COPY")
	copy_btn.pressed.connect(_on_device_dialog_copy)
	code_row.add_child(copy_btn)
	vbox.add_child(code_row)

	var open_btn := Button.new()
	open_btn.text = tr("BTN_OPEN_BROWSER")
	open_btn.pressed.connect(_open_device_uri)
	vbox.add_child(open_btn)

	var status := Label.new()
	status.text = tr("DEVICE_FLOW_STATUS_REQUESTING")
	status.add_theme_font_size_override("font_size", _scaled(11))
	vbox.add_child(status)

	dialog.set_meta("uri_link", uri_link)
	dialog.set_meta("code_label", code_label)
	dialog.set_meta("copy_btn", copy_btn)
	dialog.set_meta("open_btn", open_btn)
	dialog.set_meta("status_label", status)

	dialog.confirmed.connect(_on_device_dialog_dismissed)
	dialog.close_requested.connect(_on_device_dialog_dismissed)
	dialog.min_size = Vector2i(dlg_w, 0)
	return dialog


func _set_device_dialog_status(text: String) -> void:
	var row: Dictionary = _settings_platform_rows.get("github", {})
	var dlg = row.get("device_dialog", null)
	if dlg == null or not is_instance_valid(dlg):
		return
	var status_lbl = dlg.get_meta("status_label", null)
	if status_lbl is Label:
		status_lbl.text = text


func _on_device_flow_code_received(
	user_code: String, verification_uri: String, _expires_in: int
) -> void:
	var key := "github"
	var row: Dictionary = _settings_platform_rows.get(key, {})
	if row.is_empty():
		return
	row["device_uri"] = verification_uri
	var dlg = row.get("device_dialog", null)
	if dlg == null or not is_instance_valid(dlg):
		return
	(dlg.get_meta("uri_link") as LinkButton).text = verification_uri
	(dlg.get_meta("code_label") as Label).text = user_code
	_set_device_dialog_status(tr("DEVICE_FLOW_STATUS_WAITING_USER"))
	# Auto-open the browser as soon as we have a URI; the manual button is a
	# fallback for headless/sandboxed environments where shell_open silently
	# fails.
	OS.shell_open(verification_uri)


func _open_device_uri() -> void:
	var row: Dictionary = _settings_platform_rows.get("github", {})
	if row.is_empty():
		return
	var uri: String = row.get("device_uri", "")
	if not uri.is_empty():
		OS.shell_open(uri)


func _on_device_dialog_copy() -> void:
	var row: Dictionary = _settings_platform_rows.get("github", {})
	var dlg = row.get("device_dialog", null)
	if dlg == null or not is_instance_valid(dlg):
		return
	var code_label = dlg.get_meta("code_label", null)
	if code_label is Label:
		DisplayServer.clipboard_set(code_label.text)
	var copy_btn_ref = dlg.get_meta("copy_btn", null)
	if copy_btn_ref is Button:
		var original_text: String = copy_btn_ref.text
		copy_btn_ref.text = tr("BTN_COPIED")
		copy_btn_ref.disabled = true
		get_tree().create_timer(1.5).timeout.connect(func():
			if is_instance_valid(copy_btn_ref):
				copy_btn_ref.text = original_text
				copy_btn_ref.disabled = false
		)


## Closing the dialog (OK button OR X / ESC) is unconditionally treated as
## "user cancelled the device flow". `_device_flow.cancel()` is idempotent;
## it's safe even if the flow already finished (succeeded/failed) and we are
## tearing the dialog down ourselves.
func _on_device_dialog_dismissed() -> void:
	if _device_flow:
		_device_flow.cancel()
	_close_device_dialog()
	var row: Dictionary = _settings_platform_rows.get("github", {})
	if not row.is_empty() and row.has("device_btn"):
		(row["device_btn"] as Button).disabled = false


func _close_device_dialog() -> void:
	var row: Dictionary = _settings_platform_rows.get("github", {})
	if row.is_empty():
		return
	var dlg = row.get("device_dialog", null)
	if dlg != null and is_instance_valid(dlg):
		dlg.hide()
		dlg.queue_free()
	row["device_dialog"] = null


func _on_device_flow_succeeded(token: String) -> void:
	var key := "github"
	release_manager.get_token_store().set_token(key, token)
	var row: Dictionary = _settings_platform_rows.get(key, {})
	if not row.is_empty():
		row["validation_state"] = "UNKNOWN"
		row.erase("validation_error_tooltip")
		# Suppress _on_device_dialog_dismissed → cancel reentry by clearing
		# the reference *before* hide(); cancel() on an already-finished
		# flow is a no-op anyway, but this keeps the intent explicit.
		_close_device_dialog()
		(row["device_btn"] as Button).disabled = false
	_refresh_platform_row(key)


func _on_device_flow_failed(error_key: String, _message: String) -> void:
	var key := "github"
	_close_device_dialog()
	var row: Dictionary = _settings_platform_rows.get(key, {})
	if not row.is_empty() and row.has("device_btn"):
		(row["device_btn"] as Button).disabled = false
	_show_toast(
		tr("DEVICE_FLOW_STATUS_FAILED").format({"err": tr(error_key)}), true
	)


# ===========================================================================
# Settings tab navigation (used by pre-check redirect)
# ===========================================================================


func _focus_settings_tab(platform_key: String) -> void:
	tab_container.current_tab = 2
	# Platforms only live in the "auth" category for now. If we add more
	# categories that host platforms, map platform_key -> category here.
	_select_settings_category("auth")
	if platform_key.is_empty():
		return
	var outer = _settings_platform_panels.get(platform_key)
	if outer == null:
		return
	var scroll: ScrollContainer = $"TabContainer/Settings/SettingsContentScroll"
	await get_tree().process_frame
	if is_instance_valid(scroll) and is_instance_valid(outer):
		scroll.ensure_control_visible(outer)
	if _settings_flash_tween and _settings_flash_tween.is_valid():
		_settings_flash_tween.kill()
	outer.modulate = Color(1.4, 1.4, 0.7, 1.0)
	_settings_flash_tween = create_tween()
	_settings_flash_tween.tween_property(outer, "modulate", Color.WHITE, 0.8)


func _is_url_like(text: String) -> bool:
	if text.begins_with("http://") or text.begins_with("https://") or text.begins_with("git@"):
		return true
	if "/" in text and " " not in text:
		return true
	return false


func _on_SearchBtn_pressed():
	if _tree_mode == TreeMode.SEARCHING:
		_on_CancelSearchBtn_pressed()
		return
	var text = search_input.text.strip_edges()
	if text.is_empty():
		_refresh_unified_tree("")
		return
	if _is_url_like(text):
		_on_SearchUrlBtn_pressed()
	else:
		_refresh_unified_tree(text)


func _on_SearchInput_submitted(_text: String):
	_on_SearchBtn_pressed()


func _on_CancelSearchBtn_pressed():
	_search_cancelled = true
	GitManager.request_cancel()
	if release_manager:
		release_manager.cancel()
		_disconnect_release_signals()
	_search_overlay.visible = false
	_search_btn.disabled = false
	_search_btn.text = tr("BTN_SEARCH")
	_tree_mode = TreeMode.AVAILABLE
	_release_search_pending = false
	_search_coordinator.reset(false)
	PlugLogger.info(_tr("LOG_SEARCH_CANCELLED"))


# ===========================================================================
# Status refresh for install-new tab
# ===========================================================================


func _update_search_tree_install_status():
	var root = search_tree.get_root()
	if root == null:
		return
	var existing_addons = _get_existing_addons()
	var child = root.get_first_child()
	while child:
		var repo_url = ""
		if child.has_meta("repo"):
			repo_url = child.get_meta("repo")
		elif child.has_meta("addon_info"):
			repo_url = _search_url
		if not repo_url.is_empty():
			var rn = GitManager.repo_name_from_url(repo_url)
			var is_installing = rn in _installing_repos
			var is_installed = addon_data.has_repo(rn)
			if is_installing:
				child.set_text(1, tr("STATUS_INSTALLING"))
				child.set_custom_color(1, COLOR_CHECKING)
			else:
				child.set_text(
					1, tr("STATUS_INSTALLED") if is_installed else tr("STATUS_NOT_INSTALLED")
				)
				child.set_custom_color(1, COLOR_UP_TO_DATE if is_installed else COLOR_UNKNOWN)
			if child.has_meta("addon_info"):
				child.set_editable(0, not is_installed and not is_installing)
				var info: Dictionary = child.get_meta("addon_info")
				var pdir: String = info.get("addon_dir", "")
				var has_conflict := false
				if not pdir.is_empty() and not is_installed and not is_installing:
					has_conflict = not (
						addon_data.check_dir_conflicts([pdir], existing_addons).is_empty()
					)
				child.set_meta("has_conflict", has_conflict)
				if is_installing:
					child.clear_custom_color(2)
					child.set_tooltip_text(2, repo_url)
				elif is_installed:
					child.set_checked(0, false)
					child.clear_custom_color(2)
					child.set_tooltip_text(2, repo_url)
					_refresh_available_item_from_installed(child, rn, pdir)
				elif has_conflict:
					child.set_custom_color(2, COLOR_CONFLICT)
					child.set_tooltip_text(2, repo_url + "\n" + tr("CONFLICT_DIR_EXISTS") % pdir)
					child.set_checked(0, false)
				else:
					child.clear_custom_color(2)
					child.set_tooltip_text(2, repo_url)
		child = child.get_next()


func _refresh_available_item_from_installed(item: TreeItem, repo_name: String, addon_dir: String):
	var installed_addons = addon_data.get_installed_addons(repo_name)
	var match_addon: Dictionary = {}
	for p in installed_addons:
		if p.get("addon_dir", "") == addon_dir:
			match_addon = p
			break
	if match_addon.is_empty() and not installed_addons.is_empty():
		match_addon = installed_addons[0]
	if match_addon.is_empty():
		return

	var ver: String = match_addon.get("version", "")
	item.set_text(3, _format_version(ver, "--"))
	item.set_text_alignment(3, HORIZONTAL_ALIGNMENT_CENTER)

	var is_release_installed: bool = match_addon.get("installed_from", "") == "release"
	if is_release_installed:
		var installed_tag: String = match_addon.get("installed_tag", "")
		var installed_asset: String = match_addon.get("installed_asset_filename", "")
		item.set_text(5, installed_tag if not installed_tag.is_empty() else "--")
		item.set_custom_color(5, COLOR_UPDATED)
		item.set_text_alignment(5, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_tooltip_text(5, tr("BRANCH_CLICK_HINT"))
		item.set_text(6, "--")
		item.set_custom_color(6, COLOR_UPDATED)
		item.set_text_alignment(6, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_meta("from_release", true)
		item.set_meta("selected_branch", "")
		item.set_meta("selected_tag", installed_tag)
		item.set_meta("selected_commit", "")
		item.set_meta("release_asset_filename", installed_asset)

		var info: Dictionary = item.get_meta("addon_info", {}) if item.has_meta("addon_info") else {}
		info["_from_release"] = true
		info["_release_tag"] = installed_tag
		if not installed_asset.is_empty():
			info["_release_asset_filename"] = installed_asset
		var is_stub: bool = info.get("_release_is_stub", false) or addon_dir.is_empty()
		info["_release_is_stub"] = is_stub
		item.set_meta("addon_info", info)

		if is_stub:
			item.set_text(7, installed_asset)
			var stub_tip: String = _tr("RELEASE_ASSET_CLICK_HINT")
			if not installed_asset.is_empty():
				stub_tip = installed_asset + "\n" + stub_tip
			item.set_tooltip_text(7, stub_tip)
		else:
			item.set_text(7, addon_dir)
			var src_tip: String = _tr("RELEASE_ASSET_CLICK_HINT")
			if not installed_asset.is_empty():
				src_tip = installed_asset + "\n" + src_tip
			elif not addon_dir.is_empty():
				src_tip = addon_dir
			item.set_tooltip_text(7, src_tip)
		return

	var branch: String = match_addon.get("branch", "")
	var tag: String = match_addon.get("tag", "")
	item.set_text(5, _format_branch_tag(branch, tag))
	item.set_custom_color(5, COLOR_UPDATED)
	item.set_text_alignment(5, HORIZONTAL_ALIGNMENT_CENTER)

	var cached = _version_cache.get(repo_name, {})
	var commit_str: String = ""
	if cached.has("current_commit") and not cached["current_commit"].is_empty():
		commit_str = _short_commit(cached["current_commit"])
	elif not match_addon.get("commit", "").is_empty():
		commit_str = _short_commit(match_addon["commit"])
	item.set_text(6, commit_str if not commit_str.is_empty() else "--")
	item.set_custom_color(6, COLOR_UPDATED)
	item.set_text_alignment(6, HORIZONTAL_ALIGNMENT_CENTER)


func _set_checked_items_status(status_text: String, color: Color, tooltip: String = ""):
	var root = search_tree.get_root()
	if root == null:
		return
	var child = root.get_first_child()
	while child:
		if child.is_checked(0):
			child.set_text(1, status_text)
			child.set_custom_color(1, color)
			child.set_tooltip_text(1, tooltip)
			child.set_editable(0, false)
		child = child.get_next()


func _restore_checked_items_status():
	var root = search_tree.get_root()
	if root == null:
		return
	var child = root.get_first_child()
	while child:
		if child.is_checked(0):
			child.set_text(1, tr("STATUS_NOT_INSTALLED"))
			child.set_custom_color(1, COLOR_UNKNOWN)
			child.set_editable(0, true)
		child = child.get_next()


# ===========================================================================
# Detail dialog
# ===========================================================================


func _show_detail_dialog(repo_name: String):
	var repo = addon_data.get_repo(repo_name)
	if repo.is_empty():
		return
	var url: String = repo.get("url", "")
	var first_addon = _first_installed_or_first(repo.get("addons", []))
	var dialog = AcceptDialog.new()
	dialog.title = tr("DETAIL_TITLE")
	dialog.ok_button_text = tr("BTN_CLOSE")
	dialog.min_size = Vector2i(_scaled(PlugUIConstants.DETAIL_DIALOG_MIN_WIDTH), 0)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", _scaled(PlugUIConstants.DETAIL_H_SEPARATION))
	grid.add_theme_constant_override("v_separation", _scaled(PlugUIConstants.DETAIL_V_SEPARATION))
	var detail_asset: String = first_addon.get("installed_asset_filename", "")
	var detail_name: String = first_addon.get("name", "")
	var detail_is_release: bool = first_addon.get("installed_from", "") == "release"
	if detail_is_release and not detail_name.is_empty() and not detail_asset.is_empty():
		if detail_name == detail_asset.get_basename():
			detail_name = ""
	if detail_name.is_empty():
		detail_name = repo_name
	var detail_desc: String = first_addon.get("description", "")
	if detail_desc.is_empty() and detail_is_release and not detail_asset.is_empty():
		detail_desc = "Release " + detail_asset
	var fields = [
		[tr("DETAIL_NAME"), detail_name],
		[tr("DETAIL_DESC"), detail_desc],
		[tr("DETAIL_VERSION"), first_addon.get("version", "")],
		[tr("DETAIL_AUTHOR"), first_addon.get("author", "")],
		[tr("DETAIL_TYPE"), "Plugin" if first_addon.get("type", "") == "plugin" else "Extension"],
		[tr("DETAIL_URL"), url],
		[tr("DETAIL_INSTALL_PATH"), first_addon.get("addon_dir", "")],
		[tr("COL_BRANCH_TAG"), AddonData.get_version_label(first_addon)],
		[tr("COL_COMMIT"), _short_commit(first_addon.get("commit", ""))],
	]
	for f in fields:
		var key_label = Label.new()
		key_label.text = f[0] + ":"
		key_label.add_theme_color_override("font_color", COLOR_URL)
		grid.add_child(key_label)
		if f[0] == tr("DETAIL_URL") and not url.is_empty():
			var url_label = Label.new()
			url_label.text = url
			url_label.tooltip_text = url
			url_label.clip_text = true
			url_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			url_label.add_theme_color_override("font_color", COLOR_URL)
			url_label.mouse_filter = Control.MOUSE_FILTER_STOP
			url_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			url_label.custom_minimum_size = Vector2(_scaled(PlugUIConstants.DETAIL_LABEL_MIN_WIDTH), 0)
			url_label.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					OS.shell_open(url))
			grid.add_child(url_label)
		else:
			var val_label = Label.new()
			val_label.text = str(f[1])
			val_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			val_label.custom_minimum_size = Vector2(_scaled(PlugUIConstants.DETAIL_LABEL_MIN_WIDTH), 0)
			grid.add_child(val_label)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _scaled(PlugUIConstants.SEPARATION_LARGE))
	vbox.add_child(grid)
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


# ===========================================================================
# Search overlay
# ===========================================================================


func _setup_search_overlay():
	_search_overlay = CenterContainer.new()
	_search_overlay.visible = false
	_search_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_search_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", _scaled(PlugUIConstants.SEPARATION_STANDARD))
	_search_overlay.add_child(hbox)
	_search_spinner = TextureRect.new()
	_search_spinner.texture = preload("res://addons/gd-plug-plus/assets/icons/loading.svg")
	_search_spinner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_search_spinner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_search_spinner.custom_minimum_size = Vector2(
		_scaled(PlugUIConstants.SPINNER_SIZE), _scaled(PlugUIConstants.SPINNER_SIZE)
	)
	hbox.add_child(_search_spinner)
	_search_overlay_label = Label.new()
	_search_overlay_label.text = tr("SEARCHING")
	hbox.add_child(_search_overlay_label)
	search_result_panel.add_child(_search_overlay)


# ===========================================================================
# Console
# ===========================================================================


func _setup_console():
	_console_panel = PanelContainer.new()
	_console_panel.name = "ConsolePanel"
	_console_panel.anchor_top = 1.0
	_console_panel.anchor_bottom = 1.0
	_console_panel.anchor_left = 0.0
	_console_panel.anchor_right = 1.0
	_console_panel.offset_top = -_console_header_height
	_console_panel.offset_bottom = 0
	var vbox = VBoxContainer.new()
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", _scaled(PlugUIConstants.SEPARATION_STANDARD))
	_console_toggle_btn = Button.new()
	_console_toggle_btn.flat = true
	_console_toggle_btn.pressed.connect(_toggle_console)
	header.add_child(_console_toggle_btn)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_console_clear_btn = Button.new()
	_console_clear_btn.flat = true
	_console_clear_btn.pressed.connect(_clear_console)
	header.add_child(_console_clear_btn)
	vbox.add_child(header)
	_console_log = RichTextLabel.new()
	_console_log.scroll_following = true
	_console_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_console_log.selection_enabled = true
	_console_log.visible = false
	_console_log.add_theme_font_size_override(
		"normal_font_size", _scaled(PlugUIConstants.CONSOLE_FONT_SIZE)
	)
	vbox.add_child(_console_log)
	_console_panel.add_child(vbox)
	add_child(_console_panel)
	tab_container.offset_bottom = -_console_header_height
	move_child(loading_overlay, -1)


func _toggle_console():
	_console_collapsed = not _console_collapsed
	if _console_collapsed:
		_console_toggle_btn.text = tr("CONSOLE_COLLAPSED")
		_console_panel.offset_top = -_console_header_height
		_console_log.visible = false
		tab_container.offset_bottom = -_console_header_height
	else:
		_console_toggle_btn.text = tr("CONSOLE_EXPANDED")
		_console_panel.offset_top = -_console_expanded_height
		_console_log.visible = true
		tab_container.offset_bottom = -_console_expanded_height


func _clear_console():
	_console_log.clear()
	PlugLogger.clear()
	_last_log_count = 0


func _update_console():
	if _console_log == null:
		return
	var count = PlugLogger.get_log_count()
	if count > _last_log_count:
		var new_logs = PlugLogger.get_logs_since(_last_log_count)
		for entry in new_logs:
			_console_log.add_text(entry + "\n")
		_last_log_count = count


func _show_toast(msg: String, is_error: bool = false):
	var dialog = AcceptDialog.new()
	dialog.title = tr("TOAST_ERROR") if is_error else tr("TOAST_INFO")
	dialog.dialog_text = msg
	dialog.min_size = Vector2i(_scaled(PlugUIConstants.TOAST_MIN_WIDTH), 0)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


## Pre-check before starting a Release-enabled URL search: returns true if the
## platform's API token is configured (so search may proceed), or false after
## popping a "Token Required" dialog with a "Configure Now" path. Choosing
## Configure opens the Token Settings dialog and re-runs `_start_search`
## once the user closes it (regardless of whether they actually saved a
## token — the next attempt will hit the same check).
func _ensure_token_for_release(url: String) -> bool:
	if release_manager == null:
		return true
	var platform: String = ProviderFactory.detect_platform_key(url)
	if platform.is_empty():
		return true
	var ts: TokenStore = release_manager.get_token_store()
	if ts == null or ts.has_token(platform):
		return true
	_prompt_missing_token(platform, url)
	return false


func _prompt_missing_token(platform: String, _retry_url: String) -> void:
	var meta: Dictionary = TokenStore.get_platform_meta(platform)
	var display_name: String = meta.get("display_name", platform.capitalize())
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("TOAST_TOKEN_MISSING_TITLE")
	dialog.dialog_text = tr("TOAST_TOKEN_MISSING_BODY") % display_name
	dialog.ok_button_text = tr("BTN_GO_SETTINGS")
	dialog.get_cancel_button().text = tr("BTN_CANCEL")
	dialog.min_size = Vector2i(_scaled(PlugUIConstants.TOAST_MIN_WIDTH), 0)
	dialog.confirmed.connect(
		func():
			dialog.queue_free()
			_focus_settings_tab(platform)
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


## Confirmation dialog shown when a URL search returns zero addons AND the
## user has NOT ticked "Search Releases". Suggests retrying with releases on,
## since the repo might only publish the addon via GitHub Releases.
##
## OK → tick the checkbox + restart `_start_search(_search_url)`.
## Cancel → fall through; caller already updated UI for the empty result.
func _prompt_retry_with_release(no_result_msg: String) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = tr("TOAST_INFO")
	dialog.dialog_text = no_result_msg + "\n\n" + tr("CONFIRM_TRY_RELEASE")
	dialog.ok_button_text = tr("BTN_RETRY_WITH_RELEASE")
	dialog.get_cancel_button().text = tr("BTN_CANCEL")
	dialog.min_size = Vector2i(_scaled(PlugUIConstants.TOAST_MIN_WIDTH), 0)
	var url := _search_url
	dialog.confirmed.connect(
		func():
			_release_checkbox.button_pressed = true
			dialog.queue_free()
			_start_search(url)
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
