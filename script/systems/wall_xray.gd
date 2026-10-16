# wall_xray.gd —— 动态高墙透视控制器 (纯连续墙体合成 90° 大扇区模型)
class_name WallXRayManager
extends Node

@export_group("高墙透视参数")
@export var rx: float = 60.0:
	set(v):
		rx = v
		if material: material.set_shader_parameter("rx", rx)
@export var ry: float = 120.0:
	set(v):
		ry = v
		if material: material.set_shader_parameter("ry", ry)
@export var feather: float = 1.0:
	set(v):
		feather = v
		if material: material.set_shader_parameter("feather", feather)
## 是否将透视瓦片降至完全透明 (100% 透明直接隐形，方便观测透视判定的具体格子)
@export var fully_transparent: bool = true:
	set(v):
		fully_transparent = v
		if material: material.set_shader_parameter("fully_transparent", fully_transparent)
@export var max_transparency: float = 0.6:
	set(v):
		max_transparency = v
		if material: material.set_shader_parameter("max_transparency", max_transparency)
## 屏幕视野网格搜索半径 (默认 14 格，覆盖整个 1080p 屏幕范围)
@export var search_radius: int = 14

@export_group("地基截面封顶参数")
@export var base_floor_color: Color = Color(0.0, 0.0, 0.0, 1.0):
	set(v):
		base_floor_color = v
		if cap_material: cap_material.set_shader_parameter("cap_color", base_floor_color)
		if tile_cap_manager: tile_cap_manager.update_channel_config(&"wall_xray", {"cap_color": base_floor_color})
@export var cap_rx: float = 80.0:
	set(v):
		cap_rx = v
		if cap_material: cap_material.set_shader_parameter("rx", cap_rx)
		if tile_cap_manager: tile_cap_manager.update_channel_config(&"wall_xray", {"rx": cap_rx})
@export var cap_ry: float = 48.0:
	set(v):
		cap_ry = v
		if cap_material: cap_material.set_shader_parameter("ry", cap_ry)
		if tile_cap_manager: tile_cap_manager.update_channel_config(&"wall_xray", {"ry": cap_ry})
@export var cap_feather: float = 0.5:
	set(v):
		cap_feather = v
		if cap_material: cap_material.set_shader_parameter("feather", cap_feather)
		if tile_cap_manager: tile_cap_manager.update_channel_config(&"wall_xray", {"feather": cap_feather})
@export var cap_max_alpha: float = 1.0:
	set(v):
		cap_max_alpha = v
		if cap_material: cap_material.set_shader_parameter("max_alpha", cap_max_alpha)
		if tile_cap_manager: tile_cap_manager.update_channel_config(&"wall_xray", {"max_alpha": cap_max_alpha})
@export var cap_enable_dither: bool = false:
	set(v):
		cap_enable_dither = v
		if cap_material: cap_material.set_shader_parameter("enable_dither", cap_enable_dither)
		if tile_cap_manager: tile_cap_manager.update_channel_config(&"wall_xray", {"enable_dither": cap_enable_dither})
@export var cap_z_index: int = 1

const TileCapManager := preload("res://script/systems/tile_cap_manager.gd")
const TerrainRenderManager := preload("res://script/systems/terrain_render_manager.gd")
var tile_cap_manager: TileCapManager = null
var terrain_render_manager: TerrainRenderManager = null
var material: ShaderMaterial
var cap_material: ShaderMaterial

# 多来源状态管理 (source_id -> Array[TileMapLayer] / Dictionary)
var _source_layers: Dictionary = {}    # source_id -> Array[TileMapLayer]
var _source_objects: Dictionary = {}   # source_id -> Dictionary { item: { "material": Material, "z_index": int } }
var _source_nodes: Dictionary = {}     # source_id -> Node2D
var _source_stamps: Dictionary = {}    # source_id -> Array[StringName]

# 向后兼容公开字段
var active_xray_layers: Array[TileMapLayer] = []
var active_xray_objects: Dictionary = {}
var active_caps: Array[Node2D] = []

