# aim_controller.gd —— 2.5D 等距极坐标 3D 瞄准控制器
class_name AimController
extends Node

@export_group("基准环与手感参数 (Base & Sensitivity)")
## 最小有效射击半径 (像素，默认 30.0)。鼠标拉至此半径以内时贴附在脚底近距离
@export var radius_min: float = 30.0
## 基准水平射击半径 (像素，θ = 0°)。鼠标光标落在此环上时俯仰角刚好为 0°
@export var radius_horizontal: float = 240.0
## 最大仰角外环半径 (像素)。鼠标拉到此半径时达到最大仰角 (+max_pitch_deg)
@export var radius_max: float = 360.0
## 最大俯仰角 (度数)。控制最大抬枪/压枪角度 (限制为 45.0 度，保证射程单调递增绝不回缩)
@export_range(15.0, 45.0, 1.0) var max_pitch_deg: float = 45.0
## 俯仰角手感响应曲线指数 (默认 y = x^2 平滑二次曲线，手感平滑响应均匀)
@export_range(1.0, 8.0, 0.5) var pitch_curve_power: float = 2.0

@export_group("视觉准心配置 (Visual Reticle)")
## 基准水平中环颜色 (θ = 0°)
@export var ring_color: Color = Color(0.2, 0.9, 1.0, 0.6)
## 最大俯角内环颜色 (θ = -max_pitch_deg)
@export var inner_ring_color: Color = Color(1.0, 0.45, 0.35, 0.45)
## 最大仰角外环颜色 (θ = +max_pitch_deg)
@export var outer_ring_color: Color = Color(0.2, 0.9, 1.0, 0.35)
## 准心指示器光标颜色
@export var cursor_color: Color = Color(0.2, 1.0, 0.5, 0.9)
## 3D 激光瞄准线颜色
@export var laser_color: Color = Color(1.0, 0.95, 0.2, 0.85)
## 激光瞄准虚线长度 (像素)
@export var laser_length: float = 180.0

@export_group("弹道与下坠参数 (Ballistics & Drop)")
## 抛射物初速度 (像素/秒，控制射击初始冲力，默认与 MagicOrb 520.0 对齐)
@export var projectile_speed: float = 520.0
## 物品重力/下坠值 (像素/秒²，下坠值越大，弹道弧度越陡峭，默认与 MagicOrb 800.0 对齐)
@export var drop_value: float = 800.0
## 出膛点到地面判定平面的垂直总落差高度 (像素，默认手部+10px至地面地表，共10.0px)
@export var launch_height: float = 10.0
## 弹道采样分段数 (数值越大折线越平滑)
@export var trajectory_segments: int = 32
## 弹道指示线颜色 (浅蓝色细线)
@export var trajectory_color: Color = Color(0.4, 0.8, 1.0, 0.85)
## 弹道指示线线宽 (像素)
@export var trajectory_width: float = 1.5

# 向后兼容别名属性
var radius_deadzone: float:
	get: return radius_min
	set(v): radius_min = v
var deadzone_color: Color:
	get: return inner_ring_color
	set(v): inner_ring_color = v

# 当前瞄准激活状态 (受手持道具控制)
var is_aim_active: bool = false

# 当前计算状态
var azimuth_rad: float = 0.0                 # 地面 360° 水平方位角 (0 ~ 2π)
var pitch_rad: float = 0.0                   # 3D 俯仰角 (-max_pitch ~ +max_pitch)
var aim_vector_3d: Vector3 = Vector3.ZERO    # 纯净 3D 单位瞄准朝向
var is_in_deadzone: bool = false             # 兼容旧代码字段，死区已取消
var _last_valid_azimuth: float = 0.0

# 默认参数备份 (用于道具卸下后恢复默认)
var _default_config: Dictionary = {}
var entity: CharacterBody2D = null

func _ready() -> void:
	_save_defaults()

	# 向上查找所属实体
	var curr := get_parent()
	while curr:
		if curr is CharacterBody2D:
			entity = curr as CharacterBody2D
			break
		curr = curr.get_parent()

