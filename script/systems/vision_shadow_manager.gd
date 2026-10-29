# vision_shadow_manager.gd —— 视线盲区几何阴影系统管理器 (纯 2D 平面几何切点投射 + 屏幕空间像素抖动)
class_name VisionShadowManager
extends Node2D

@export_group("视线阴影外观")
## 是否启用视线阴影
@export var enabled: bool = true:
	set(value):
		enabled = value
		visible = value
		if not enabled:
			_shadow_quads.clear()
			queue_redraw()

## 阴影深度 (0.0 = 全透/无阴影, 0.65 = 经典半透点阵, 1.0 = 纯黑点阵)
@export_range(0.0, 1.0) var shadow_darkness: float = 0.65:
	set(value):
		shadow_darkness = value
		_sync_shader_params()

## 阴影边缘柔和虚化强度 (0.0 = 锐利硬切, 0.15 = 经典自然点阵虚化, 0.5 = 全程平滑过渡)
@export_range(0.0, 0.5, 0.01) var edge_softness: float = 0.15:
	set(value):
		edge_softness = value
		_sync_shader_params()

## 像素抖动模式 (0 = Bayer 8x8 64阶平滑, 1 = Interleaved Noise 噪波, 2 = Bayer 4x4 16阶经典)
@export_enum("Bayer 8x8 (64阶平滑)", "Interleaved Noise (噪波)", "Bayer 4x4 (16阶经典)") var dither_mode: int = 0:
	set(value):
		dither_mode = value
		_sync_shader_params()

## 像素颗粒缩放尺寸 (1 = 原生屏幕像素, 2 = 2x2 像素块，与 2x 摄像机缩放完美像素对齐)
@export_range(1, 4) var dither_scale: int = 1:
	set(value):
		dither_scale = value
		_sync_shader_params()

## 阴影着色颜色 (默认纯黑)
@export var shadow_color: Color = Color(0, 0, 0, 1.0):
	set(value):
		shadow_color = value
		_sync_shader_params()

@export_group("视野与投影计算")
## 视线观察者实体 (留空时自动抓取 player 组首个节点)
@export var target_entity: Node2D

## 视线原点偏移 (例如 Vector2(0, -8) 代表齐胸高视角，Vector2.ZERO 代表足底平视)
@export var vision_origin_offset: Vector2 = Vector2.ZERO

## 屏幕外扩检测边界 (像素，提前将屏幕外边缘的障碍物阴影平滑投射进视野)
@export var screen_margin: float = 96.0

## 阴影向屏幕外投射延伸倍率 (相对于屏幕对角线长度)
@export var shadow_extend_multiplier: float = 1.5

## 参与遮挡视线的物理碰撞层掩码 (Layer 1 = 1，与树木/实体碰撞层对应)
@export_flags_2d_physics var obstacle_mask: int = 1

## 屏幕内最大处理障碍物上限
@export var max_obstacles: int = 256

# 内部物理探测与脏标记检测
var _rect_shape: RectangleShape2D
var _shape_query: PhysicsShapeQueryParameters2D
var _last_player_pos := Vector2(-99999, -99999)
var _last_cam_pos := Vector2(-99999, -99999)
var _last_cam_zoom := Vector2(-99999, -99999)
var _shadow_quads: Array[PackedVector2Array] = []

func _ready() -> void:
	# 若未配置材质，动态载入默认材质
	if material == null:
		material = load("res://resources/materials/vision_shadow.tres")
	_sync_shader_params()

	# 初始化屏幕空间物理探测参数
	_rect_shape = RectangleShape2D.new()
	_shape_query = PhysicsShapeQueryParameters2D.new()
	_shape_query.shape = _rect_shape
	_shape_query.collision_mask = obstacle_mask
	_shape_query.collide_with_bodies = true
	_shape_query.collide_with_areas = false

func _sync_shader_params() -> void:
	if material is ShaderMaterial:
		var sm := material as ShaderMaterial
		sm.set_shader_parameter("shadow_color", shadow_color)
		sm.set_shader_parameter("shadow_darkness", shadow_darkness)
		sm.set_shader_parameter("edge_softness", edge_softness)
		sm.set_shader_parameter("dither_scale", dither_scale)
		sm.set_shader_parameter("dither_mode", dither_mode)

func _physics_process(_delta: float) -> void:
	if not enabled:
		return

	if target_entity == null or not is_instance_valid(target_entity):
		target_entity = get_tree().get_first_node_in_group("player") as Node2D
		if target_entity == null:
			return

	var player_pos: Vector2 = target_entity.global_position + vision_origin_offset
	var cam := get_viewport().get_camera_2d()
	var cam_pos := player_pos
	var cam_zoom := Vector2.ONE
	if is_instance_valid(cam):
		cam_pos = cam.get_screen_center_position()
		cam_zoom = cam.zoom

	# 检测脏标记：仅当玩家或摄像机位移超过阈值，或定期 (每 15 物理帧) 刷新时才重新计算
	var moved := player_pos.distance_squared_to(_last_player_pos) > 0.04 \
		or cam_pos.distance_squared_to(_last_cam_pos) > 0.04 \
		or cam_zoom != _last_cam_zoom
	var periodic := (Engine.get_physics_frames() % 15 == 0)

	if moved or periodic:
		_last_player_pos = player_pos
		_last_cam_pos = cam_pos
		_last_cam_zoom = cam_zoom
		_calculate_shadow_quads(player_pos, cam_pos, cam_zoom)
		queue_redraw()

## 强制刷新阴影多边形
func force_update() -> void:
	_last_player_pos = Vector2(-99999, -99999)

