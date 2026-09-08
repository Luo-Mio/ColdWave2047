# aim_controller.gd —— 2.5D 等距极坐标 3D 瞄准控制器
class_name AimController
extends Node

@export_group("基准环与手感参数 (Base & Sensitivity)")
## 内圈死区半径 (像素)。当鼠标贴近角色脚底小于该距离时锁定朝向
@export var radius_deadzone: float = 25.0
## 基准水平射击半径 (像素，θ = 0°)。鼠标光标落在此环上时俯仰角刚好为 0°
@export var radius_horizontal: float = 240.0
## 最大仰角外环半径 (像素)。鼠标拉到此半径时达到最大仰角
@export var radius_max: float = 360.0
## 最大俯仰角 (度数)。控制最大抬枪/压枪角度
@export_range(15.0, 89.0, 1.0) var max_pitch_deg: float = 75.0
## 俯仰角手感响应曲线指数 (默认 y = x^2 平滑二次曲线，手感平滑响应均匀)
@export_range(1.0, 8.0, 0.5) var pitch_curve_power: float = 2.0

@export_group("视觉准心配置 (Visual Reticle)")
## 基准水平环颜色
@export var ring_color: Color = Color(0.2, 0.9, 1.0, 0.6)
## 准心指示器光标颜色
@export var cursor_color: Color = Color(0.2, 1.0, 0.5, 0.9)
## 死区环颜色
@export var deadzone_color: Color = Color(1.0, 0.3, 0.3, 0.45)
## 3D 激光瞄准线颜色
@export var laser_color: Color = Color(1.0, 0.95, 0.2, 0.85)
## 激光瞄准虚线长度 (像素)
@export var laser_length: float = 180.0

# 当前瞄准激活状态 (受手持道具控制)
var is_aim_active: bool = false

# 当前计算状态
var azimuth_rad: float = 0.0                 # 地面 360° 水平方位角 (0 ~ 2π)
var pitch_rad: float = 0.0                   # 3D 俯仰角 (-max_pitch ~ +max_pitch)
var aim_vector_3d: Vector3 = Vector3.ZERO    # 纯净 3D 单位瞄准朝向
var is_in_deadzone: bool = false
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
		"radius_deadzone": radius_deadzone,
		"radius_horizontal": radius_horizontal,
		"radius_max": radius_max,
		"max_pitch_deg": max_pitch_deg,
		"pitch_curve_power": pitch_curve_power,
		"ring_color": ring_color,
		"cursor_color": cursor_color,
		"deadzone_color": deadzone_color,
		"laser_color": laser_color,
		"laser_length": laser_length,
	}

# 动态应用道具专属的瞄准参数 (如不同武器具有不同基准环大小或射程)
func apply_aim_config(config: Dictionary) -> void:
	is_aim_active = true
	# 先重置为默认值，保证省略未指定的参数能平滑继承 Inspector 默认配置
	if not _default_config.is_empty():
		radius_deadzone = _default_config["radius_deadzone"]
		radius_horizontal = _default_config["radius_horizontal"]
		radius_max = _default_config["radius_max"]
		max_pitch_deg = _default_config["max_pitch_deg"]
		pitch_curve_power = _default_config["pitch_curve_power"]
		ring_color = _default_config["ring_color"]
		cursor_color = _default_config["cursor_color"]
		deadzone_color = _default_config["deadzone_color"]
		laser_color = _default_config["laser_color"]
		laser_length = _default_config["laser_length"]

	if config.has("radius_horizontal"):
		radius_horizontal = float(config["radius_horizontal"])
		radius_max = maxf(radius_max, radius_horizontal * 1.8)
	if config.has("radius_deadzone"):
		radius_deadzone = float(config["radius_deadzone"])
	if config.has("radius_max"):
		radius_max = float(config["radius_max"])
	if config.has("max_pitch_deg"):
		max_pitch_deg = float(config["max_pitch_deg"])
	if config.has("pitch_curve_power"):
		pitch_curve_power = float(config["pitch_curve_power"])
	if config.has("ring_color"):
		ring_color = config["ring_color"]
	if config.has("cursor_color"):
		cursor_color = config["cursor_color"]
	if config.has("laser_color"):
		laser_color = config["laser_color"]
	if config.has("laser_length"):
		laser_length = float(config["laser_length"])

# 清除道具覆盖，重置为 Inspector 默认参数并关闭瞄准
func clear_aim_config() -> void:
	is_aim_active = false
	if _default_config.is_empty():
		return
	radius_deadzone = _default_config["radius_deadzone"]
	radius_horizontal = _default_config["radius_horizontal"]
	radius_max = _default_config["radius_max"]
	max_pitch_deg = _default_config["max_pitch_deg"]
	pitch_curve_power = _default_config["pitch_curve_power"]
	ring_color = _default_config["ring_color"]
	cursor_color = _default_config["cursor_color"]
	deadzone_color = _default_config["deadzone_color"]
	laser_color = _default_config["laser_color"]
	laser_length = _default_config["laser_length"]

func get_effective_radius_max() -> float:
	return maxf(radius_max, radius_horizontal + 30.0)

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
			var eff_max := get_effective_radius_max()
			var norm_x := (r_iso - radius_horizontal) / maxf(eff_max - radius_horizontal, 1.0)
			norm_x = clampf(norm_x, 0.0, 1.0)
			# 平滑 U 形响应曲线
			var curve_y := pow(norm_x, pitch_curve_power)
			pitch_rad = deg_to_rad(curve_y * max_pitch_deg)
		else:
			# 内侧俯角区间 [R_dead, R0] -> norm_x ∈ [-1.0, 0.0]
			var norm_x := (r_iso - radius_horizontal) / maxf(radius_horizontal - radius_deadzone, 1.0)
			norm_x = clampf(norm_x, -1.0, 0.0)
			# 深度 U 形曲线
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

