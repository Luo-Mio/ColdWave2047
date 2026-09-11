# aim_controller.gd —— 2.5D 等距极坐标 3D 瞄准控制器
class_name AimController
extends Node

@export_group("基准环与手感参数 (Base & Sensitivity)")
## 最小有效射击半径 (像素，默认 16.0)。鼠标拉至此半径以内时贴附在脚底近距离
@export var radius_min: float = 16.0
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

@export_group("性能与更新频率 (Performance & Tick Rate)")
## 瞄准计算与准星刷新目标频率 (Hz，默认 60.0 次/秒；若 <= 0 则无限制跟随渲染帧率)
@export var update_rate_hz: float = 60.0

# 向后兼容别名属性
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
		"update_rate_hz": update_rate_hz,
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
	if config.has("update_rate_hz"):
		update_rate_hz = float(config["update_rate_hz"])

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
	if _default_config.has("update_rate_hz"):
		update_rate_hz = _default_config["update_rate_hz"]

func get_effective_radius_min() -> float:
	return maxf(radius_min, 1.0)

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

func _process(delta: float) -> void:
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
	
	# 2. 全向自由跟踪方位角 (小于 3px 时防抖锁定，避免圆心角速度奇点)
	if r_iso > 3.0:
		azimuth_rad = atan2(2.0 * dy, dx)
		_last_valid_azimuth = azimuth_rad
	else:
		azimuth_rad = _last_valid_azimuth
	
	# 3. 混合式俯仰角计算：
	#    - 仰角区间 (r_iso >= r0)：采用物理弹道精确反解，鼠标位置即为同层着弹点 (1:1 指哪打哪)
	#    - 俯角区间 (r_iso < r0)：采用缓出手感响应曲线 (Ease-Out Curve)，越靠近死区影响越小，防止角速度暴冲与灵敏度发散
	var eff_min := get_effective_radius_min()
	var eff_horiz := get_effective_radius_horizontal()
	var max_range := get_max_physical_range()

	if r_iso >= eff_horiz:
		if drop_value > 0.001 and projectile_speed > 0.001:
			var target_r := clampf(r_iso, eff_horiz, max_range)
			pitch_rad = solve_pitch_for_distance(target_r)
		else:
			var norm_x := clampf((r_iso - eff_horiz) / maxf(max_range - eff_horiz, 1.0), 0.0, 1.0)
			pitch_rad = deg_to_rad(pow(norm_x, pitch_curve_power) * max_pitch_deg)
	else:
		# 归一化向内收缩距离 u: r_iso 从 eff_horiz (u=0) 缩进到 eff_min (u=1)
		var span := maxf(eff_horiz - eff_min, 1.0)
		var u := clampf((eff_horiz - r_iso) / span, 0.0, 1.0)
		# 缓出响应曲线 (Ease-Out): u=0 处初始斜率良好接近线性，u->1 处导数平缓趋于 0，消除靠近死区时的暴跳
		var power := maxf(pitch_curve_power, 1.0)
		var f_u := 1.0 - pow(1.0 - u, power)
		pitch_rad = deg_to_rad(-f_u * max_pitch_deg)

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

