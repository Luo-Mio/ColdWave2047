# tile_cap_manager.gd —— 通用等轴测地基/高墙截面纯黑遮罩管理器 (Tile Cap Manager)
# 统一管理角色高墙透视地基截面与弹道着弹点落点遮罩等多来源黑盖渲染
# 采用统一 GPU xray_cap.gdshader 材质 + 64x32 菱形几何节点池化管理，深度排序接入 sort_world
class_name TileCapManager
extends Node

const CapShader := preload("res://script/shaders/xray_cap.gdshader")

# 内部轻量菱形绘制节点 (配合 GPU Shader 实现平滑淡出与 Bayer 点阵抖动)
class TileCapNode extends Node2D:
	var sort_key: float = 0.0
	var layer_no: int = 999
	var cell: Vector2i = Vector2i.ZERO
	var floor_level: int = 0
	var source_id: StringName = &""

	func _draw() -> void:
		var pts := PackedVector2Array([
			Vector2(0, -16),
			Vector2(32, 0),
			Vector2(0, 16),
			Vector2(-32, 0)
		])
		draw_colored_polygon(pts, Color.WHITE)

@export_group("全局默认封顶参数")
@export var default_cap_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var default_rx: float = 80.0
@export var default_ry: float = 48.0
@export var default_feather: float = 0.5
@export var default_max_alpha: float = 1.0
@export var default_enable_dither: bool = false
@export var default_cap_z_index: int = 1

# 引用缓存
var _sort_world: Node2D = null
var _player_node: Node2D = null
var grid_data: Node = null

# 通道状态管理 (支持多系统独立并发调用)
# source_id -> ShaderMaterial
var _channel_materials: Dictionary = {}
# source_id -> Array[TileCapNode]
var _channel_active_caps: Dictionary = {}
# source_id -> Dictionary (保存上次 update_caps_in_range 的参数以优化高频刷新)
var _last_range_params: Dictionary = {}

# 对象池 (消除频繁 new() 和 queue_free() 带来的内存抖动)
var _node_pool: Array[TileCapNode] = []

func _get_grid_data() -> Node:
	if grid_data != null and is_instance_valid(grid_data):
		return grid_data
	if is_inside_tree() and get_tree() and get_tree().root:
		grid_data = get_tree().root.get_node_or_null("GridData")
	if grid_data == null and Engine.has_singleton("GridData"):
		grid_data = Engine.get_singleton("GridData")
	return grid_data

func _get_cell_world_pos(cell: Vector2i, fl: int) -> Vector2:
	var gd = _get_grid_data()
	if gd:
		return gd.cell_to_world(cell) + Vector2(0.0, gd.get_floor_pixel_offset(fl))
	var x := float(cell.x) * 32.0 - float(cell.y) * 32.0
	var y := float(cell.x) * 16.0 + float(cell.y) * 16.0 - float(fl) * 16.0
	return Vector2(x, y)

func _get_cell_sort_key(cell: Vector2i) -> float:
	var gd = _get_grid_data()
	if gd:
		return gd.cell_to_sort_key(cell)
	return float(cell.x + cell.y)

func _has_tile(cell: Vector2i) -> bool:
	var gd = _get_grid_data()
	if gd:
		return gd.has_any_tile(cell)
	return true

func _get_highest_floor(cell: Vector2i) -> int:
	var gd = _get_grid_data()
	if gd:
		return gd.get_highest_floor(cell)
	return 0

func _exit_tree() -> void:
	clear_all_caps()
	for node in _node_pool:
		if is_instance_valid(node):
			node.queue_free()
	_node_pool.clear()

## 初始化绑定排序容器与角色
func setup(p_sort_world: Node2D, p_player_node: Node2D = null) -> void:
	_sort_world = p_sort_world
	_player_node = p_player_node
	if _player_node == null and _sort_world != null:
		_player_node = _sort_world.get_node_or_null("CharacterBody2D")

## 获取或初始化指定渠道的专用 ShaderMaterial
func get_or_create_channel_material(source_id: StringName) -> ShaderMaterial:
	if _channel_materials.has(source_id):
		return _channel_materials[source_id]

	var mat := ShaderMaterial.new()
	mat.shader = CapShader
	mat.set_shader_parameter("cap_color", default_cap_color)
	mat.set_shader_parameter("rx", default_rx)
	mat.set_shader_parameter("ry", default_ry)
	mat.set_shader_parameter("feather", default_feather)
	mat.set_shader_parameter("max_alpha", default_max_alpha)
	mat.set_shader_parameter("enable_dither", default_enable_dither)
	mat.set_shader_parameter("use_custom_center", false)
	mat.set_shader_parameter("center_world_pos", Vector2.ZERO)
	_channel_materials[source_id] = mat
	return mat

