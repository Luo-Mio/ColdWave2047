# magic_orb.gd —— 2.5D 地面基准精准排序魔法飞弹
class_name MagicOrb
extends Node2D

@export var speed: float = 400.0   # 飞行速度 (像素/秒)
var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 2.5          # 飞行寿命（秒）

# 2.5D 深度与高度追踪
var ground_pos: Vector2 = Vector2.ZERO   # 飞弹在地面平面的投影位置
var height_offset: float = -8.0         # 飞行悬浮高度 (胸口偏移)
var floor_level: int = 0                # 所在楼层高度

var layer_no: int = 1000
var sort_key: float = 0.0
var foot_y: float = 0.0

# 外部发射时调用
func launch(dir: Vector2, start_ground_pos: Vector2, start_floor: int) -> void:
	ground_pos = start_ground_pos
	floor_level = start_floor
	
	var norm_dir := dir.normalized()
	velocity = norm_dir * speed
	rotation = norm_dir.angle()
	
	_update_visual_and_sorting()

func _physics_process(delta: float) -> void:
	# 1. 地面投影平滑前进
	ground_pos += velocity * delta

	# 2. 实时更新屏幕空中位置与精准 2.5D 深度
	_update_visual_and_sorting()

	# 3. 超时自动销毁
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

# 核心：用地面影子计算真实排序，用空中坐标渲染贴图
func _update_visual_and_sorting() -> void:
	# 1. 空中视觉位置 = 地面位置 + 楼层抬升 + 胸口悬浮高度
	var floor_y_lift := GridData.get_floor_pixel_offset(floor_level)
	global_position = ground_pos + Vector2(0.0, floor_y_lift + height_offset)
	foot_y = ground_pos.y

	# 2. 基于纯净的地面坐标计算 sort_key，绝不产生坐标跳变！
	var current_cell := GridData.world_to_cell(ground_pos)
	var base_key := GridData.cell_to_sort_key(current_cell)
	var cell_center := GridData.cell_to_world(current_cell)
	var rel_y := clampf((ground_pos.y - cell_center.y) + 16.0, 0.0, 32.0)
	var sub_depth := (rel_y / 32.0) * 15.0
	
	sort_key = base_key + sub_depth

	# 3. 通知 sort_world 平稳排位
	var parent_sort := get_parent()
	if parent_sort and parent_sort.has_method("insert_sort"):
		parent_sort.call("insert_sort", self)