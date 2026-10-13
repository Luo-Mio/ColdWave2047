# wall_xray.gd —— 动态高墙与表面/物体透视控制器（支持高墙透视 + 草皮透视 + 柱顶物体透视 + 同层地基截面纯黑效果）
class_name WallXRayManager
extends Node

# 可在右侧检查器中可视化微调的参数
@export_group("高墙透视参数")
@export var rx: float = 60.0:
	set(v):
		rx = v
		if material: material.set_shader_parameter("rx", rx)
@export var ry: float = 120.0:
	set(v):
		ry = v
		if material: material.set_shader_parameter("ry", ry)
@export var feather: float = 1.0:           # 透视边缘羽化 (0.0=硬边, 1.0=极柔)
	set(v):
		feather = v
		if material: material.set_shader_parameter("feather", feather)
@export var max_transparency: float = 0.6: # 透明透视强度 (0.0=不透, 1.0=中心完全透空)
	set(v):
		max_transparency = v
		if material: material.set_shader_parameter("max_transparency", max_transparency)

@export_group("地基截面封顶参数")
## 透视时同层地基截面的渲染颜色（默认为纯黑，可在检查器微调）
@export var base_floor_color: Color = Color(0.0, 0.0, 0.0, 1.0):
	set(v):
		base_floor_color = v
		if cap_material: cap_material.set_shader_parameter("cap_color", base_floor_color)
		if tile_cap_manager: tile_cap_manager.update_channel_config(&"wall_xray", {"cap_color": base_floor_color})
## GPU 截面显现水平半径 (椭圆长半轴)
@export var cap_rx: float = 80.0:
	set(v):
		cap_rx = v
		if cap_material: cap_material.set_shader_parameter("rx", cap_rx)
		if tile_cap_manager: tile_cap_manager.update_channel_config(&"wall_xray", {"rx": cap_rx})
## GPU 截面显现垂直半径 (椭圆短半轴，适配 2:1 等距视角)
@export var cap_ry: float = 48.0:
	set(v):
		cap_ry = v
		if cap_material: cap_material.set_shader_parameter("ry", cap_ry)
		if tile_cap_manager: tile_cap_manager.update_channel_config(&"wall_xray", {"ry": cap_ry})
## GPU 截面边缘羽化渐变柔和度 (0.01=硬边, 1.0=极柔和淡出)
@export var cap_feather: float = 0.5:
	set(v):
		cap_feather = v
		if cap_material: cap_material.set_shader_parameter("feather", cap_feather)
		if tile_cap_manager: tile_cap_manager.update_channel_config(&"wall_xray", {"feather": cap_feather})
## GPU 截面最大不透明度
@export var cap_max_alpha: float = 1.0:
	set(v):
		cap_max_alpha = v
		if cap_material: cap_material.set_shader_parameter("max_alpha", cap_max_alpha)
		if tile_cap_manager: tile_cap_manager.update_channel_config(&"wall_xray", {"max_alpha": cap_max_alpha})
## 是否启用复古 Bayer 4x4 像素点阵抖动镂空
@export var cap_enable_dither: bool = false:
	set(v):
		cap_enable_dither = v
		if cap_material: cap_material.set_shader_parameter("enable_dither", cap_enable_dither)
		if tile_cap_manager: tile_cap_manager.update_channel_config(&"wall_xray", {"enable_dither": cap_enable_dither})
## 截面封顶的 Z-Index 渲染层级 (默认 1，高于所有 Z=0 瓷砖与物件，防止被前景立面截断)
@export var cap_z_index: int = 1

# 轻量截面封顶多边形绘制节点 (保留向后兼容别名)
class XRayCap extends Node2D:
	var sort_key: float = 0.0
	var layer_no: int = 999

	func _draw() -> void:
		var pts := PackedVector2Array([
			Vector2(0, -16),
			Vector2(32, 0),
			Vector2(0, 16),
			Vector2(-32, 0)
		])
		draw_colored_polygon(pts, Color.WHITE)

const TileCapManager := preload("res://script/systems/tile_cap_manager.gd")
var tile_cap_manager: TileCapManager = null
var material: ShaderMaterial
var cap_material: ShaderMaterial

