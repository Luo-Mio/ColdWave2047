# aim_terrain_solver.gd —— 2.5D 等距空间 3D 地形自适应步进与视线遮挡探测器
class_name AimTerrainSolver

## 检查屏幕某点在 3D 高度 point_z 处是否被前方高层瓷砖遮挡 (2.5D 等距视线步进)
static func is_point_occluded(screen_pt: Vector2, point_z: float, grid: Object = null) -> bool:
	if grid == null:
		return false

	var max_layers: int = grid.layers.size() if ("layers" in grid and grid.layers is Array) else 6
	var max_h := float(maxi(max_layers, 4)) * 16.0
	if point_z >= max_h:
		return false

	var z := max_h
	var step_z := 8.0 # 地面层高为16px，8px步进实现半层超采样精度同时减半计算量
	var last_cell := Vector2i(-999999, -999999)
	var last_h_floor := -1.0

	while z > point_z + 0.5 and z > 0.5:
		var test_ground := Vector2(screen_pt.x, screen_pt.y + z)
		var c: Vector2i = grid.world_to_cell(test_ground)
		var h_floor: float
		if c == last_cell:
			h_floor = last_h_floor
		else:
			last_cell = c
			if grid.has_any_tile(c):
				h_floor = float(grid.get_highest_floor(c)) * 16.0
			else:
				h_floor = 0.0
			last_h_floor = h_floor

		if h_floor >= z:
			return true
		z -= step_z
	return false

## 计算考虑真实 3D 地形高度的自适应弹道数据
# - 若遭遇前方高层/高台阻挡：实线主弹道提前在撞击点截断，返回 hit_type = 1
# - 若落在角色同层地表：保持常规平滑实线，返回 hit_type = 0
# - 若飞离高台/跌入悬崖低层：角色层高以上为实线，随后向下延伸为虚线，返回 hit_type = -1
static func solve_adaptive_trajectory(
	player_ground: Vector2,
	p_floor: int,
	chest_origin: Vector2,
	pitch_rad: float,
	azimuth_rad: float,
	projectile_speed: float,
	drop_value: float,
	launch_height: float,
	trajectory_segments: int,
	grid: Object = null
) -> Dictionary:
	if drop_value <= 0.001 or projectile_speed <= 0.001:
		return _create_empty_result(p_floor)

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
		return _create_empty_result(p_floor)
	var t_base := (vy + sqrt(disc_base)) / drop_value
	if t_base <= 0.0001:
		return _create_empty_result(p_floor)

	var primary_points := PackedVector2Array()
	var primary_z := PackedFloat32Array()
	var dashed_points := PackedVector2Array()
	var dashed_z := PackedFloat32Array()
	var hit_type := 0
	var hit_screen_pos := Vector2.ZERO
	var hit_floor := p_floor
	var hit_z := 0.0

	primary_points.push_back(chest_origin)
	primary_z.push_back(z_start)

	var segs := maxi(trajectory_segments, 16)
	var high_floor_hit := false
	var prev_t := 0.0
	var prev_z := z_start

	# 1. 角色层高基准面以上采样 (检测高台阻碍)
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
				# 撞击高台垂直侧面墙体：高度保持为真实弹道飞抵侧壁的高度
				t_hit = lerpf(prev_t, t, 0.5)
				z_hit = clampf(lerpf(prev_z, z_t, 0.5), 0.0, surface_h)

			var g_hit := player_ground + Vector2(cos_a, 0.5 * sin_a) * (vx * t_hit)
			var p_hit := g_hit - Vector2(0.0, z_hit)
			primary_points.push_back(p_hit)
			primary_z.push_back(z_hit)
			hit_screen_pos = p_hit
			hit_z = z_hit
			break

		primary_points.push_back(p_screen)
		primary_z.push_back(z_t)
		prev_t = t
		prev_z = z_t

	# 2. 未遭遇高台阻挡：判断同层着弹还是跌入悬崖
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
			# 同层着弹
			hit_type = 0
			hit_floor = fl_base
			hit_screen_pos = g_base - Vector2(0.0, surface_base)
			hit_z = surface_base
			primary_points[-1] = hit_screen_pos
			primary_z[-1] = surface_base
		else:
			# 悬崖低层延伸
			hit_type = -1
			dashed_points.push_back(primary_points[-1])
			dashed_z.push_back(primary_z[-1])

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
						var denom := (curr_z - z_next)
						var frac := clampf((curr_z - s_h) / denom, 0.0, 1.0) if absf(denom) > 0.0001 else 0.5
						t_hit = lerpf(curr_t, next_t, frac)
					else:
						t_hit = lerpf(curr_t, next_t, 0.5)
						z_hit = clampf(lerpf(curr_z, z_next, 0.5), 0.0, s_h)

					var g_hit := player_ground + Vector2(cos_a, 0.5 * sin_a) * (vx * t_hit)
					var p_hit := g_hit - Vector2(0.0, z_hit)
					dashed_points.push_back(p_hit)
					dashed_z.push_back(z_hit)
					hit_floor = s_fl
					hit_screen_pos = p_hit
					hit_z = z_hit
					low_hit = true
					break

				dashed_points.push_back(p_next)
				dashed_z.push_back(z_next)
				curr_t = next_t
				curr_z = z_next

			if not low_hit and not dashed_points.is_empty():
				var g_max := player_ground + Vector2(cos_a, 0.5 * sin_a) * (vx * t_max)
				hit_floor = 0
				hit_screen_pos = g_max - Vector2(0.0, 0.0)
				hit_z = 0.0
				dashed_points.push_back(hit_screen_pos)
				dashed_z.push_back(0.0)

	var is_hit_occluded: bool = is_point_occluded(hit_screen_pos, hit_z, grid)

	return {
		"is_valid": true,
		"hit_type": hit_type,
		"primary_points": primary_points,
		"primary_z": primary_z,
		"dashed_points": dashed_points,
		"dashed_z": dashed_z,
		"hit_screen_pos": hit_screen_pos,
		"hit_floor": hit_floor,
		"hit_z": hit_z,
		"is_hit_occluded": is_hit_occluded
	}

static func _create_empty_result(p_floor: int) -> Dictionary:
	return {
		"is_valid": false,
		"hit_type": 0,
		"primary_points": PackedVector2Array(),
		"primary_z": PackedFloat32Array(),
		"dashed_points": PackedVector2Array(),
		"dashed_z": PackedFloat32Array(),
		"hit_screen_pos": Vector2.ZERO,
		"hit_floor": p_floor,
		"hit_z": 0.0,
		"is_hit_occluded": false
	}