# 获取考虑真实 3D 地形高度的自适应弹道数据：
# - 若遭遇前方高层/高台阻挡：实线主弹道提前在撞击点截断，不穿模穿透地表，返回 hit_type = 1
# - 若落在角色同层地表：保持常规平滑实线，返回 hit_type = 0
# - 若飞离高台/跌入悬崖低层：角色层高以上为实线，跌出层高后平滑延伸为虚线，返回 hit_type = -1
# 返回数据结构:
# {
#     "is_valid": bool,
#     "hit_type": int,                 # 0: 同层, 1: 高层提前截断, -1: 低层悬崖延伸
#     "primary_points": PackedVector2Array, # 实线轨迹点 (高层时自动提前截断)
#     "dashed_points": PackedVector2Array,  # 虚线延伸轨迹点 (低层时向下延伸)
#     "hit_screen_pos": Vector2,       # 真实着弹屏幕坐标 (用于绘制 2:1 椭圆小红点)
#     "hit_floor": int,                # 最终着弹楼层
# }
func get_terrain_adaptive_trajectory(player_ground: Vector2, p_floor: int, chest_origin: Vector2, custom_grid = null) -> Dictionary:
	if drop_value <= 0.001 or projectile_speed <= 0.001:
		return { "is_valid": false, "hit_type": 0, "primary_points": PackedVector2Array(), "dashed_points": PackedVector2Array(), "hit_screen_pos": Vector2.ZERO, "hit_floor": p_floor }

	var grid = custom_grid
	if grid == null:
		var tree := get_tree()
		if tree and tree.root and tree.root.has_node("GridData"):
			grid = tree.root.get_node("GridData")
		elif Engine.has_singleton("GridData"):
			grid = Engine.get_singleton("GridData")

	var cos_p := cos(pitch_rad)
	var sin_p := sin(pitch_rad)
	var cos_a := cos(azimuth_rad)
	var sin_a := sin(azimuth_rad)

	var vx := projectile_speed * cos_p
	var vy := projectile_speed * sin_p

	var h_player := float(p_floor) * 16.0
	var z_start := h_player + launch_height

	# 计算下落到角色当前层高基准面 (z = h_player) 的基准时间
	var disc_base := vy * vy + 2.0 * drop_value * launch_height
	if disc_base < 0.0:
		return { "is_valid": false, "hit_type": 0, "primary_points": PackedVector2Array(), "dashed_points": PackedVector2Array(), "hit_screen_pos": Vector2.ZERO, "hit_floor": p_floor }
	var t_base := (vy + sqrt(disc_base)) / drop_value
	if t_base <= 0.0001:
		return { "is_valid": false, "hit_type": 0, "primary_points": PackedVector2Array(), "dashed_points": PackedVector2Array(), "hit_screen_pos": Vector2.ZERO, "hit_floor": p_floor }

	var primary_points := PackedVector2Array()
	var dashed_points := PackedVector2Array()
	var hit_type := 0
	var hit_screen_pos := Vector2.ZERO
	var hit_floor := p_floor

	primary_points.push_back(chest_origin)

	var segs := maxi(trajectory_segments, 16)
	var high_floor_hit := false
	var prev_t := 0.0
	var prev_z := z_start

	for i in range(1, segs + 1):
		var t := t_base * (float(i) / float(segs))
		var g_t := player_ground + Vector2(cos_a, 0.5 * sin_a) * (vx * t)
		var z_t := z_start + vy * t - 0.5 * drop_value * t * t
		var p_screen := g_t - Vector2(0.0, z_t)

		var fl := p_floor
		var surface_h := h_player
		if grid:
			var c: Vector2i = grid.world_to_cell(g_t)
			if grid.has_any_tile(c):
				fl = grid.get_highest_floor(c)
				surface_h = float(fl) * 16.0
			else:
				fl = 0
				surface_h = 0.0

		# 撞击高层检测：地表高于角色基准层，且当前飞弹高度低于或等于该地表
		if surface_h > h_player and z_t <= surface_h:
			high_floor_hit = true
			hit_type = 1
			hit_floor = fl
			
			var z_hit := surface_h
			var t_hit := t
			if prev_z >= surface_h:
				# 从高空俯冲降落至高台顶面
				var denom := (prev_z - z_t)
				var frac := clampf((prev_z - surface_h) / denom, 0.0, 1.0) if absf(denom) > 0.0001 else 0.5
				t_hit = lerpf(prev_t, t, frac)
			else:
				# 撞击高台垂直侧面墙体：高度保持为真实弹道飞抵侧壁的高度，不发生天台瞬移
				t_hit = lerpf(prev_t, t, 0.5)
				z_hit = clampf(lerpf(prev_z, z_t, 0.5), 0.0, surface_h)

			var g_hit := player_ground + Vector2(cos_a, 0.5 * sin_a) * (vx * t_hit)
			var p_hit := g_hit - Vector2(0.0, z_hit)
			primary_points.push_back(p_hit)
			hit_screen_pos = p_hit
			break

		primary_points.push_back(p_screen)
		prev_t = t
		prev_z = z_t

	if not high_floor_hit:
		var g_base := player_ground + Vector2(cos_a, 0.5 * sin_a) * (vx * t_base)
		var fl_base := p_floor
		var surface_base := h_player
		if grid:
			var c_base: Vector2i = grid.world_to_cell(g_base)
			if grid.has_any_tile(c_base):
				fl_base = grid.get_highest_floor(c_base)
				surface_base = float(fl_base) * 16.0
			else:
				fl_base = 0
				surface_base = 0.0

		if fl_base >= p_floor:
			# 同层着弹：精确对齐真实地表屏幕位置
			hit_type = 0
			hit_floor = fl_base
			hit_screen_pos = g_base - Vector2(0.0, surface_base)
			primary_points[-1] = hit_screen_pos
		else:
			# 悬崖低层情况：实线到达角色基准面，随后向低层解析延伸为虚线
			hit_type = -1
			dashed_points.push_back(primary_points[-1])

			# 计算到达绝对地面 (z = 0) 的解析极限时间，避免步长过小在半空超时腰斩
			var disc_max := vy * vy + 2.0 * drop_value * z_start
			var t_max := (vy + sqrt(maxf(disc_max, 0.0))) / drop_value
			var cliff_segs := maxi(segs, 24)
			var dt_cliff := maxf((t_max - t_base) / float(cliff_segs), 0.001)

			var curr_t := t_base
			var curr_z := h_player
			var low_hit := false

			for s in range(1, cliff_segs + 1):
				var next_t := t_base + dt_cliff * float(s)
				var g_next := player_ground + Vector2(cos_a, 0.5 * sin_a) * (vx * next_t)
				var z_next := z_start + vy * next_t - 0.5 * drop_value * next_t * next_t
				var p_next := g_next - Vector2(0.0, z_next)

				var s_fl := 0
				var s_h := 0.0
				if grid:
					var c_next: Vector2i = grid.world_to_cell(g_next)
					if grid.has_any_tile(c_next):
						s_fl = grid.get_highest_floor(c_next)
						s_h = float(s_fl) * 16.0

				if z_next <= s_h:
					var z_hit := s_h
					var t_hit := next_t
					if curr_z >= s_h:
						# 从空中下落至该地表顶面
						var denom := (curr_z - z_next)
						var frac := clampf((curr_z - s_h) / denom, 0.0, 1.0) if absf(denom) > 0.0001 else 0.5
						t_hit = lerpf(curr_t, next_t, frac)
					else:
						# 撞击前方阻挡体垂直侧壁：高度为飞弹实际飞行高度
						t_hit = lerpf(curr_t, next_t, 0.5)
						z_hit = clampf(lerpf(curr_z, z_next, 0.5), 0.0, s_h)

					var g_hit := player_ground + Vector2(cos_a, 0.5 * sin_a) * (vx * t_hit)
					var p_hit := g_hit - Vector2(0.0, z_hit)
					dashed_points.push_back(p_hit)
					hit_floor = s_fl
					hit_screen_pos = p_hit
					low_hit = true
					break

				dashed_points.push_back(p_next)
				curr_t = next_t
				curr_z = z_next

			if not low_hit and not dashed_points.is_empty():
				var g_max := player_ground + Vector2(cos_a, 0.5 * sin_a) * (vx * t_max)
				hit_floor = 0
				hit_screen_pos = g_max - Vector2(0.0, 0.0)
				dashed_points.push_back(hit_screen_pos)

	return {
		"is_valid": true,
		"hit_type": hit_type,
		"primary_points": primary_points,
		"dashed_points": dashed_points,
		"hit_screen_pos": hit_screen_pos,
		"hit_floor": hit_floor
	}