# 多来源状态管理 (source_id -> Array[TileMapLayer] / Dictionary)
var _source_layers: Dictionary = {}   # source_id (StringName) -> Array[TileMapLayer]
var _source_objects: Dictionary = {}  # source_id (StringName) -> Dictionary { item (CanvasItem): { "material": Material, "z_index": int } }
var _source_nodes: Dictionary = {}    # source_id (StringName) -> Node2D
var _source_cap_items: Dictionary = {} # source_id (StringName) -> Array

# 兼容保留
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
		if s_id != exclude_source_id:
			if _source_layers[s_id].has(layer):
				return true
	return false

func _is_object_used_by_other_source(item: CanvasItem, exclude_source_id: StringName) -> bool:
	for s_id in _source_objects:
		if s_id != exclude_source_id:
			if _source_objects[s_id].has(item):
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
				if data is Dictionary:
					item.material = data.get("material")
					item.z_index = data.get("z_index", 0)
				else:
					item.material = data
					item.z_index = 0

# 核心判定算法：判断一个高墙格子是否属于真正的“背面遮挡端点” (采用“沿侧面延申方向向上追溯链条”法则)
func is_backside_occluder(front_cell: Vector2i, target_visual: Vector2, target_floor: int) -> bool:
	var wall_floor := GridData.get_highest_floor(front_cell)
	if wall_floor <= target_floor:
		return false

	var cell_center := GridData.cell_to_world(front_cell)

	# 规则 1：目标必须在格子的水平横轴之上 (即 cell_center.y > target_visual.y)
	if cell_center.y <= target_visual.y:
		return false

	# 规则 2：横向偏差判定与连续侧面骨架追溯
	var dx_screen := target_visual.x - cell_center.x

	# 若目标与格子水平正中对齐 (偏差 <= 16px)，说明角色正好处在正后方
	if absf(dx_screen) <= 16.0:
		return true

	# 若目标在右侧 (dx_screen > 16.0)：
	# 检查该格向右上 (北东方向) 是否有一整条连续高墙砖穿过目标的 Y 水平线
	if dx_screen > 16.0:
		var curr := front_cell
		while true:
			var is_odd := (absi(curr.y) % 2 == 1)
			var next_c := curr + (Vector2i(1, -1) if is_odd else Vector2i(0, -1))
			if GridData.has_any_tile(next_c) and GridData.get_highest_floor(next_c) > target_floor:
				var next_center := GridData.cell_to_world(next_c)
				if next_center.y <= target_visual.y:
					return false # 连成完整侧面，目标在开阔侧，绝非背面！
				curr = next_c
			else:
				break

	# 若目标在左侧 (dx_screen < -16.0)：
	# 检查该格向左上 (北西方向) 是否有一整条连续高墙砖穿过目标的 Y 水平线
	if dx_screen < -16.0:
		var curr := front_cell
		while true:
			var is_odd := (absi(curr.y) % 2 == 1)
			var next_c := curr + (Vector2i(0, -1) if is_odd else Vector2i(-1, -1))
			if GridData.has_any_tile(next_c) and GridData.get_highest_floor(next_c) > target_floor:
				var next_center := GridData.cell_to_world(next_c)
				if next_center.y <= target_visual.y:
					return false # 连成完整侧面，目标在开阔侧，绝非背面！
				curr = next_c
			else:
				break

	# 链条断裂且在目标下方：判定为真正的背面暴露端点！
	return true

