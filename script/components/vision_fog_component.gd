# vision_fog_component.gd —— 战争迷雾与 2.5D 视线遮蔽通用组件 (全屏分辨率视野)
class_name VisionFogComponent
extends Node

@export_group("视野核心参数")
## 屏幕边缘外扩裕量 (像素)。用于在障碍物刚接近屏幕边缘时提前生成阴影，防止边缘闪烁
@export var screen_margin: float = 96.0
## 历史探索区域的留底深浅 (0.0=全亮探索即清空, 0.35=半透明辅助阴影, 1.0=完全纯黑未见)
@export_range(0.0, 1.0, 0.05) var explored_alpha: float = 0.35:
	set(v):
		explored_alpha = v
		_sync_tile_shadow_params()
## 未探索未知区域的浓雾深浅 (0.5=半透明开发调试, 1.0=纯黑伸手不见五指)
@export_range(0.0, 1.0, 0.05) var unexplored_alpha: float = 0.50:
	set(v):
		unexplored_alpha = v
		_sync_tile_shadow_params()
## 是否隐藏视线盲区内的其他生物。勾选后，躲在阴影或厚墙后的生物将彻底隐形
@export var enable_creature_hiding: bool = true
## 遮挡视线的物理障碍层掩码。通常为 Layer 2 障碍物层 (数值 2)
@export_flags_2d_physics var obstacle_mask: int = 2
## 屏幕内单次最大障碍物探测数量上限。极限密林测试可调大至 1024
@export var max_obstacles: int = 512
## 地图边界覆盖尺寸 (像素)。用于历史探索图尺寸范围映射
@export var map_bounds: float = 4096.0

@export_group("迷雾表现与点阵模式")
## 是否在全屏渲染迷雾覆盖层。设为 false 将完全关闭全屏黑雾
@export var enable_black_fog_overlay: bool = true:
	set(v):
		enable_black_fog_overlay = v
		if is_instance_valid(fog_rect):
			fog_rect.visible = enable_black_fog_overlay
## 是否启用纯黑点阵抖动迷雾。开启后呈现边缘黑点稀疏、中心纯黑的复古像素艺术质感；关闭则为平滑灰色渐变
@export var enable_dither_fog: bool = true:
	set(v):
		enable_dither_fog = v
		_sync_tile_shadow_params()
## 点阵像素缩放颗粒度 (1=精细屏幕像素, 2=2x2复古像素块)
@export_range(1, 4) var dither_scale: int = 1:
	set(v):
		dither_scale = v
		_sync_tile_shadow_params()
## 阴影边缘过渡羽化柔和度 (像素)。数值越大，边缘黑点向中心过渡越宽越柔和
@export_range(4.0, 80.0, 1.0) var fog_edge_softness: float = 24.0:
	set(v):
		fog_edge_softness = v
		_sync_tile_shadow_params()
## 是否将动态投影仅渲染在地表瓷砖层 (物体之下)。开启后树木等前景物体自然遮盖地表阴影，全屏层仅负责未知黑雾
@export var render_shadows_under_objects: bool = true:
	set(v):
		render_shadows_under_objects = v
		_sync_tile_shadow_params()
## 是否允许生物透过半透明树冠显现 (屏幕内生物处于树叶下时保留可见轮廓)
@export var show_creatures_through_canopy: bool = true

@export_group("透视遮罩全局配置 (X-Ray)")
## 透视默认边缘透明度渐变曲线弧度 (0.0=45度直线线性渐变, 1.0=1/4圆弧先平缓再陡降)
@export_range(0.0, 1.0, 0.05) var default_xray_curve: float = 0.0

@export_group("地形 3D 视线遮挡 (Route B)")
## 是否启用基于 2.5D 高度场的 3D 视线步进地形阴影 (高台与悬崖遮挡)
@export var enable_terrain_shadows: bool = true
## 3D 视线步进步数 (推荐 24~48，步数越高光影边缘越平滑)
@export_range(8, 64, 1) var terrain_raymarch_steps: int = 32:
	set(v):
		terrain_raymarch_steps = v
		if terrain_mat != null:
			terrain_mat.set_shader_parameter("raymarch_steps", terrain_raymarch_steps)
## 3D 地形阴影边缘半影软化宽度 (0.0=硬阴影, 16.0=极柔和半影，过渡平缓)
@export_range(0.0, 48.0, 1.0) var terrain_shadow_softness: float = 16.0:
	set(v):
		terrain_shadow_softness = v
		if terrain_mat != null:
			terrain_mat.set_shader_parameter("shadow_softness", terrain_shadow_softness)


var entity: CharacterBody2D
var main_cam: Camera2D

# 内部全屏迷雾画布与视口
var canvas_layer: CanvasLayer
var fog_rect: ColorRect
var fog_viewport: SubViewport
var fog_cam: Camera2D
var terrain_drawer: Node2D
var terrain_mat: ShaderMaterial
var fog_drawer: Node2D


# 享元模式：全局地表瓦片阴影共享材质单例 (所有 cell_layer 瓦片共用一份材质，显存零浪费且底层自动合批)
static var shared_tile_shadow_material: ShaderMaterial = null

static func get_tile_shadow_material() -> ShaderMaterial:
	if shared_tile_shadow_material == null:
		var shader := load("res://script/shaders/tile_ground_shadow.gdshader") as Shader
		if shader:
			shared_tile_shadow_material = ShaderMaterial.new()
			shared_tile_shadow_material.shader = shader
	return shared_tile_shadow_material

func _sync_tile_shadow_params() -> void:
	if is_instance_valid(fog_rect) and fog_rect.material is ShaderMaterial:
		var fog_mat := fog_rect.material as ShaderMaterial
		fog_mat.set_shader_parameter("explored_alpha", explored_alpha)
		fog_mat.set_shader_parameter("unexplored_alpha", unexplored_alpha)
		fog_mat.set_shader_parameter("enable_dither_fog", enable_dither_fog)
		fog_mat.set_shader_parameter("dither_scale", dither_scale)
		fog_mat.set_shader_parameter("edge_softness", fog_edge_softness)
		fog_mat.set_shader_parameter("render_shadows_under_objects", render_shadows_under_objects)

	var tile_mat := get_tile_shadow_material()
	if tile_mat != null:
		tile_mat.set_shader_parameter("active", render_shadows_under_objects)
		tile_mat.set_shader_parameter("shadow_darkness", explored_alpha)
		tile_mat.set_shader_parameter("enable_dither_fog", enable_dither_fog)
		tile_mat.set_shader_parameter("dither_scale", dither_scale)
		tile_mat.set_shader_parameter("edge_softness", fog_edge_softness)

	var obj_mat := ObjectXRayComponent.get_shared_material()
	if obj_mat != null:
		obj_mat.set_shader_parameter("shadow_darkness", explored_alpha)
		obj_mat.set_shader_parameter("enable_dither_fog", enable_dither_fog)
		obj_mat.set_shader_parameter("dither_scale", dither_scale)

