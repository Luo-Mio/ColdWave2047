# magic_orb.gd —— 真实 3D 弹道与等距深度排序飞弹实体
class_name MagicOrb
extends Node2D

@export var speed: float = 420.0             # 飞行初速度 (像素/秒)
@export var gravity: float = 0.0             # 3D 垂直重力下坠 (0 = 直线魔法流, >0 = 抛物线)

# 3D 物理状态
var ground_pos: Vector2 = Vector2.ZERO       # 地面投影坐标 (像素)
var height_px: float = 8.0                   # 垂直离地高度 (像素, 16px = 1层楼)
var velocity_ground: Vector2 = Vector2.ZERO  # 地面平移速度
var velocity_z: float = 0.0                  # 垂直爬升/下坠速度 (像素/秒)
var lifetime: float = 2.5                    # 最大寿命 (秒)

# 2.5D 深度排序属性
var layer_no: int = 1000
var sort_key: float = 0.0
var foot_y: float = 0.0

# 3D 发射接口：接收 3D 单位瞄准向量、角色地面坐标与站立楼层
func launch_3d(aim_3d: Vector3, start_ground: Vector2, start_floor: int) -> void:
	ground_pos = start_ground
	# 站在 start_floor 楼层时，飞弹从该楼层表面上方 +10 像素（胸口位置）出膛
	height_px = float(start_floor) * 16.0 + 10.0
	
	# 1. 纯净 3D 物理速度分解
	var horiz_length := sqrt(aim_3d.x * aim_3d.x + aim_3d.y * aim_3d.y)
	var v_horiz := speed * horiz_length
	velocity_z = aim_3d.z * speed
	
	# 2. 真实 2:1 等距地面速度分解 (X轴全速, Y轴压缩为 0.5 倍，形成严格 2:1 椭圆地面落点)
	if horiz_length > 0.001:
		var gx := aim_3d.x / horiz_length
		var gy := aim_3d.y / horiz_length
		var cos_a := (gx - gy) / sqrt(2.0)
		var sin_a := (gx + gy) / sqrt(2.0)
		velocity_ground = Vector2(cos_a, sin_a * 0.5) * v_horiz
	else:
		velocity_ground = Vector2.ZERO
	
	_update_3d_transform_and_sorting()

# 兼容旧版 2D 接口
func launch(dir_2d: Vector2, start_ground: Vector2, start_floor: int) -> void:
	launch_3d(Vector3(dir_2d.x, dir_2d.y, 0.0).normalized(), start_ground, start_floor)

func _physics_process(delta: float) -> void:
	# 1. 3D 空间物理推进
	ground_pos += velocity_ground * delta
	height_px += velocity_z * delta
	velocity_z -= gravity * delta

	# 2. 更新 2.5D 屏幕位置与 3D 空间深度
	_update_3d_transform_and_sorting()

	# 3. 地形高度与触地/撞墙检测
	var current_cell := GridData.world_to_cell(ground_pos)
	if GridData.has_any_tile(current_cell):
		var terrain_floor := GridData.get_highest_floor(current_cell)
		var terrain_surface_px := float(terrain_floor) * 16.0
		# 只有当高度跌落进当前格子的地表表面以下时才判定为撞地销毁
		if height_px <= terrain_surface_px - 2.0:
			queue_free()
			return

	# 4. 超时销毁
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

# 核心：计算 3D 空间屏幕投影与 3D 视线深度
func _update_3d_transform_and_sorting() -> void:
	# 1. 屏幕视觉位置 = 地面位置 - 空中高度抬升 (向上为负 Y)
	global_position = ground_pos - Vector2(0.0, height_px)
	foot_y = ground_pos.y

	# 2. 飞弹自身朝向（始终沿着屏幕运动速度切线）
	var screen_velocity := velocity_ground - Vector2(0.0, velocity_z)
	if screen_velocity.length_squared() > 0.1:
		rotation = screen_velocity.angle()

	# 3. 黄金 3D 视线深度公式：
	#    sort_key = (地面大格基准深度) + (格内微深度) + (3D空中高度加成！)
	var current_cell := GridData.world_to_cell(ground_pos)
	var base_key := GridData.cell_to_sort_key(current_cell)
	var cell_center := GridData.cell_to_world(current_cell)
	var rel_y := clampf((ground_pos.y - cell_center.y) + 16.0, 0.0, 32.0)
	var sub_depth := (rel_y / 32.0) * 15.0
	
	# 【最核心关键】：将垂直高度 height_px 转化为深度权重加成！
	# 飞得越高，深度越大，稳稳呈现在大树和地砖的上层！
	sort_key = base_key + sub_depth + height_px

	# 4. 通知 sort_world 动态排位
	var parent_sort := get_parent()
	if parent_sort and parent_sort.has_method("insert_sort"):
		parent_sort.call("insert_sort", self)