func _save_defaults() -> void:
	_default_config = {
		"radius_min": radius_min,
		"radius_horizontal": radius_horizontal,
		"radius_max": radius_max,
		"max_pitch_deg": max_pitch_deg,
		"pitch_curve_power": pitch_curve_power,
		"ring_color": ring_color,
		"inner_ring_color": inner_ring_color,
		"outer_ring_color": outer_ring_color,
		"cursor_color": cursor_color,
		"laser_color": laser_color,
		"laser_length": laser_length,
		"projectile_speed": projectile_speed,
		"drop_value": drop_value,
		"launch_height": launch_height,
		"trajectory_segments": trajectory_segments,
		"trajectory_color": trajectory_color,
		"trajectory_width": trajectory_width,
	}

# 动态应用道具专属的瞄准参数 (如不同武器具有不同基准环大小或射程)
func apply_aim_config(config: Dictionary) -> void:
	is_aim_active = true
	# 先重置为默认值，保证省略未指定的参数能平滑继承 Inspector 默认配置
	if not _default_config.is_empty():
		radius_min = _default_config["radius_min"]
		radius_horizontal = _default_config["radius_horizontal"]
		radius_max = _default_config["radius_max"]
		max_pitch_deg = _default_config["max_pitch_deg"]
		pitch_curve_power = _default_config["pitch_curve_power"]
		ring_color = _default_config["ring_color"]
		inner_ring_color = _default_config["inner_ring_color"]
		outer_ring_color = _default_config["outer_ring_color"]
		cursor_color = _default_config["cursor_color"]
		laser_color = _default_config["laser_color"]
		laser_length = _default_config["laser_length"]
		projectile_speed = _default_config["projectile_speed"]
		drop_value = _default_config["drop_value"]
		launch_height = _default_config["launch_height"]
		trajectory_segments = _default_config["trajectory_segments"]
		trajectory_color = _default_config["trajectory_color"]
		trajectory_width = _default_config["trajectory_width"]

	if config.has("radius_min"):
		radius_min = float(config["radius_min"])
	elif config.has("radius_deadzone"):
		radius_min = float(config["radius_deadzone"])
	if config.has("radius_horizontal"):
		radius_horizontal = float(config["radius_horizontal"])
		radius_max = maxf(radius_max, radius_horizontal * 1.5)
	if config.has("radius_max"):
		radius_max = float(config["radius_max"])
	if config.has("max_pitch_deg"):
		max_pitch_deg = float(config["max_pitch_deg"])
	if config.has("pitch_curve_power"):
		pitch_curve_power = float(config["pitch_curve_power"])
	if config.has("ring_color"):
		ring_color = config["ring_color"]
	if config.has("inner_ring_color"):
		inner_ring_color = config["inner_ring_color"]
	elif config.has("deadzone_color"):
		inner_ring_color = config["deadzone_color"]
	if config.has("outer_ring_color"):
		outer_ring_color = config["outer_ring_color"]
	if config.has("cursor_color"):
		cursor_color = config["cursor_color"]
	if config.has("laser_color"):
		laser_color = config["laser_color"]
	if config.has("laser_length"):
		laser_length = float(config["laser_length"])
	if config.has("projectile_speed"):
		projectile_speed = float(config["projectile_speed"])
	elif config.has("speed"):
		projectile_speed = float(config["speed"])
	if config.has("drop_value"):
		drop_value = float(config["drop_value"])
	elif config.has("gravity"):
		drop_value = float(config["gravity"])
	if config.has("launch_height"):
		launch_height = float(config["launch_height"])
	if config.has("trajectory_segments"):
		trajectory_segments = int(config["trajectory_segments"])
	if config.has("trajectory_color"):
		trajectory_color = config["trajectory_color"]
	if config.has("trajectory_width"):
		trajectory_width = float(config["trajectory_width"])

# 清除道具覆盖，重置为 Inspector 默认参数并关闭瞄准
func clear_aim_config() -> void:
	is_aim_active = false
	if _default_config.is_empty():
		return
	radius_min = _default_config["radius_min"]
	radius_horizontal = _default_config["radius_horizontal"]
	radius_max = _default_config["radius_max"]
	max_pitch_deg = _default_config["max_pitch_deg"]
	pitch_curve_power = _default_config["pitch_curve_power"]
	ring_color = _default_config["ring_color"]
	inner_ring_color = _default_config["inner_ring_color"]
	outer_ring_color = _default_config["outer_ring_color"]
	cursor_color = _default_config["cursor_color"]
	laser_color = _default_config["laser_color"]
	laser_length = _default_config["laser_length"]
	projectile_speed = _default_config["projectile_speed"]
	drop_value = _default_config["drop_value"]
	launch_height = _default_config["launch_height"]
	trajectory_segments = _default_config["trajectory_segments"]
	trajectory_color = _default_config["trajectory_color"]
	trajectory_width = _default_config["trajectory_width"]

