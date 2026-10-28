# hotbar.gd —— 底部快捷物品栏视图控制器 (View 表现层)
class_name HotbarUI
extends CanvasLayer

@export var inventory: InventoryComponent

@onready var slots_container: HBoxContainer = $MarginContainer/SlotsContainer

# 普通边框与选中高亮边框样式
var normal_style: StyleBoxFlat
var selected_style: StyleBoxFlat

func _ready() -> void:
	_init_styles()
	_setup_slot_clicks()
	
	# 如果未手动指定，自动寻找玩家的 InventoryComponent
	if inventory == null:
		var player := get_tree().get_first_node_in_group("player")
		if player:
			inventory = player.find_child("InventoryComponent", true, false) as InventoryComponent
	
	if inventory:
		bind_inventory(inventory)

## 绑定目标背包数据组件
func bind_inventory(inv: InventoryComponent) -> void:
	inventory = inv
	if not inventory.active_slot_changed.is_connected(_on_active_slot_changed):
		inventory.active_slot_changed.connect(_on_active_slot_changed)
	if not inventory.slot_updated.is_connected(_on_slot_updated):
		inventory.slot_updated.connect(_on_slot_updated)
	
	_refresh_all_slots()
	_update_highlight(inventory.active_slot_index)

## 初始化边框样式
func _init_styles() -> void:
	normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.03, 0.14, 0.27, 0.85)
	normal_style.set_border_width_all(2)
	normal_style.border_color = Color(0.47, 0.68, 0.94, 0.8)
	normal_style.set_corner_radius_all(4)

	selected_style = normal_style.duplicate()
	selected_style.bg_color = Color(0.05, 0.20, 0.38, 0.95)
	selected_style.border_color = Color(1.0, 0.85, 0.2, 1.0) # 金黄色高亮
	selected_style.set_border_width_all(3)

## 监听鼠标直接点击槽位
func _setup_slot_clicks() -> void:
	for i in slots_container.get_child_count():
		var slot := slots_container.get_child(i) as Control
		if slot:
			var idx := i
			slot.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					if inventory:
						inventory.select_slot(idx)
			)

## 监听按键 1~5 和鼠标滚轮
func _unhandled_input(event: InputEvent) -> void:
	if inventory == null:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			inventory.select_slot(0)
		elif event.keycode == KEY_2:
			inventory.select_slot(1)
		elif event.keycode == KEY_3:
			inventory.select_slot(2)
		elif event.keycode == KEY_4:
			inventory.select_slot(3)
		elif event.keycode == KEY_5:
			inventory.select_slot(4)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			inventory.step_slot(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			inventory.step_slot(1)

## 刷新所有槽位的贴图和数量
func _refresh_all_slots() -> void:
	if inventory == null:
		return
	for i in slots_container.get_child_count():
		var item_data := inventory.get_slot_item(i)
		_update_slot_view(i, item_data)

## 更新单个槽位的显示
func _update_slot_view(index: int, item_data: Dictionary) -> void:
	if index < 0 or index >= slots_container.get_child_count():
		return
	var slot := slots_container.get_child(index)
	var icon_rect := slot.find_child("TextureRect", true, false) as TextureRect
	var count_label := slot.find_child("CountLabel", true, false) as Label

	if icon_rect:
		var icon_path: String = item_data.get("icon", "")
		if icon_path != "" and ResourceLoader.exists(icon_path):
			icon_rect.texture = load(icon_path)
		else:
			icon_rect.texture = null

	if count_label:
		var count: int = item_data.get("count", 0)
		if count > 1:
			count_label.text = str(count)
			count_label.visible = true
		else:
			count_label.visible = false

## 槽位激活变更回调
func _on_active_slot_changed(index: int, _item_data: Dictionary) -> void:
	_update_highlight(index)

## 槽位内容更新回调
func _on_slot_updated(index: int, item_data: Dictionary) -> void:
	_update_slot_view(index, item_data)

## 更新高亮边框
func _update_highlight(active_idx: int) -> void:
	for i in slots_container.get_child_count():
		var slot := slots_container.get_child(i) as PanelContainer
		if slot:
			if i == active_idx:
				slot.add_theme_stylebox_override("panel", selected_style)
			else:
				slot.add_theme_stylebox_override("panel", normal_style)