func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://script/shaders/xray.gdshader")
	material.set_shader_parameter("rx", rx)
	material.set_shader_parameter("ry", ry)
	material.set_shader_parameter("feather", feather)
	material.set_shader_parameter("max_transparency", max_transparency)
	material.set_shader_parameter("fully_transparent", fully_transparent)

	cap_material = ShaderMaterial.new()
	cap_material.shader = load("res://script/shaders/xray_cap.gdshader")
	cap_material.set_shader_parameter("cap_color", base_floor_color)
	cap_material.set_shader_parameter("rx", cap_rx)
	cap_material.set_shader_parameter("ry", cap_ry)
	cap_material.set_shader_parameter("feather", cap_feather)
	cap_material.set_shader_parameter("max_alpha", cap_max_alpha)
	cap_material.set_shader_parameter("enable_dither", cap_enable_dither)

func _exit_tree() -> void:
	for s_id in _source_layers.keys().duplicate():
		clear_source_xray(s_id)

func _sync_active_arrays() -> void:
	active_xray_layers.clear()
	active_xray_objects.clear()
	for s_id in _source_layers:
		for layer in _source_layers[s_id]:
			if is_instance_valid(layer) and not active_xray_layers.has(layer):
				active_xray_layers.append(layer)
	for s_id in _source_objects:
		var objs: Dictionary = _source_objects[s_id]
		for item in objs:
			if is_instance_valid(item) and not active_xray_objects.has(item):
				active_xray_objects[item] = objs[item]

func _is_layer_used_by_other_source(layer: TileMapLayer, exclude_source_id: StringName) -> bool:
	for s_id in _source_layers:
		if s_id != exclude_source_id and _source_layers[s_id].has(layer):
			return true
	return false

func _is_object_used_by_other_source(item: CanvasItem, exclude_source_id: StringName) -> bool:
	for s_id in _source_objects:
		if s_id != exclude_source_id and _source_objects[s_id].has(item):
			return true
	return false

func _release_source_items(source_id: StringName, keep_layers: Array = [], keep_objects: Dictionary = {}) -> void:
	var old_layers: Array = _source_layers.get(source_id, [])
	for layer in old_layers:
		if not keep_layers.has(layer) and is_instance_valid(layer):
			if not _is_layer_used_by_other_source(layer, source_id):
				layer.material = VisionFogComponent.get_tile_shadow_material()
				layer.z_index = 0

	var old_objs: Dictionary = _source_objects.get(source_id, {})
	for item in old_objs.keys():
		if not keep_objects.has(item) and is_instance_valid(item):
			if not _is_object_used_by_other_source(item, source_id):
				var data = old_objs[item]
				item.material = data.get("material") if data is Dictionary else data
				item.z_index = data.get("z_index", 0) if data is Dictionary else 0

