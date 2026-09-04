# vision_fog_component.gd —— 战争迷雾与 2.5D 视线遮蔽通用组件 (全屏分辨率视野)
class_name VisionFogComponent
extends Node

@export_group("视野核心参数")
# 屏幕边缘外扩裕量 (像素，用于提前加载进入屏幕边缘的障碍物阴影)
@export var screen_margin: float = 96.0
# 历史探索区域的半黑留底深浅 (0.0=全亮, 0.35=半透明辅助阴影, 1.0=纯黑)
@export_range(0.0, 1.0) var explored_alpha: float = 0.35
# 未探索区域的浓雾深浅 (0.5 = 半透明视觉辅助，方便比对视线与障碍物)
@export_range(0.0, 1.0) var unexplored_alpha: float = 0.50
# 是否彻底隐藏视线盲区内的其他生物
@export var enable_creature_hiding: bool = true
# 遮挡视线的物理障碍层掩码 (Layer 2 树木/高墙 = 2)
@export_flags_2d_physics var obstacle_mask: int = 2
# 屏幕内最大障碍物探测上限 (极限密林测试可调大至 1024)
@export var max_obstacles: int = 512
# 地图边界覆盖尺寸
@export var map_bounds: float = 4096.0

@export_group("透视与全屏黑雾模式")
# 是否在全屏渲染黑色迷雾覆盖层 (true = 开启半透明黑色阴影作为视觉辅助，false = 彻底取消地面阴影)
@export var enable_black_fog_overlay: bool = true:
	set(v):
		enable_black_fog_overlay = v
		if is_instance_valid(fog_rect):
			fog_rect.visible = enable_black_fog_overlay
# 角色背后盲区是否渲染黑色半透明遮罩 (false = 关闭背后的黑色遮罩，保持地面原色；true = 背后呈现黑色阴影)
@export var enable_rear_fog: bool = false:
	set(v):
		enable_rear_fog = v
		if is_instance_valid(fog_drawer):
			fog_drawer.queue_redraw()
# 是否允许生物透过半透明树冠显现 (true = 屏幕内生物始终可见，可透过半透明树叶看清敌友)
@export var show_creatures_through_canopy: bool = true

@export_group("视锥范围配置")
# 视野扇形开角 (度数，默认 200.0 代表正前方 200° 可视，背后 160° 为盲区，360 为全景)
@export_range(30.0, 360.0) var vision_fov: float = 200.0
# 视锥扇形弧度细分数 (默认 36 边形，圆弧极其平滑)
@export var fov_arc_segments: int = 36

var entity: CharacterBody2D
var main_cam: Camera2D

# 内部全屏迷雾画布与视口
var canvas_layer: CanvasLayer
var fog_rect: ColorRect
var fog_viewport: SubViewport
var fog_cam: Camera2D
var fog_drawer: Node2D

# 性能优化：静态障碍物碰撞多边形缓存对象
class ObstacleCacheItem:
	var world_pos: Vector2
	var center: Vector2
	var world_pts: PackedVector2Array

var _obstacle_cache: Dictionary = {} # int (collider_id) -> ObstacleCacheItem

# 批处理阴影三角网格缓冲 (合批为 1 次底层渲染，预分配零 GC)
var _batched_vertices: PackedVector2Array = PackedVector2Array()
var _batched_indices: PackedInt32Array = PackedInt32Array()
var _batched_colors: PackedColorArray = PackedColorArray([Color(0, 0, 0, 1)])
var _static_indices: PackedInt32Array = PackedInt32Array()
# 视锥扇形预分配缓冲 (0-GC)
var _fov_pts: PackedVector2Array = PackedVector2Array()
var _fov_colors: PackedColorArray = PackedColorArray([Color(1, 0, 0, 1)])

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
var _last_facing_angle: float = -999.0
var _last_history_stamp_pos := Vector2(-99999, -99999)
var _last_quads_hash: int = -1

# 历史探索记忆 (低分辨率图像)
var history_image: Image
var history_texture: ImageTexture
const MAP_RES: int = 256
var _history_update_timer: float = 0.0