## 更新指定渠道的着色器材质参数
func update_channel_config(source_id: StringName, config: Dictionary) -> void:
	var mat := get_or_create_channel_material(source_id)
	if config.has("cap_color"):
		mat.set_shader_parameter("cap_color", config["cap_color"])
	if config.has("rx"):
		mat.set_shader_parameter("rx", float(config["rx"]))
	if config.has("ry"):
		mat.set_shader_parameter("ry", float(config["ry"]))
	if config.has("feather"):
		mat.set_shader_parameter("feather", float(config["feather"]))
	if config.has("max_alpha"):
		mat.set_shader_parameter("max_alpha", float(config["max_alpha"]))
	if config.has("enable_dither"):
		mat.set_shader_parameter("enable_dither", bool(config["enable_dither"]))
	if config.has("use_custom_center"):
		mat.set_shader_parameter("use_custom_center", bool(config["use_custom_center"]))
	if config.has("center_pos"):
		mat.set_shader_parameter("center_world_pos", config["center_pos"])

## 快速更新指定渠道的焦点世界坐标 (仅更新 uniform，零节点重构开销)
func update_channel_focal_pos(source_id: StringName, focal_pos: Vector2) -> void:
	var mat := get_or_create_channel_material(source_id)
	mat.set_shader_parameter("use_custom_center", true)
	mat.set_shader_parameter("center_world_pos", focal_pos)

## 核心接口 1：根据格子列表批量更新指定渠道的封顶遮罩面 (通用底层接口)
## items: Array[Dictionary] 或 Array[Vector3i] 或 Array[Vector2i]
##   字典格式: [{"cell": Vector2i, "floor": int}, ...]
##   Vector3i 格式: [Vector3i(x, y, floor), ...]
## config: 可选配置覆盖字典 (rx, ry, feather, max_alpha, cap_color, enable_dither, z_index 等)
func update_caps(source_id: StringName, items: Array, config: Dictionary = {}) -> void:
	if _sort_world == null:
		return

	# 1. 材质与层级参数配置
	if not config.is_empty():
		update_channel_config(source_id, config)
	var mat := get_or_create_channel_material(source_id)
	var z_idx: int = int(config.get("z_index", default_cap_z_index))

	var active_list: Array[TileCapNode]
	if _channel_active_caps.has(source_id):
		active_list = _channel_active_caps[source_id]
	else:
		active_list = []
		_channel_active_caps[source_id] = active_list

	var target_count := items.size()

	# 2. 从对象池获取节点或将超额节点归还池中
	while active_list.size() < target_count:
		var node: TileCapNode
		if not _node_pool.is_empty():
			node = _node_pool.pop_back()
		else:
			node = TileCapNode.new()
		node.source_id = source_id
		_sort_world.add_child(node)
		active_list.append(node)

	while active_list.size() > target_count:
		var node: TileCapNode = active_list.pop_back()
		if node.get_parent() == _sort_world:
			_sort_world.remove_child(node)
		_node_pool.append(node)

	# 3. 逐个刷新节点属性
	for i in range(target_count):
		var item = items[i]
		var c: Vector2i = Vector2i.ZERO
		var fl: int = 0
		if item is Dictionary:
			c = item.get("cell", Vector2i.ZERO)
			fl = int(item.get("floor", 0))
		elif item is Vector3i:
			c = Vector2i(item.x, item.y)
			fl = item.z
		elif item is Vector2i:
			c = item
			fl = int(config.get("floor", 0))

		var node: TileCapNode = active_list[i]
		node.name = "cap_%s_%d_%d" % [String(source_id), c.x, c.y]
		node.cell = c
		node.floor_level = fl
		node.position = _get_cell_world_pos(c, fl)
		node.sort_key = _get_cell_sort_key(c)
		node.layer_no = 999
		node.material = mat
		node.z_index = z_idx
		node.visible = true

	# 4. 角色层级同步与世界深度排序
	_sync_player_z_index()
	if target_count > 0 and _sort_world != null and _sort_world.has_method("sort_now"):
		_sort_world.call("sort_now")

