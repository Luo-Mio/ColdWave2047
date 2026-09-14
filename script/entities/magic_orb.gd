# magic_orb.gd —— 真实 3D 弹道与等距深度排序飞弹实体
class_name MagicOrb
extends Node2D

@export var speed: float = 420.0             # 飞行初速度 (像素/秒)
@export var gravity: float = 0.0             # 3D 垂直重力下坠 (0 = 直线魔法流, >0 = 抛物线)
@export var launch_height: float = 10.0       # 出膛落差高度 (像素，默认 10px)
@export var damage: float = 35.0              # 伤害数值 (每次命中造成的生命值扣减)
@export var shooter: Node = null              # 发射者引用 (防止发射瞬间自伤)

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
	# 站在 start_floor 楼层时，飞弹从该楼层表面上方 +launch_height 像素（胸口/手部位置）出膛
	height_px = float(start_floor) * 16.0 + launch_height
	
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
	# 1. 3D 空间精确运动学步进 (二阶 Verlet 积分)
	var next_ground := ground_pos + velocity_ground * delta
	var next_height := height_px + (velocity_z - 0.5 * gravity * delta) * delta
	var next_vz := velocity_z - gravity * delta

	# 2. 命中生物碰撞箱检测 (Layer 3: 活体生物层)
	if _check_creature_hit(ground_pos, next_ground, next_height):
		ground_pos = next_ground
		height_px = next_height
		_update_3d_transform_and_sorting()
		queue_free()
		return

	# 3. 地形高度与连续触地截断检测 (Continuous Impact Clamping)
	var prev_cell := GridData.world_to_cell(ground_pos)
	var prev_surf := float(GridData.get_highest_floor(prev_cell)) * 16.0 if GridData.has_any_tile(prev_cell) else 0.0

	var next_cell := GridData.world_to_cell(next_ground)
	var next_surf := float(GridData.get_highest_floor(next_cell)) * 16.0 if GridData.has_any_tile(next_cell) else 0.0

	var hit := false
	var hit_surf := 0.0
	var hit_ground := next_ground

	# 优先检测当前平面下穿触地：若本帧高度下穿至或低于当前所在地面高度 prev_surf
	if next_height <= prev_surf:
		var denom := maxf(height_px - next_height, 0.0001)
		var frac := clampf((height_px - prev_surf) / denom, 0.0, 1.0)
		var test_g := ground_pos.lerp(next_ground, frac)
		var test_cell := GridData.world_to_cell(test_g)
		var test_surf := float(GridData.get_highest_floor(test_cell)) * 16.0 if GridData.has_any_tile(test_cell) else 0.0

		if test_surf <= prev_surf:
			# 在飞入前方任何更高障碍前，已精确落在当前地面上
			hit_ground = test_g
			hit_surf = test_surf
			hit = true
		else:
			# 着地点处于更高格子，撞击高台侧面
			hit_ground = test_g
			hit_surf = height_px
			hit = true
	elif next_surf > prev_surf:
		# 前方地表高于当前地表
		if height_px >= next_surf and next_height <= next_surf:
			# 从上方降落到高台台面
			var denom := maxf(height_px - next_height, 0.0001)
			var frac := clampf((height_px - next_surf) / denom, 0.0, 1.0)
			hit_ground = ground_pos.lerp(next_ground, frac)
			hit_surf = next_surf
			hit = true
		elif height_px < next_surf and next_height <= next_surf:
			# 飞弹高度低于高台台面，撞击高台侧面墙体截断：取跨格接触中点，与瞄准线预测一致
			hit_ground = ground_pos.lerp(next_ground, 0.5)
			hit_surf = clampf(lerpf(height_px, next_height, 0.5), 0.0, next_surf)
			hit = true
	elif next_height <= next_surf:
		# 下落触及次级较低地面
		var denom := maxf(height_px - next_height, 0.0001)
		var frac := clampf((height_px - next_surf) / denom, 0.0, 1.0)
		hit_ground = ground_pos.lerp(next_ground, frac)
		hit_surf = next_surf
		hit = true

	if hit:
		ground_pos = hit_ground
		height_px = hit_surf
		_update_3d_transform_and_sorting()
		queue_free()
		return

	ground_pos = next_ground
	height_px = next_height
	velocity_z = next_vz

	# 3. 更新 2.5D 屏幕位置与 3D 空间深度
	_update_3d_transform_and_sorting()

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

	# 3. 2.5D 等距视线深度排序：
	#    严格基于地面大格与格内微偏移，与角色和生物深度排序系统完全统一。
	#    杜绝直接累加 height_px，否则会导致处于立柱/高墙后方（-xy）时因高度加成错误被提至立柱前方！
	var current_cell := GridData.world_to_cell(ground_pos)
	var base_key := GridData.cell_to_sort_key(current_cell)
	var cell_center := GridData.cell_to_world(current_cell)
	var rel_y := clampf((ground_pos.y - cell_center.y) + 16.0, 0.0, 32.0)
	var sub_depth := (rel_y / 32.0) * 15.0
	
	sort_key = base_key + sub_depth

	# 4. 通知 sort_world 动态排位
	var parent_sort := get_parent()
	if parent_sort and parent_sort.has_method("insert_sort"):
		parent_sort.call("insert_sort", self)

## 检测飞弹是否与场景中的活体生物发生碰撞
func _check_creature_hit(from_ground: Vector2, to_ground: Vector2, current_h: float) -> bool:
	var space := get_world_2d().direct_space_state
	if space == null:
		return false

	# 1. 沿地面位移线段检测 Layer 3 (数值 4: 活体生物层)
	var ray_param := PhysicsRayQueryParameters2D.create(from_ground, to_ground, 4)
	ray_param.collide_with_bodies = true
	ray_param.collide_with_areas = false
	if shooter and shooter is CollisionObject2D:
		ray_param.exclude = [shooter.get_rid()]

	var hit_dict := space.intersect_ray(ray_param)
	var target_body: Node2D = null

	if not hit_dict.is_empty():
		target_body = hit_dict.get("collider") as Node2D
	else:
		# 2. 射线未命中时，点检测终点位置
		var point_param := PhysicsPointQueryParameters2D.new()
		point_param.position = to_ground
		point_param.collision_mask = 4
		if shooter and shooter is CollisionObject2D:
			point_param.exclude = [shooter.get_rid()]
		var point_hits := space.intersect_point(point_param, 1)
		if not point_hits.is_empty():
			target_body = point_hits[0].get("collider") as Node2D

	if target_body and is_instance_valid(target_body) and target_body != shooter:
		# 3. 2.5D 垂直高度判定：飞弹离地高度必须处于生物垂直高度范围内
		var target_floor: int = target_body.call("get_current_floor") if target_body.has_method("get_current_floor") else 0
		var ground_h := float(target_floor) * 16.0
		var eye_h: float = float(target_body.get("eye_height")) if ("eye_height" in target_body) else 18.0
		var body_scale: float = target_body.scale.y if ("scale" in target_body) else 1.0
		var top_h := ground_h + eye_h * body_scale + 6.0

		if current_h >= ground_h - 6.0 and current_h <= top_h:
			if target_body.has_method("take_damage"):
				target_body.call("take_damage", damage, shooter if shooter else self)
			else:
				var health: Node = target_body.find_child("HealthComponent", true, false)
				if health and health.has_method("take_damage"):
					health.call("take_damage", damage, shooter if shooter else self)
			return true

	return false