# main_chara.gd —— 主角控制器（纯净组件装配版）
extends CharacterBody2D

const MovementControllerScript := preload("res://script/components/movement_controller.gd")
const HeightTrackerScript := preload("res://script/components/height_tracker.gd")
const AnimationControllerScript := preload("res://script/components/animation_controller.gd")

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = get_node_or_null("Camera2D")

@onready var movement: Node = get_node_or_null("MovementController")
@onready var height_tracker: Node = get_node_or_null("HeightTracker")
@onready var anim_controller: Node = get_node_or_null("AnimationController")

var layer_no: int = 1000
var sort_key: float = 0.0
var foot_y: float = 0.0

var _last_cell: Vector2i = Vector2i(-99999, -99999)

func _ready() -> void:
	if movement == null:
		movement = MovementControllerScript.new()
		add_child(movement)
	if height_tracker == null:
		height_tracker = HeightTrackerScript.new()
		add_child(height_tracker)
	if anim_controller == null:
		anim_controller = AnimationControllerScript.new()
		add_child(anim_controller)

	await get_tree().process_frame
	foot_y = global_position.y
	_update_sort_key()

func _physics_process(delta: float) -> void:
	velocity = movement.call("get_movement_velocity")
	move_and_slide()

	# 2. 楼层高度跟踪与摄像机平滑阻尼
	height_tracker.call("update_height", global_position, animated_sprite, camera, delta)

	# 3. 更新脚底坐标并执行 2.5D 深度排序
	foot_y = global_position.y
	_update_sort_key()

	# 4. 驱动 4 向行走/待机定格动画
	var input_dir: Vector2 = movement.call("get_input_direction")
	anim_controller.call("update_animation", input_dir, animated_sprite)

	foot_y = global_position.y
	_update_sort_key()

func _update_sort_key() -> void:
	var current_cell := GridData.world_to_cell(global_position)
	var base_key := GridData.cell_to_sort_key(current_cell)
	
	# 实时计算角色在当前菱形内的相对 Y 偏移，映射为连续的微深度（0.0 ~ 7.0）
	var cell_center := GridData.cell_to_world(current_cell)
	var rel_y := clampf((global_position.y - cell_center.y) + 8.0, 0.0, 16.0)
	var sub_depth := (rel_y / 16.0) * 7.0
	
	sort_key = base_key + sub_depth

	var parent_sort := get_parent()
	if parent_sort and parent_sort.has_method("insert_sort"):
		parent_sort.call("insert_sort", self)

	# 供全局 Shader（树干与高墙透视）获取角色的视觉身体/脸部世界坐标
func get_visual_foot_position() -> Vector2:
	if animated_sprite:
		# animated_sprite.global_position 已包含真实楼层高度抬升，上移 6px 精准对齐脸部！
		return animated_sprite.global_position + Vector2(0.0, 2.0)
	return global_position