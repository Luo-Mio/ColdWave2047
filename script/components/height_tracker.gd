# height_tracker.gd —— 楼层高度跟踪与摄像机阻尼跟随组件
class_name HeightTracker
extends Node

# 32x32 角色贴图中心在 (0, -12)，确保角色脚底刚好落在碰撞体 (0, 0)
@export var foot_offset: float = -12.0

@export_group("摄像机高度阻尼曲线")
@export var enable_camera_height_smooth: bool = true
@export var camera_speed: float = 8.0

var current_floor: int = 0

# 每物理帧更新角色贴图高度与摄像机阻尼
func update_height(player_pos: Vector2, sprite: AnimatedSprite2D, camera: Camera2D, delta: float) -> void:
	var cell := GridData.world_to_cell(player_pos)
	current_floor = GridData.get_highest_floor(cell)

	var parent_node := get_parent() as Node2D
	var s_y := parent_node.scale.y if (parent_node and parent_node.scale.y != 0.0) else 1.0
	var floor_offset := GridData.get_floor_pixel_offset(current_floor)

	if sprite:
		# 换算局部缩放：消除 CharacterBody2D 设置 scale (如 2x) 带来的高度翻倍 Bug！
		sprite.position.y = (floor_offset / s_y) + foot_offset

	# 同步赋予角色碰撞箱楼层高度加成
	if parent_node:
		var col := parent_node.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
		if col:
			col.position.y = floor_offset / s_y

	if camera and sprite:
		var target_camera_y := sprite.position.y
		if enable_camera_height_smooth:
			camera.position.y = lerpf(camera.position.y, target_camera_y, 1.0 - exp(-camera_speed * delta))
		else:
			camera.position.y = target_camera_y

# 获取角色脚底的视觉世界坐标（供 X-Ray 透视 Shader 使用）
func get_visual_foot_position(player_pos: Vector2) -> Vector2:
	var foot_y_pos := player_pos.y + GridData.get_floor_pixel_offset(current_floor) - 8.0
	return Vector2(player_pos.x, foot_y_pos)

# 获取 2.5D 深度排序键
func get_sort_key(player_pos: Vector2) -> float:
	var cell := GridData.world_to_cell(player_pos)
	return GridData.cell_to_sort_key(cell)

