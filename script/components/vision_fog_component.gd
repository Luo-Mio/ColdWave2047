# vision_fog_component.gd —— 战争迷雾与 2.5D 视线遮蔽通用组件 (全屏分辨率视野)
class_name VisionFogComponent
extends Node

@export_group("视野核心参数")
# 屏幕边缘外扩裕量 (像素，用于提前加载进入屏幕边缘的障碍物阴影)
@export var screen_margin: float = 96.0
# 历史探索区域的半黑留底深浅 (0.0=全亮, 0.65=经典半黑, 1.0=纯黑)
@export_range(0.0, 1.0) var explored_alpha: float = 0.65
# 未探索区域的浓雾深浅 (1.0 = 纯黑)
@export_range(0.0, 1.0) var unexplored_alpha: float = 1.0
# 是否彻底隐藏视线盲区内的其他生物
@export var enable_creature_hiding: bool = true
# 遮挡视线的物理障碍层掩码 (Layer 2 树木/高墙 = 2)
@export_flags_2d_physics var obstacle_mask: int = 2
# 屏幕内最大障碍物探测上限 (极限密林测试可调大至 1024)
@export var max_obstacles: int = 512
# 地图边界覆盖尺寸
@export var map_bounds: float = 4096.0

var entity: CharacterBody2D
var main_cam: Camera2D

# 内部全屏迷雾画布与视口
var canvas_layer: CanvasLayer
var fog_rect: ColorRect
var fog_viewport: SubViewport
var fog_cam: Camera2D
var fog_drawer: Node2D

# 性能优化：预分配矩形物理查询对象、排除列表与脏重绘检测
var _rect_shape: RectangleShape2D
var _shape_query: PhysicsShapeQueryParameters2D
var _excluded_rids: Array[RID] = []
var _last_draw_pos := Vector2(-99999, -99999)
var _last_draw_player_pos := Vector2(-99999, -99999)
var _last_history_stamp_pos := Vector2(-99999, -99999)
var _last_quads_hash: int = -1

# 历史探索记忆 (低分辨率图像)
var history_image: Image
var history_texture: ImageTexture
const MAP_RES: int = 256
var _history_update_timer: float = 0.0

# 当帧计算的阴影四边形
var current_shadow_quads: Array[PackedVector2Array] = []

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

	# 同步视口摄像机
	# 同步视口摄像机
	if is_instance_valid(fog_cam):
		fog_cam.position = cam_pos
		fog_cam.zoom = cam_zoom

	# 确保物理排除列表（虚空空气墙与自身）已注入底层查询，完全不占用检测名额
	_ensure_excluded_rids()

	# 当前屏幕分辨率对应的世界空间可视包围盒
	var screen_world_rect := _get_screen_world_rect(cam_pos, cam_zoom, 48.0)

	# 1. 运算屏幕内生物显隐与视线遮蔽 (反向单射线法)
	if enable_creature_hiding:
		_update_creature_visibility(player_pos, screen_world_rect)

	# 2. 收集屏幕内的物理障碍物，几何运算投射到屏幕外的阴影体
	var quads_changed := _calculate_shadow_quads(player_pos, cam_pos, cam_zoom)

	# 3. 同步摄像机与屏幕参数给全屏 Shader
	if is_instance_valid(fog_rect) and fog_rect.material is ShaderMaterial and is_instance_valid(fog_cam):
		var mat := fog_rect.material as ShaderMaterial
		mat.set_shader_parameter("cam_world_pos", fog_cam.position)
		mat.set_shader_parameter("cam_zoom", fog_cam.zoom)
		mat.set_shader_parameter("screen_size", Vector2(fog_viewport.size))
		mat.set_shader_parameter("map_bounds", Vector2(map_bounds, map_bounds))
		mat.set_shader_parameter("explored_alpha", explored_alpha)
		mat.set_shader_parameter("unexplored_alpha", unexplored_alpha)

	# 脏标记智能重绘：仅当摄像机位移、角色位移或阴影形状变动时才重绘，静止时 0 额外 CPU/GPU 消耗！
	var moved := player_pos.distance_squared_to(_last_draw_player_pos) > 0.25 or cam_pos.distance_squared_to(_last_draw_pos) > 0.25
	if is_instance_valid(fog_drawer) and (moved or quads_changed):
		_last_draw_pos = cam_pos
		_last_draw_player_pos = player_pos
		fog_drawer.queue_redraw()

	# 4. 周期性累加全屏视野的历史探索足迹
	_history_update_timer -= delta
	if _history_update_timer <= 0.0:
		_history_update_timer = 0.15 # 每 150ms 检查一次
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
# 一、生物显隐判定：屏幕视口剔除 + 反向单射线 (极其高效)
# -------------------------------------------------------------
func _update_creature_visibility(player_pos: Vector2, screen_rect: Rect2) -> void:
	var space_state := entity.get_world_2d().direct_space_state
	var creatures := get_tree().get_nodes_in_group("creatures")

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

		# 2. 屏幕内生物：向主角发射 1 条视线射线（检测 Layer 2 障碍物层）
		var ray_query := PhysicsRayQueryParameters2D.create(c_foot, player_pos, obstacle_mask)
		ray_query.exclude = _excluded_rids + [c_node.get_rid()]
		var hit := space_state.intersect_ray(ray_query)

		# 射线通畅且未被真实障碍物阻挡 -> 可见；被大树等挡住 -> 隐形！
		c_node.visible = hit.is_empty()

