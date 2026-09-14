# aim_controller.gd —— 2.5D 等距极坐标 3D 瞄准控制器 (核心协调器)
class_name AimController
extends Node

# 依赖子系统模块
const Ballistics = preload("res://script/systems/aim_ballistics.gd")
const TerrainSolver = preload("res://script/systems/aim_terrain_solver.gd")
const CameraAssist = preload("res://script/systems/aim_camera_assist.gd")

@export_group("基准环与手感参数 (Base & Sensitivity)")
## 最小有效射击半径 (像素，默认 48.0)。鼠标拉至此半径以内时贴附在脚底近距离
@export var radius_min: float = 48.0
## 基准水平射击半径 (像素，θ = 0°)。鼠标光标落在此环上时俯仰角刚好为 0°
@export var radius_horizontal: float = 240.0
## 最大仰角外环半径 (像素)。鼠标拉到此半径时达到最大仰角 (+max_pitch_deg)
@export var radius_max: float = 360.0
## 最大俯仰角 (度数)。控制最大抬枪/压枪角度 (限制为 45.0 度，保证射程单调递增绝不回缩)
@export_range(15.0, 45.0, 1.0) var max_pitch_deg: float = 45.0
## 俯角手感缓出响应曲线指数 (默认 2.0 二次缓出曲线：0° 起点线性响应，越靠近死区变化率越小、越平缓)
@export_range(1.0, 8.0, 0.5) var pitch_curve_power: float = 2.0

@export_group("视觉准心配置 (Visual Reticle)")
## 基准水平中环颜色 (θ = 0°)
@export var ring_color: Color = Color(0.2, 0.9, 1.0, 0.6)
## 最大俯角内环颜色 (θ = -max_pitch_deg)
@export var inner_ring_color: Color = Color(1.0, 0.45, 0.35, 0.45)
## 最大仰角外环颜色 (θ = +max_pitch_deg)
@export var outer_ring_color: Color = Color(0.2, 0.9, 1.0, 0.35)
## 是否显示死区内环 (默认 false，视觉极简)
@export var show_deadzone_ring: bool = false
## 是否显示 0° 水平基准中环 (默认 false，视觉极简)
@export var show_horizontal_ring: bool = false
## 是否显示 45° 最大仰角限制弧 (默认 true，仅在角度到达 45° 最大时在准星两侧渐变显示)
@export var show_max_pitch_arc: bool = true
## 45° 限制弧半张角 (弧度，默认 0.35 弧度 ≈ 20°，两侧对称展开共约 40°)
@export var max_pitch_arc_angle: float = 0.35
## 45° 限制弧采样分段数 (默认 16 段，保证极致平滑)
@export var max_pitch_arc_segments: int = 16
## 是否显示地面引导射线 (默认 true，连接角色原点与准星点，强化空间感)
@export var show_ground_ray: bool = true
## 地面引导射线颜色 (默认带有一定透明度的绿色/青色)
@export var ground_ray_color: Color = Color(0.2, 1.0, 0.5, 0.5)
## 地面引导射线被高墙/瓷砖遮挡时的透明度保留比例 (默认 0.5，与弹道线一致在墙后半透明透视)
@export_range(0.0, 1.0, 0.05) var ground_ray_occluded_alpha_ratio: float = 0.5
## 地面引导射线是否仅在同层地表显示 (碰到高层或高度不一致地表时截断，高度一致后恢复)
@export var ground_ray_require_same_floor: bool = true
## 是否显示同层绿色准星点 (默认 true，角色同层投影参考点，强化 2.5D 空间感)
@export var show_ground_cursor_point: bool = true
## 是否显示 0° 参考十字 (默认 false，视觉极简)
@export var show_zero_cross: bool = false
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
## 弹道指示线线宽 (像素，像素风格推荐 1.0 像素细线)
@export var trajectory_width: float = 1.0
## 弹道指示线被瓷砖遮挡时的透明度保留比例 (默认 0.5 即 50% 半透明透视，0.0 为完全隐藏，1.0 为无透视效果)
@export_range(0.0, 1.0, 0.05) var trajectory_occluded_alpha_ratio: float = 0.5

