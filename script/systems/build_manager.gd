# build_manager.gd —— 纯平面建造与放置控制器
class_name BuildManager
extends Node

const SelectorScript := preload("res://script/systems/selector.gd")

@export var selector: Node2D
@export var entities_container: Node2D
@export var ground_layer: TileMapLayer
@export var air_wall_manager: StaticBody2D

var inventory: InventoryComponent = null

func _ready() -> void:
	if ground_layer:
		GridData.register_ground_layer(ground_layer)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return

	_ensure_inventory()
	if selector == null or inventory == null:
		return

	var cell: Vector2i = selector.get("target_cell")
	var sub_cell: Vector2i = selector.get("target_sub_cell")
	if cell == Vector2i(-99999, -99999):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		_handle_place(cell, sub_cell)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_demolish(cell, sub_cell)

func _ensure_inventory() -> void:
	if inventory == null:
		var p := get_tree().get_first_node_in_group("player")
		if p:
			inventory = p.find_child("InventoryComponent", true, false) as InventoryComponent

## 处理鼠标左键放置
func _handle_place(cell: Vector2i, sub_cell: Vector2i) -> void:
	var item := inventory.get_active_item()
	if item.is_empty():
		return

	var itype: int = item.get("type", 0)
	var count: int = item.get("count", 0)
	if count <= 0:
		return

	if itype == 3: # OBJECT (树木、小麦、箱子等微格实体)
		var grid_size: Vector2i = item.get("grid_size", Vector2i(4, 4))
		if grid_size == Vector2i(4, 4):
			sub_cell = Vector2i.ZERO # 4x4 大物体严格居中对齐 (0, 0)

		if GridData.is_slot_occupied(cell, sub_cell, grid_size):
			return

		var scene_path: String = item.get("scene", "")
		if scene_path == "" or not ResourceLoader.exists(scene_path):
			return

		var packed := load(scene_path) as PackedScene
		if packed == null:
			return

		var obj := packed.instantiate() as Node2D
		var cell_center := GridData.cell_to_world(cell)
		var sub_offset := GridData.sub_cell_to_local_offset(sub_cell, grid_size)
		obj.position = cell_center + sub_offset

		if entities_container:
			entities_container.add_child(obj)
		else:
			get_parent().add_child(obj)

		GridData.register_object(cell, obj, sub_cell, grid_size)
		_consume_active_item(1)
		selector.force_update()

	elif itype == 1: # TILE (地砖)
		if ground_layer:
			var atlas: Vector2i = item.get("atlas", Vector2i(0, 0))
			ground_layer.set_cell(cell, 0, atlas, 0)
			_consume_active_item(1)
			selector.force_update()
			if air_wall_manager and air_wall_manager.has_method("rebuild_walls"):
				air_wall_manager.call("rebuild_walls")

## 处理鼠标右键拆除/收割
func _handle_demolish(cell: Vector2i, sub_cell: Vector2i) -> void:
	var obj := GridData.get_object_at(cell, sub_cell)
	if obj:
		var is_full_cell := GridData.objects_at.has(cell)
		var size := Vector2i(4, 4) if is_full_cell else Vector2i(1, 1)
		GridData.unregister_object(cell, sub_cell, size)
		obj.queue_free()
		selector.force_update()

## 扣减当前激活槽位的物品数量
func _consume_active_item(amount: int = 1) -> void:
	var item := inventory.get_active_item()
	var cur_count: int = item.get("count", 0)
	var new_count := cur_count - amount
	if new_count > 0:
		item["count"] = new_count
		inventory.set_slot_item(inventory.active_slot_index, item)
	else:
		inventory.set_slot_item(inventory.active_slot_index, {})