# -------------------------------------------------------------
# 二、几何运算：提取屏幕内障碍物并向屏幕外延展阴影体
# -------------------------------------------------------------
func _calculate_shadow_quads(player_pos: Vector2, cam_pos: Vector2, cam_zoom: Vector2) -> bool:
	current_shadow_quads.clear()

	if _shape_query == null:
		return false

	# 将物理探测框设为当前屏幕世界范围（带 screen_margin 外扩，确保边界物体阴影平滑切入）
	var screen_rect := _get_screen_world_rect(cam_pos, cam_zoom, screen_margin)
	_rect_shape.size = screen_rect.size
	_shape_query.transform = Transform2D(0.0, cam_pos)

	var space_state := entity.get_world_2d().direct_space_state
	# 使用 max_obstacles (默认 512，支持上千树木极限压力测试)
	var hits := space_state.intersect_shape(_shape_query, max_obstacles)
	var processed_polys: Dictionary = {}

	# 阴影四边形外推长度：保证阴影贯穿整个屏幕并穿透到屏幕之外
	var extend_len := screen_rect.size.length() * 1.5

	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider == null or not (collider is Node):
			continue

		# 过滤虚空空气墙
		var c_node := collider as Node
		if c_node is AirWallManager or c_node.name.begins_with("AirWall") or c_node.name.begins_with("@StaticBody2D"):
			continue

		# 遍历障碍物直接子节点
		for child in c_node.get_children():
			if not (child is CollisionPolygon2D):
				continue
			var poly_node := child as CollisionPolygon2D
			if poly_node.polygon.size() < 3:
				continue

			if processed_polys.has(poly_node):
				continue
			processed_polys[poly_node] = true

			var poly_world_pos := poly_node.global_position
			if not screen_rect.has_point(poly_world_pos):
				continue

			var xform := poly_node.global_transform
			var world_pts: Array[Vector2] = []
			var center := Vector2.ZERO
			for local_pt in poly_node.polygon:
				var wp := xform * local_pt
				world_pts.append(wp)
				center += wp
			center /= float(world_pts.size())

			var base_dir := (center - player_pos)
			if base_dir.is_zero_approx():
				continue
			var base_angle := base_dir.angle()

			var min_rel := INF
			var max_rel := -INF
			var v_left := Vector2.ZERO
			var v_right := Vector2.ZERO

			# 核心极值顶点扫描法 (基于相对偏差角)
			for v in world_pts:
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

			# 形成闭合的阴影四边形
			current_shadow_quads.append(PackedVector2Array([v_left, e_left, e_right, v_right]))

	var new_hash := current_shadow_quads.size()
	var changed := (new_hash != _last_quads_hash)
	_last_quads_hash = new_hash
	return changed

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

	# 静止或移动极小时不重复执行贴图更新
	if cam_pos.distance_squared_to(_last_history_stamp_pos) < 64.0:
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

	# 2. 创建用于绘制视锥的 SubViewport (自适应视口分辨率)
	fog_viewport = SubViewport.new()
	var vp_size := get_viewport().get_visible_rect().size
	fog_viewport.size = Vector2i(vp_size) if vp_size.x > 0 and vp_size.y > 0 else Vector2i(1152, 648)
	fog_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	fog_viewport.transparent_bg = false
	add_child(fog_viewport)

	# 窗口尺寸变动时动态同步
	get_viewport().size_changed.connect(func():
		if is_instance_valid(fog_viewport):
			fog_viewport.size = Vector2i(get_viewport().get_visible_rect().size)
	)

	# 视口摄像机
	fog_cam = Camera2D.new()
	fog_viewport.add_child(fog_cam)

	# 视口绘制节点
	fog_drawer = Node2D.new()
	fog_drawer.draw.connect(_on_fog_drawer_draw)
	fog_viewport.add_child(fog_drawer)

	# 3. 创建全屏后处理 ColorRect
	fog_rect = ColorRect.new()
	fog_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

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

# 视口内的具体绘制 (全屏点亮 + 覆盖黑色阴影四边形)
func _on_fog_drawer_draw() -> void:
	if entity == null:
		return

	var cam_pos := fog_cam.position if is_instance_valid(fog_cam) else entity.global_position
	var cam_zoom := fog_cam.zoom if is_instance_valid(fog_cam) else Vector2.ONE
	var screen_rect := _get_screen_world_rect(cam_pos, cam_zoom, 32.0)

	# 1. 全屏视野点亮：将整个屏幕视口绘制为全亮白色 (R=1)
	fog_drawer.draw_rect(screen_rect, Color(1, 0, 0, 1))

	# 2. 覆盖所有障碍物背后投射向屏幕外的黑色阴影四边形 (R=0)
	for quad in current_shadow_quads:
		if quad.size() >= 3:
			fog_drawer.draw_colored_polygon(quad, Color(0, 0, 0, 1))