## 核心多来源高墙与表面透视刷新接口 (纯连续墙体合成 90° 大扇区模型)
func update_target_xray(
	source_id: StringName,
	target_visual: Vector2,
	target_cell: Vector2i,
	target_floor: int,
	_target_sort_key: float,
	sort_world: Node2D,
	config: Dictionary = {}
) -> void:
	_ensure_tile_cap_manager(sort_world)
	if sort_world == null or material == null:
		clear_source_xray(source_id)
		return

	var cur_rx: float = float(config.get("rx", rx))
	var cur_ry: float = float(config.get("ry", ry))
	var cur_cap_rx: float = float(config.get("cap_rx", cap_rx))
	var cur_cap_ry: float = float(config.get("cap_ry", cap_ry))
	var cur_cap_feather: float = float(config.get("cap_feather", cap_feather))
	var cur_cap_max_alpha: float = float(config.get("cap_max_alpha", cap_max_alpha))
	var cur_cap_color: Color = config.get("cap_color", base_floor_color)
	var cur_cap_dither: bool = bool(config.get("cap_enable_dither", cap_enable_dither))
	var channel_id: StringName = config.get("channel_id", source_id)
	var target_node: Node2D = config.get("target_node", null)
	var enable_stamp: bool = bool(config.get("enable_stamp", (source_id != &"player")))
	var xray_trans: float = float(config.get("max_transparency", max_transparency))
	var xray_curve: float = float(config.get("xray_curve", 0.0))
	var is_custom_center: bool = bool(config.get("use_custom_center", (source_id != &"player" and channel_id != &"wall_xray")))
	var center_world_p: Vector2 = config.get("center_pos", target_visual)

	# 1. 收集视野搜索范围内高于观察者的高墙格子 (优先使用动态视距窗口渲染集)
	var high_cells: Array[Vector2i] = []
	if terrain_render_manager and terrain_render_manager.is_enabled and source_id == &"player":
		terrain_render_manager.update_window(target_cell)
		high_cells = terrain_render_manager.get_high_cells(target_floor)
	else:
		for dy in range(-search_radius, search_radius + 1):
			for dx in range(-search_radius, search_radius + 1):
				var w_cell := target_cell + Vector2i(dx, dy)
				if GridData.has_any_tile(w_cell) and GridData.get_highest_floor(w_cell) > target_floor:
					high_cells.append(w_cell)

	# 2. 连通块聚类为连续墙体整体 (Clusters)
	var visited: Dictionary = {}
	var clusters: Array[Array] = []
	for c in high_cells:
		if visited.has(c):
			continue
		var cluster: Array[Vector2i] = []
		var queue: Array[Vector2i] = [c]
		visited[c] = true
		while not queue.is_empty():
			var curr: Vector2i = queue.pop_front()
			cluster.append(curr)
			for offset in [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1),
				Vector2i(0, 2), Vector2i(0, -2)
			]:
				var neighbor: Vector2i = curr + offset
				if high_cells.has(neighbor) and not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)
		clusters.append(cluster)

	# 3. 纯连续墙体合成 90° 大扇区判定 (方案 A)
	# 正面两条朝南(+Y)延展的边界射线方程为: y + 0.5x = L, y - 0.5x = R
	var occluding_cells: Dictionary = {}
	for cluster in clusters:
		var l_min: float = 999999.0
		var r_min: float = 999999.0
		for c: Vector2i in cluster:
			var w_pos := GridData.cell_to_world(c)
			var l_val := (w_pos.y - 16.0) + 0.5 * w_pos.x
			var r_val := (w_pos.y - 16.0) - 0.5 * w_pos.x
			l_min = minf(l_min, l_val)
			r_min = minf(r_min, r_val)

		var y_apex := (l_min + r_min) * 0.5
		var p_l := target_visual.y + 0.5 * target_visual.x
		var p_r := target_visual.y - 0.5 * target_visual.x

		var is_in_footprint: bool = cluster.has(target_cell)
		# 只要角色处于正面 90° 扇区内且身处交点南方，整堵连续墙体坚固阻挡视线，100% 豁免透视！
		# 但若角色直接站在墙体底座占地格子内，则必须透视！
		var in_cluster_sector: bool = (p_l >= l_min and p_r >= r_min and not is_in_footprint and target_visual.y >= y_apex)
		if in_cluster_sector:
			continue

		# 角色在正面 90° 扇区之外（身在墙后或墙侧盲区）：整堵连续墙直接全量透视！
		for c: Vector2i in cluster:
			occluding_cells[c] = mini(occluding_cells.get(c, 999), target_floor)

	# 4. 收集透视瓦片、表层地毯、树木与截面封顶
	var new_layers: Array[TileMapLayer] = []
	var new_objects: Dictionary = {}
	var cap_items: Array = []
	var new_stamp_ids: Array[StringName] = []

	for w_cell in occluding_cells.keys():
		var base_floor: int = occluding_cells[w_cell]
		var w_floor: int = GridData.get_highest_floor(w_cell)

		for z in range(base_floor + 1, w_floor + 1):
			var key := "cell_z%d_%d_%d" % [z, w_cell.x, w_cell.y]
			var cell_layer := sort_world.get_node_or_null(key) as TileMapLayer
			if cell_layer and not new_layers.has(cell_layer):
				cell_layer.material = material
				cell_layer.z_index = cap_z_index + 2
				new_layers.append(cell_layer)
			_collect_surf_for_source(w_cell, z, sort_world, new_objects)

		_collect_objects_for_source(w_cell, base_floor, new_objects)
		cap_items.append({"cell": w_cell, "floor": base_floor})

		var stamp_id := StringName("%s_w_%d_%d" % [source_id, w_cell.x, w_cell.y])
		var w_pos := GridData.cell_to_world(w_cell) + Vector2(0.0, GridData.get_floor_pixel_offset(base_floor))
		VisionFogComponent.set_custom_xray_stamp(stamp_id, w_pos, 44.0, 32.0, xray_trans, 0.0)
		new_stamp_ids.append(stamp_id)

	# 5. 释放本 source 上一轮占用但当前不再遮挡的图层、物件与印章
	_release_source_items(source_id, new_layers, new_objects)
	_source_layers[source_id] = new_layers
	_source_objects[source_id] = new_objects
	_sync_active_arrays()

	var old_stamps: Array = _source_stamps.get(source_id, [])
	for s in old_stamps:
		if not new_stamp_ids.has(s):
			VisionFogComponent.clear_custom_xray_stamp(s)
	_source_stamps[source_id] = new_stamp_ids

	# 6. 封顶截面黑盖与目标层级更新
	if not cap_items.is_empty():
		if tile_cap_manager:
			tile_cap_manager.update_caps(channel_id, cap_items, {
				"use_custom_center": is_custom_center,
				"center_pos": center_world_p,
				"disable_distance_fade": true,
				"rx": cur_cap_rx,
				"ry": cur_cap_ry,
				"feather": cur_cap_feather,
				"max_alpha": cur_cap_max_alpha,
				"cap_color": cur_cap_color,
				"enable_dither": cur_cap_dither,
				"z_index": cap_z_index
			})
		if is_instance_valid(target_node):
			target_node.z_index = cap_z_index + 1
			_source_nodes[source_id] = target_node
	else:
		if tile_cap_manager:
			tile_cap_manager.clear_caps(channel_id)
		if is_instance_valid(target_node) and target_node.z_index != 0:
			target_node.z_index = 0
		_source_nodes.erase(source_id)

	if enable_stamp:
		if not cap_items.is_empty() or config.get("force_stamp", true):
			VisionFogComponent.set_custom_xray_stamp(source_id, target_visual, cur_rx, cur_ry, xray_trans, xray_curve)
		else:
			VisionFogComponent.clear_custom_xray_stamp(source_id)