# 内部多实体透视遮罩视口与摄像机
var xray_viewport: SubViewport
var xray_cam: Camera2D
var xray_drawer: Node2D
var _radial_tex_cache: Dictionary = {}
var _visible_creatures: Array[Node2D] = []

# 性能优化：静态障碍物碰撞多边形缓存对象
class ObstacleCacheItem:
	var world_pos: Vector2
	var center: Vector2
	var world_pts: PackedVector2Array
	var obstacle_node: Node = null
	var obstacle_height: float = 48.0
	var floor_level: int = 0

var _obstacle_cache: Dictionary = {} # int (collider_id) -> ObstacleCacheItem

# 批处理阴影三角网格缓冲 (合批为 1 次底层渲染，预分配零 GC)
var _batched_vertices: PackedVector2Array = PackedVector2Array()
var _batched_indices: PackedInt32Array = PackedInt32Array()
var _batched_colors: PackedColorArray = PackedColorArray([Color(0, 0, 0, 1)])
var _static_indices: PackedInt32Array = PackedInt32Array()

# 移动距离微阈值 (像素，防止极微小抖动造成无意义重绘)
@export var move_threshold: float = 1.0

# 视野几何运算节流刷新率 (默认 30.0 FPS，省电且大幅节约 CPU 算力)
@export var vision_fps: float = 60.0
var _vision_timer: float = 999.0
var _mask_cam_pos := Vector2(-99999, -99999)

# 性能优化：预分配矩形物理查询对象、单射线查询对象、排除列表与脏重绘检测
var _rect_shape: RectangleShape2D
var _shape_query: PhysicsShapeQueryParameters2D
var _shared_ray_query: PhysicsRayQueryParameters2D
var _excluded_rids: Array[RID] = []
var _ray_exclude_rids: Array[RID] = []
var _last_draw_pos := Vector2(-99999, -99999)
var _last_draw_player_pos := Vector2(-99999, -99999)
var _last_history_stamp_pos := Vector2(-99999, -99999)
var _last_quads_hash: int = -1

# 历史探索记忆 (低分辨率图像)
var history_image: Image
var history_texture: ImageTexture
const MAP_RES: int = 256
var _history_update_timer: float = 0.0

# 当帧计算的阴影四边形与对应投射体 Collider ID
var current_shadow_quads: Array[PackedVector2Array] = []
var _quad_source_cids: Array[int] = []
var current_quads_count: int = 0

func _ready() -> void:
	# 向上查找实体
	var curr := get_parent()
	while curr:
		if curr is CharacterBody2D:
			entity = curr as CharacterBody2D
			break
		curr = curr.get_parent()

	if entity == null:
		return

	main_cam = entity.find_child("Camera2D", true, false) as Camera2D

	# 预分配矩形物理探测参数（直接匹配屏幕视口包围盒），避免每帧分配垃圾
	_rect_shape = RectangleShape2D.new()
	_shape_query = PhysicsShapeQueryParameters2D.new()
	_shape_query.shape = _rect_shape
	_shape_query.collision_mask = obstacle_mask
	_shape_query.collide_with_bodies = true
	_shape_query.collide_with_areas = false

	# 预分配生物单射线物理探测参数 (零 GC 垃圾回收)
	_shared_ray_query = PhysicsRayQueryParameters2D.new()
	_shared_ray_query.collision_mask = obstacle_mask
	_shared_ray_query.collide_with_bodies = true
	_shared_ray_query.collide_with_areas = false

	# 预分配底层顶点与索引合批池 (避免运行时动态扩容)
	_batched_vertices.resize(max_obstacles * 4)
	_init_indices_pool(max_obstacles)

	_init_history_map()
	_setup_fog_rendering_pipeline()
	_sync_tile_shadow_params()