@export_group("视角辅助参数 (Camera Aim Assist)")
## 是否启用瞄准时的视角边缘拉扯辅助
@export var enable_camera_aim_assist: bool = true
## 视角横向平移拉扯的最大距离 (像素，可在检查器动态调节测试，推荐 180.0 ~ 300.0)
@export var camera_aim_offset_distance: float = 240.0
## 视角竖向与横向平移比例 (默认 0.5 即 2:1 等距比例。横向最大拉扯 240px 时竖向为 120px)
@export_range(0.1, 1.0, 0.05) var camera_aim_vertical_ratio: float = 0.5
## 触发视角平移的屏幕边缘死区阈值 (0.0 ~ 0.9，默认 0.4 表示鼠标在屏幕中心 40% 区域内镜头保持居中稳定)
@export_range(0.0, 0.9, 0.05) var camera_aim_edge_threshold: float = 0.4
## 视角平移与回中的平滑插值速度 (数值越大越灵敏，数值越小越柔和，推荐 4.0 ~ 12.0)
@export var camera_aim_smooth_speed: float = 6.0

@export_group("落点网格辅助 (Impact Grid Hint)")
## 是否在弹道着弹点绘制隐形范围渐变显示的瓷砖网格 (消除 2.5D 高低差连续假象)
@export var show_impact_grid: bool = true
## 落点网格潜在扫描半径 (默认 2 即 5x5 瓷砖区域)
@export_range(1, 4, 1) var impact_grid_range: int = 2
## 落点网格渐变显示水平半径 (默认 128.0 像素)
@export var impact_grid_radius_x: float = 128.0
## 落点网格渐变显示垂直半径 (默认 64.0 像素，与 2:1 等轴测视角完美契合)
@export var impact_grid_radius_y: float = 64.0
## 落点网格线条颜色与中心最大不透明度
@export var impact_grid_color: Color = Color(0.45, 0.85, 1.0, 0.6)
## 被墙体/瓷砖遮挡时网格的不透明度倍率 (默认 1.0 = 不降低透明度，保持原样清晰可见；0.5 = 半透明透视)
@export_range(0.0, 1.0, 0.05) var impact_grid_occluded_alpha_ratio: float = 1.0
## 是否在落点渐变范围内显示墙体/地基底部截面提示 (与高墙透视同款纯黑截面，消除高低差光学假象)
@export var show_impact_cap: bool = true
## 截面封顶底色 (默认纯黑，与高墙透视 base_floor_color 保持完全一致)
@export var impact_cap_color: Color = Color(0.0, 0.0, 0.0, 1.0)
## 截面封顶适用范围 (0: 仅高墙底部 fl > hit_floor; 1: 高墙底与地表全部 fl >= hit_floor; 2: 仅地表 fl == hit_floor)
@export_enum("仅高墙底 (Walls Only)", "高墙底与地表 (Walls & Floor)", "仅地表 (Floor Only)") var impact_cap_target: int = 0

@export_group("性能与更新频率 (Performance & Tick Rate)")
## 瞄准计算与准星刷新目标频率 (Hz，默认 60.0 次/秒；若 <= 0 则无限制跟随渲染帧率)
@export var update_rate_hz: float = 60.0

# 声明式可配置属性列表 (用于武器切换时的快速备份、重置与覆盖)
const CONFIG_PROPERTIES: Array[String] = [
	"radius_min", "radius_horizontal", "radius_max", "max_pitch_deg", "pitch_curve_power",
	"ring_color", "inner_ring_color", "outer_ring_color", "cursor_color", "laser_color", "laser_length",
	"projectile_speed", "drop_value", "launch_height", "trajectory_segments",
	"trajectory_color", "trajectory_width", "trajectory_occluded_alpha_ratio", "update_rate_hz",
	"enable_camera_aim_assist", "camera_aim_offset_distance", "camera_aim_vertical_ratio",
	"camera_aim_edge_threshold", "camera_aim_smooth_speed",
	"show_impact_grid", "impact_grid_range", "impact_grid_radius_x", "impact_grid_radius_y", "impact_grid_color",
	"impact_grid_occluded_alpha_ratio", "show_impact_cap", "impact_cap_color", "impact_cap_target",
	"show_deadzone_ring", "show_horizontal_ring", "show_max_pitch_arc", "max_pitch_arc_angle", "max_pitch_arc_segments",
	"show_ground_ray", "ground_ray_color", "ground_ray_occluded_alpha_ratio", "ground_ray_require_same_floor",
	"show_ground_cursor_point", "show_zero_cross"
]

