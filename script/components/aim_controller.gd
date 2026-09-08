# aim_controller.gd —— 2.5D 等距极坐标 3D 瞄准控制器
class_name AimController
extends Node

@export_group("基准环与手感参数 (Base & Sensitivity)")
## 最大俯角内环半径 (像素，暂定 140.0)。鼠标拉到此半径或更内侧时达到最大俯角 (-max_pitch_deg)
@export var radius_min: float = 140.0
## 基准水平射击半径 (像素，θ = 0°)。鼠标光标落在此环上时俯仰角刚好为 0°
@export var radius_horizontal: float = 240.0
## 最大仰角外环半径 (像素)。鼠标拉到此半径时达到最大仰角 (+max_pitch_deg)
@export var radius_max: float = 360.0
## 最大俯仰角 (度数)。控制最大抬枪/压枪角度
@export_range(15.0, 89.0, 1.0) var max_pitch_deg: float = 75.0
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

func get_effective_radius_min() -> float:
	return maxf(radius_min, 10.0)

func get_effective_radius_horizontal() -> float:
	return maxf(radius_horizontal, get_effective_radius_min() + 20.0)

func get_effective_radius_max() -> float:
	return maxf(radius_max, get_effective_radius_horizontal() + 20.0)

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
	
	# 2. 取消死区：无论鼠标距离多近，全向自由跟踪方位角
	if r_iso > 0.001:
		azimuth_rad = atan2(2.0 * dy, dx)
		_last_valid_azimuth = azimuth_rad
	else:
		azimuth_rad = _last_valid_azimuth
	
	# 3. 三环俯仰角手感响应计算
	var eff_min := get_effective_radius_min()
	var eff_horiz := get_effective_radius_horizontal()
	var eff_max := get_effective_radius_max()

	if r_iso >= eff_horiz:
		# 外侧仰角区间 [R_horiz, R_max] -> norm_x ∈ [0.0, 1.0]
		var norm_x := (r_iso - eff_horiz) / maxf(eff_max - eff_horiz, 1.0)
		norm_x = clampf(norm_x, 0.0, 1.0)
		# 平滑 U 形响应曲线
		var curve_y := pow(norm_x, pitch_curve_power)
		pitch_rad = deg_to_rad(curve_y * max_pitch_deg)
	else:
		# 内侧俯角区间 [R_min, R_horiz] -> norm_x ∈ [-1.0, 0.0]
		# 当鼠标落在此内环以内 (r_iso <= eff_min) 时，norm_x 被 clamp 到 -1.0，俯角达到最大 (-max_pitch_deg)
		var norm_x := (r_iso - eff_horiz) / maxf(eff_horiz - eff_min, 1.0)
		norm_x = clampf(norm_x, -1.0, 0.0)
		# 深度 U 形响应曲线
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

