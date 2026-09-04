# iso_depth_component.gd —— 2.5D 等距深度排序与楼层高度跟踪通用组件
class_name IsoDepthComponent
extends Node

@export_group("2.5D 深度与触地锚点")
# 贴图中心到脚底/爪底的局部像素距离 (例如: 32x32 角色中心到脚底为 -12px; 64x64 狼中心到爪底为 -16px)
@export var foot_offset_y: float = -12.0
# 深度排序锚点微调 (像素)
@export var sort_origin_offset_y: float = 0.0
# 排序次键 (同深度时实体图层号，默认 1000)
@export var layer_no: int = 1000

@export_group("摄像机平滑跟随 (仅玩家需要)")
@export var enable_camera_follow: bool = false
@export var camera_speed: float = 8.0

var parent_entity: Node2D
var sprite: AnimatedSprite2D
var col_shape: CollisionPolygon2D
var camera: Camera2D

var current_floor: int = 0

func _ready() -> void:
	parent_entity = get_parent() as Node2D
	if parent_entity == null:
		return

	# 自动寻找常见的关键子节点
	sprite = parent_entity.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	col_shape = parent_entity.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	camera = parent_entity.get_node_or_null("Camera2D") as Camera2D

	# 确保父节点具备排序所需的变量
	if not ("sort_key" in parent_entity):
		parent_entity.set("sort_key", 0.0)
	if not ("foot_y" in parent_entity):
		parent_entity.set("foot_y", 0.0)
	if not ("layer_no" in parent_entity):
		parent_entity.set("layer_no", layer_no)

	# 等待一帧让场景和 GridData 完全初始化
	await get_tree().process_frame
	update_depth(0.0)

# 获取实体脚底/四爪接触地面的精确全局世界坐标
func get_visual_foot_position() -> Vector2:
	if sprite and parent_entity:
		var s_y := parent_entity.scale.y if parent_entity.scale.y != 0.0 else 1.0
		# 贴图世界坐标中心往下偏移 |foot_offset_y| * scale.y 即为视觉脚底
		return sprite.global_position + Vector2(0.0, absf(foot_offset_y) * s_y)
	return parent_entity.global_position if parent_entity else Vector2.ZERO

# 每物理帧调用：处理楼层高度抬升、贴地与 2.5D 深度动态排序
func update_depth(delta: float) -> void:
	if parent_entity == null:
		return

	var s_y := parent_entity.scale.y if parent_entity.scale.y != 0.0 else 1.0

	# 1. 查询当前脚底所在格子的楼层高度 (必须使用物理实体的地面坐标 parent_entity.global_position，绝不能用抬升后的视觉贴图坐标，否则会导致高频闪烁死循环！)
	var ground_pos := parent_entity.global_position
	var cell := GridData.world_to_cell(ground_pos)
	current_floor = GridData.get_highest_floor(cell)
	var floor_offset := GridData.get_floor_pixel_offset(current_floor)
	var local_floor_y := floor_offset / s_y

	# 2. 贴图视觉抬升 (scale 换算补偿，严丝合缝贴合楼层)
	if sprite:
		sprite.position.y = local_floor_y + foot_offset_y

	# 3. 碰撞体高度同步抬升
	if col_shape:
		col_shape.position.y = local_floor_y

	# 4. 摄像机平滑跟随 (如果有)
	if enable_camera_follow and camera and sprite:
		var target_cam_y := sprite.position.y
		camera.position.y = lerpf(camera.position.y, target_cam_y, 1.0 - exp(-camera_speed * delta))

	# 5. 2.5D 深度排序计算 (基于实体的地面基准坐标)
	var eval_pos := ground_pos + Vector2(0.0, sort_origin_offset_y)
	var current_cell := GridData.world_to_cell(eval_pos)
	var base_key := GridData.cell_to_sort_key(current_cell)

	var cell_center := GridData.cell_to_world(current_cell)
	var rel_y := clampf((eval_pos.y - cell_center.y) + 16.0, 0.0, 32.0)
	var sub_depth := (rel_y / 32.0) * 15.0

	var final_sort_key := base_key + sub_depth
	parent_entity.set("sort_key", final_sort_key)
	parent_entity.set("foot_y", eval_pos.y)
	parent_entity.set("layer_no", layer_no)

	# 6. 通知父级排序容器 sort_world 重排
	var parent_sort := parent_entity.get_parent()
	if parent_sort and parent_sort.has_method("insert_sort"):
		parent_sort.call("insert_sort", parent_entity)

