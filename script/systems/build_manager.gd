
# build_manager.gd —— 建造与破坏控制器
class_name BuildManager
extends Node

var cell_script: GDScript = preload("res://script/core/row_layer.gd")

# 放置物品（瓷砖或物体）
func place_active_item(cell: Vector2i, hotbar_node: Node, sort_world: Node2D, selector: Node2D, tile_layers: Array[TileMapLayer]) -> void:
	if hotbar_node == null:
		return
	var item: Dictionary = hotbar_node.call("get_active_item")
	if item.is_empty():
		return

	if item["type"] == 0:  # TILE
		_place_tile(cell, item["atlas"], sort_world, selector, tile_layers)
	elif item["type"] == 1:  # OBJECT
		var grid_size: Vector2i = item.get("grid_size", Vector2i(4, 4))
		var sub_cell: Vector2i = Vector2i.ZERO
		# 只有非 4x4 的微小物体（如小麦）才读取鼠标瞄准的微格，4x4 大树必须始终居中对齐 (0, 0)
		if grid_size != Vector2i(4, 4) and selector != null:
			sub_cell = selector.get("target_sub_cell")
		_place_object(cell, item["scene"], sort_world, sub_cell, grid_size)

# 放置瓷砖
func _place_tile(cell: Vector2i, tile_atlas: Vector2i, sort_world: Node2D, selector: Node2D, tile_layers: Array[TileMapLayer]) -> void:
	var z := GridData.get_highest_floor(cell) + 1
	var cell_layer := get_or_create_cell_layer(z, cell, sort_world, tile_layers)
	cell_layer.set_cell(cell, 0, tile_atlas, 0)
	GridData.set_tile(cell, z, true)
	sort_world.call("sort_now")
	selector.call("force_update")

# 放置物体（支持 1x1 小麦、2x2 灌木、4x4 大树）
func _place_object(cell: Vector2i, scene_path: String, sort_world: Node2D, sub_cell: Vector2i = Vector2i.ZERO, size: Vector2i = Vector2i(4, 4)) -> void:
	if GridData.is_slot_occupied(cell, sub_cell, size):
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var obj := packed.instantiate() as Node2D

	var cell_center := GridData.cell_to_world(cell)
	var sub_offset := GridData.sub_cell_to_local_offset(sub_cell, size)
	var floor_val := GridData.get_highest_floor(cell)

	obj.set("base_position", cell_center + sub_offset)
	obj.set("floor_level", floor_val)
	obj.set("grid_size", size)
	obj.set("sub_cell", sub_cell)
	obj.set("sort_key", GridData.cell_to_sort_key(cell))

	sort_world.add_child(obj)
	sort_world.call("insert_sort", obj)
	GridData.register_object(cell, obj, sub_cell, size)

# 右键智能破坏（最上层优先）
func destroy_top_at(cell: Vector2i, sort_world: Node2D, selector: Node2D) -> void:
	# 1. 优先破坏物体（如果是大树直接拆整格；如果是微作物，拆当前鼠标指着的微格）
	var sub_cell: Vector2i = selector.get("target_sub_cell") if selector else Vector2i.ZERO
	var obj := GridData.get_object_at(cell, sub_cell)
	if obj:
		var size: Vector2i = obj.get("grid_size") if obj.get("grid_size") != null else Vector2i(4, 4)
		var sp: Vector2i = obj.get("sub_cell") if obj.get("sub_cell") != null else Vector2i.ZERO
		GridData.unregister_object(cell, sp, size)
		obj.queue_free()
		selector.call("force_update")
		return

	# 2. 其次破坏最上层瓷砖（地面0层不拆）
	var z := GridData.get_highest_floor(cell)
	if z <= 0:
		return
	var key := "cell_z%d_%d_%d" % [z, cell.x, cell.y]
	var cell_layer := sort_world.get_node_or_null(key) as TileMapLayer
	if cell_layer:
		cell_layer.erase_cell(cell)
		GridData.set_tile(cell, z, false)
		if cell_layer.get_used_cells().is_empty():
			cell_layer.queue_free()
		else:
			sort_world.call("sort_now")
		selector.call("force_update")

# 查找或创建格级图层
func get_or_create_cell_layer(z: int, cell: Vector2i, sort_world: Node2D, tile_layers: Array[TileMapLayer]) -> TileMapLayer:
	var key := "cell_z%d_%d_%d" % [z, cell.x, cell.y]
	var cell_layer := sort_world.get_node_or_null(key) as TileMapLayer
	if cell_layer != null:
		return cell_layer

	cell_layer = cell_script.new()
	cell_layer.name = key
	# 统一使用第 0 层的 TileSet 材质图集
	cell_layer.tile_set = tile_layers[0].tile_set
	# 【核心】：纯数学计算该层 Y 坐标偏移（每高 1 层往上移 8 像素，无限支持！）
	cell_layer.position = Vector2(0.0, -float(z) * 8.0)
	cell_layer.y_sort_enabled = true
	cell_layer.collision_enabled = false
	cell_layer.set("sort_key", GridData.cell_to_sort_key(cell))
	cell_layer.set("layer_no", z)
	sort_world.add_child(cell_layer)
	return cell_layer