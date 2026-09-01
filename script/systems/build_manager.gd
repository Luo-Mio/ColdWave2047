
# build_manager.gd —— 建造与破坏控制器
class_name BuildManager
extends Node

var cell_script: GDScript = preload("res://script/core/row_layer.gd")
var dirt_scene: PackedScene = preload("res://scene/object/dirt.tscn")

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
	# 【新增拦截】：如果本格种有小麦（哪怕只有1株）或种有大树，严禁在其上方叠放瓷砖！
	if GridData.is_slot_occupied(cell, Vector2i.ZERO, Vector2i(4, 4)):
		return

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

# 右键智能破坏
func destroy_top_at(cell: Vector2i, sort_world: Node2D, selector: Node2D) -> void:
	# 1. 优先破坏鼠标精准指向的单个物体（如单独收割某株小麦）
	var sub_cell: Vector2i = selector.get("target_sub_cell") if selector else Vector2i.ZERO
	var targeted_obj := GridData.get_object_at(cell, sub_cell)
	if targeted_obj:
		var size: Vector2i = targeted_obj.get("grid_size") if targeted_obj.get("grid_size") != null else Vector2i(4, 4)
		var sp: Vector2i = targeted_obj.get("sub_cell") if targeted_obj.get("sub_cell") != null else Vector2i.ZERO
		GridData.unregister_object(cell, sp, size)

		var drop_id: String = targeted_obj.get("drop_item_id") if targeted_obj.get("drop_item_id") != null else ""
		var drop_cnt: int = targeted_obj.get("drop_count") if targeted_obj.get("drop_count") != null else 1
		var obj_z: int = targeted_obj.get("floor_level") if targeted_obj.get("floor_level") != null else GridData.get_highest_floor(cell)
		
		targeted_obj.queue_free()

		# 爆出该物体的掉落物
		if drop_id != "":
			var valid_neighbors := _get_valid_drop_neighbors(cell, obj_z)
			if not valid_neighbors.is_empty():
				_spawn_item_drops(drop_id, drop_cnt, cell, obj_z, valid_neighbors, sort_world)

		selector.call("force_update")
		return

	# 2. 准备破坏最上层瓷砖（地面0层不拆）
	var z := GridData.get_highest_floor(cell)
	if z <= 0:
		return

	# 【安全审查】：检查地砖上方是否有坚固重型物体（如大树 break_with_tile == false）
	var objects_on_tile: Array[Node] = GridData.get_all_objects_at(cell)
	for obj in objects_on_tile:
		var can_break: bool = obj.get("break_with_tile") if obj.get("break_with_tile") != null else true
		if not can_break:
			# 上方有大树/巨石等坚固结构，严禁直接挖地基！
			return

	# 检查周围是否有合法抛土落点
	var valid_neighbors := _get_valid_drop_neighbors(cell, z)
	if valid_neighbors.is_empty():
		return

	# 敲碎地砖
	var key := "cell_z%d_%d_%d" % [z, cell.x, cell.y]
	var cell_layer := sort_world.get_node_or_null(key) as TileMapLayer
	if cell_layer:
		cell_layer.erase_cell(cell)
		GridData.set_tile(cell, z, false)
		if cell_layer.get_used_cells().is_empty():
			cell_layer.queue_free()
		else:
			sort_world.call("sort_now")

		# 【连带瓦解】：地砖上的轻型植被（小麦）连带收割破坏，并爆出对应的小麦掉落物！
		for plant in objects_on_tile:
			var p_size: Vector2i = plant.get("grid_size") if plant.get("grid_size") != null else Vector2i(1, 1)
			var p_sp: Vector2i = plant.get("sub_cell") if plant.get("sub_cell") != null else Vector2i.ZERO
			var p_drop: String = plant.get("drop_item_id") if plant.get("drop_item_id") != null else ""
			var p_cnt: int = plant.get("drop_count") if plant.get("drop_count") != null else 1
			
			GridData.unregister_object(cell, p_sp, p_size)
			plant.queue_free()
			
			if p_drop != "":
				_spawn_item_drops(p_drop, p_cnt, cell, z, valid_neighbors, sort_world)

		# 抛出地砖自身的 3 堆泥土掉落物
		_spawn_item_drops("dirt", 3, cell, z, valid_neighbors, sort_world)

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
	
