
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
		_place_object(cell, item["scene"], sort_world)

# 放置瓷砖
func _place_tile(cell: Vector2i, tile_atlas: Vector2i, sort_world: Node2D, selector: Node2D, tile_layers: Array[TileMapLayer]) -> void:
	var z := GridData.get_highest_floor(cell) + 1
	if z >= tile_layers.size():
		return
	var cell_layer := get_or_create_cell_layer(z, cell, sort_world, tile_layers)
	cell_layer.set_cell(cell, 0, tile_atlas, 0)
	GridData.set_tile(cell, z, true)
	sort_world.call("sort_now")
	selector.call("force_update")

# 放置物体（树木等）
func _place_object(cell: Vector2i, scene_path: String, sort_world: Node2D) -> void:
	if GridData.has_object(cell):
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var obj := packed.instantiate() as Node2D
	obj.set("base_position", GridData.cell_to_world(cell))
	obj.set("floor_level", GridData.get_highest_floor(cell))
	obj.set("sort_key", GridData.cell_to_sort_key(cell))
	sort_world.add_child(obj)
	sort_world.call("insert_sort", obj)

# 右键智能破坏（最上层优先）
func destroy_top_at(cell: Vector2i, sort_world: Node2D, selector: Node2D) -> void:
	# 1. 优先破坏物体
	if GridData.has_object(cell):
		var key := GridData.cell_key(cell)
		var obj = GridData.objects_at.get(key) as Node
		if obj:
			GridData.unregister_object(cell)
			obj.queue_free()
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
	cell_layer.tile_set = tile_layers[z].tile_set
	cell_layer.position = tile_layers[z].position
	cell_layer.y_sort_enabled = true
	cell_layer.collision_enabled = false
	cell_layer.set("sort_key", GridData.cell_to_sort_key(cell))
	cell_layer.set("layer_no", z)
	sort_world.add_child(cell_layer)
	return cell_layer