func get_effective_radius_min() -> float:
	return maxf(radius_min, 10.0)

# 水平射击距离 (θ = 0°): 由手部出膛高度与下坠值决定的平射落地距离
func get_effective_radius_horizontal() -> float:
	if drop_value > 0.001 and projectile_speed > 0.001 and launch_height > 0.0:
		return projectile_speed * sqrt(2.0 * launch_height / drop_value)
	return maxf(radius_horizontal, get_effective_radius_min() + 20.0)

# 极限最大射程 (θ ≈ 44°-45°): 武器物理极限距离
func get_effective_radius_max() -> float:
	return get_max_physical_range()

# 计算当前武器在重力与初速物理限制下的最大绝对极限射程 R_max (发生在 ~44°-45° 仰角时)
func get_max_physical_range() -> float:
	if drop_value <= 0.001 or projectile_speed <= 0.001:
		return maxf(radius_max, 400.0)
	var factor := 1.0 + (2.0 * drop_value * launch_height) / (projectile_speed * projectile_speed)
	return (projectile_speed * projectile_speed / drop_value) * sqrt(maxf(factor, 1.0))

# 经典弹道逆解核心算法：给定目标地面距离 R，依据初速度、下坠与出膛落差，精确反求所需仰角 theta (<= 45°)
func solve_pitch_for_distance(target_distance: float) -> float:
	if drop_value <= 0.001 or projectile_speed <= 0.001:
		return 0.0

	var r_max := get_max_physical_range()
	var r := clampf(target_distance, 1.0, r_max)

	# 求解一元二次方程: A * u^2 - R * u + (A - h) = 0, 其中 u = tan(theta)
	var v0_sq := projectile_speed * projectile_speed
	var A := (drop_value * r * r) / (2.0 * v0_sq)
	var disc := r * r - 4.0 * A * (A - launch_height)

	# 若刚好等于或超过物理极限，取最大射程仰角 (44°-45°)
	if disc <= 0.0 or A <= 0.0001:
		var u_max := r / (2.0 * maxf(A, 0.0001))
		return minf(atan(u_max), deg_to_rad(max_pitch_deg))

	# 取低弹道平滑单调解 (theta <= 45°)
	var u := (r - sqrt(maxf(disc, 0.0))) / (2.0 * A)
	var pitch := atan(u)
	return clampf(pitch, deg_to_rad(-max_pitch_deg), deg_to_rad(max_pitch_deg))

func _process(_delta: float) -> void:
	if not is_aim_active or entity == null:
		return
	# 自动计算实体脚底中心与鼠标坐标
	var p_pos := entity.global_position
	var tree := get_tree()
	if tree and tree.root and tree.root.has_node("GridData"):
		var gd = tree.root.get_node("GridData")
		if gd.has_method("world_to_cell") and gd.has_method("get_highest_floor") and gd.has_method("get_floor_pixel_offset"):
			var p_cell: Vector2i = gd.world_to_cell(p_pos)
			var p_floor: int = gd.get_highest_floor(p_cell)
			p_pos += Vector2(0.0, gd.get_floor_pixel_offset(p_floor))
	
	var mouse_pos := entity.get_global_mouse_position()
	update_aim(p_pos, mouse_pos)