func _physics_process(delta: float) -> void:
	if entity == null:
		return

	var player_pos := entity.global_position
	if entity.has_method("get_visual_foot_position"):
		player_pos = entity.call("get_visual_foot_position")

	# 获取主摄像机
	if not is_instance_valid(main_cam):
		main_cam = entity.find_child("Camera2D", true, false) as Camera2D
		if not is_instance_valid(main_cam):
			main_cam = get_viewport().get_camera_2d()

	var cam_pos := player_pos
	var cam_zoom := Vector2.ONE
	if is_instance_valid(main_cam):
		cam_pos = main_cam.get_screen_center_position()
		cam_zoom = main_cam.zoom

	if _mask_cam_pos == Vector2(-99999, -99999):
		_mask_cam_pos = cam_pos

	# 1. 广播全局 Shader 变量给树冠与遮挡物透视以及地表阴影
	var vp_size_vec := Vector2(fog_viewport.size) if is_instance_valid(fog_viewport) else Vector2(1152, 648)
	var facing_dir_global: Vector2 = entity.call("get_facing_direction") if entity.has_method("get_facing_direction") else Vector2.DOWN
	RenderingServer.global_shader_parameter_set("vision_cam_pos", _mask_cam_pos)
	RenderingServer.global_shader_parameter_set("vision_cam_zoom", cam_zoom)
	RenderingServer.global_shader_parameter_set("vision_screen_size", vp_size_vec)
	RenderingServer.global_shader_parameter_set("player_facing_dir", facing_dir_global)
	RenderingServer.global_shader_parameter_set("vision_fov", 360.0)

	# 1.5 同步透视遮罩视口摄像机并触发平滑重绘 (多实体移动实时响应)
	if is_instance_valid(xray_cam):
		xray_cam.position = cam_pos
		xray_cam.zoom = cam_zoom
	if is_instance_valid(xray_drawer):
		xray_drawer.queue_redraw()

	# 2. 同步摄像机与屏幕参数给全屏黑雾 Shader (若开启黑雾)
	if is_instance_valid(fog_rect):
		fog_rect.visible = enable_black_fog_overlay
		if enable_black_fog_overlay and fog_rect.material is ShaderMaterial:
			var mat := fog_rect.material as ShaderMaterial
			mat.set_shader_parameter("cam_world_pos", cam_pos)
			mat.set_shader_parameter("mask_cam_pos", _mask_cam_pos)
			mat.set_shader_parameter("cam_zoom", cam_zoom)
			mat.set_shader_parameter("screen_size", vp_size_vec)
			mat.set_shader_parameter("map_bounds", Vector2(map_bounds, map_bounds))
			mat.set_shader_parameter("explored_alpha", explored_alpha)
			mat.set_shader_parameter("unexplored_alpha", unexplored_alpha)

	# 2. 视野几何运算与遮蔽判定节流 (按 vision_fps，例如 30 FPS 执行，CPU 算力直降 75%！)
	_vision_timer += delta
	var vision_interval := 1.0 / maxi(1, int(vision_fps))
	if _vision_timer >= vision_interval:
		_vision_timer = fmod(_vision_timer, vision_interval)

		# 确保物理排除列表（虚空空气墙与自身）已注入底层查询，完全不占用检测名额
		_ensure_excluded_rids()

		# 获取角色的楼层高度与海平面绝对视线高度
		var player_floor: int = 0
		if entity.has_method("get_current_floor"):
			player_floor = entity.call("get_current_floor")
		elif "depth_comp" in entity and is_instance_valid(entity.get("depth_comp")) and "current_floor" in entity.get("depth_comp"):
			player_floor = entity.get("depth_comp").current_floor
		else:
			player_floor = _get_cell_floor(player_pos)

		var player_eye_h: float = float(entity.get("eye_height")) if entity.get("eye_height") != null else 18.0
		var h_eye_total := float(player_floor) * 16.0 + player_eye_h

		# 当前屏幕分辨率对应的世界空间可视包围盒
		var screen_world_rect := _get_screen_world_rect(cam_pos, cam_zoom, 48.0)

		# 收集屏幕内的物理障碍物，几何运算投射到屏幕外的阴影体 (纯净地表坐标与 3D 几何截断)
		var quads_changed := _calculate_shadow_quads(player_pos, cam_pos, cam_zoom, player_floor, h_eye_total)

		# 运算屏幕内生物显隐与视线遮蔽 (结合几何阴影体判定与 3D 视线高度判定)
		if enable_creature_hiding:
			_update_creature_visibility(player_pos, screen_world_rect, h_eye_total)
		else:
			_collect_visible_creatures(screen_world_rect)

		# 运算屏幕内物体阴影覆盖状态 (在投影内的物体叠加阴影，不在投影内的物体处于阴影之上)
		_update_objects_shadow_state(player_pos, screen_world_rect, h_eye_total)

		# 脏标记智能重绘：仅当摄像机位移、角色位移或阴影形状变动时才重绘，静止时 0 额外 CPU/GPU 消耗！
		var threshold_sq := move_threshold * move_threshold
		var moved := player_pos.distance_squared_to(_last_draw_player_pos) > threshold_sq or cam_pos.distance_squared_to(_last_draw_pos) > threshold_sq
		if is_instance_valid(fog_drawer) and (moved or quads_changed or _last_draw_pos == Vector2(-99999, -99999)):
			_last_draw_pos = cam_pos
			_last_draw_player_pos = player_pos
			_mask_cam_pos = cam_pos
			# 同步视口摄像机
			if is_instance_valid(fog_cam):
				fog_cam.position = cam_pos
				fog_cam.zoom = cam_zoom
			var true_ground_pos := entity.global_position if entity != null else player_pos
			_update_terrain_raymarch_params(true_ground_pos, h_eye_total)
			if is_instance_valid(terrain_drawer):
				terrain_drawer.queue_redraw()

			fog_drawer.queue_redraw()
			if is_instance_valid(fog_viewport):
				fog_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


	# 3. 周期性累加全屏视野的历史探索足迹
	_history_update_timer -= delta
	if _history_update_timer <= 0.0:
		_history_update_timer = 0.5 # 每 500ms 检查一次，大幅降低 CPU 到 GPU 的显存写回频次
		_stamp_history_exploration(cam_pos, cam_zoom)

# 安全获取指定世界坐标对应的网格地表楼层 (兼容独立运行与单元测试)
func _get_cell_floor(world_pos: Vector2) -> int:
	var tree := get_tree()
	if tree and tree.root and tree.root.has_node("GridData"):
		var gd = tree.root.get_node("GridData")
		if gd.has_method("world_to_cell") and gd.has_method("get_highest_floor"):
			return gd.get_highest_floor(gd.world_to_cell(world_pos))
	return 0

# 确保虚空空气墙与自身被底层物理查询排除
func _ensure_excluded_rids() -> void:
	if _excluded_rids.is_empty() or _excluded_rids.size() < 2:
		var rids: Array[RID] = []
		if is_instance_valid(entity):
			rids.append(entity.get_rid())
		var air_walls := get_tree().get_nodes_in_group("air_walls")
		for aw in air_walls:
			if aw is CollisionObject2D and not rids.has(aw.get_rid()):
				rids.append(aw.get_rid())
		if rids.size() < 2:
			var aw_fallback := get_tree().root.find_child("AirWallManager", true, false)
			if is_instance_valid(aw_fallback) and aw_fallback is CollisionObject2D and not rids.has(aw_fallback.get_rid()):
				rids.append(aw_fallback.get_rid())
		if rids.size() != _excluded_rids.size():
			_excluded_rids = rids
			_ray_exclude_rids = _excluded_rids.duplicate()
			if _shape_query:
				_shape_query.exclude = _excluded_rids

# 获取屏幕分辨率在世界空间中的矩形范围
func _get_screen_world_rect(cam_pos: Vector2, cam_zoom: Vector2, margin: float = 0.0) -> Rect2:
	var vp_size := Vector2(fog_viewport.size) if is_instance_valid(fog_viewport) else Vector2(1152, 648)
	var z := cam_zoom if cam_zoom.x > 0.0 and cam_zoom.y > 0.0 else Vector2.ONE
	var half_w := (vp_size.x * 0.5) / z.x + margin
	var half_h := (vp_size.y * 0.5) / z.y + margin
	return Rect2(cam_pos.x - half_w, cam_pos.y - half_h, half_w * 2.0, half_h * 2.0)

