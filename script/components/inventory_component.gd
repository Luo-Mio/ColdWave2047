# inventory_component.gd —— 背包与快捷栏数据组件 (Model 数据层，挂载在角色身下)
class_name InventoryComponent
extends Node

## 槽位激活变更信号 (当玩家按 1~5 或滚轮切换手持物品时触发)
signal active_slot_changed(slot_index: int, item_data: Dictionary)
## 槽位内容刷新信号 (当物品增删或数量改变时触发)
signal slot_updated(slot_index: int, item_data: Dictionary)

enum ItemType {
	NONE = 0,
	TILE = 1,    # 地砖 (如: 泥土)
	SURF = 2,    # 覆盖层 (如: 草皮)
	OBJECT = 3,  # 放置物 (如: 树木、作物、箱子)
	WEAPON = 4   # 武器工具 (如: 剑、斧、木棍)
}

@export var max_slots: int = 5
@export var active_slot_index: int = 0

# 存储所有槽位的数据列表
var slots: Array[Dictionary] = []

func _ready() -> void:
	if slots.is_empty():
		_setup_default_slots()

## 初始化默认 5 个槽位的测试物品 (仅保留树和小麦，无数量限制)
func _setup_default_slots() -> void:
	slots.resize(max_slots)
	for i in max_slots:
		slots[i] = {}

	# 1 号位：白桦树 (4x4 整格，无限数量)
	slots[0] = ItemDatabase.create_item("birch_tree", -1)

	# 2 号位：小麦 (1x1 微格，无限数量)
	slots[1] = ItemDatabase.create_item("wheat", -1)

	# 3、4、5 号位：空槽位

	# 触发初始选中信号
	call_deferred("_emit_initial_selection")

func _emit_initial_selection() -> void:
	active_slot_changed.emit(active_slot_index, get_active_item())

## 切换当前激活槽位
func select_slot(index: int) -> void:
	if index < 0 or index >= max_slots:
		return
	if index == active_slot_index:
		return
	active_slot_index = index
	active_slot_changed.emit(active_slot_index, get_active_item())

## 步进切换槽位 (滚轮操作: step = +1 或 -1)
func step_slot(step: int) -> void:
	var target = (active_slot_index + step) % max_slots
	if target < 0:
		target += max_slots
	select_slot(target)

## 获取当前正在手持激活的物品数据
func get_active_item() -> Dictionary:
	return get_slot_item(active_slot_index)

## 获取指定槽位的物品数据
func get_slot_item(index: int) -> Dictionary:
	if index >= 0 and index < slots.size():
		return slots[index]
	return {}

## 设置/替换指定槽位的物品数据
func set_slot_item(index: int, item_data: Dictionary) -> void:
	if index < 0 or index >= max_slots:
		return
	slots[index] = item_data.duplicate()
	slot_updated.emit(index, slots[index])
	if index == active_slot_index:
		active_slot_changed.emit(index, slots[index])

