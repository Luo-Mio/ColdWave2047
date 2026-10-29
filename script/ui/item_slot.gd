# item_slot.gd —— 通用物品槽位 UI 组件 (用于创造模式面板、快捷栏、背包、箱子)
class_name ItemSlotUI
extends PanelContainer

signal slot_clicked(slot: Control, button_index: int)
signal item_dropped_on_slot(source_slot: Control, target_slot: Control, dropped_item: Dictionary)

@export var slot_index: int = -1
@export var is_storage_slot: bool = false # true 时允许放置/丢入物品，false 时作为只读展示库

var item_data: Dictionary = {}
var is_active_selected: bool = false
var is_hovered: bool = false

# UI 节点引用
@onready var texture_rect: TextureRect = $TextureRect
@onready var count_label: Label = $CountLabel
@onready var key_label: Label = $KeyLabel

# 预设样式
var normal_style: StyleBoxFlat
var hover_style: StyleBoxFlat
var selected_style: StyleBoxFlat

func _ready() -> void:
	_init_styles()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	_update_view()
	_update_appearance()

func _init_styles() -> void:
	normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.04, 0.12, 0.22, 0.85)
	normal_style.set_border_width_all(2)
	normal_style.border_color = Color(0.35, 0.55, 0.8, 0.7)
	normal_style.set_corner_radius_all(4)

	hover_style = normal_style.duplicate()
	hover_style.bg_color = Color(0.08, 0.20, 0.35, 0.95)
	hover_style.border_color = Color(0.65, 0.85, 1.0, 1.0)
	hover_style.set_border_width_all(2)

	selected_style = normal_style.duplicate()
	selected_style.bg_color = Color(0.08, 0.22, 0.40, 0.95)
	selected_style.border_color = Color(1.0, 0.85, 0.25, 1.0) # 金黄色高亮
	selected_style.set_border_width_all(3)

func set_item(data: Dictionary) -> void:
	item_data = data.duplicate(true)
	_update_view()

func clear_item() -> void:
	item_data = {}
	_update_view()

func get_item() -> Dictionary:
	return item_data

func is_empty() -> bool:
	return item_data.is_empty()

func set_active_selected(selected: bool) -> void:
	is_active_selected = selected
	_update_appearance()

func set_key_hint(text: String) -> void:
	if key_label:
		key_label.text = text
		key_label.visible = not text.is_empty()

func _update_view() -> void:
	if not is_inside_tree():
		return

	if texture_rect:
		var icon_path: String = item_data.get("icon", "")
		if icon_path != "" and ResourceLoader.exists(icon_path):
			texture_rect.texture = load(icon_path)
		else:
			texture_rect.texture = null

	if count_label:
		var count: int = item_data.get("count", 0)
		if count > 1:
			count_label.text = str(count)
			count_label.visible = true
		else:
			count_label.visible = false

	_update_tooltip()

func _update_tooltip() -> void:
	if item_data.is_empty():
		tooltip_text = ""
		return

	var name_str: String = item_data.get("name", "未知物品")
	var grid_size: Vector2i = item_data.get("grid_size", Vector2i.ONE)
	var type_int: int = item_data.get("type", 0)
	var type_name: String = ""
	match type_int:
		1: type_name = "地砖"
		2: type_name = "覆盖层"
		3: type_name = "实体建筑/植被"
		4: type_name = "工具武器"

	var size_str = "4x4 (整格)" if grid_size == Vector2i(4, 4) else ("%dx%d (微格)" % [grid_size.x, grid_size.y])
	var desc: String = item_data.get("description", "")

	tooltip_text = "【%s】\n类型: %s | 占地: %s\n%s" % [name_str, type_name, size_str, desc]

func _update_appearance() -> void:
	if not is_inside_tree():
		return
	if is_active_selected:
		add_theme_stylebox_override("panel", selected_style)
	elif is_hovered:
		add_theme_stylebox_override("panel", hover_style)
	else:
		add_theme_stylebox_override("panel", normal_style)

func _on_mouse_entered() -> void:
	is_hovered = true
	_update_appearance()

func _on_mouse_exited() -> void:
	is_hovered = false
	_update_appearance()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		slot_clicked.emit(self, event.button_index)

# === 支持拖拽 (Drag & Drop) ===
func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_data.is_empty():
		return null

	var preview := TextureRect.new()
	preview.texture = texture_rect.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(48, 48)
	preview.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(preview)

	return {
		"source_slot": self,
		"item_data": item_data.duplicate(true)
	}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return is_storage_slot and data is Dictionary and data.has("item_data")

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not is_storage_slot:
		return
	var source_slot: ItemSlotUI = data.get("source_slot")
	var dropped_item: Dictionary = data.get("item_data", {}).duplicate(true)
	item_dropped_on_slot.emit(source_slot, self, dropped_item)
