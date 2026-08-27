@tool
class_name SelectorPopup
extends AcceptDialog

## Generic selector popup with search filter, multi-column Tree, grouping,
## loading state and error state.  Reused for branch/tag and commit selection.

signal item_selected(metadata: Dictionary)

const _DOMAIN_NAME = "gd-plug-plus"

var _filter: LineEdit
var _tree: Tree
var _loading_box: CenterContainer
var _loading_label: Label
var _loading_spinner: TextureRect
var _error_label: Label

var _columns: int = 1
var _all_groups: Array = []


static func _tr(key: String) -> String:
	return TranslationServer.get_or_add_domain(_DOMAIN_NAME).translate(key)


static func _get_editor_scale() -> float:
	if Engine.is_editor_hint():
		return EditorInterface.get_editor_scale()
	return 1.0


static func _scaled(value: float) -> int:
	return int(value * _get_editor_scale())


func _init():
	ok_button_text = _tr("BTN_CLOSE")
	min_size = Vector2i(
		_scaled(PlugUIConstants.SELECTOR_DEFAULT_SIZE.x),
		_scaled(PlugUIConstants.SELECTOR_DEFAULT_SIZE.y)
	)


func _ready():
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", _scaled(PlugUIConstants.SEPARATION_COMPACT))

	_filter = LineEdit.new()
	_filter.placeholder_text = _tr("BRANCH_POPUP_FILTER")
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(_on_filter_changed)
	vbox.add_child(_filter)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, _scaled(PlugUIConstants.SELECTOR_TREE_MIN_HEIGHT))
	_tree.item_mouse_selected.connect(_on_tree_mouse_selected)
	vbox.add_child(_tree)

	_loading_box = CenterContainer.new()
	_loading_box.visible = false
	_loading_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_loading_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lhbox = HBoxContainer.new()
	lhbox.add_theme_constant_override("separation", _scaled(PlugUIConstants.SEPARATION_STANDARD))
	_loading_box.add_child(lhbox)

	var spinner_path = "res://addons/gd-plug-plus/assets/icons/loading.svg"
	if ResourceLoader.exists(spinner_path):
		_loading_spinner = TextureRect.new()
		_loading_spinner.texture = load(spinner_path)
		_loading_spinner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_loading_spinner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_loading_spinner.custom_minimum_size = Vector2(
			_scaled(PlugUIConstants.SPINNER_SIZE), _scaled(PlugUIConstants.SPINNER_SIZE)
		)
		lhbox.add_child(_loading_spinner)

	_loading_label = Label.new()
	_loading_label.text = _tr("SELECTOR_LOADING")
	lhbox.add_child(_loading_label)
	vbox.add_child(_loading_box)

	_error_label = Label.new()
	_error_label.visible = false
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_error_label.add_theme_color_override("font_color", PlugUIConstants.COLOR_BEHIND)
	_error_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_error_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_error_label)

	add_child(vbox)


func _process(delta: float):
	if _loading_spinner and _loading_box.visible:
		_loading_spinner.pivot_offset = _loading_spinner.size * 0.5
		_loading_spinner.rotation += delta * TAU * PlugUIConstants.SPINNER_SPEED


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


func setup(config: Dictionary) -> void:
	title = config.get("title", "")
	var sz: Vector2i = config.get(
		"size",
		Vector2i(
			_scaled(PlugUIConstants.SELECTOR_DEFAULT_SIZE.x),
			_scaled(PlugUIConstants.SELECTOR_DEFAULT_SIZE.y)
		)
	)
	min_size = sz
	size = sz

	if config.has("filter_placeholder"):
		_filter.placeholder_text = config["filter_placeholder"]

	_columns = config.get("columns", 1)
	_tree.columns = _columns
	_tree.column_titles_visible = config.get("show_column_titles", false)

	var col_widths: Array = config.get("column_widths", [])
	for i in range(_columns):
		if i < col_widths.size() and col_widths[i] > 0:
			_tree.set_column_expand(i, false)
			_tree.set_column_custom_minimum_width(i, col_widths[i])
		else:
			_tree.set_column_expand(i, true)
		_tree.set_column_clip_content(i, true)

	_all_groups = config.get("groups", [])
	_filter.text = ""
	_show_tree()
	_populate("")


func show_loading(p_title: String, loading_text: String = "") -> void:
	title = p_title
	_filter.visible = false
	_tree.visible = false
	_error_label.visible = false
	_loading_box.visible = true
	if not loading_text.is_empty():
		_loading_label.text = loading_text
	else:
		_loading_label.text = _tr("SELECTOR_LOADING")


func show_error(error_text: String) -> void:
	_loading_box.visible = false
	_filter.visible = false
	_tree.visible = false
	_error_label.visible = true
	_error_label.text = error_text


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------


func _show_tree() -> void:
	_loading_box.visible = false
	_error_label.visible = false
	_filter.visible = true
	_tree.visible = true
	_filter.grab_focus()


func _populate(filter_text: String) -> void:
	_tree.clear()
	_tree.create_item()
	var filter_lower = filter_text.to_lower()

	for group in _all_groups:
		var header_text: String = group.get("header", "")
		var items: Array = group.get("items", [])
		var matched_items: Array = []

		for it in items:
			if filter_lower.is_empty():
				matched_items.append(it)
				continue
			var cols: Array = it.get("columns", [])
			var any_match = false
			for c in cols:
				if filter_lower in str(c).to_lower():
					any_match = true
					break
			if any_match:
				matched_items.append(it)

		if matched_items.is_empty():
			continue

		if not header_text.is_empty():
			var h = _tree.create_item(_tree.get_root())
			h.set_text(0, header_text)
			h.set_selectable(0, false)
			h.set_custom_color(0, PlugUIConstants.COLOR_CHECKING)
			for ci in range(1, _columns):
				h.set_selectable(ci, false)

		for it in matched_items:
			var child = _tree.create_item(_tree.get_root())
			var cols: Array = it.get("columns", [])
			for ci in range(_columns):
				var val = cols[ci] if ci < cols.size() else ""
				child.set_text(ci, "  " + str(val) if ci == 0 else str(val))
			child.set_meta("selector_meta", it.get("meta", {}))

			var colors: Array = it.get("colors", [])
			for ci in range(colors.size()):
				if ci < _columns and colors[ci] is Color:
					child.set_custom_color(ci, colors[ci])


func _on_filter_changed(text: String) -> void:
	_populate(text)


func _on_tree_mouse_selected(_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	var item = _tree.get_selected()
	if item == null:
		return
	if not item.has_meta("selector_meta"):
		return
	var meta: Dictionary = item.get_meta("selector_meta")
	if meta.is_empty():
		return
	hide()
	emit_signal("item_selected", meta)
