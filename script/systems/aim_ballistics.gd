# aim_ballistics.gd —— 2.5D 等距空间 3D 弹道物理与逆解算纯函数库
class_name AimBallistics

## 计算最小有效射程
static func calc_effective_radius_min(radius_min: float) -> float:
	return maxf(radius_min, 1.0)

## 计算水平平射射程 (θ = 0°)
static func calc_effective_radius_horizontal(projectile_speed: float, drop_value: float, launch_height: float, fallback: float) -> float:
	if drop_value > 0.001 and projectile_speed > 0.001 and launch_height > 0.0:
		return projectile_speed * sqrt(2.0 * launch_height / drop_value)
	return maxf(fallback, 20.0)

## 计算物理极限最大射程 (θ ≈ 44°-45°)
static func calc_max_physical_range(projectile_speed: float, drop_value: float, launch_height: float, fallback: float) -> float:
	if drop_value <= 0.001 or projectile_speed <= 0.001:
		return maxf(fallback, 400.0)
	var factor := 1.0 + (2.0 * drop_value * launch_height) / (projectile_speed * projectile_speed)
	return (projectile_speed * projectile_speed / drop_value) * sqrt(maxf(factor, 1.0))

## 经典弹道逆解核心算法：给定目标地面距离 R，依据初速度、下坠与出膛落差反求仰角 theta (<= 45°)
static func solve_pitch_for_distance(target_distance: float, projectile_speed: float, drop_value: float, launch_height: float, max_pitch_deg: float) -> float:
	if drop_value <= 0.001 or projectile_speed <= 0.001:
		return 0.0

	var r_max := calc_max_physical_range(projectile_speed, drop_value, launch_height, 400.0)
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

## 混合式俯仰角解算 (仰角区间精确物理反解 + 俯角区间缓出手感曲线)
static func calc_pitch_angle(r_iso: float, eff_min: float, eff_horiz: float, max_range: float, projectile_speed: float, drop_value: float, launch_height: float, max_pitch_deg: float, pitch_curve_power: float) -> float:
	if r_iso >= eff_horiz:
		if drop_value > 0.001 and projectile_speed > 0.001:
			var target_r := clampf(r_iso, eff_horiz, max_range)
			return solve_pitch_for_distance(target_r, projectile_speed, drop_value, launch_height, max_pitch_deg)
		else:
			var norm_x := clampf((r_iso - eff_horiz) / maxf(max_range - eff_horiz, 1.0), 0.0, 1.0)
			return deg_to_rad(pow(norm_x, pitch_curve_power) * max_pitch_deg)
	else:
		# 归一化向内收缩距离 u: r_iso 从 eff_horiz (u=0) 缩进到 eff_min (u=1)
		var span := maxf(eff_horiz - eff_min, 1.0)
		var u := clampf((eff_horiz - r_iso) / span, 0.0, 1.0)
		# 缓出响应曲线 (Ease-Out): u=0 处初始斜率良好接近线性，u->1 处导数平缓趋于 0，消除靠近死区时的暴跳
		var power := maxf(pitch_curve_power, 1.0)
		var f_u := 1.0 - pow(1.0 - u, power)
		return deg_to_rad(-f_u * max_pitch_deg)

## 合成标准的 3D 空间单位朝向向量 (X: 东, Y: 南, Z: 上)
static func compose_aim_vector_3d(pitch_rad: float, azimuth_rad: float) -> Vector3:
	var cos_p := cos(pitch_rad)
	var sin_p := sin(pitch_rad)
	var cos_a := cos(azimuth_rad)
	var sin_a := sin(azimuth_rad)

	var grid_x := cos_a + sin_a
	var grid_y := -cos_a + sin_a
	var grid_dir_2d := Vector2(grid_x, grid_y).normalized()

	return Vector3(grid_dir_2d.x * cos_p, grid_dir_2d.y * cos_p, sin_p).normalized()

## 获取 2D 屏幕投影的射击方向向量 (严格 2:1 等距地面与垂直 Z 轴合成)
static func calc_screen_aim_direction(pitch_rad: float, azimuth_rad: float) -> Vector2:
	var cos_p := cos(pitch_rad)
	var sin_p := sin(pitch_rad)
	var cos_a := cos(azimuth_rad)
	var sin_a := sin(azimuth_rad)

	var screen_v := Vector2(cos_p * cos_a, cos_p * sin_a * 0.5 - sin_p)
	return screen_v.normalized()

## 计算无地形干扰时的水平离散弹道采样点集
static func calc_trajectory_points(origin: Vector2, pitch_rad: float, azimuth_rad: float, projectile_speed: float, drop_value: float, launch_height: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	if drop_value <= 0.001 or projectile_speed <= 0.001:
		return points

	var cos_p := cos(pitch_rad)
	var sin_p := sin(pitch_rad)
	var cos_a := cos(azimuth_rad)
	var sin_a := sin(azimuth_rad)

	var vx := projectile_speed * cos_p
	var vy := projectile_speed * sin_p

	var disc := vy * vy + 2.0 * drop_value * launch_height
	if disc < 0.0:
		return points
	var t_impact := (vy + sqrt(disc)) / drop_value
	if t_impact <= 0.0001:
		return points

	var segs := maxi(segments, 8)
	points.resize(segs + 1)

	for i in range(segs + 1):
		var frac := float(i) / float(segs)
		var t := t_impact * frac
		var x_dist := vx * t
		var y_height := vy * t - 0.5 * drop_value * t * t
		var screen_pt := origin + Vector2(x_dist * cos_a, x_dist * sin_a * 0.5 - y_height)
		points[i] = screen_pt

	return points

## 获取弹道飞行物理数据 (用于 UI 或调试显示)
static func calc_flight_info(pitch_rad: float, projectile_speed: float, drop_value: float, launch_height: float) -> Dictionary:
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

