# creative_menu.gd —— 创造模式全物品库面板控制器
class_name CreativeMenuUI
extends CanvasLayer

signal menu_opened
signal menu_closed

const ItemSlotScene := preload("res://scene/ui/item_slot.tscn")
const ItemSlotScript := preload("res://script/ui/item_slot.gd")

@export var inventory: InventoryComponent

# UI 节点引用
@onready var backdrop: ColorRect = $Backdrop
@onready var main_panel: PanelContainer = $CenterContainer/MainPanel
@onready var close_btn: Button = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/Header/CloseButton
@onready var catalog_grid: GridContainer = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/ScrollContainer/CatalogGrid
@onready var hotbar_container: HBoxContainer = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/HotbarSection/HotbarGrid
@onready var tab_all: Button = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/TabAll
@onready var tab_nature: Button = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/TabNature
@onready var tab_terrain: Button = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/TabContainer/TabTerrain

var current_category: String = "all"
var selected_hotbar_index: int = 0
var hotbar_slots: Array = []

func _ready() -> void:
	visible = false # 游戏开始默认隐藏
	_setup_signals()
	_init_hotbar_slots()

	# 尝试自动查找玩家背包
	if inventory == null:
		var player := get_tree().get_first_node_in_group("player")
		if player:
			inventory = player.find_child("InventoryComponent", true, false) as InventoryComponent

	if inventory:
		bind_inventory(inventory)

func bind_inventory(inv: InventoryComponent) -> void:
	inventory = inv
	if not inventory.active_slot_changed.is_connected(_on_inventory_active_changed):
		inventory.active_slot_changed.connect(_on_inventory_active_changed)
	if not inventory.slot_updated.is_connected(_on_inventory_slot_updated):
		inventory.slot_updated.connect(_on_inventory_slot_updated)

func _setup_signals() -> void:
	if close_btn:
		close_btn.pressed.connect(close)

	if tab_all:
		tab_all.pressed.connect(func(): _switch_tab("all"))
	if tab_nature:
		tab_nature.pressed.connect(func(): _switch_tab("nature"))
	if tab_terrain:
		tab_terrain.pressed.connect(func(): _switch_tab("terrain"))

	# 点击遮罩空白区域也可关闭
	if backdrop:
		backdrop.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				close()
		)

## 初始化底部 5 个快捷栏槽位镜像
func _init_hotbar_slots() -> void:
	# 清空现有子节点
	for child in hotbar_container.get_children():
		child.queue_free()
	hotbar_slots.clear()

	for i in 5:
		var slot = ItemSlotScene.instantiate()
		slot.slot_index = i
		slot.is_storage_slot = true
		hotbar_container.add_child(slot)
		slot.set_key_hint(str(i + 1))
		slot.slot_clicked.connect(_on_hotbar_slot_clicked)
		slot.item_dropped_on_slot.connect(_on_item_dropped_on_hotbar)
		hotbar_slots.append(slot)

## 监听全局快捷键切换 (E / Tab / Esc)
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E or event.keycode == KEY_TAB:
			toggle()
			get_viewport().set_input_as_handled()
		elif visible:
			if event.keycode == KEY_ESCAPE:
				close()
				get_viewport().set_input_as_handled()
			elif event.keycode >= KEY_1 and event.keycode <= KEY_5:
				var idx: int = int(event.keycode - KEY_1)
				_select_hotbar_slot(idx)
				get_viewport().set_input_as_handled()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	_set_gameplay_active(false)
	_switch_tab(current_category)
	_sync_all_hotbar_slots()
	if inventory:
		_select_hotbar_slot(inventory.active_slot_index)
	menu_opened.emit()

func close() -> void:
	if not visible:
		return
	visible = false
	_set_gameplay_active(true)
	menu_closed.emit()

## 冻结或恢复主游戏移动与放置
func _set_gameplay_active(is_active: bool) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var input_comp := player.find_child("PlayerInputComponent", true, false) as PlayerInputComponent
		if input_comp:
			input_comp.is_active = is_active

	var selector := get_tree().get_first_node_in_group("selector")
	if selector:
		selector.visible = is_active

	var builder := get_tree().get_first_node_in_group("build_manager")
	if builder:
		builder.set_process_unhandled_input(is_active)

