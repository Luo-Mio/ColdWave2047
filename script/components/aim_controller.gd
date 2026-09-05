# aim_controller.gd —— 2.5D 等距极坐标 3D 瞄准控制器
class_name AimController
extends Node

# 极坐标与手感参数
@export var radius_deadzone: float = 25.0    # 内圈死区半径 (像素)
@export var radius_horizontal: float = 120.0 # 基准水平射击半径 (θ = 0°)
@export var radius_max: float = 260.0        # 最大仰角半径
@export var max_pitch_deg: float = 75.0      # 最大俯仰角 (度数)
@export var pitch_curve_power: float = 4.0   # 手感响应指数 (默认 y = x^4 深U形，越靠近基准环影响越小)

# 当前计算状态
var azimuth_rad: float = 0.0                 # 地面 360° 水平方位角 (0 ~ 2π)
var pitch_rad: float = 0.0                   # 3D 俯仰角 (-max_pitch ~ +max_pitch)
var aim_vector_3d: Vector3 = Vector3.ZERO    # 纯净 3D 单位瞄准朝向
var is_in_deadzone: bool = false
var _last_valid_azimuth: float = 0.0

# 每一帧更新瞄准计算
# ground_center: 角色脚底地面等距基准点
# mouse_screen: 鼠标屏幕世界坐标
func update_aim(ground_center: Vector2, mouse_screen: Vector2) -> void:
	var delta := mouse_screen - ground_center
	var dx: float = delta.x
	var dy: float = delta.y
	
	# 1. 2:1 等距椭圆等效距离 (r_iso) 与 360° 方位角
	var r_iso: float = sqrt(dx * dx + 4.0 * dy * dy)
	
	# 2. 死区保护：若鼠标贴近角色脚底，保持上一帧朝向
	if r_iso < radius_deadzone:
		is_in_deadzone = true
		azimuth_rad = _last_valid_azimuth
		pitch_rad = deg_to_rad(-max_pitch_deg)
	else:
		is_in_deadzone = false
		azimuth_rad = atan2(2.0 * dy, dx)
		_last_valid_azimuth = azimuth_rad
		
		# 3. 计算二维手感响应坐标 (x: 离基准环的相对偏移, y: 俯仰角输出)
		# 基准环上 x = 0；环内测 x < 0；外侧 x > 0
		if r_iso >= radius_horizontal:
			# 外侧仰角区间 [R0, R_max] -> norm_x ∈ [0.0, 1.0]
			var norm_x := (r_iso - radius_horizontal) / maxf(radius_max - radius_horizontal, 1.0)
			norm_x = clampf(norm_x, 0.0, 1.0)
			# y = x^4 深度 U 形曲线：靠近零点平缓如镜，边缘陡峭拉升
			var curve_y := pow(norm_x, pitch_curve_power)
			pitch_rad = deg_to_rad(curve_y * max_pitch_deg)
		else:
			# 内侧俯角区间 [R_dead, R0] -> norm_x ∈ [-1.0, 0.0]
			var norm_x := (r_iso - radius_horizontal) / maxf(radius_horizontal - radius_deadzone, 1.0)
			norm_x = clampf(norm_x, -1.0, 0.0)
			# y = -|x|^4 深度 U 形曲线
			var curve_y := pow(absf(norm_x), pitch_curve_power)
			pitch_rad = deg_to_rad(-curve_y * max_pitch_deg)

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

