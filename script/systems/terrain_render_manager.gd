# terrain_render_manager.gd —— 2.5D 动态地形与世界渲染范围视距管理器 (Terrain Render Window Manager)
# 职责：
# 1. 以玩家/摄像机为中心，动态维护 19x19 等轴测菱形活动渲染网格窗口 (Active Render Window)。
# 2. 视野范围外的地形切片 (cell_layer)、地表切片 (surf_layer)、落差边缘 (edge_layer)、静态装饰物自动隐藏 (visible = false)，消除不可见绘制。
# 3. 视野范围外的生物/实体 (Creatures/Entities) 仅隐藏渲染 (visible = false)，其 _physics_process、AI与物理碰撞照常全速运行。
# 4. 提供进入视野 (tile_entered_window) 与离开视野 (tile_exited_window) 的事件/回调与动画钩子 (Animation Hooks)，支持未来瓦片升起/掉落动态加载表现。
# 5. 集中暴露当前渲染区域的全部有效格子集合 (get_rendered_cells)，供高墙透视 (WallXRay) 直接调用，彻底杜绝远景大型地貌误透视。
# 6. 【极速优化】：全节点 O(1) 哈希索引缓存 + 动态实体列表追踪，彻底消除运行时字符串拼接与全场景遍历，保证 120 FPS 丝滑运行。
class_name TerrainRenderManager
extends Node

signal render_window_updated(center_cell: Vector2i, rendered_cells: Dictionary)
signal tile_entered_window(cell: Vector2i, floor_level: int, node: CanvasItem)
signal tile_exited_window(cell: Vector2i, floor_level: int, node: CanvasItem)

@export_group("地貌采样与视距参数")
## 是否启用地貌活动窗口采样 (供 WallXRay 聚类与地貌分析)
@export var is_enabled: bool = true:
	set(v):
		is_enabled = v
		if is_inside_tree() and _sort_world:
			if not is_enabled:
				_restore_all_visuals()
			elif _last_center_cell != Vector2i(-99999, -99999):
				update_window(_last_center_cell, true)

## 是否限制地形渲染范围 (false = 取消限制渲染，全图自然完整渲染，绝无切边或半截浮空草皮；true = 裁剪视距外瓦片)
@export var cull_terrain_visuals: bool = false:
	set(v):
		cull_terrain_visuals = v
		if is_inside_tree() and _sort_world:
			if not cull_terrain_visuals:
				_restore_all_visuals()
			elif _last_center_cell != Vector2i(-99999, -99999):
				update_window(_last_center_cell, true)

## 地貌分析采样菱形半宽 (默认 20，即 [-20, 20] 构成 41x41 菱形采样窗口，跨度达 2560x1280 像素，远超屏幕之外)
@export_range(5, 50, 1) var sample_radius: int = 20:
	set(v):
		sample_radius = v
		if is_inside_tree() and _last_center_cell != Vector2i(-99999, -99999):
			update_window(_last_center_cell, true)

## 东南方向额外补偿排数 (用于补偿 2.5D 俯视角向南倾斜或前置高台视觉落差，默认 0)
@export_range(-10, 10, 1) var se_offset_rows: int = 0:
	set(v):
		se_offset_rows = v
		if is_inside_tree() and _last_center_cell != Vector2i(-99999, -99999):
			update_window(_last_center_cell, true)

## 是否对范围外的生物执行渲染剔除 (仅 visible = false，物理与AI逻辑持续满帧运行)
@export var cull_creatures_outside: bool = false

# 兼容旧代码变量名
var render_radius: int:
	get: return sample_radius
	set(v): sample_radius = v

## 是否启用新进入视野瓦片的动画钩子
@export var enable_spawn_animation: bool = false

## 瓦片入场过渡时长 (秒)
@export_range(0.05, 1.0, 0.05) var anim_duration: float = 0.25

# 内部引用
var _sort_world: Node2D = null
var _floor0_layer: TileMapLayer = null
var _floor0_surf_layer: TileMapLayer = null
var _player_node: Node2D = null

# 渲染窗口数据
var rendered_cells: Dictionary = {} # Vector2i -> bool
var _last_center_cell: Vector2i = Vector2i(-99999, -99999)

# 0层瓦片图元模板缓存 (用于动态从 0 层 TileMapLayer 中擦除/重新写入): cell (Vector2i) -> Dictionary
var _floor0_template: Dictionary = {}
var _floor0_surf_template: Dictionary = {}

# 【极速缓存】：cell_key (int) -> Array[CanvasItem] (立体瓦片、草皮、落差边缘)
var _cell_nodes_cache: Dictionary = {}

# 【实体跟踪】：仅跟踪动态生物，杜绝每帧遍历 sort_world
var _tracked_entities: Array[CanvasItem] = []

