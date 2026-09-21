# inventory.gd —— 分类调试/测试背包控制器
extends CanvasLayer

const ItemDatabase = preload("res://script/data/item_database.gd")

signal item_equipped(slot_index: int, item_data: Dictionary)

# 当前选中的分类
var current_category: ItemDatabase.Category = ItemDatabase.Category.ALL

# 目标装配快捷栏槽位 (0 ~ 4，默认跟踪 hotbar.active_index)
var target_slot_index: int = 0

# 节点引用
@onready var backdrop: ColorRect = $Backdrop
@onready var main_panel: PanelContainer = $CenterContainer/MainPanel
@onready var category_container: HBoxContainer = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/CategoryBar
@onready var grid_container: GridContainer = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/GridContainer
@onready var hotbar_preview_container: HBoxContainer = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/HotbarBindingBar/BarHeader/SlotsContainer
@onready var tip_label: Label = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/HotbarBindingBar/TipLabel
@onready var close_btn: Button = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/Header/CloseButton

# 样式缓存
var slot_normal_style: StyleBoxFlat
var slot_active_style: StyleBoxFlat
var card_normal_style: StyleBoxFlat
var card_hover_style: StyleBoxFlat

func _ready() -> void:
	visible = false
	_init_styles()
	_setup_category_buttons()
	close_btn.pressed.connect(close)
	backdrop.gui_input.connect(_on_backdrop_gui_input)

	# 延迟一帧等待主场景和 Hotbar 就绪
	await get_tree().process_frame
	_refresh_hotbar_preview()

# 处理快捷键唤起 (B, Tab, Esc)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B or event.keycode == KEY_TAB:
			toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and visible:
			close()
			get_viewport().set_input_as_handled()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	# 同步当前快捷栏激活槽位
	var hotbar = _get_hotbar()
	if hotbar and "active_index" in hotbar:
		target_slot_index = hotbar.active_index
	_refresh_category_items()
	_refresh_hotbar_preview()

func close() -> void:
	visible = false

func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()

# 样式初始化
func _init_styles() -> void:
	# 快捷栏预览槽位样式
	slot_normal_style = StyleBoxFlat.new()
	slot_normal_style.bg_color = Color(0.04, 0.08, 0.16, 0.85)
	slot_normal_style.set_border_width_all(2)
	slot_normal_style.border_color = Color(0.3, 0.5, 0.8, 0.7)
	slot_normal_style.set_corner_radius_all(3)

	slot_active_style = slot_normal_style.duplicate()
	slot_active_style.border_color = Color(1.0, 0.85, 0.2, 1.0)
	slot_active_style.set_border_width_all(3)

	# 物品卡片样式
	card_normal_style = StyleBoxFlat.new()
	card_normal_style.bg_color = Color(0.08, 0.14, 0.24, 0.9)
	card_normal_style.set_border_width_all(1)
	card_normal_style.border_color = Color(0.25, 0.45, 0.7, 0.6)
	card_normal_style.set_corner_radius_all(4)

	card_hover_style = card_normal_style.duplicate()
	card_hover_style.bg_color = Color(0.12, 0.22, 0.36, 0.95)
	card_hover_style.border_color = Color(0.5, 0.85, 1.0, 1.0)
	card_hover_style.set_border_width_all(2)

# 创建分类切换按钮
func _setup_category_buttons() -> void:
	for child in category_container.get_children():
		child.queue_free()

	for cat_key in ItemDatabase.CATEGORY_NAMES.keys():
		var cat_enum: ItemDatabase.Category = cat_key
		var btn := Button.new()
		btn.text = ItemDatabase.CATEGORY_NAMES[cat_enum]
		btn.custom_minimum_size = Vector2(76, 28)
		btn.toggle_mode = true
		btn.button_pressed = (cat_enum == current_category)
		btn.pressed.connect(_on_category_button_pressed.bind(cat_enum))
		category_container.add_child(btn)

func _on_category_button_pressed(cat: ItemDatabase.Category) -> void:
	current_category = cat
	for child in category_container.get_children():
		if child is Button:
			child.button_pressed = (child.text == ItemDatabase.CATEGORY_NAMES[cat])
	_refresh_category_items()