## 清除指定来源的高墙与表面透视
func clear_source_xray(source_id: StringName) -> void:
	_release_source_items(source_id, [], {})
	_source_layers.erase(source_id)
	_source_objects.erase(source_id)
	_sync_active_arrays()

	if _source_nodes.has(source_id):
		var node: Node2D = _source_nodes[source_id]
		if is_instance_valid(node) and node.z_index != 0:
			node.z_index = 0
		_source_nodes.erase(source_id)

	if tile_cap_manager:
		var ch_id: StringName = &"wall_xray" if source_id == &"player" else source_id
		tile_cap_manager.clear_caps(ch_id)

	var old_stamps: Array = _source_stamps.get(source_id, [])
	for s in old_stamps:
		VisionFogComponent.clear_custom_xray_stamp(s)
	_source_stamps.erase(source_id)
	VisionFogComponent.clear_custom_xray_stamp(source_id)

## 动态刷新角色高墙透视 (向后兼容调用)
func update_wall_xray(player_node: Node2D, sort_world: Node2D) -> void:
	if player_node == null:
		clear_source_xray(&"player")
		return

	var player_visual: Vector2 = player_node.global_position
	if player_node.has_method("get_visual_foot_position"):
		player_visual = player_node.call("get_visual_foot_position")

	var player_cell := GridData.world_to_cell(player_node.global_position)
	var player_floor: int = player_node.call("get_current_floor") if player_node.has_method("get_current_floor") else GridData.get_floor_at_pos(player_node.global_position)
	var player_sort_key: float = float(player_node.get("sort_key")) if player_node.get("sort_key") != null else GridData.cell_to_sort_key(player_cell)

	update_target_xray(&"player", player_visual, player_cell, player_floor, player_sort_key, sort_world, {
		"target_node": player_node,
		"target_height": 48.0,
		"channel_id": &"wall_xray",
		"enable_stamp": false,
	})

func _ensure_tile_cap_manager(sort_world: Node2D) -> void:
	if tile_cap_manager != null:
		return
	if get_parent() and get_parent().get("tile_cap_manager"):
		tile_cap_manager = get_parent().tile_cap_manager
	elif get_tree() and get_tree().root:
		tile_cap_manager = get_tree().root.find_child("TileCapManager", true, false)