# 每一帧更新瞄准计算
# ground_center: 角色脚底地面等距基准点
# mouse_screen: 鼠标屏幕世界坐标
func update_aim(ground_center: Vector2, mouse_screen: Vector2) -> void:
	var delta := mouse_screen - ground_center
	var dx: float = delta.x
	var dy: float = delta.y
	
	# 1. 2:1 等距椭圆等效距离 (r_iso) 与 360° 方位角
	var r_iso: float = sqrt(dx * dx + 4.0 * dy * dy)
	
	# 2. 全向自由跟踪方位角
	if r_iso > 0.001:
		azimuth_rad = atan2(2.0 * dy, dx)
		_last_valid_azimuth = azimuth_rad
	else:
		azimuth_rad = _last_valid_azimuth
	
	# 3. 弹道逆解：直接将鼠标瞄准距离反算为所需仰角 (<= 45°，单调递增绝不回缩，鼠标指哪打哪)
	var eff_min := get_effective_radius_min()
	var max_range := get_max_physical_range()
	var target_r := clampf(r_iso, eff_min, max_range)
	pitch_rad = solve_pitch_for_distance(target_r)

	# 4. 合成标准的 3D 空间单位朝向向量 (X: 东, Y: 南, Z: 上)
	var cos_p := cos(pitch_rad)
	var sin_p := sin(pitch_rad)
	var cos_a := cos(azimuth_rad)
	var sin_a := sin(azimuth_rad)
	
	var grid_x := cos_a + sin_a
	var grid_y := -cos_a + sin_a
	var grid_dir_2d := Vector2(grid_x, grid_y).normalized()
	
	aim_vector_3d = Vector3(grid_dir_2d.x * cos_p, grid_dir_2d.y * cos_p, sin_p).normalized()

# 获取 2D 屏幕投影的射击方向向量 (严格 2:1 等距地面与垂直 Z 轴合成)
func get_screen_aim_direction() -> Vector2:
	var cos_p := cos(pitch_rad)
	var sin_p := sin(pitch_rad)
	var cos_a := cos(azimuth_rad)
	var sin_a := sin(azimuth_rad)
	
	var screen_v := Vector2(cos_p * cos_a, cos_p * sin_a * 0.5 - sin_p)
	return screen_v.normalized()

# 获取当前俯仰角度（度数，用于 UI 或调试显示）
func get_pitch_degrees() -> float:
	return rad_to_deg(pitch_rad)

# 获取当前弹道在 3D 物理空间从出膛点至真实地面接触点的屏幕离散采样点集
# 精确考虑了出膛点（手部+10px）到地面判定平面（-2px）的垂直落差 launch_height (12px)
# 使得弹道指示线末端与游戏内真实飞弹 (MagicOrb) 的落地位置 100% 像素级对齐！
func get_trajectory_points(origin: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	if drop_value <= 0.001 or projectile_speed <= 0.001:
		return points

	var cos_p := cos(pitch_rad)
	var sin_p := sin(pitch_rad)
	var cos_a := cos(azimuth_rad)
	var sin_a := sin(azimuth_rad)

	var vx := projectile_speed * cos_p
	var vy := projectile_speed * sin_p

	# 求解飞弹触地时刻：vy * t - 0.5 * drop_value * t^2 = -launch_height
	# 即 0.5 * drop_value * t^2 - vy * t - launch_height = 0
	var disc := vy * vy + 2.0 * drop_value * launch_height
	if disc < 0.0:
		return points
	var t_impact := (vy + sqrt(disc)) / drop_value
	if t_impact <= 0.0001:
		return points

	var segs := maxi(trajectory_segments, 8)
	points.resize(segs + 1)

	for i in range(segs + 1):
		var frac := float(i) / float(segs)
		var t := t_impact * frac
		var x_dist := vx * t
		var y_height := vy * t - 0.5 * drop_value * t * t

		# 投影至 2:1 等距地面与垂直 Z 轴 (屏幕负 Y 方向)
		var screen_pt := origin + Vector2(x_dist * cos_a, x_dist * sin_a * 0.5 - y_height)
		points[i] = screen_pt

	return points

# 获取当前弹道飞行物理数据 (用于 UI 或调试)
func get_trajectory_flight_info() -> Dictionary:
	if drop_value <= 0.001 or projectile_speed <= 0.001:
		return { "is_valid": false, "t_land": 0.0, "x_land": 0.0, "max_height": 0.0 }

	var cos_p := cos(pitch_rad)
	var sin_p := sin(pitch_rad)
	var vx := projectile_speed * cos_p
	var vy := projectile_speed * sin_p
	var disc := vy * vy + 2.0 * drop_value * launch_height
	var t_impact := (vy + sqrt(maxf(disc, 0.0))) / drop_value
	var x_land := vx * t_impact
	var max_height := (vy * vy) / (2.0 * drop_value) if vy > 0.0 else 0.0

	return {
		"is_valid": true,
		"t_land": t_impact,
		"x_land": x_land,
		"max_height": max_height
	}


