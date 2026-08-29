# mainchara.gd —— 主角脚本(格子高度加成·极简版)
extends CharacterBody2D

@export var move_speed: float = 60

# 瓷砖锚点在视觉底面,角色要站在顶面 → 额外上移 8px
@export var foot_offset: float = -8.0
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = get_node_or_null("Camera2D")
# 可在检查器实时微调的摄像机速度曲线参数
@export_group("摄像机速度曲线与跟随")
@export var enable_camera_height_smooth: bool = true # 是否开启高度平滑缓动
@export var camera_speed: float = 8.0                # 跟随速度（数值越大越紧凑，数值越小越柔和）

var current_anim: String = "walkSouth"
var sort_key: float = 0.0        # 排序主键(所在格基底 y)
var layer_no: int = 1000         # 排序次键(实体,不参与同格实体比较)
var foot_y: float = 0.0          # 精确脚底屏幕 y(同格实体间比较用)


func _ready() -> void:
	# 等一帧:确保 mainScene._ready 已构建高度场
	await get_tree().process_frame
	_update_sort_key()


func _physics_process(_delta: float) -> void:
	# ---------- 1. 输入(屏幕方向:W上 S下 A左 D右) ----------
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_down"):
		input_dir.y += 1.0
	if Input.is_action_pressed("move_up"):
		input_dir.y -= 1.0
	input_dir = input_dir.normalized()

	# ---------- 2. 移动(屏幕十字;对角对齐格子边) ----------
	var move_dir := input_dir
	if input_dir.x != 0.0 and input_dir.y != 0.0:
		# 对角:吸附到最近的等距格子边方向(斜率 ±0.5,即 2:1)
		move_dir = Vector2(
			signf(input_dir.x) * 16.0,
			signf(input_dir.y) * 8.0
		).normalized()
	velocity = move_dir * move_speed
	move_and_slide()

	# ---------- 3. 高度加成与摄像机阻尼速度曲线 ----------
	var cell := GridData.world_to_cell(global_position)
	var floor := GridData.get_highest_floor(cell)
	animated_sprite.position.y = GridData.get_floor_pixel_offset(floor) + foot_offset

	if camera:
		var target_camera_y := animated_sprite.position.y
		if enable_camera_height_smooth:
			# 指数衰减阻尼曲线（Ease-Out：快速响应、柔和减速靠拢）
			camera.position.y = lerpf(camera.position.y, target_camera_y, 1.0 - exp(-camera_speed * _delta))
		else:
			camera.position.y = target_camera_y

	# ---------- 4. 更新排序键(只有换格子才重排) ----------
	_update_sort_key()

	# ---------- 5. 动画(用输入方向判断) ----------
	if input_dir != Vector2.ZERO:
		var anim := _get_walk_anim(input_dir)
		if anim != current_anim:
			current_anim = anim
		animated_sprite.play(current_anim)
	else:
		animated_sprite.pause()


# 更新排序键,并通知父级排序容器重排
func _update_sort_key() -> void:
	if GridData.layers.is_empty():
		return
	var cell := GridData.world_to_cell(global_position)
	var new_key := GridData.cell_to_sort_key(cell)
	var new_foot := global_position.y + GridData.get_floor_pixel_offset(GridData.get_highest_floor(cell))
	if new_key != sort_key or new_foot != foot_y:
		sort_key = new_key
		foot_y = new_foot
		var parent_sort := get_parent()
		if parent_sort and parent_sort.has_method("insert_sort"):
			parent_sort.insert_sort(self)


func _get_walk_anim(dir: Vector2) -> String:
	var anim := "walk"
	if dir.x < 0.0:
		anim += "West"
	elif dir.x > 0.0:
		anim += "East"
	elif dir.y < 0.0:
		anim += "North"
	else:
		anim += "South"
	return anim

# 获取角色当前视觉脚底的世界坐标（支持楼层高度变化）
func get_visual_foot_position() -> Vector2:
	var cell := GridData.world_to_cell(global_position)
	var floor := GridData.get_highest_floor(cell)
	# 脚底 Y = 角色自身平面 Y + 楼层抬高偏移 - 8px（往上抬高 8 像素）
	var foot_y_pos := global_position.y + GridData.get_floor_pixel_offset(floor) - 6.0
	return Vector2(global_position.x, foot_y_pos)