## 初始化配置接口
func setup(sort_world_ref: Node2D, floor0_ref: TileMapLayer, floor0_surf_ref: TileMapLayer, player_ref: Node2D) -> void:
	_sort_world = sort_world_ref
	_floor0_layer = floor0_ref
	_floor0_surf_layer = floor0_surf_ref
	_player_node = player_ref

	# 1. 缓存 0 层底板全部地砖图元数据
	_floor0_template.clear()
	if _floor0_layer:
		for c in _floor0_layer.get_used_cells():
			_floor0_template[c] = {
				"source": _floor0_layer.get_cell_source_id(c),
				"atlas": _floor0_layer.get_cell_atlas_coords(c),
				"alt": _floor0_layer.get_cell_alternative_tile(c)
			}

	# 2. 缓存 0 层草皮表面图元数据
	_floor0_surf_template.clear()
	if _floor0_surf_layer:
		for c in _floor0_surf_layer.get_used_cells():
			_floor0_surf_template[c] = {
				"source": _floor0_surf_layer.get_cell_source_id(c),
				"atlas": _floor0_surf_layer.get_cell_atlas_coords(c),
				"alt": _floor0_surf_layer.get_cell_alternative_tile(c)
			}

	# 3. 建立 sort_world 节点 O(1) 瞬时反查索引，并收集动态生物
	_rebuild_node_index()

	if is_enabled and cull_terrain_visuals:
		_init_cull()
	else:
		_restore_all_visuals()

## 建立立体地形切片与实体的 O(1) 快速索引缓存
func _rebuild_node_index() -> void:
	_cell_nodes_cache.clear()
	_tracked_entities.clear()
	if _sort_world == null:
		return

	for child in _sort_world.get_children():
		if child == _player_node or child.name == "CharacterBody2D":
			continue

		# 动态生物实体 (仅加入生物清单)
		if child is CharacterBody2D or ("foot_y" in child and not (child is TileMapLayer)):
			if child is CanvasItem and not _tracked_entities.has(child):
				_tracked_entities.append(child)
			continue

		# 地形节点：cell_z%d_%d_%d, surf_z%d_%d_%d, turf_z%d_%d_%d, edge_z%d_%d_%d
		var n_name: String = child.name
		if n_name.begins_with("cell_z") or n_name.begins_with("surf_z") or n_name.begins_with("turf_z") or n_name.begins_with("edge_z"):
			var parts := n_name.split("_")
			if parts.size() >= 4:
				var cx := int(parts[2])
				var cy := int(parts[3])
				var ck := GridData.cell_key(Vector2i(cx, cy))
				if not _cell_nodes_cache.has(ck):
					_cell_nodes_cache[ck] = []
				_cell_nodes_cache[ck].append(child)

## 初始化全图视距裁剪（仅在启用视觉裁剪时调用）
func _init_cull() -> void:
	if not cull_terrain_visuals:
		return
	if _floor0_layer:
		_floor0_layer.clear()
	if _floor0_surf_layer:
		_floor0_surf_layer.clear()
	for ck in _cell_nodes_cache:
		var arr: Array = _cell_nodes_cache[ck]
		for item in arr:
			if item is CanvasItem:
				item.visible = false

## 恢复所有图层与瓦片的可见性（禁用本管理器时自动复原全图显示）
func _restore_all_visuals() -> void:
	if _floor0_layer:
		for c in _floor0_template:
			var d: Dictionary = _floor0_template[c]
			_floor0_layer.set_cell(c, d["source"], d["atlas"], d["alt"])
	if _floor0_surf_layer:
		for c in _floor0_surf_template:
			var d: Dictionary = _floor0_surf_template[c]
			_floor0_surf_layer.set_cell(c, d["source"], d["atlas"], d["alt"])
	for ck in _cell_nodes_cache:
		var arr: Array = _cell_nodes_cache[ck]
		for item in arr:
			if item is CanvasItem:
				item.visible = true
	for entity in _tracked_entities:
		if is_instance_valid(entity):
			entity.visible = true

