
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

	var item_id: String = item.get("id", "")
	if item_id.ends_with("_surf") or item_id.ends_with("_turf") or item_id == "grass_surf" or item_id == "grass_turf":
		_place_surf(cell, selector, item_id)
	elif item["type"] == 0:  # TILE
		_place_tile(cell, item["atlas"], sort_world, selector, tile_layers)
	elif item["type"] == 1:  # OBJECT
		var grid_size: Vector2i = item.get("grid_size", Vector2i(4, 4))
		var sub_cell: Vector2i = Vector2i.ZERO
		# 只有非 4x4 的微小物体（如小麦）才读取鼠标瞄准的微格，4x4 大树必须始终居中对齐 (0, 0)
		if grid_size != Vector2i(4, 4) and selector != null:
			sub_cell = selector.get("target_sub_cell")
		_place_object(cell, item["scene"], sort_world, sub_cell, grid_size)

# 放置表面覆盖物（草皮/菌毯/积雪等）
func _place_surf(cell: Vector2i, selector: Node2D, item_id: String = "grass_surf") -> void:
	if not GridData.has_any_tile(cell):
		return
	var z := GridData.get_highest_floor(cell)
	var surf_type := "grass"
	if item_id.begins_with("creep"):
		surf_type = "creep"
	elif item_id.begins_with("snow"):
		surf_type = "snow"

	if LayerSurfSystem.instance and not LayerSurfSystem.instance.has_surf(cell, z):
		LayerSurfSystem.instance.set_surf(cell, z, true, surf_type)
		if selector:
			selector.call("force_update")

# 兼容旧方法
func _place_turf(cell: Vector2i, selector: Node2D) -> void:
	_place_surf(cell, selector, "grass_surf")

# 放置瓷砖
func _place_tile(cell: Vector2i, tile_atlas: Vector2i, sort_world: Node2D, selector: Node2D, tile_layers: Array[TileMapLayer]) -> void:
	# 【拦截】：如果本格种有小麦（哪怕只有1株）或种有大树，严禁在其上方叠放瓷砖！
	if GridData.has_any_object(cell):
		return

	var prev_z := GridData.get_highest_floor(cell)

	var z: int
	if GridData.is_half_tile(cell, prev_z):
		# 如果本格当前顶层是自动半砖，放置完整地砖直接升级替换该半砖为完整砖块！
		z = prev_z
		GridData.remove_auto_half_tile_only(cell, z)
	else:
		z = prev_z + 1

	# 【新约束】：放置新瓷砖时，覆压摧毁原顶面上的草皮/表面覆层
	# 当前不掉落（spawn_drop = false），底层复用通用掉落系统，未来只需置为 true 即可掉落
	if LayerSurfSystem.instance and LayerSurfSystem.instance.has_surf(cell, prev_z):
		destroy_surf_at(cell, prev_z, sort_world, false)

	_set_tile_visual(cell, z, tile_atlas, sort_world, tile_layers)
	GridData.set_tile(cell, z, true)
	if LayerSurfSystem.instance:
		LayerSurfSystem.instance.update_surf_around_tile(cell, z)

	# 联动刷新本格及四周的三角半砖
	update_half_tiles_around(cell, z, sort_world, tile_layers)
	_rebuild_air_wall_if_present(sort_world)

	sort_world.call("sort_now")
	selector.call("force_update")

## 统一表面覆层破坏接口（支持草皮、菌毯、积雪等）
## [spawn_drop] 为 false 时仅清除不产出掉落物，为 true 时按通用掉落规则抛出掉落物
func destroy_surf_at(cell: Vector2i, z: int, sort_world: Node2D, spawn_drop: bool = false) -> void:
	if LayerSurfSystem.instance == null or not LayerSurfSystem.instance.has_surf(cell, z):
		return

	var s_type := GridData.get_surf(cell, z)
	var drop_item_id := s_type + "_surf"

	# 1. 从双网格系统与 GridData 中彻底清除
	LayerSurfSystem.instance.set_surf(cell, z, false)

	# 2. 掉落物产出（与瓷砖、物体共用同一套抛物线掉落系统）
	if spawn_drop:
		var surf_valid_neighbors := _get_valid_drop_neighbors(cell, z)
		if not surf_valid_neighbors.is_empty():
			_spawn_item_drops(drop_item_id, 1, cell, z, surf_valid_neighbors, sort_world)

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
func destroy_top_at(cell: Vector2i, sort_world: Node2D, selector: Node2D, tile_layers: Array[TileMapLayer] = []) -> void:
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

	# 2. 如果地表有表面覆盖物（草皮/菌毯/雪），优先铲除（爆出对应掉落物，保留底下的泥土地砖！）
	var top_z := GridData.get_highest_floor(cell)
	if LayerSurfSystem.instance and LayerSurfSystem.instance.has_surf(cell, top_z):
		destroy_surf_at(cell, top_z, sort_world, true)
		selector.call("force_update")
		return

	# 3. 准备破坏最上层瓷砖（地面0层不拆）
	var z := top_z
	if z <= 0:
		return

	# 自动半砖由两侧完整砖块支撑，不允许单独挖除
	if GridData.is_half_tile(cell, z):
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
		if LayerSurfSystem.instance:
			LayerSurfSystem.instance.update_surf_around_tile(cell, z)
		if cell_layer.get_used_cells().is_empty():
			cell_layer.queue_free()
		else:
			sort_world.call("sort_now")

		# 【半砖联动刷新】：摧毁该层地砖后，周围受其支撑的半砖自动清除！
		var layers_to_use: Array[TileMapLayer] = tile_layers if not tile_layers.is_empty() else GridData.layers
		update_half_tiles_around(cell, z, sort_world, layers_to_use)
		_rebuild_air_wall_if_present(sort_world)

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
# 每高 1 层往上移 16 像素
	cell_layer.position = Vector2(0.0, -float(z) * 16.0) # 8.0 改为 16.0
	cell_layer.y_sort_enabled = true
	cell_layer.collision_enabled = false
	cell_layer.set("sort_key", GridData.cell_to_sort_key(cell))
	cell_layer.set("layer_no", z)
	# 统一挂载地表动态阴影共享材质 (享元模式，所有瓦片共用一份 ShaderMaterial)
	cell_layer.material = VisionFogComponent.get_tile_shadow_material()
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
		# 在 64x32 菱形范围内更宽广自然地散落
		var rx := 24.0 # 原本是 12.0
		var ry := 12.0 # 原本是 6.0
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