# 兼容旧代码字段的别名映射字典
const ALIAS_MAP: Dictionary = {
	"radius_deadzone": "radius_min",
	"deadzone_color": "inner_ring_color",
	"speed": "projectile_speed",
	"gravity": "drop_value",
	"aim_offset_distance": "camera_aim_offset_distance",
	"vertical_ratio": "camera_aim_vertical_ratio"
}

# 向后兼容属性别名
var radius_deadzone: float:
	get: return radius_min
	set(v): radius_min = v
var deadzone_color: Color:
	get: return inner_ring_color
	set(v): inner_ring_color = v

# 当前瞄准激活状态 (受手持道具控制)
var is_aim_active: bool = false
var _was_aim_active: bool = false
var _update_timer: float = 0.0

# 当前计算状态
var azimuth_rad: float = 0.0                 # 地面 360° 水平方位角 (0 ~ 2π)
var pitch_rad: float = 0.0                   # 3D 俯仰角 (-max_pitch ~ +max_pitch)
var aim_vector_3d: Vector3 = Vector3.ZERO    # 纯净 3D 单位瞄准朝向
var is_in_deadzone: bool = false             # 兼容旧代码字段
var _last_valid_azimuth: float = 0.0

# 默认参数备份与所属实体
var _default_config: Dictionary = {}
var entity: CharacterBody2D = null

# 视角辅助子处理器
var _camera_assist: CameraAssist = CameraAssist.new()

func _ready() -> void:
	_save_defaults()

	# 向上查找所属实体
	var curr := get_parent()
	while curr:
		if curr is CharacterBody2D:
			entity = curr as CharacterBody2D
			break
		curr = curr.get_parent()

func _exit_tree() -> void:
	if _camera_assist:
		_camera_assist.reset_offset()

func _save_defaults() -> void:
	_default_config.clear()
	for prop in CONFIG_PROPERTIES:
		_default_config[prop] = get(prop)

## 动态应用道具专属的瞄准参数 (如不同武器具有不同基准环大小或射程)
func apply_aim_config(config: Dictionary) -> void:
	is_aim_active = true
	if _default_config.is_empty():
		_save_defaults()

	# 先重置为默认值，保证省略未指定的参数能平滑继承 Inspector 默认配置
	for prop in CONFIG_PROPERTIES:
		if _default_config.has(prop):
			set(prop, _default_config[prop])

	# 自动类型转换并应用传入的参数
	for key in config:
		var target_prop: String = ALIAS_MAP.get(key, key)
		if target_prop in CONFIG_PROPERTIES:
			var val = config[key]
			var cur = get(target_prop)
			if cur is float:
				set(target_prop, float(val))
			elif cur is int:
				set(target_prop, int(val))
			elif cur is bool:
				set(target_prop, bool(val))
			else:
				set(target_prop, val)

	if config.has("radius_horizontal") and not config.has("radius_max"):
		radius_max = maxf(radius_max, radius_horizontal * 1.5)

## 清除道具覆盖，重置为 Inspector 默认参数并关闭瞄准
func clear_aim_config() -> void:
	is_aim_active = false
	if _default_config.is_empty():
		_save_defaults()
	for prop in CONFIG_PROPERTIES:
		if _default_config.has(prop):
			set(prop, _default_config[prop])

# ==================== 物理与几何计算门面 (API Facades) ====================

func get_effective_radius_min() -> float:
	return Ballistics.calc_effective_radius_min(radius_min)

func get_effective_radius_horizontal() -> float:
	return Ballistics.calc_effective_radius_horizontal(projectile_speed, drop_value, launch_height, radius_horizontal)

func get_effective_radius_max() -> float:
	return Ballistics.calc_max_physical_range(projectile_speed, drop_value, launch_height, radius_max)

func get_max_physical_range() -> float:
	return Ballistics.calc_max_physical_range(projectile_speed, drop_value, launch_height, radius_max)

func solve_pitch_for_distance(target_distance: float) -> float:
	return Ballistics.solve_pitch_for_distance(target_distance, projectile_speed, drop_value, launch_height, max_pitch_deg)

func get_screen_aim_direction() -> Vector2:
	return Ballistics.calc_screen_aim_direction(pitch_rad, azimuth_rad)

func get_pitch_degrees() -> float:
	return rad_to_deg(pitch_rad)