# -------------------------------------------------------------
# 一、生物显隐判定：屏幕视口剔除 + 反向单射线 (极其高效，零 GC 堆分配)
# -------------------------------------------------------------
func _update_creature_visibility(player_pos: Vector2, screen_rect: Rect2, h_eye_total: float = 18.0) -> void:
	_visible_creatures.clear()
	var space_state := entity.get_world_2d().direct_space_state
	var creatures := get_tree().get_nodes_in_group("creatures")
	var p_ground_pos := entity.global_position if entity != null else player_pos

	for c in creatures:
		if not is_instance_valid(c) or c == entity or not (c is Node2D):
			continue

		var c_node := c as Node2D
		var c_ground_pos := c_node.global_position
		var c_foot := c_ground_pos
		if c_node.has_method("get_visual_foot_position"):
			c_foot = c_node.call("get_visual_foot_position")

		# 1. 屏幕视口剔除：不在当前屏幕可见范围内的生物直接隐藏
		if not screen_rect.has_point(c_foot):
			c_node.visible = false
			continue

		# 2. 屏幕内生物处于物体阴影判定：检查脚底是否落入任何正在投射的阴影体中 (与屏幕视觉阴影 100% 精确对齐)
		var in_shadow := false
		for i in current_quads_count:
			if Geometry2D.is_point_in_polygon(c_foot, current_shadow_quads[i]):
				in_shadow = true
				break

		if in_shadow:
			c_node.visible = false
			continue

		# 获取生物的楼层高度与海平面绝对视线高度
		var c_floor: int = 0
		if c_node.has_method("get_current_floor"):
			c_floor = c_node.call("get_current_floor")
		elif "depth_comp" in c_node and is_instance_valid(c_node.get("depth_comp")) and "current_floor" in c_node.get("depth_comp"):
			c_floor = c_node.get("depth_comp").current_floor
		else:
			c_floor = _get_cell_floor(c_ground_pos)

		var c_ground_z := float(c_floor) * 16.0

		# 2.5 屏幕内生物处于地形 3D 高度场阴影判定 (与 GPU 视线步进阴影 100% 精确对齐)
		if enable_terrain_shadows and _is_blocked_by_terrain(p_ground_pos, h_eye_total, c_ground_pos, c_ground_z, c_floor):
			c_node.visible = false
			continue

		# 3. 严格射线物理遮蔽检测（针对角色与生物之间的实体碰撞体，如高墙/厚障碍物）
		_shared_ray_query.from = c_ground_pos
		_shared_ray_query.to = p_ground_pos
		_shared_ray_query.collision_mask = obstacle_mask
		_ray_exclude_rids.append(c_node.get_rid())
		_shared_ray_query.exclude = _ray_exclude_rids
		var hit := space_state.intersect_ray(_shared_ray_query)
		_ray_exclude_rids.pop_back()

		# 射线通畅且未被真实障碍物阻挡 -> 可见；被挡住时判断视线是否能越顶俯视
		var is_vis := true
		if not hit.is_empty():
			var hit_cid: int = hit.get("collider_id", 0)
			var hit_item: ObstacleCacheItem = _obstacle_cache.get(hit_cid)
			var h_obs_hit: float = 48.0
			if hit_item != null:
				h_obs_hit = float(hit_item.floor_level) * 16.0 + hit_item.obstacle_height
			else:
				var hit_col: Object = hit.get("collider")
				if hit_col is Node:
					var hit_node := hit_col as Node
					if hit_node.get_parent() != null and (hit_node.get_parent().get("obstacle_height") != null or hit_node.get_parent().get("floor_level") != null):
						hit_node = hit_node.get_parent()
					var fl := int(hit_node.get("floor_level")) if hit_node.get("floor_level") != null else _get_cell_floor(hit.get("position", Vector2.ZERO))
					var oh := float(hit_node.get("obstacle_height")) if hit_node.get("obstacle_height") != null else 48.0
					h_obs_hit = float(fl) * 16.0 + oh

			var c_eye_h: float = float(c_node.get("eye_height")) if c_node.get("eye_height") != null else 10.0
			var h_c_eye := c_ground_z + c_eye_h

			var hit_pos: Vector2 = hit.get("position", c_foot)
			var total_dist := c_foot.distance_to(player_pos)
			var t := (c_foot.distance_to(hit_pos) / total_dist) if total_dist > 0.001 else 0.0
			var h_sight := lerpf(h_c_eye, h_eye_total, t)

			if h_sight <= h_obs_hit:
				is_vis = false

		c_node.visible = is_vis
		if is_vis:
			_visible_creatures.append(c_node)

# 检查目标地面/生物是否处于地形高度场阴影中 (与 GPU 视线步进 3D 光影 100% 像素级对齐)
func _is_blocked_by_terrain(p_pos: Vector2, p_eye_z: float, target_pos: Vector2, target_z: float, target_floor: int) -> bool:
	if not enable_terrain_shadows:
		return false
	if target_z >= p_eye_z:
		return true # 目标水平顶面高于视线高度，背面朝向不可见
	var gd: Object = _get_grid_data()
	if gd == null or not gd.has_method("world_to_cell") or not gd.has_method("get_highest_floor"):
		return false

	var total_dist := p_pos.distance_to(target_pos)
	if total_dist < 16.0:
		return false

	var p_cell: Vector2i = gd.world_to_cell(p_pos)
	var t_cell: Vector2i = gd.world_to_cell(target_pos)

	var p_floor := maxi(0, int(round((p_eye_z - 18.0) / 16.0)))
	var min_elev: float = float(mini(p_floor, target_floor)) * 16.0

	var steps := clampi(int(total_dist / 24.0), 6, 32)
	for i in range(1, steps):
		var s := float(i) / float(steps)
		var cur_pos := p_pos.lerp(target_pos, s)
		var cur_ray_z := lerpf(p_eye_z, target_z, s)
		var cell: Vector2i = gd.world_to_cell(cur_pos)

		if cell == p_cell or cell == t_cell:
			continue

		var cell_floor: int = gd.get_highest_floor(cell)
		var h := float(cell_floor) * 16.0

		if h <= min_elev + 0.1:
			continue

		if cur_ray_z < h:
			return true

	return false