## 切换物品库分类
func _switch_tab(cat: String) -> void:
	current_category = cat
	_update_tab_button_styles()
	_refresh_catalog_grid()

func _update_tab_button_styles() -> void:
	if tab_all:
		tab_all.button_pressed = (current_category == "all")
	if tab_nature:
		tab_nature.button_pressed = (current_category == "nature")
	if tab_terrain:
		tab_terrain.button_pressed = (current_category == "terrain")

## 重新填充图鉴物品展示网格
func _refresh_catalog_grid() -> void:
	for child in catalog_grid.get_children():
		child.queue_free()

	var items: Array[Dictionary] = ItemDatabase.get_items_by_category(current_category)
	for item_data in items:
		var slot = ItemSlotScene.instantiate()
		slot.is_storage_slot = false # 图鉴库槽位只读
		catalog_grid.add_child(slot)
		slot.set_item(item_data)
		slot.slot_clicked.connect(_on_catalog_slot_clicked)

## 点击图鉴物品：放入当前选中的快捷栏槽位 (数量为 -1 无限)
func _on_catalog_slot_clicked(slot: Control, button_index: int) -> void:
	if button_index != MOUSE_BUTTON_LEFT:
		return
	var item: Dictionary = slot.get_item()
	if item.is_empty() or inventory == null:
		return

	var item_id: String = item.get("id", "")
	var infinite_item: Dictionary = ItemDatabase.create_item(item_id, -1)
	inventory.set_slot_item(selected_hotbar_index, infinite_item)

## 点击底部快捷栏槽位：左键选中目标槽，右键清空
func _on_hotbar_slot_clicked(slot: Control, button_index: int) -> void:
	if button_index == MOUSE_BUTTON_LEFT:
		_select_hotbar_slot(slot.slot_index)
	elif button_index == MOUSE_BUTTON_RIGHT:
		if inventory:
			inventory.set_slot_item(slot.slot_index, {})

## 选中指定的快捷栏槽位
func _select_hotbar_slot(idx: int) -> void:
	if idx < 0 or idx >= hotbar_slots.size():
		return
	selected_hotbar_index = idx
	for i in hotbar_slots.size():
		hotbar_slots[i].set_active_selected(i == selected_hotbar_index)
	if inventory:
		inventory.select_slot(selected_hotbar_index)

## 拖拽放入快捷栏
func _on_item_dropped_on_hotbar(source_slot: Control, target_slot: Control, dropped_item: Dictionary) -> void:
	if inventory == null:
		return

	var target_idx: int = target_slot.slot_index
	if source_slot != null and source_slot.is_storage_slot:
		# 快捷栏之间互换
		var src_idx: int = source_slot.slot_index
		var src_item: Dictionary = inventory.get_slot_item(src_idx)
		var tgt_item: Dictionary = inventory.get_slot_item(target_idx)
		inventory.set_slot_item(src_idx, tgt_item)
		inventory.set_slot_item(target_idx, src_item)
	else:
		# 从图鉴拖入：自动无限数量
		var item_id: String = dropped_item.get("id", "")
		var infinite_item: Dictionary = ItemDatabase.create_item(item_id, -1)
		inventory.set_slot_item(target_idx, infinite_item)

## 同步所有快捷栏槽位数据
func _sync_all_hotbar_slots() -> void:
	if inventory == null:
		return
	for i in hotbar_slots.size():
		var data: Dictionary = inventory.get_slot_item(i)
		hotbar_slots[i].set_item(data)

## 背包激活槽位变更回调
func _on_inventory_active_changed(index: int, _data: Dictionary) -> void:
	if visible:
		_select_hotbar_slot(index)

## 背包槽位内容更新回调
func _on_inventory_slot_updated(index: int, data: Dictionary) -> void:
	if index >= 0 and index < hotbar_slots.size():
		hotbar_slots[index].set_item(data)