# 精准获取 2.5D 等距网格紧邻的 8 个物理相邻格（严格区分奇偶行）
func _get_surrounding_cells(cell: Vector2i) -> Array[Vector2i]:
	var is_odd := (absi(cell.y) % 2 == 1)
	if is_odd:
		return [
			Vector2i(cell.x, cell.y - 2),     # 正北 (North)
			Vector2i(cell.x, cell.y + 2),     # 正南 (South)
			Vector2i(cell.x - 1, cell.y),     # 正西 (West)
			Vector2i(cell.x + 1, cell.y),     # 正东 (East)
			Vector2i(cell.x, cell.y - 1),     # 西北 (North-West)
			Vector2i(cell.x + 1, cell.y - 1), # 东北 (North-East)
			Vector2i(cell.x, cell.y + 1),     # 西南 (South-West)
			Vector2i(cell.x + 1, cell.y + 1)  # 东南 (South-East)
		]
	else:
		return [
			Vector2i(cell.x, cell.y - 2),     # 正北 (North)
			Vector2i(cell.x, cell.y + 2),     # 正南 (South)
			Vector2i(cell.x - 1, cell.y),     # 正西 (West)
			Vector2i(cell.x + 1, cell.y),     # 正东 (East)
			Vector2i(cell.x - 1, cell.y - 1), # 西北 (North-West)
			Vector2i(cell.x, cell.y - 1),     # 东北 (North-East)
			Vector2i(cell.x - 1, cell.y + 1), # 西南 (South-West)
			Vector2i(cell.x, cell.y + 1)      # 东南 (South-East)
		]

# 收集周围 8 格中合法的邻居格子（有地面 且 高于本格不多于2层）
func _get_valid_drop_neighbors(center_cell: Vector2i, from_z: int) -> Array[Vector2i]:
	var surrounding := _get_surrounding_cells(center_cell)
	var valids: Array[Vector2i] = []
	
	for n_cell in surrounding:
		if not GridData.has_any_tile(n_cell):
			continue
		var n_z := GridData.get_highest_floor(n_cell)
		# 【单向拟真落差】：邻居高度 - 本格高度 <= 2
		if (n_z - from_z) <= 2:
			valids.append(n_cell)
			
	return valids

# 通用抛物线掉落物生成器（支持泥土、小麦、木头等任意物品）
func _spawn_item_drops(item_id: String, count: int, broken_cell: Vector2i, broken_z: int, valid_neighbors: Array[Vector2i], sort_world: Node2D) -> void:
	if dirt_scene == null or valid_neighbors.is_empty() or count <= 0:
		return

	var start_world_pos := GridData.cell_to_world(broken_cell) + Vector2(0.0, GridData.get_floor_pixel_offset(broken_z))

	for i in range(count):
		var target_cell: Vector2i = valid_neighbors.pick_random()
		var target_floor := GridData.get_highest_floor(target_cell)

		var rx := 12.0
		var ry := 6.0
		var rand_offset := Vector2.ZERO
		while true:
			var pt := Vector2(randf_range(-rx, rx), randf_range(-ry, ry)).round()
			if (abs(pt.x) / rx) + (abs(pt.y) / ry) <= 1.0:
				rand_offset = pt
				break

		var item_obj := dirt_scene.instantiate() as Node2D
		var target_world_pos := GridData.cell_to_world(target_cell) + rand_offset

		sort_world.add_child(item_obj)

		if item_obj.has_method("set_item_type"):
			item_obj.call("set_item_type", item_id)

		if item_obj.has_method("spawn_bounce"):
			item_obj.call("spawn_bounce", start_world_pos, target_world_pos, target_floor)
		else:
			item_obj.set("floor_level", target_floor)
			item_obj.set("base_position", target_world_pos)

	sort_world.call("sort_now")