# 刷新当前分类下的物品网格
func _refresh_category_items() -> void:
	for child in grid_container.get_children():
		grid_container.remove_child(child)
		child.queue_free()

	var items := ItemDatabase.get_items_by_category(current_category)
	for item_data in items:
		var card := _create_item_card(item_data)
		grid_container.add_child(card)

# 创建单个物品展示卡片
func _create_item_card(item_data: Dictionary) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(88, 92)
	btn.flat = false
	btn.add_theme_stylebox_override("normal", card_normal_style)
	btn.add_theme_stylebox_override("hover", card_hover_style)
	btn.add_theme_stylebox_override("pressed", card_hover_style)
	btn.tooltip_text = "%s\n%s" % [item_data.get("name", ""), item_data.get("description", "")]

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)

	# 物品图标
	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(48, 48)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex_rect.texture = _get_item_icon(item_data)
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(tex_rect)

	# 物品名称标签
	var lbl := Label.new()
	lbl.text = item_data.get("name", "")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lbl)

	btn.add_child(vbox)
	btn.pressed.connect(_on_item_card_clicked.bind(item_data))
	return btn

# 点击物品卡片 -> 装配到目标快捷栏槽位
func _on_item_card_clicked(item_data: Dictionary) -> void:
	var hotbar = _get_hotbar()
	if hotbar and hotbar.has_method("set_slot_item"):
		hotbar.call("set_slot_item", target_slot_index, item_data)
		_refresh_hotbar_preview()
		tip_label.text = "已将【%s】装入第 %d 号槽位！(按 B 关闭)" % [item_data.get("name", ""), target_slot_index + 1]
		item_equipped.emit(target_slot_index, item_data)

# 刷新底部快捷栏预览槽位
func _refresh_hotbar_preview() -> void:
	var hotbar = _get_hotbar()
	if hotbar == null:
		return

	var hotbar_items: Array = hotbar.get("items") if ("items" in hotbar) else []
	for i in range(5):
		var slot_btn: Button
		if i < hotbar_preview_container.get_child_count():
			slot_btn = hotbar_preview_container.get_child(i) as Button
		else:
			slot_btn = Button.new()
			slot_btn.custom_minimum_size = Vector2(44, 44)
			slot_btn.pressed.connect(_on_target_slot_selected.bind(i))
			hotbar_preview_container.add_child(slot_btn)

		var is_active := (i == target_slot_index)
		slot_btn.add_theme_stylebox_override("normal", slot_active_style if is_active else slot_normal_style)
		slot_btn.add_theme_stylebox_override("hover", slot_active_style)

		# 设置图标与快捷键标签
		var item_data: Dictionary = hotbar_items[i] if (i < hotbar_items.size()) else {}
		var icon_tex := _get_item_icon(item_data)
		slot_btn.icon = icon_tex
		slot_btn.expand_icon = true
		slot_btn.text = str(i + 1)
		slot_btn.tooltip_text = "槽位 %d: %s (点击选中为装配目标)" % [i + 1, item_data.get("name", "空")]

func _on_target_slot_selected(slot_idx: int) -> void:
	target_slot_index = slot_idx
	var hotbar = _get_hotbar()
	if hotbar and hotbar.has_method("_select_slot"):
		hotbar.call("_select_slot", slot_idx)
	_refresh_hotbar_preview()
	tip_label.text = "已选定快捷栏第 %d 号槽位作为装配目标。" % (target_slot_index + 1)

# 获取物品图标
func _get_item_icon(item_data: Dictionary) -> Texture2D:
	if item_data.is_empty():
		return null
	if item_data.has("icon") and str(item_data["icon"]) != "":
		if ResourceLoader.exists(item_data["icon"]):
			return load(item_data["icon"])
	if item_data.get("type") == ItemDatabase.ItemType.TILE:
		var grid_data = get_tree().root.get_node_or_null("GridData") if (get_tree() and get_tree().root) else null
		if grid_data and "layers" in grid_data and not grid_data.layers.is_empty():
			var ts: TileSet = grid_data.layers[0].tile_set
			var source = ts.get_source(0) as TileSetAtlasSource
			if source and item_data.has("atlas"):
				var atlas_tex := AtlasTexture.new()
				atlas_tex.atlas = source.texture
				atlas_tex.region = source.get_tile_texture_region(item_data["atlas"])
				return atlas_tex
	return null

func _get_hotbar() -> Node:
	return get_tree().root.find_child("hotbar", true, false)