func _collect_visible_creatures(screen_rect: Rect2) -> void:
	_visible_creatures.clear()
	var creatures := get_tree().get_nodes_in_group("creatures")
	for c in creatures:
		if not is_instance_valid(c) or c == entity or not (c is Node2D):
			continue
		var c_node := c as Node2D
		var c_foot := c_node.global_position
		if c_node.has_method("get_visual_foot_position"):
			c_foot = c_node.call("get_visual_foot_position")
		if screen_rect.has_point(c_foot):
			c_node.visible = true
			_visible_creatures.append(c_node)

# 运算屏幕内物体阴影覆盖状态 (处于投影内的物体叠加点阵阴影，不在投影内的物体处于地表阴影之上保持原色)
func _update_objects_shadow_state(player_pos: Vector2, screen_rect: Rect2, h_eye_total: float = 18.0) -> void:
	var objects := get_tree().get_nodes_in_group("world_objects")
	if objects.is_empty():
		return

	var p_ground_pos := entity.global_position if entity != null else player_pos

	for obj in objects:
		if not is_instance_valid(obj) or not (obj is Node2D):
			continue
		var obj_node := obj as Node2D
		var obj_foot := obj_node.global_position
		if obj_node.has_method("get_visual_foot_position"):
			obj_foot = obj_node.call("get_visual_foot_position")

		# 1. 屏幕视口剔除：不在当前屏幕可见范围内的物体不更新
		if not screen_rect.has_point(obj_foot):
			continue

		var in_shadow := false

		# 2. 障碍物投影四边形检测 (排除物体自身碰撞体投射的阴影体，严防自阴影)
		var obj_cid: int = 0
		var col_body := obj_node.find_child("StaticBody2D", true, false) as CollisionObject2D
		if col_body:
			obj_cid = col_body.get_instance_id()

		for i in current_quads_count:
			if i < _quad_source_cids.size() and _quad_source_cids[i] == obj_cid:
				continue
			if Geometry2D.is_point_in_polygon(obj_foot, current_shadow_quads[i]):
				in_shadow = true
				break

		# 3. 地形 3D 高度场视线步进阴影判定
		if not in_shadow and enable_terrain_shadows:
			var obj_floor: int = 0
			if obj_node.has_method("get_current_floor"):
				obj_floor = obj_node.call("get_current_floor")
			elif "floor_level" in obj_node:
				obj_floor = int(obj_node.get("floor_level"))
			else:
				obj_floor = _get_cell_floor(obj_foot)

			var obj_ground_z := float(obj_floor) * 16.0
			if _is_blocked_by_terrain(p_ground_pos, h_eye_total, obj_foot, obj_ground_z, obj_floor):
				in_shadow = true

		if obj_node.has_method("set_in_shadow"):
			obj_node.call("set_in_shadow", in_shadow)

# -------------------------------------------------------------
# 二、几何运算：提取屏幕内障碍物并向屏幕外延展阴影体 (零 GC 内存复用)
# -------------------------------------------------------------
func _init_indices_pool(max_quads: int) -> void:
	var total_indices := max_quads * 6
	_static_indices.resize(total_indices)
	for i in max_quads:
		var v_base := i * 4
		var i_base := i * 6
		_static_indices[i_base] = v_base
		_static_indices[i_base + 1] = v_base + 1
		_static_indices[i_base + 2] = v_base + 2
		_static_indices[i_base + 3] = v_base
		_static_indices[i_base + 4] = v_base + 2
		_static_indices[i_base + 5] = v_base + 3