func get_trajectory_points(origin: Vector2) -> PackedVector2Array:
	return Ballistics.calc_trajectory_points(origin, pitch_rad, azimuth_rad, projectile_speed, drop_value, launch_height, trajectory_segments)

func get_trajectory_flight_info() -> Dictionary:
	return Ballistics.calc_flight_info(pitch_rad, projectile_speed, drop_value, launch_height)

func is_point_occluded(screen_pt: Vector2, point_z: float, custom_grid = null) -> bool:
	var grid = custom_grid if custom_grid else _get_grid_data()
	return TerrainSolver.is_point_occluded(screen_pt, point_z, grid)

func get_terrain_adaptive_trajectory(player_ground: Vector2, p_floor: int, chest_origin: Vector2, custom_grid = null) -> Dictionary:
	var grid = custom_grid if custom_grid else _get_grid_data()
	return TerrainSolver.solve_adaptive_trajectory(
		player_ground, p_floor, chest_origin,
		pitch_rad, azimuth_rad,
		projectile_speed, drop_value, launch_height,
		trajectory_segments, grid
	)

# ==================== 运行周期与瞄准逻辑 ====================

func _process(delta: float) -> void:
	# 1. 视角辅助平滑更新 (每帧执行，确保镜头平移与回中丝滑无顿挫)
	_camera_assist.update(
		delta, is_aim_active, entity, get_tree(),
		enable_camera_aim_assist, camera_aim_offset_distance,
		camera_aim_vertical_ratio, camera_aim_edge_threshold,
		camera_aim_smooth_speed
	)

	if not is_aim_active or entity == null:
		_was_aim_active = false
		return

	# 瞄准刚激活的第一帧立即执行计算，避免切换时的初次响应延迟
	if not _was_aim_active:
		_was_aim_active = true
		_update_timer = 0.0
		_do_update_aim()
		return

	# 频率限制检测 (<= 0 则跟随渲染帧率无限制运行)
	if update_rate_hz > 0.0:
		_update_timer += delta
		var interval := 1.0 / update_rate_hz
		if _update_timer < interval:
			return
		_update_timer = fmod(_update_timer, interval)

	_do_update_aim()

func _do_update_aim() -> void:
	if not is_inside_tree() or entity == null or not entity.is_inside_tree():
		return

	var p_pos := entity.global_position
	var gd = _get_grid_data()
	if gd and gd.has_method("world_to_cell") and gd.has_method("get_highest_floor") and gd.has_method("get_floor_pixel_offset"):
		var p_cell: Vector2i = gd.world_to_cell(p_pos)
		var p_floor: int = gd.get_highest_floor(p_cell)
		p_pos += Vector2(0.0, gd.get_floor_pixel_offset(p_floor))

	var mouse_pos := entity.get_global_mouse_position()
	update_aim(p_pos, mouse_pos)

## 每一帧更新瞄准计算
func update_aim(ground_center: Vector2, mouse_screen: Vector2) -> void:
	var delta := mouse_screen - ground_center
	var dx: float = delta.x
	var dy: float = delta.y

	# 1. 2:1 等距椭圆等效距离 (r_iso) 与 360° 方位角
	var r_iso: float = sqrt(dx * dx + 4.0 * dy * dy)

	# 2. 全向自由跟踪方位角 (小于 3px 时防抖锁定，避免圆心角速度奇点)
	if r_iso > 3.0:
		azimuth_rad = atan2(2.0 * dy, dx)
		_last_valid_azimuth = azimuth_rad
	else:
		azimuth_rad = _last_valid_azimuth

	# 3. 混合式俯仰角计算
	var eff_min := get_effective_radius_min()
	var eff_horiz := get_effective_radius_horizontal()
	var max_range := get_max_physical_range()

	pitch_rad = Ballistics.calc_pitch_angle(
		r_iso, eff_min, eff_horiz, max_range,
		projectile_speed, drop_value, launch_height,
		max_pitch_deg, pitch_curve_power
	)

	# 4. 合成标准的 3D 空间单位朝向向量
	aim_vector_3d = Ballistics.compose_aim_vector_3d(pitch_rad, azimuth_rad)

func _get_grid_data() -> Node:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree and tree.root and tree.root.has_node("GridData"):
		return tree.root.get_node("GridData")
	elif Engine.has_singleton("GridData"):
		return Engine.get_singleton("GridData")
	return null