## 计算屏幕世界矩形范围
func _get_screen_world_rect(cam_pos: Vector2, cam_zoom: Vector2, margin: float = 0.0) -> Rect2:
	var vp_size := get_viewport_rect().size
	var z := cam_zoom if cam_zoom.x > 0.0 and cam_zoom.y > 0.0 else Vector2.ONE
	var half_w := (vp_size.x * 0.5) / z.x + margin
	var half_h := (vp_size.y * 0.5) / z.y + margin
	return Rect2(cam_pos.x - half_w, cam_pos.y - half_h, half_w * 2.0, half_h * 2.0)

## 提取障碍物的所有物理多边形顶点集合 (支持 CollisionPolygon2D 及各种 CollisionShape2D)
func _extract_obstacle_polygons(node: Node) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for child in node.get_children():
		if child is CollisionPolygon2D:
			var poly := child as CollisionPolygon2D
			if poly.polygon.size() >= 3:
				var xform := poly.global_transform
				var world_pts := PackedVector2Array()
				for pt in poly.polygon:
					world_pts.append(xform * pt)
				result.append(world_pts)
		elif child is CollisionShape2D:
			var cs := child as CollisionShape2D
			if cs.shape:
				var pts := _points_from_shape(cs.shape)
				if pts.size() >= 3:
					var xform := cs.global_transform
					var world_pts := PackedVector2Array()
					for pt in pts:
						world_pts.append(xform * pt)
					result.append(world_pts)
	return result

## 将各类 Shape2D 转换为几何多边形点集
func _points_from_shape(shape: Shape2D) -> PackedVector2Array:
	if shape is RectangleShape2D:
		var hs := (shape as RectangleShape2D).size * 0.5
		return PackedVector2Array([
			Vector2(-hs.x, -hs.y),
			Vector2(hs.x, -hs.y),
			Vector2(hs.x, hs.y),
			Vector2(-hs.x, hs.y)
		])
	elif shape is CircleShape2D:
		var r := (shape as CircleShape2D).radius
		var pts := PackedVector2Array()
		const SEGMENTS := 12
		for i in range(SEGMENTS):
			var a := (TAU * i) / float(SEGMENTS)
			pts.append(Vector2(cos(a) * r, sin(a) * r))
		return pts
	elif shape is ConvexPolygonShape2D:
		return (shape as ConvexPolygonShape2D).points
	return PackedVector2Array()

## 核心算法：提取屏幕内障碍物极值切点并向外投射阴影四边形
func _calculate_shadow_quads(player_pos: Vector2, cam_pos: Vector2, cam_zoom: Vector2) -> void:
	_shadow_quads.clear()

	if _shape_query == null:
		return

	var screen_rect := _get_screen_world_rect(cam_pos, cam_zoom, screen_margin)
	_rect_shape.size = screen_rect.size
	_shape_query.transform = Transform2D(0.0, cam_pos)
	_shape_query.collision_mask = obstacle_mask

	var space_state := get_world_2d().direct_space_state
	var hits := space_state.intersect_shape(_shape_query, max_obstacles)
	if hits.is_empty():
		return

	var extend_len := screen_rect.size.length() * shadow_extend_multiplier
	var processed_colliders: Dictionary = {}

	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider == null or not (collider is Node):
			continue

		var c_node := collider as Node
		if processed_colliders.has(c_node):
			continue
		processed_colliders[c_node] = true

		# 过滤自身、空气墙
		if c_node == target_entity or c_node.is_in_group("air_walls") or c_node is AirWallManager:
			continue
		if c_node.name.begins_with("AirWall"):
			continue

		var polygons := _extract_obstacle_polygons(c_node)
		for world_pts in polygons:
			if world_pts.size() < 3:
				continue

			# 计算几何中心
			var center := Vector2.ZERO
			for pt in world_pts:
				center += pt
			center /= float(world_pts.size())

			var base_dir := (center - player_pos)
			if base_dir.is_zero_approx():
				continue
			var base_angle := base_dir.angle()

			var min_rel := INF
			var max_rel := -INF
			var v_left := Vector2.ZERO
			var v_right := Vector2.ZERO

			# 极值顶点扫描法 (基于相对偏差角)
			for v in world_pts:
				var rel := wrapf((v - player_pos).angle() - base_angle, -PI, PI)
				if rel < min_rel:
					min_rel = rel
					v_left = v
				if rel > max_rel:
					max_rel = rel
					v_right = v

			# 异常防呆：相对角过小或跨度接近 PI (角色身处物体中心内部)
			if max_rel - min_rel < 0.001 or max_rel - min_rel > PI * 0.98:
				continue

			# 沿玩家到极值顶点的射线方向推向屏幕之外
			var dir_left := (v_left - player_pos).normalized()
			var dir_right := (v_right - player_pos).normalized()
			var e_left := player_pos + dir_left * extend_len
			var e_right := player_pos + dir_right * extend_len

			# 形成闭合的阴影四边形
			_shadow_quads.append(PackedVector2Array([v_left, e_left, e_right, v_right]))

const QUAD_UVS: PackedVector2Array = [
	Vector2(0.0, 0.0), # v_left (左切点基座)
	Vector2(0.0, 1.0), # e_left (左延伸远端)
	Vector2(1.0, 1.0), # e_right (右延伸远端)
	Vector2(1.0, 0.0)  # v_right (右切点基座)
]

func _draw() -> void:
	if not enabled or _shadow_quads.is_empty():
		return

	# 绘制所有阴影多边形，片元着色器将自动应用屏幕空间像素抖动与边缘柔和衰减
	for quad in _shadow_quads:
		if quad.size() >= 3:
			var local_quad := PackedVector2Array()
			for pt in quad:
				local_quad.append(to_local(pt))
			draw_colored_polygon(local_quad, shadow_color, QUAD_UVS)