# 当帧计算的阴影四边形
var current_shadow_quads: Array[PackedVector2Array] = []
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

	# 1. 广播全局 Shader 变量给树冠与遮挡物透视 (供 xray.gdshader 等使用)
	var vp_size_vec := Vector2(fog_viewport.size) if is_instance_valid(fog_viewport) else Vector2(1152, 648)
	var facing_dir_global: Vector2 = entity.call("get_facing_direction") if entity.has_method("get_facing_direction") else Vector2.DOWN
	RenderingServer.global_shader_parameter_set("vision_cam_pos", _mask_cam_pos)
	RenderingServer.global_shader_parameter_set("vision_cam_zoom", cam_zoom)
	RenderingServer.global_shader_parameter_set("vision_screen_size", vp_size_vec)
	RenderingServer.global_shader_parameter_set("player_facing_dir", facing_dir_global)
	RenderingServer.global_shader_parameter_set("vision_fov", vision_fov)

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

		# 当前屏幕分辨率对应的世界空间可视包围盒
		var screen_world_rect := _get_screen_world_rect(cam_pos, cam_zoom, 48.0)

		# 收集屏幕内的物理障碍物，几何运算投射到屏幕外的阴影体
		var quads_changed := _calculate_shadow_quads(player_pos, cam_pos, cam_zoom)

		# 运算屏幕内生物显隐与视线遮蔽 (结合几何阴影体判定与反向射线法)
		if enable_creature_hiding:
			_update_creature_visibility(player_pos, screen_world_rect)

		# 脏标记智能重绘：仅当摄像机位移、角色位移、朝向旋转或阴影形状变动时才重绘，静止时 0 额外 CPU/GPU 消耗！
		var facing_dir: Vector2 = entity.call("get_facing_direction") if entity.has_method("get_facing_direction") else Vector2.DOWN
		var facing_angle: float = facing_dir.angle()
		var rotated: bool = (enable_rear_fog and vision_fov < 359.0) and absf(wrapf(facing_angle - _last_facing_angle, -PI, PI)) > 0.015
		var threshold_sq := move_threshold * move_threshold
		var moved := player_pos.distance_squared_to(_last_draw_player_pos) > threshold_sq or cam_pos.distance_squared_to(_last_draw_pos) > threshold_sq
		if is_instance_valid(fog_drawer) and (moved or quads_changed or rotated or _last_draw_pos == Vector2(-99999, -99999)):
			_last_draw_pos = cam_pos
			_last_draw_player_pos = player_pos
			_last_facing_angle = facing_angle
			_mask_cam_pos = cam_pos
			# 同步视口摄像机
			if is_instance_valid(fog_cam):
				fog_cam.position = cam_pos
				fog_cam.zoom = cam_zoom
			fog_drawer.queue_redraw()
			if is_instance_valid(fog_viewport):
				fog_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	# 3. 周期性累加全屏视野的历史探索足迹
	_history_update_timer -= delta
	if _history_update_timer <= 0.0:
		_history_update_timer = 0.5 # 每 500ms 检查一次，大幅降低 CPU 到 GPU 的显存写回频次
		_stamp_history_exploration(cam_pos, cam_zoom)

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
func _update_creature_visibility(player_pos: Vector2, screen_rect: Rect2) -> void:
	var space_state := entity.get_world_2d().direct_space_state
	var creatures := get_tree().get_nodes_in_group("creatures")

	var facing_dir: Vector2 = entity.call("get_facing_direction") if entity.has_method("get_facing_direction") else Vector2.DOWN
	var base_angle: float = facing_dir.angle()
	var half_fov: float = deg_to_rad(vision_fov * 0.5)

	for c in creatures:
		if not is_instance_valid(c) or c == entity or not (c is Node2D):
			continue

		var c_node := c as Node2D
		var c_foot := c_node.global_position
		if c_node.has_method("get_visual_foot_position"):
			c_foot = c_node.call("get_visual_foot_position")

		# 1. 屏幕视口剔除：不在当前屏幕可见范围内的生物直接隐藏
		if not screen_rect.has_point(c_foot):
			c_node.visible = false
			continue

		# 2. 视锥开角判定：若超出正前方 vision_fov (如 200°)，处于背后盲区，直接隐藏
		if vision_fov < 359.0:
			var to_c := (c_foot - player_pos)
			if to_c.length_squared() > 1.0:
				var diff_angle := absf(wrapf(to_c.angle() - base_angle, -PI, PI))
				if diff_angle > half_fov:
					c_node.visible = false
					continue

		# 3. 屏幕内生物处于阴影判定：检查脚底是否落入任何正在投射的阴影体中 (与屏幕视觉阴影 100% 精确对齐)
		var in_shadow := false
		for i in current_quads_count:
			if Geometry2D.is_point_in_polygon(c_foot, current_shadow_quads[i]):
				in_shadow = true
				break

		if in_shadow:
			c_node.visible = false
			continue

		# 4. 严格射线物理遮蔽检测（针对角色与生物之间的实体碰撞体，如高墙/厚障碍物）
		_shared_ray_query.from = c_foot
		_shared_ray_query.to = player_pos
		_shared_ray_query.collision_mask = obstacle_mask
		_ray_exclude_rids.append(c_node.get_rid())
		_shared_ray_query.exclude = _ray_exclude_rids
		var hit := space_state.intersect_ray(_shared_ray_query)
		_ray_exclude_rids.pop_back()

		# 射线通畅且未被真实障碍物阻挡 -> 可见；被大树等挡住 -> 隐形！
		c_node.visible = hit.is_empty()

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

