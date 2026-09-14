# aim_camera_assist.gd —— 2.5D 等距空间瞄准视角延伸拉扯辅助处理器
class_name AimCameraAssist
extends RefCounted

var _camera: Camera2D = null
var current_cam_offset: Vector2 = Vector2.ZERO

## 获取并缓存活动摄像机引用
func get_camera(entity: CanvasItem, tree: SceneTree) -> Camera2D:
	if is_instance_valid(_camera):
		return _camera
	if entity and is_instance_valid(entity):
		var vp := entity.get_viewport()
		if vp:
			_camera = vp.get_camera_2d()
		if not is_instance_valid(_camera):
			_camera = entity.find_child("Camera2D", true, false) as Camera2D
	elif tree and tree.root:
		_camera = tree.root.find_child("Camera2D", true, false) as Camera2D
	return _camera

## 每帧平滑更新视角平移与回中
func update(
	delta: float,
	is_aim_active: bool,
	entity: CanvasItem,
	tree: SceneTree,
	enable_assist: bool,
	offset_dist: float,
	vert_ratio: float,
	edge_threshold: float,
	smooth_speed: float
) -> void:
	var cam := get_camera(entity, tree)
	if cam == null:
		return

	var target_offset := Vector2.ZERO

	if enable_assist and is_aim_active and entity and entity.is_inside_tree():
		var vp := entity.get_viewport()
		if vp:
			var vp_rect := vp.get_visible_rect()
			var vp_size := vp_rect.size
			if vp_size.x > 1.0 and vp_size.y > 1.0:
				var vp_center := vp_size * 0.5
				var mouse_vp := vp.get_mouse_position()
				var delta_mouse := mouse_vp - vp_center
				var norm_vec := Vector2(
					delta_mouse.x / vp_center.x,
					delta_mouse.y / vp_center.y
				)
				var dist := minf(norm_vec.length(), 1.0)
				if dist > edge_threshold:
					var u := clampf((dist - edge_threshold) / maxf(1.0 - edge_threshold, 0.001), 0.0, 1.0)
					var factor := u * u * (3.0 - 2.0 * u)
					var dir := delta_mouse.normalized()
					target_offset = Vector2(
						dir.x * offset_dist,
						dir.y * (offset_dist * vert_ratio)
					) * factor

	# 平滑插值 (指数平滑衰减，不受渲染帧率波动影响)
	if current_cam_offset.distance_squared_to(target_offset) > 0.01:
		var t := 1.0 - exp(-smooth_speed * delta)
		current_cam_offset = current_cam_offset.lerp(target_offset, t)
		if current_cam_offset.distance_squared_to(target_offset) < 0.01:
			current_cam_offset = target_offset
		cam.offset = current_cam_offset
	elif cam.offset != target_offset:
		current_cam_offset = target_offset
		cam.offset = target_offset

## 重置镜头偏移至居中原点
func reset_offset() -> void:
	if is_instance_valid(_camera):
		_camera.offset = Vector2.ZERO
	current_cam_offset = Vector2.ZERO