## 核心接口 2：根据等距几何范围自动生成封顶遮罩面 (适用于弹道落点等)
## cap_target: 0=仅高于参考层的墙底(fl > floor_level), 1=高墙底与地表(fl >= floor_level), 2=仅同层地表(fl == floor_level)
func update_caps_in_range(
	source_id: StringName,
	center_cell: Vector2i,
	range_radius: int,
	floor_level: int,
	cap_target: int = 0,
	config: Dictionary = {}
) -> void:
	if _sort_world == null:
		return

	# 高频优化：若中心格子与范围参数完全未变，仅更新材质 uniform (如准星平滑漂移)，无需重复构建节点
	var last_p: Dictionary = _last_range_params.get(source_id, {})
	var is_same_range: bool = (
		last_p.get("center_cell") == center_cell and
		last_p.get("range_radius") == range_radius and
		last_p.get("floor_level") == floor_level and
		last_p.get("cap_target") == cap_target and
		_channel_active_caps.has(source_id) and
		not _channel_active_caps[source_id].is_empty()
	)

	if is_same_range:
		update_channel_config(source_id, config)
		return

	_last_range_params[source_id] = {
		"center_cell": center_cell,
		"range_radius": range_radius,
		"floor_level": floor_level,
		"cap_target": cap_target
	}

	# 几何范围筛选
	var items: Array = []
	var scan_rx := range_radius + 1
	var scan_ry := range_radius * 2 + 1
	for dy in range(-scan_ry, scan_ry + 1):
		for dx in range(-scan_rx, scan_rx + 1):
			var cell := center_cell + Vector2i(dx, dy)
			if not _has_tile(cell):
				continue
			var fl: int = _get_highest_floor(cell)
			if fl < floor_level:
				continue

			var is_target := false
			if cap_target == 0:
				is_target = (fl > floor_level)
			elif cap_target == 1:
				is_target = (fl >= floor_level)
			elif cap_target == 2:
				is_target = (fl == floor_level)

			if not is_target:
				continue

			items.append({"cell": cell, "floor": floor_level})

	update_caps(source_id, items, config)

## 清除指定渠道的遮罩面 (节点自动回收至对象池)
func clear_caps(source_id: StringName) -> void:
	_last_range_params.erase(source_id)
	if not _channel_active_caps.has(source_id):
		return
	var active_list: Array[TileCapNode] = _channel_active_caps[source_id]
	if active_list.is_empty():
		return

	for node in active_list:
		if is_instance_valid(node) and node.get_parent() == _sort_world:
			_sort_world.remove_child(node)
		_node_pool.append(node)
	active_list.clear()

	_sync_player_z_index()
	if _sort_world != null and _sort_world.has_method("sort_now"):
		_sort_world.call("sort_now")

## 清除所有渠道的遮罩面
func clear_all_caps() -> void:
	_last_range_params.clear()
	for source_id in _channel_active_caps.keys():
		var active_list: Array[TileCapNode] = _channel_active_caps[source_id]
		for node in active_list:
			if is_instance_valid(node) and node.get_parent() == _sort_world:
				_sort_world.remove_child(node)
			_node_pool.append(node)
		active_list.clear()

	_sync_player_z_index()
	if _sort_world != null and _sort_world.has_method("sort_now"):
		_sort_world.call("sort_now")

## 查询指定渠道是否拥有活跃封顶面
func has_caps(source_id: StringName) -> bool:
	if not _channel_active_caps.has(source_id):
		return false
	return not _channel_active_caps[source_id].is_empty()

## 获取所有活跃封顶面总数
func get_total_active_caps() -> int:
	var total := 0
	for list in _channel_active_caps.values():
		total += list.size()
	return total

## 同步角色渲染层级：当存在遮罩面时提升角色层级至遮罩上方，遮罩全部清除后复原
func _sync_player_z_index() -> void:
	if not is_instance_valid(_player_node):
		if _sort_world != null:
			_player_node = _sort_world.get_node_or_null("CharacterBody2D")
		if not is_instance_valid(_player_node):
			return

	if get_total_active_caps() > 0:
		_player_node.z_index = default_cap_z_index + 1
	else:
		if _player_node.z_index != 0:
			_player_node.z_index = 0