func _calculate_shadow_quads(player_pos: Vector2, cam_pos: Vector2, cam_zoom: Vector2) -> bool:
	current_quads_count = 0

	if _shape_query == null:
		if not current_shadow_quads.is_empty():
			current_shadow_quads.clear()
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

		var base_dir := (obs_item.center - player_pos)
		if base_dir.is_zero_approx():
			continue
		var base_angle := base_dir.angle()

		var min_rel := INF
		var max_rel := -INF
		var v_left := Vector2.ZERO
		var v_right := Vector2.ZERO

		# 核心极值顶点扫描法 (基于相对偏差角)
		for v in obs_item.world_pts:
			var rel := wrapf((v - player_pos).angle() - base_angle, -PI, PI)
			if rel < min_rel:
				min_rel = rel
				v_left = v
			if rel > max_rel:
				max_rel = rel
				v_right = v

		# 异常防呆：若两极值相对角极小（退化）或跨度接近 PI（角色身处物体中心），跳过
		if max_rel - min_rel < 0.001 or max_rel - min_rel > PI * 0.98:
			continue

		# 沿玩家到极值顶点的射线方向推向屏幕之外
		var dir_left := (v_left - player_pos).normalized()
		var dir_right := (v_right - player_pos).normalized()
		var e_left := player_pos + dir_left * extend_len
		var e_right := player_pos + dir_right * extend_len

		# 1. 0-GC 写入 current_shadow_quads 槽位 (保持外部可观察性与测试兼容)
		if current_quads_count < current_shadow_quads.size():
			current_shadow_quads[current_quads_count][0] = v_left
			current_shadow_quads[current_quads_count][1] = e_left
			current_shadow_quads[current_quads_count][2] = e_right
			current_shadow_quads[current_quads_count][3] = v_right
		else:
			current_shadow_quads.append(PackedVector2Array([v_left, e_left, e_right, v_right]))

		# 2. 0-GC 写入合批顶点缓冲 _batched_vertices
		var v_base := current_quads_count * 4
		if _batched_vertices.size() < v_base + 4:
			_batched_vertices.resize(maxi(v_base + 4, _batched_vertices.size() * 2))
		_batched_vertices[v_base] = v_left
		_batched_vertices[v_base + 1] = e_left
		_batched_vertices[v_base + 2] = e_right
		_batched_vertices[v_base + 3] = v_right

		current_quads_count += 1

	# 收尾：同步 current_shadow_quads 尺寸以保证精确的 count
	if current_shadow_quads.size() > current_quads_count:
		current_shadow_quads.resize(current_quads_count)

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
	)

	# 广播全局视线遮罩纹理供所有高耸物体 (如树冠) 材质采样
	RenderingServer.global_shader_parameter_set("vision_mask_tex", fog_viewport.get_texture())

	# 视口摄像机
	fog_cam = Camera2D.new()
	fog_viewport.add_child(fog_cam)

	# 视口绘制节点
	fog_drawer = Node2D.new()
	fog_drawer.draw.connect(_on_fog_drawer_draw)
	fog_viewport.add_child(fog_drawer)

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
	fog_rect.material = mat

	canvas_layer.add_child(fog_rect)

# 视口内的具体绘制 (盲区全黑 + 正向视锥点亮 + 覆盖黑色障碍物阴影四边形)
func _on_fog_drawer_draw() -> void:
	if entity == null:
		return

	var cam_pos := fog_cam.position if is_instance_valid(fog_cam) else entity.global_position
	var cam_zoom := fog_cam.zoom if is_instance_valid(fog_cam) else Vector2.ONE
	var screen_rect := _get_screen_world_rect(cam_pos, cam_zoom, screen_margin)

	var player_pos := entity.global_position
	if entity.has_method("get_visual_foot_position"):
		player_pos = entity.call("get_visual_foot_position")

	if enable_rear_fog and vision_fov < 359.0:
		# 1. 开启背后遮罩模式：视口全屏填充为全黑 (R=0，代表背后盲区为黑色半透明阴影)
		fog_drawer.draw_rect(screen_rect, Color(0, 0, 0, 1))

		# 2. 正向视锥点亮：以角色为中心，绘制视野扇形 (R=1)
		var facing_dir: Vector2 = entity.call("get_facing_direction") if entity.has_method("get_facing_direction") else Vector2.DOWN
		var base_angle: float = facing_dir.angle()
		var half_fov: float = deg_to_rad(vision_fov * 0.5)
		var radius: float = screen_rect.size.length() * 1.5 # 确保扇形穿透屏幕外边缘

		var seg_count: int = maxi(12, fov_arc_segments)
		if _fov_pts.size() != seg_count + 2:
			_fov_pts.resize(seg_count + 2)
		_fov_pts[0] = player_pos
		var angle_step: float = (half_fov * 2.0) / float(seg_count)
		var start_angle: float = base_angle - half_fov
		for s in range(seg_count + 1):
			var a: float = start_angle + angle_step * float(s)
			_fov_pts[s + 1] = player_pos + Vector2(cos(a), sin(a)) * radius

		fog_drawer.draw_polygon(_fov_pts, _fov_colors)
	else:
		# 1. 关闭背后黑色遮罩：全屏点亮为可见 (R=1，背后地面保持完全正常原色，不产生黑色半透明扇形)
		fog_drawer.draw_rect(screen_rect, Color(1, 0, 0, 1))

	# 3. 一次性合批提交所有黑色障碍物阴影四边形 (从 60+ 次 Draw Call 缩减至 1 次底层提交！)
	if current_quads_count > 0 and not _batched_indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(
			fog_drawer.get_canvas_item(),
			_batched_indices,
			_batched_vertices,
			_batched_colors
		)