## 核心窗口刷新：根据中心格子坐标，计算新进入与离开视野的 19x19 菱形格子集合
func update_window(center_cell: Vector2i, force: bool = false) -> void:
	if not is_enabled:
		return
	if center_cell == _last_center_cell and not force:
		return
	_last_center_cell = center_cell

	# 1. 计算以 center_cell 为中心的 41x41 等轴测菱形采样窗口 (对角线横跨 2560x1280 像素，远在屏幕之外)
	var center_pos := GridData.cell_to_world(center_cell)
	var new_rendered: Dictionary = {}
	var max_r: int = sample_radius + maxi(0, se_offset_rows)
	var max_dy: int = max_r * 2
	var max_dx: int = int(ceil(float(max_r) * 1.3))
	var limit: float = float(sample_radius) + 0.5
	var u_min: float = -limit
	var u_max: float = limit + float(se_offset_rows)

	for dy in range(-max_dy, max_dy + 1):
		for dx in range(-max_dx, max_dx + 1):
			var c := center_cell + Vector2i(dx, dy)
			if not GridData.has_any_tile(c):
				continue
			var w_pos := GridData.cell_to_world(c)
			var rel := w_pos - center_pos
			var u := (rel.x / 64.0) + (rel.y / 32.0)
			var v := (rel.y / 32.0) - (rel.x / 64.0)
			if u >= u_min and u <= u_max and absf(v) <= limit:
				new_rendered[c] = true

	# 2. 仅在启用视觉裁剪时才操作瓦片隐藏与写入
	if cull_terrain_visuals:
		var entered_cells: Array[Vector2i] = []
		var exited_cells: Array[Vector2i] = []

		for c: Vector2i in new_rendered:
			if not rendered_cells.has(c):
				entered_cells.append(c)

		for c: Vector2i in rendered_cells:
			if not new_rendered.has(c):
				exited_cells.append(c)

		for c in exited_cells:
			_set_cell_visual_state(c, false)

		for c in entered_cells:
			_set_cell_visual_state(c, true)

	rendered_cells = new_rendered

	# 3. 生物实体视距裁剪 (仅当启用生物剔除且开启视觉裁剪时触发)
	if cull_creatures_outside and cull_terrain_visuals:
		_cull_entities()

	render_window_updated.emit(center_cell, rendered_cells)

## 控制单个网格格子的视觉呈现状态 (纯 O(1) 字典检索，零节点遍历，零字符串拼接)
func _set_cell_visual_state(c: Vector2i, is_vis: bool) -> void:
	# 1. 底层 0 层地砖 (从静态 TileMapLayer 中擦除或动态绘制)
	if _floor0_layer:
		if is_vis:
			if _floor0_template.has(c):
				var data: Dictionary = _floor0_template[c]
				_floor0_layer.set_cell(c, data["source"], data["atlas"], data["alt"])
		else:
			_floor0_layer.erase_cell(c)

	# 2. 底层 0 层草皮表面
	if _floor0_surf_layer:
		if is_vis:
			if _floor0_surf_template.has(c):
				var data: Dictionary = _floor0_surf_template[c]
				_floor0_surf_layer.set_cell(c, data["source"], data["atlas"], data["alt"])
		else:
			_floor0_surf_layer.erase_cell(c)

	# 3. 1 层及以上立体瓦片、地表切片与落差白边 (O(1) 索引直出)
	var ck := GridData.cell_key(c)
	var nodes: Array = _cell_nodes_cache.get(ck, [])
	for item in nodes:
		if item is CanvasItem:
			item.visible = is_vis
			if is_vis:
				_handle_spawn_animation(item, c)
				tile_entered_window.emit(c, int(item.get("layer_no")) if item.get("layer_no") != null else 1, item)
			else:
				tile_exited_window.emit(c, int(item.get("layer_no")) if item.get("layer_no") != null else 1, item)

	# 4. 格子上的世界物体 (大树、农作物等)
	var objs: Array[Node] = GridData.get_all_objects_at(c)
	for obj in objs:
		if obj is CanvasItem:
			var c_item := obj as CanvasItem
			c_item.visible = is_vis
			if is_vis:
				_handle_spawn_animation(c_item, c)

## 生物实体极速视距裁剪 (仅检查动态生物清单，零全图遍历)
func _cull_entities() -> void:
	for entity in _tracked_entities:
		if is_instance_valid(entity):
			var e_cell := GridData.world_to_cell(entity.global_position)
			entity.visible = rendered_cells.has(e_cell)

## 瓦片与物体进入视野时的动画钩子
func _handle_spawn_animation(node: CanvasItem, _cell: Vector2i) -> void:
	if not enable_spawn_animation:
		return
	if node == null or not is_instance_valid(node):
		return
	node.modulate.a = 0.0
	var tween := node.create_tween()
	tween.tween_property(node, "modulate:a", 1.0, anim_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 运行时动态放置/破坏瓦片时的通知接口
func notify_tile_modified(cell: Vector2i, z: int) -> void:
	if z == 0 and _floor0_layer:
		if GridData.has_tile(cell, 0):
			_floor0_template[cell] = {
				"source": _floor0_layer.get_cell_source_id(cell),
				"atlas": _floor0_layer.get_cell_atlas_coords(cell),
				"alt": _floor0_layer.get_cell_alternative_tile(cell)
			}
		else:
			_floor0_template.erase(cell)
	else:
		_rebuild_node_index()

	if rendered_cells.has(cell):
		_set_cell_visual_state(cell, true)

## 公共查询接口：获取当前活动渲染窗口内的所有有效格子字典
func get_rendered_cells() -> Dictionary:
	return rendered_cells

## 公共查询接口：获取当前活动渲染窗口内高于指定楼层的高墙格子列表
func get_high_cells(target_floor: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for c: Vector2i in rendered_cells.keys():
		if GridData.get_highest_floor(c) > target_floor:
			result.append(c)
	return result

## 公共查询接口：指定格子当前是否处于渲染视窗内
func is_cell_rendered(cell: Vector2i) -> bool:
	return rendered_cells.has(cell)