# === 三角半砖 (1/2 Tile) 自动生成、消除与渲染同步 ===

# 统一设置指定坐标与楼层的地砖视觉 (0层使用地面基底图层，1层及以上在 sort_world 动态分层)
func _set_tile_visual(cell: Vector2i, z: int, atlas: Vector2i, sort_world: Node2D, tile_layers: Array[TileMapLayer]) -> void:
	if z == 0 and not tile_layers.is_empty():
		tile_layers[0].set_cell(cell, 0, atlas, 0)
	else:
		var cell_layer := get_or_create_cell_layer(z, cell, sort_world, tile_layers)
		cell_layer.set_cell(cell, 0, atlas, 0)

# 统一清除指定坐标与楼层的地砖视觉
func _erase_tile_visual(cell: Vector2i, z: int, sort_world: Node2D, tile_layers: Array[TileMapLayer]) -> void:
	if z == 0 and not tile_layers.is_empty():
		tile_layers[0].erase_cell(cell)
	var key := "cell_z%d_%d_%d" % [z, cell.x, cell.y]
	var cell_layer := sort_world.get_node_or_null(key) as TileMapLayer
	if cell_layer:
		cell_layer.erase_cell(cell)
		if cell_layer.get_used_cells().is_empty():
			cell_layer.queue_free()

# 当某格地砖发生变动时，联动检测本格及周围物理相邻格，自动增删填补三角半砖
func update_half_tiles_around(center_cell: Vector2i, z: int, sort_world: Node2D, tile_layers: Array[TileMapLayer]) -> void:
	var layers_to_use: Array[TileMapLayer] = tile_layers if not tile_layers.is_empty() else GridData.layers
	var candidates: Array[Vector2i] = [center_cell]
	for n in _get_surrounding_cells(center_cell):
		if not candidates.has(n):
			candidates.append(n)

	for c in candidates:
		# 若本格在该层已有完整砖块，绝不生成半砖
		if GridData.has_full_tile(c, z):
			continue

		var desired_shape: int = GridData.determine_half_tile_shape(c, z)
		var current_shape: int = GridData.get_auto_half_tile_shape(c, z)

		if desired_shape != -1:
			# 需要半砖
			if current_shape != desired_shape:
				GridData.set_auto_half_tile(c, z, desired_shape)
				_set_tile_visual(c, z, GridData.TILE_SHAPE_ATLAS[desired_shape], sort_world, layers_to_use)
		else:
			# 不需要半砖
			if current_shape != -1:
				_cleanup_objects_on_cell(c, z, sort_world)
				GridData.remove_auto_half_tile(c, z)
				_erase_tile_visual(c, z, sort_world, layers_to_use)

# 全量构建所有楼层的三角半砖 (地图初始化时调用)
func update_all_half_tiles(sort_world: Node2D, tile_layers: Array[TileMapLayer]) -> void:
	var layers_to_use: Array[TileMapLayer] = tile_layers if not tile_layers.is_empty() else GridData.layers
	var floors_checked: Dictionary = {}
	for k in GridData.grid.keys():
		floors_checked[k.z] = true

	for z in floors_checked.keys():
		var cells_at_z: Array[Vector2i] = []
		for k in GridData.grid.keys():
			if k.z == z and not GridData.is_half_tile(Vector2i(k.x, k.y), z):
				cells_at_z.append(Vector2i(k.x, k.y))
		for cell in cells_at_z:
			update_half_tiles_around(cell, z, sort_world, layers_to_use)
	_rebuild_air_wall_if_present(sort_world)

# 清理某格指定楼层上的植物与掉落物
func _cleanup_objects_on_cell(cell: Vector2i, z: int, sort_world: Node2D) -> void:
	var objects_on_tile: Array[Node] = GridData.get_all_objects_at(cell)
	if objects_on_tile.is_empty():
		return
	var valid_neighbors := _get_valid_drop_neighbors(cell, z)
	for plant in objects_on_tile:
		var p_size: Vector2i = plant.get("grid_size") if plant.get("grid_size") != null else Vector2i(1, 1)
		var p_sp: Vector2i = plant.get("sub_cell") if plant.get("sub_cell") != null else Vector2i.ZERO
		var p_drop: String = plant.get("drop_item_id") if plant.get("drop_item_id") != null else ""
		var p_cnt: int = plant.get("drop_count") if plant.get("drop_count") != null else 1

		GridData.unregister_object(cell, p_sp, p_size)
		plant.queue_free()

		if p_drop != "" and not valid_neighbors.is_empty():
			_spawn_item_drops(p_drop, p_cnt, cell, z, valid_neighbors, sort_world)

# 联动更新边缘空气墙 (若场景中存在 AirWall)
func _rebuild_air_wall_if_present(sort_world: Node2D) -> void:
	if sort_world == null:
		return
	var parent := sort_world.get_parent()
	if parent != null:
		var aw = parent.get_node_or_null("AirWall")
		if aw != null and aw.has_method("rebuild_walls"):
			aw.call("rebuild_walls")