func _calculate_shadow_quads(player_pos: Vector2, cam_pos: Vector2, cam_zoom: Vector2, player_floor: int = -9999, h_eye_total_in: float = -9999.0) -> bool:
	current_quads_count = 0

	if _shape_query == null:
		if not current_shadow_quads.is_empty():
			current_shadow_quads.clear()
		_quad_source_cids.clear()
		_batched_indices = PackedInt32Array()
		return false

	# 将物理探测框设为当前屏幕世界范围（带 screen_margin 外扩，确保边界物体阴影平滑切入）
	var screen_rect := _get_screen_world_rect(cam_pos, cam_zoom, screen_margin)
	_rect_shape.size = screen_rect.size
	_shape_query.transform = Transform2D(0.0, cam_pos)

	var space_state := entity.get_world_2d().direct_space_state
	# 使用 max_obstacles (默认 512，支持上千树木极限压力测试)
	var hits := space_state.intersect_shape(_shape_query, max_obstacles)

	# 阴影四边形外推长度：保证阴影贯穿整个屏幕并穿透到屏幕之外
	var extend_len := screen_rect.size.length() * 1.5

	# 自动推断角色的楼层与海平面绝对视线高度 (若未指定)
	var p_floor := player_floor
	if p_floor == -9999:
		if entity.has_method("get_current_floor"):
			p_floor = entity.call("get_current_floor")
		elif "depth_comp" in entity and is_instance_valid(entity.get("depth_comp")) and "current_floor" in entity.get("depth_comp"):
			p_floor = entity.get("depth_comp").current_floor
		else:
			p_floor = _get_cell_floor(player_pos)

	var h_eye_total := h_eye_total_in
	if h_eye_total < -9000.0:
		var player_eye_h: float = float(entity.get("eye_height")) if entity.get("eye_height") != null else 18.0
		h_eye_total = float(p_floor) * 16.0 + player_eye_h

	# 角色纯净地表坐标 (基准物理坐标，确保光线角度不受垂直高度污染)
	var player_ground_pos := player_pos

	for hit in hits:
		var cid: int = hit.get("collider_id", 0)
		var obs_item: ObstacleCacheItem = _obstacle_cache.get(cid)

		if obs_item == null:
			var collider: Object = hit.get("collider")
			if collider == null or not (collider is Node):
				continue
			var c_node := collider as Node
			if c_node is AirWallManager or c_node.name.begins_with("AirWall") or c_node.name.begins_with("@StaticBody2D"):
				continue

			obs_item = _extract_obstacle_cache(c_node)
			if obs_item != null:
				_obstacle_cache[cid] = obs_item
				if not c_node.tree_exiting.is_connected(_on_obstacle_exiting):
					c_node.tree_exiting.connect(_on_obstacle_exiting.bind(cid))

		if obs_item == null or not screen_rect.has_point(obs_item.world_pos):
			continue

		var obs_node := obs_item.obstacle_node
		var obs_floor := obs_item.floor_level
		if is_instance_valid(obs_node) and obs_node.get("floor_level") != null:
			obs_floor = int(obs_node.get("floor_level"))

		var obs_h := obs_item.obstacle_height
		if is_instance_valid(obs_node) and obs_node.get("obstacle_height") != null:
			obs_h = float(obs_node.get("obstacle_height"))

		# 若物体高度为 0，视为纯地表扁平贴花，不投射视野阴影
		if obs_h <= 0.0:
			continue

		# 障碍物地表中心坐标与绝对海平面立面高度
		var obs_floor_offset := float(obs_floor) * 16.0
		var obs_ground_center := obs_item.center + Vector2(0.0, obs_floor_offset)
		var h_obs_total := obs_floor_offset + obs_h

		var base_dir_ground := (obs_ground_center - player_ground_pos)
		if base_dir_ground.is_zero_approx():
			continue
		var base_angle_ground := base_dir_ground.angle()

		var min_rel := INF
		var max_rel := -INF
		var v_left := Vector2.ZERO
		var v_right := Vector2.ZERO
		var v_left_ground := Vector2.ZERO
		var v_right_ground := Vector2.ZERO

		# 核心极值顶点扫描法 (基于纯净地表坐标的相对偏差角，绝不因楼层升降发生角度偏转)
		for v in obs_item.world_pts:
			var vg := v + Vector2(0.0, obs_floor_offset)
			var rel := wrapf((vg - player_ground_pos).angle() - base_angle_ground, -PI, PI)
			if rel < min_rel:
				min_rel = rel
				v_left = v
				v_left_ground = vg
			if rel > max_rel:
				max_rel = rel
				v_right = v
				v_right_ground = vg

		# 异常防呆：若两极值相对角极小（退化）或跨度接近 PI（角色身处物体中心），跳过
		if max_rel - min_rel < 0.001 or max_rel - min_rel > PI * 0.98:
			continue

		# 地表射线方向
		var dir_left_ground := (v_left_ground - player_ground_pos).normalized()
		var dir_right_ground := (v_right_ground - player_ground_pos).normalized()

		# 基于 3D 相似三角形计算阴影落点长度 (若视线高于障碍物顶端则产生有限长截断阴影)
		var len_left := extend_len
		var len_right := extend_len
		var height_diff := h_eye_total - h_obs_total
		if height_diff > 0.001:
			var dist_left := (v_left_ground - player_ground_pos).length()
			var dist_right := (v_right_ground - player_ground_pos).length()
			len_left = minf(extend_len, dist_left * (obs_h / height_diff))
			len_right = minf(extend_len, dist_right * (obs_h / height_diff))

		# 若阴影被截断到极短（例如微弱矮草），可忽略
		if len_left < 0.5 and len_right < 0.5:
			continue

		# 计算屏幕阴影边缘落点
		var e_left := v_left + dir_left_ground * len_left
		var e_right := v_right + dir_right_ground * len_right

		# 1. 0-GC 写入 current_shadow_quads 槽位 (保持外部可观察性与测试兼容)
		if current_quads_count < current_shadow_quads.size():
			current_shadow_quads[current_quads_count][0] = v_left
			current_shadow_quads[current_quads_count][1] = e_left
			current_shadow_quads[current_quads_count][2] = e_right
			current_shadow_quads[current_quads_count][3] = v_right
			_quad_source_cids[current_quads_count] = cid
		else:
			current_shadow_quads.append(PackedVector2Array([v_left, e_left, e_right, v_right]))
			_quad_source_cids.append(cid)

		# 2. 0-GC 写入合批顶点缓冲 _batched_vertices
		var v_base := current_quads_count * 4
		if _batched_vertices.size() < v_base + 4:
			_batched_vertices.resize(maxi(v_base + 4, _batched_vertices.size() * 2))
		_batched_vertices[v_base] = v_left
		_batched_vertices[v_base + 1] = e_left
		_batched_vertices[v_base + 2] = e_right
		_batched_vertices[v_base + 3] = v_right

		current_quads_count += 1

	# 收尾：同步 current_shadow_quads 与 _quad_source_cids 尺寸以保证精确的 count
	if current_shadow_quads.size() > current_quads_count:
		current_shadow_quads.resize(current_quads_count)
	if _quad_source_cids.size() > current_quads_count:
		_quad_source_cids.resize(current_quads_count)

	# 同步合批索引缓冲 _batched_indices
	var target_idx_count := current_quads_count * 6
	if target_idx_count > _static_indices.size():
		_init_indices_pool(current_quads_count + 128)
	if _batched_indices.size() != target_idx_count:
		_batched_indices = _static_indices.slice(0, target_idx_count)

	var changed := (current_quads_count != _last_quads_hash)
	_last_quads_hash = current_quads_count
	return changed

func _extract_obstacle_cache(c_node: Node) -> ObstacleCacheItem:
	for child in c_node.get_children():
		if not (child is CollisionPolygon2D):
			continue
		var poly_node := child as CollisionPolygon2D
		if poly_node.polygon.size() < 3:
			continue

		var item := ObstacleCacheItem.new()
		item.world_pos = poly_node.global_position
		var xform := poly_node.global_transform
		var pts := PackedVector2Array()
		var center := Vector2.ZERO
		for local_pt in poly_node.polygon:
			var wp := xform * local_pt
			pts.append(wp)
			center += wp
		item.center = center / float(pts.size())
		item.world_pts = pts

		var obs_node: Node = c_node
		var p_node := c_node.get_parent()
		if p_node != null and (p_node.get("obstacle_height") != null or p_node.get("floor_level") != null):
			obs_node = p_node
		item.obstacle_node = obs_node

		var obs_h: float = 48.0
		var h_val = obs_node.get("obstacle_height")
		if h_val != null:
			obs_h = float(h_val)
		elif c_node.get("obstacle_height") != null:
			obs_h = float(c_node.get("obstacle_height"))
		item.obstacle_height = obs_h

		var fl: int = 0
		var fl_val = obs_node.get("floor_level")
		if fl_val != null:
			fl = int(fl_val)
		elif c_node.get("floor_level") != null:
			fl = int(c_node.get("floor_level"))
		else:
			fl = _get_cell_floor(item.center)
		item.floor_level = fl

		return item
	return null