## 核心多来源高墙与表面透视刷新接口
func update_target_xray(
	source_id: StringName,
	target_visual: Vector2,
	target_cell: Vector2i,
	target_floor: int,
	target_sort_key: float,
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
	var cur_target_height: float = float(config.get("target_height", 48.0))
	var channel_id: StringName = config.get("channel_id", source_id)
	var target_node: Node2D = config.get("target_node", null)
	var enable_stamp: bool = bool(config.get("enable_stamp", (source_id != &"player")))
	var xray_trans: float = float(config.get("max_transparency", max_transparency))
	var xray_curve: float = float(config.get("xray_curve", 0.0))

	var is_custom_center: bool = bool(config.get("use_custom_center", (source_id != &"player" and channel_id != &"wall_xray")))
	var center_world_p: Vector2 = config.get("center_pos", target_visual)

	var eff_rx := maxf(cur_rx, cur_cap_rx) + 32.0
	var eff_ry := maxf(cur_ry, cur_cap_ry) + 32.0

	var new_layers: Array[TileMapLayer] = []
	var new_objects: Dictionary = {}
	var cap_items: Array = []
	var cap_cells_set: Dictionary = {}

	var scan_r: int = clampi(int(ceil(eff_rx / 24.0)), 4, 16)

	for dy in range(-4, scan_r):
		for dx in range(-scan_r, scan_r):
			var front_cell := target_cell + Vector2i(dx, dy)
			var wall_floor := GridData.get_highest_floor(front_cell)

			if wall_floor <= target_floor:
				continue

			# 【核心深度准则 1】：地形障碍必须在角色/目标南侧 (前景)，其排序键必须严格大于目标！
			var wall_sort_key := GridData.cell_to_sort_key(front_cell)
			if wall_sort_key <= target_sort_key:
				continue

			var cell_center := GridData.cell_to_world(front_cell)

			# 【核心准则 2】：背面遮挡连续侧面判定（沿侧面延申方向向上追溯链条）
			if not is_backside_occluder(front_cell, target_visual, target_floor):
				continue

			# 【核心几何准则 3】：横向屏幕范围初筛
			if absf(target_visual.x - cell_center.x) > eff_rx:
				continue

			# 【核心几何准则 4】：垂直屏幕立面重叠判定
			var wall_bottom_y := cell_center.y + GridData.get_floor_pixel_offset(target_floor) + 16.0
			var wall_top_y := cell_center.y + GridData.get_floor_pixel_offset(wall_floor) - 16.0
			var tgt_top_y := target_visual.y - cur_target_height
			var tgt_bottom_y := target_visual.y + 4.0

			if wall_top_y > tgt_bottom_y or wall_bottom_y < (tgt_top_y - eff_ry):
				continue

			var is_cell_occluding := false

			# 3. 逐层检查高出目标视野的砖块是否进入透视范围
			for z in range(target_floor + 1, wall_floor + 1):
				var block_screen_pos := Vector2(cell_center.x, cell_center.y - float(z) * 16.0)
				var norm_x := (block_screen_pos.x - target_visual.x) / eff_rx
				var norm_y := (block_screen_pos.y - target_visual.y) / eff_ry

				if (norm_x * norm_x + norm_y * norm_y) <= 1.0:
					var key := "cell_z%d_%d_%d" % [z, front_cell.x, front_cell.y]
					var cell_layer := sort_world.get_node_or_null(key) as TileMapLayer
					if cell_layer:
						if not new_layers.has(cell_layer):
							cell_layer.material = material
							cell_layer.z_index = cap_z_index + 2
							new_layers.append(cell_layer)
						is_cell_occluding = true

			# 4. 【遮挡处理与封顶】：如果该格有砖块遮挡目标
			if is_cell_occluding:
				for z in range(target_floor + 1, wall_floor + 1):
					var key := "cell_z%d_%d_%d" % [z, front_cell.x, front_cell.y]
					var cell_layer := sort_world.get_node_or_null(key) as TileMapLayer
					if cell_layer and not new_layers.has(cell_layer):
						cell_layer.material = material
						cell_layer.z_index = cap_z_index + 2
						new_layers.append(cell_layer)
					_collect_surf_for_source(front_cell, z, sort_world, new_objects)

				_collect_objects_for_source(front_cell, target_floor, new_objects)
				cap_items.append({"cell": front_cell, "floor": target_floor})
				cap_cells_set[front_cell] = true

	# 5. 【几何范围封顶补充】(支持弹道落点等根据 cap_target 与 cap_range 补充附近瓷砖封顶)
	if cur_cap_max_alpha > 0.0 and config.has("cap_target"):
		var cap_tgt: int = int(config.get("cap_target", 0))
		var cap_range: int = int(config.get("cap_range", 2))
		var scan_rx := cap_range + 1
		var scan_ry := cap_range * 2 + 1
		for dy in range(-scan_ry, scan_ry + 1):
			for dx in range(-scan_rx, scan_rx + 1):
				var cell := target_cell + Vector2i(dx, dy)
				if not GridData.has_any_tile(cell):
					continue
				var fl: int = GridData.get_highest_floor(cell)
				if fl < target_floor:
					continue

				var is_cap_target := false
				if cap_tgt == 0:
					is_cap_target = (fl > target_floor) # 仅高墙底部
				elif cap_tgt == 1:
					is_cap_target = (fl >= target_floor) # 高墙底与同层地表
				elif cap_tgt == 2:
					is_cap_target = (fl == target_floor) # 仅同层地表

				if is_cap_target and not cap_cells_set.has(cell):
					cap_items.append({"cell": cell, "floor": target_floor})
					cap_cells_set[cell] = true

	# 释放本 source 上一轮占用但当前不再遮挡的图层与物件
	_release_source_items(source_id, new_layers, new_objects)
	_source_layers[source_id] = new_layers
	_source_objects[source_id] = new_objects
	_sync_active_arrays()

	# 封顶截面黑盖更新 (TileCapManager)
	if not cap_items.is_empty():
		if tile_cap_manager:
			tile_cap_manager.update_caps(channel_id, cap_items, {
				"use_custom_center": is_custom_center,
				"center_pos": center_world_p,
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

	# 注入透视光晕印章至 VisionFogComponent (供 xray.gdshader 采样点阵透视)
	if enable_stamp:
		if not cap_items.is_empty() or config.get("force_stamp", true):
			VisionFogComponent.set_custom_xray_stamp(source_id, target_visual, cur_rx, cur_ry, xray_trans, xray_curve)
		else:
			VisionFogComponent.clear_custom_xray_stamp(source_id)

	sort_world.call("sort_now")

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

	VisionFogComponent.clear_custom_xray_stamp(source_id)

## 动态刷新角色高墙透视 (向后兼容经典调用方式)
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
		"enable_stamp": false, # 角色自身的透视印章已由 VisionFogComponent 内建绘制
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
		if not is_instance_valid(obj):
			continue
		var obj_fl: int = obj.get("floor_level") if obj.get("floor_level") != null else GridData.get_highest_floor(cell)
		if obj_fl > min_floor:
			_collect_node_sprites(obj, target_objs)

	if objs.is_empty():
		for obj in get_tree().get_nodes_in_group("world_objects"):
			if not is_instance_valid(obj):
				continue
			var obj_base_pos: Vector2 = obj.get("base_position") if obj.get("base_position") != null and obj.get("base_position") != Vector2.ZERO else obj.global_position
			var obj_cell := GridData.world_to_cell(obj_base_pos)
			if obj_cell == cell:
				var obj_fl: int = obj.get("floor_level") if obj.get("floor_level") != null else GridData.get_highest_floor(cell)
				if obj_fl > min_floor:
					_collect_node_sprites(obj, target_objs)

	for drop in get_tree().get_nodes_in_group("drop_items"):
		if not is_instance_valid(drop):
			continue
		var drop_pos: Vector2 = drop.get("base_position") if drop.get("base_position") != null and drop.get("base_position") != Vector2.ZERO else drop.global_position
		var drop_cell := GridData.world_to_cell(drop_pos)
		if drop_cell == cell:
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

func _apply_xray_to_surf(cell: Vector2i, z: int, sort_world: Node2D) -> void:
	var def_objs: Dictionary = _source_objects.get(&"player", active_xray_objects)
	_collect_surf_for_source(cell, z, sort_world, def_objs)

func _apply_xray_to_objects_at(cell: Vector2i, min_floor: int) -> void:
	var def_objs: Dictionary = _source_objects.get(&"player", active_xray_objects)
	_collect_objects_for_source(cell, min_floor, def_objs)

func _apply_xray_to_node_sprites(obj: Node) -> void:
	var def_objs: Dictionary = _source_objects.get(&"player", active_xray_objects)
	_collect_node_sprites(obj, def_objs)

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