func _collect_surf_for_source(cell: Vector2i, z: int, sort_world: Node2D, target_objs: Dictionary) -> void:
	if sort_world == null:
		return
	var dual_cells := LayerSurfSystem.get_affected_dual_cells(cell)
	for d in dual_cells:
		var key := "surf_z%d_%d_%d" % [z, d.x, d.y]
		var surf_node := sort_world.get_node_or_null(key) as CanvasItem
		if surf_node == null:
			surf_node = sort_world.get_node_or_null("turf_z%d_%d_%d" % [z, d.x, d.y]) as CanvasItem
		
		if surf_node and not target_objs.has(surf_node):
			var orig_mat = surf_node.material
			var orig_z = surf_node.z_index
			for s_id in _source_objects:
				if _source_objects[s_id].has(surf_node):
					orig_mat = _source_objects[s_id][surf_node].get("material", orig_mat)
					orig_z = _source_objects[s_id][surf_node].get("z_index", orig_z)
					break
			target_objs[surf_node] = {
				"material": orig_mat,
				"z_index": orig_z
			}
			surf_node.material = material
			surf_node.z_index = cap_z_index + 2

func _collect_objects_for_source(cell: Vector2i, min_floor: int, target_objs: Dictionary) -> void:
	var objs := GridData.get_all_objects_at(cell)
	for obj in objs:
		if is_instance_valid(obj):
			var obj_fl: int = obj.get("floor_level") if obj.get("floor_level") != null else GridData.get_highest_floor(cell)
			if obj_fl > min_floor:
				_collect_node_sprites(obj, target_objs)

	if objs.is_empty():
		for obj in get_tree().get_nodes_in_group("world_objects"):
			if is_instance_valid(obj):
				var obj_base_pos: Vector2 = obj.get("base_position") if obj.get("base_position") != null and obj.get("base_position") != Vector2.ZERO else obj.global_position
				if GridData.world_to_cell(obj_base_pos) == cell:
					var obj_fl: int = obj.get("floor_level") if obj.get("floor_level") != null else GridData.get_highest_floor(cell)
					if obj_fl > min_floor:
						_collect_node_sprites(obj, target_objs)

	for drop in get_tree().get_nodes_in_group("drop_items"):
		if is_instance_valid(drop):
			var drop_pos: Vector2 = drop.get("base_position") if drop.get("base_position") != null and drop.get("base_position") != Vector2.ZERO else drop.global_position
			if GridData.world_to_cell(drop_pos) == cell:
				var drop_fl: int = drop.get("floor_level") if drop.get("floor_level") != null else 0
				if drop_fl > min_floor:
					_collect_node_sprites(drop, target_objs)

func _collect_node_sprites(obj: Node, target_objs: Dictionary) -> void:
	if obj is CanvasItem and not target_objs.has(obj):
		var orig_mat = (obj as CanvasItem).material
		var orig_z = (obj as CanvasItem).z_index
		for s_id in _source_objects:
			if _source_objects[s_id].has(obj):
				orig_mat = _source_objects[s_id][obj].get("material", orig_mat)
				orig_z = _source_objects[s_id][obj].get("z_index", orig_z)
				break
		target_objs[obj] = {
			"material": orig_mat,
			"z_index": orig_z
		}
		(obj as CanvasItem).z_index = cap_z_index + 2

	for sprite in _get_all_visual_sprites(obj):
		if not target_objs.has(sprite):
			var orig_mat = sprite.material
			var orig_z = sprite.z_index
			for s_id in _source_objects:
				if _source_objects[s_id].has(sprite):
					orig_mat = _source_objects[s_id][sprite].get("material", orig_mat)
					orig_z = _source_objects[s_id][sprite].get("z_index", orig_z)
					break
			target_objs[sprite] = {
				"material": orig_mat,
				"z_index": orig_z
			}
		sprite.material = material
		if not (obj is CanvasItem):
			sprite.z_index = cap_z_index + 2

func _get_all_visual_sprites(obj: Node) -> Array[CanvasItem]:
	var result: Array[CanvasItem] = []
	if obj == null:
		return result
	var stack: Array[Node] = [obj]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Sprite2D or n is AnimatedSprite2D or n is Polygon2D:
			result.append(n as CanvasItem)
		for c in n.get_children():
			stack.push_back(c)
	return result
