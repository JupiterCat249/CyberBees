@tool
extends EditorPlugin
const PlugLogger = preload("res://addons/gd-plug-plus/Logger.gd")
const AddonManager = preload("scene/addon_manager/AddonManager.tscn")

const TRANSLATIONS_DIR = "res://addons/gd-plug-plus/translations"
const DOMAIN_NAME = "gd-plug-plus"

var addon_manager = AddonManager.instantiate()


func _enter_tree():
	_load_translations()
	addon_manager.set_translation_domain(DOMAIN_NAME)
	add_control_to_container(EditorPlugin.CONTAINER_PROJECT_SETTING_TAB_LEFT, addon_manager)
	var tab_container = addon_manager.get_parent()
	for child in tab_container.get_children():
		if child.name == "Plugins":
			tab_container.move_child(addon_manager, child.get_index())
			break


func _exit_tree():
	if is_instance_valid(addon_manager):
		remove_control_from_container(
			EditorPlugin.CONTAINER_PROJECT_SETTING_TAB_LEFT, addon_manager
		)
		addon_manager.queue_free()
	TranslationServer.remove_domain(DOMAIN_NAME)


func _load_translations():
	var domain := TranslationServer.get_or_add_domain(DOMAIN_NAME)
	var dir := DirAccess.open(TRANSLATIONS_DIR)
	if dir == null:
		PlugLogger.debug("Cannot open translations dir: %s" % TRANSLATIONS_DIR)
		return

	var count := 0
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if file_name.ends_with(".translation"):
			var t = load(TRANSLATIONS_DIR + "/" + file_name)
			if t:
				domain.add_translation(t)
				count += 1
		file_name = dir.get_next()
	dir.list_dir_end()

	var sample := domain.translate("TAB_INSTALLED")
	PlugLogger.debug(
		(
			"TranslationDomain '%s': %d translations loaded, locale=%s, tr('TAB_INSTALLED')='%s'"
			% [DOMAIN_NAME, count, TranslationServer.get_locale(), sample]
		)
	)