func _on_obstacle_exiting(cid: int) -> void:
	_obstacle_cache.erase(cid)

# -------------------------------------------------------------
# 三、初始化历史迷雾贴图 (纯内存 Image，零开销)
# -------------------------------------------------------------
func _init_history_map() -> void:
	history_image = Image.create(MAP_RES, MAP_RES, false, Image.FORMAT_R8)
	history_image.fill(Color(0, 0, 0, 1)) # 初始全黑 (从未探索)
	history_texture = ImageTexture.create_from_image(history_image)

func _stamp_history_exploration(cam_pos: Vector2, cam_zoom: Vector2) -> void:
	if history_image == null or history_texture == null:
		return

	# 静止或移动极小 (< 16px) 时不重复执行贴图更新，避免频繁 VRAM 显存数据写回
	if cam_pos.distance_squared_to(_last_history_stamp_pos) < 256.0:
		return
	_last_history_stamp_pos = cam_pos

	var screen_rect := _get_screen_world_rect(cam_pos, cam_zoom, 0.0)
	var half_bound := map_bounds * 0.5

	# 将当前屏幕矩形映射到 256x256 历史像素坐标
	var x0 := clampi(int((screen_rect.position.x + half_bound) / map_bounds * float(MAP_RES)), 0, MAP_RES - 1)
	var y0 := clampi(int((screen_rect.position.y + half_bound) / map_bounds * float(MAP_RES)), 0, MAP_RES - 1)
	var x1 := clampi(int((screen_rect.end.x + half_bound) / map_bounds * float(MAP_RES)), 0, MAP_RES - 1)
	var y1 := clampi(int((screen_rect.end.y + half_bound) / map_bounds * float(MAP_RES)), 0, MAP_RES - 1)

	var w := maxi(1, x1 - x0 + 1)
	var h := maxi(1, y1 - y0 + 1)

	# 直接调用底层高效 C++ fill_rect，零 GDScript 像素循环
	history_image.fill_rect(Rect2i(x0, y0, w, h), Color(1, 1, 1, 1))
	history_texture.update(history_image)

# -------------------------------------------------------------
# 四、自动搭建视口与全屏 Shader 管线 (即插即用，零配置)
# -------------------------------------------------------------
func _setup_fog_rendering_pipeline() -> void:
	# 1. 创建全屏覆盖 CanvasLayer (layer=5，高于游戏场景世界0，低于 HUD界面100)
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 5
	add_child(canvas_layer)

	# 2. 创建用于绘制视锥的 SubViewport (自适应视口分辨率，默认 UPDATE_ONCE 极致省电)
	fog_viewport = SubViewport.new()
	var vp_size := get_viewport().get_visible_rect().size
	fog_viewport.size = Vector2i(vp_size) if vp_size.x > 0 and vp_size.y > 0 else Vector2i(1152, 648)
	fog_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	fog_viewport.transparent_bg = false
	add_child(fog_viewport)

	# 窗口尺寸变动时动态同步
	get_viewport().size_changed.connect(func():
		if is_instance_valid(fog_viewport):
			fog_viewport.size = Vector2i(get_viewport().get_visible_rect().size)
			fog_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			RenderingServer.global_shader_parameter_set("vision_mask_tex", fog_viewport.get_texture())
		if is_instance_valid(xray_viewport):
			xray_viewport.size = Vector2i(get_viewport().get_visible_rect().size)
			RenderingServer.global_shader_parameter_set("xray_mask_tex", xray_viewport.get_texture())
	)

	# 广播全局视线遮罩纹理供所有高耸物体 (如树冠) 材质采样
	RenderingServer.global_shader_parameter_set("vision_mask_tex", fog_viewport.get_texture())

	# 视口摄像机
	fog_cam = Camera2D.new()
	fog_viewport.add_child(fog_cam)

	# 2.1 地形 3D 视线步进底图绘制节点 (位于视口底层)
	terrain_drawer = Node2D.new()
	var terrain_shader := load("res://script/shaders/terrain_raymarch.gdshader") as Shader
	if terrain_shader != null:
		terrain_mat = ShaderMaterial.new()
		terrain_mat.shader = terrain_shader
		terrain_drawer.material = terrain_mat
		_update_terrain_raymarch_params(entity.global_position if entity != null else Vector2.ZERO, 18.0)
	terrain_drawer.draw.connect(_on_terrain_drawer_draw)
	fog_viewport.add_child(terrain_drawer)


	# 2.2 障碍物阴影绘制节点 (位于顶层，叠加树木/微物体黑色阴影四边形)
	fog_drawer = Node2D.new()
	fog_drawer.draw.connect(_on_fog_drawer_draw)
	fog_viewport.add_child(fog_drawer)


	# 2.5 创建用于绘制多实体透视遮罩的 SubViewport
	xray_viewport = SubViewport.new()
	xray_viewport.size = fog_viewport.size
	xray_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	xray_viewport.transparent_bg = true
	add_child(xray_viewport)

	xray_cam = Camera2D.new()
	xray_viewport.add_child(xray_cam)

	xray_drawer = Node2D.new()
	var xray_mat := CanvasItemMaterial.new()
	xray_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	xray_drawer.material = xray_mat
	xray_drawer.draw.connect(_on_xray_drawer_draw)
	xray_viewport.add_child(xray_drawer)

	RenderingServer.global_shader_parameter_set("xray_mask_tex", xray_viewport.get_texture())

	# 3. 创建全屏后处理 ColorRect (若未开启全屏黑雾，保持隐藏)
	fog_rect = ColorRect.new()
	fog_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog_rect.visible = enable_black_fog_overlay

	var shader := load("res://script/shaders/fog_of_war.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("fog_mask", fog_viewport.get_texture())
	mat.set_shader_parameter("history_mask", history_texture)
	mat.set_shader_parameter("explored_alpha", explored_alpha)
	mat.set_shader_parameter("unexplored_alpha", unexplored_alpha)
	mat.set_shader_parameter("map_bounds", Vector2(map_bounds, map_bounds))
	mat.set_shader_parameter("enable_dither_fog", enable_dither_fog)
	mat.set_shader_parameter("dither_scale", dither_scale)
	mat.set_shader_parameter("edge_softness", fog_edge_softness)
	mat.set_shader_parameter("render_shadows_under_objects", render_shadows_under_objects)
	fog_rect.material = mat

	canvas_layer.add_child(fog_rect)

# 视口最底层的地形光影绘制 (运行 3D 视线步进着色器)
func _on_terrain_drawer_draw() -> void:
	if entity == null:
		return

	var cam_pos := fog_cam.position if is_instance_valid(fog_cam) else entity.global_position
	var cam_zoom := fog_cam.zoom if is_instance_valid(fog_cam) else Vector2.ONE
	var screen_rect := _get_screen_world_rect(cam_pos, cam_zoom, screen_margin)

	if enable_terrain_shadows and terrain_mat != null:
		terrain_drawer.draw_rect(screen_rect, Color.WHITE)
	else:
		terrain_drawer.draw_rect(screen_rect, Color(1, 0, 0, 1))

# 视口内的障碍物具体绘制 (在地形底图之上覆盖黑色树木等障碍物阴影)
func _on_fog_drawer_draw() -> void:
	if entity == null:
		return

	# 一次性合批提交所有黑色障碍物阴影四边形 (从 60+ 次 Draw Call 缩减至 1 次底层提交！)
	if current_quads_count > 0 and not _batched_indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(
			fog_drawer.get_canvas_item(),
			_batched_indices,
			_batched_vertices,
			_batched_colors
		)

# 安全获取 GridData 节点 (兼容独立运行与单元测试)
func _get_grid_data() -> Object:
	var tree := get_tree()
	if tree and tree.root and tree.root.has_node("GridData"):
		return tree.root.get_node("GridData")
	return null

# 更新地形 3D 视线步进 Shader 参数
func _update_terrain_raymarch_params(player_ground_pos: Vector2, h_eye_total: float) -> void:
	if terrain_mat == null or not enable_terrain_shadows:
		return
	terrain_mat.set_shader_parameter("player_ground_pos", player_ground_pos)
	terrain_mat.set_shader_parameter("player_eye_z", h_eye_total)
	terrain_mat.set_shader_parameter("raymarch_steps", terrain_raymarch_steps)
	terrain_mat.set_shader_parameter("shadow_softness", terrain_shadow_softness)
	var gd: Object = _get_grid_data()

	if gd != null:
		if "layers" in gd and not gd.layers.is_empty():
			terrain_mat.set_shader_parameter("layer_offset_y", gd.layers[0].position.y)
		if gd.has_method("get_height_map_texture"):
			terrain_mat.set_shader_parameter("height_map_tex", gd.call("get_height_map_texture"))



# 获取或动态创建指定曲线弧度的径向渐变纹理 (按 0.05 步长离散缓存，运行时 0 GC)
func _get_radial_gradient_tex(curve: float) -> Texture2D:
	var clamped: float = clampf(curve, 0.0, 1.0)
	var key: float = snappedf(clamped, 0.05)
	if _radial_tex_cache.has(key):
		return _radial_tex_cache[key]

	var grad := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	var sample_count := 33
	for i in range(sample_count):
		var u: float = float(i) / float(sample_count - 1)
		var linear_val: float = 1.0 - u
		var circle_val: float = sqrt(maxf(0.0, 1.0 - u * u))
		var alpha: float = lerpf(linear_val, circle_val, key)
		offsets.append(u)
		colors.append(Color(1.0, 1.0, 1.0, alpha))
	grad.offsets = offsets
	grad.colors = colors

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128

	_radial_tex_cache[key] = tex
	return tex

# 视口内绘制玩家与视野内所有可见生物的范围透视印章 (写入 xray_mask_tex)
func _on_xray_drawer_draw() -> void:
	if entity == null or not is_instance_valid(xray_drawer):
		return

	# 1. 绘制玩家自身的透视光晕印章
	var p_pos := entity.global_position
	if entity.has_method("get_visual_foot_position"):
		p_pos = entity.call("get_visual_foot_position")
	var p_rx: float = entity.get("xray_radius").x if entity.get("xray_radius") != null else 85.0
	var p_ry: float = entity.get("xray_radius").y if entity.get("xray_radius") != null else 55.0
	var p_offset: Vector2 = entity.get("xray_offset") if entity.get("xray_offset") != null else Vector2(0.0, -16.0)
	var p_trans: float = entity.get("xray_max_transparency") if entity.get("xray_max_transparency") != null else 0.85
	var p_curve: float = entity.get("xray_curve") if entity.get("xray_curve") != null else default_xray_curve
	var p_center := p_pos + p_offset
	var p_rect := Rect2(p_center.x - p_rx, p_center.y - p_ry, p_rx * 2.0, p_ry * 2.0)
	var p_tex := _get_radial_gradient_tex(p_curve)
	if p_tex != null:
		xray_drawer.draw_texture_rect(p_tex, p_rect, false, Color(1, 1, 1, p_trans))

	# 2. 批量绘制当前屏幕视野内所有可见生物的透视印章
	for c_node in _visible_creatures:
		if not is_instance_valid(c_node) or not c_node.is_inside_tree() or c_node == entity:
			continue
		if c_node.get("xray_enabled") == false:
			continue

		var c_pos := c_node.global_position
		if c_node.has_method("get_visual_foot_position"):
			c_pos = c_node.call("get_visual_foot_position")

		var c_rx: float = c_node.get("xray_radius").x if c_node.get("xray_radius") != null else 85.0
		var c_ry: float = c_node.get("xray_radius").y if c_node.get("xray_radius") != null else 55.0
		var c_offset: Vector2 = c_node.get("xray_offset") if c_node.get("xray_offset") != null else Vector2(0.0, -16.0)
		var c_trans: float = c_node.get("xray_max_transparency") if c_node.get("xray_max_transparency") != null else 0.85
		var c_curve: float = c_node.get("xray_curve") if c_node.get("xray_curve") != null else default_xray_curve
		var c_center := c_pos + c_offset
		var c_rect := Rect2(c_center.x - c_rx, c_center.y - c_ry, c_rx * 2.0, c_ry * 2.0)
		var c_tex := _get_radial_gradient_tex(c_curve)
		if c_tex != null:
			xray_drawer.draw_texture_rect(c_tex, c_rect, false, Color(1, 1, 1, c_trans))

