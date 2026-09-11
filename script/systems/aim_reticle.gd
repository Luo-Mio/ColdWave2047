# aim_reticle.gd —— 2.5D 等距地面基准光环与 3D 激光准心线渲染器
class_name AimReticle
extends Node2D

@export var player_path: NodePath
var aim_controller: Node
@onready var hotbar_node: Node = get_node_or_null("../hotbar")

# 视觉颜色配置
var ring_color: Color = Color(0.2, 0.9, 1.0, 0.6)        # 基准水平环 (亮青色)
var cursor_color: Color = Color(0.2, 1.0, 0.5, 0.9)       # 准心指示器 (亮绿)
var deadzone_color: Color = Color(1.0, 0.3, 0.3, 0.45)    # 死区环 (淡红)
var laser_color: Color = Color(1.0, 0.95, 0.2, 0.85)      # 激光瞄准线 (亮金黄)

@export_group("性能与更新频率 (Performance & Tick Rate)")
## 准星与瞄准线重绘刷新率 (Hz，默认 60.0 次/秒；若 <= 0 则跟随游戏渲染帧率无限制刷新)
@export var update_rate_hz: float = 60.0

var _update_timer: float = 0.0
var _was_aim_active: bool = false

func _ready() -> void:
	z_index = 150
	if hotbar_node == null and get_tree() and get_tree().root:
		hotbar_node = get_tree().root.find_child("hotbar", true, false)

func _process(delta: float) -> void:
	if aim_controller == null:
		var player: Node2D = get_node_or_null(player_path)
		if player == null and get_tree() and get_tree().root:
			player = get_tree().root.find_child("CharacterBody2D", true, false)
		if player != null:
			aim_controller = player.find_child("AimController", true, false)

	var is_active: bool = false
	if aim_controller and aim_controller.get("is_aim_active"):
		is_active = true

	# 状态切换检测：若从未激活变为激活，或者从激活变为未激活，立即重绘一帧以确保准星即时显示/隐藏，零延迟响应
	if is_active != _was_aim_active:
		_was_aim_active = is_active
		_update_timer = 0.0
		queue_redraw()
		return

	if not is_active:
		return

	# 获取目标刷新率 (优先读取 AimController 的配置保持完全同步)
	var target_hz: float = update_rate_hz
	if aim_controller and "update_rate_hz" in aim_controller:
		target_hz = float(aim_controller.update_rate_hz)

	# 若 <= 0 则无限制跟随游戏渲染帧率
	if target_hz <= 0.0:
		queue_redraw()
		return

	_update_timer += delta
	var interval := 1.0 / target_hz
	if _update_timer >= interval:
		_update_timer = fmod(_update_timer, interval)
		queue_redraw()

func _draw() -> void:
	var player: Node2D = get_node_or_null(player_path)
	if player == null and get_tree() and get_tree().root:
		player = get_tree().root.find_child("CharacterBody2D", true, false)
	if aim_controller == null and player != null:
		aim_controller = player.find_child("AimController", true, false)

	if player == null or aim_controller == null:
		return

	# 1. 检查当前瞄准系统是否处于激活状态 (由当前手持装备/道具决定)
	if not aim_controller.get("is_aim_active"):
		return

	# 2. 读取瞄准控制器当前样式与尺寸 (支持道具定制化动态覆盖)
	var ring_col: Color = aim_controller.ring_color if "ring_color" in aim_controller else ring_color
	var inner_ring_col: Color = aim_controller.inner_ring_color if "inner_ring_color" in aim_controller else (aim_controller.deadzone_color if "deadzone_color" in aim_controller else Color(1.0, 0.45, 0.35, 0.45))
	var outer_ring_col: Color = aim_controller.outer_ring_color if "outer_ring_color" in aim_controller else Color(ring_col.r, ring_col.g, ring_col.b, 0.35)
	var cursor_col: Color = aim_controller.cursor_color if "cursor_color" in aim_controller else cursor_color
	var laser_col: Color = aim_controller.laser_color if "laser_color" in aim_controller else laser_color
	var laser_len: float = float(aim_controller.laser_length) if "laser_length" in aim_controller else 180.0

	# 3. 获取角色地面坐标与胸口/手部起点
	var player_ground: Vector2 = player.global_position
	var tree := get_tree()
	var gd = tree.root.get_node_or_null("GridData") if (tree and tree.root) else null
	var player_cell: Vector2i = gd.world_to_cell(player_ground) if gd else Vector2i.ZERO
	var p_floor: int = gd.get_highest_floor(player_cell) if gd else 0
	var floor_y_lift: float = gd.get_floor_pixel_offset(p_floor) if gd else 0.0
	
	# 地面环中心（等距地面基准面）
	var ground_center := player_ground + Vector2(0.0, floor_y_lift)
	# 激光起点：优先使用武器手部挂点位置，保证法杖旋转与瞄准虚线 100% 贴合
	var hand_node: Node2D = player.find_child("hand", true, false) as Node2D
	var chest_origin: Vector2
	if hand_node != null:
		chest_origin = hand_node.global_position
	else:
		chest_origin = player_ground + Vector2(0.0, floor_y_lift - 8.0)

	# 动态手部出膛高度与弹道物理落差同步
	var hand_height := maxf(ground_center.y - chest_origin.y, 4.0)
	if "launch_height" in aim_controller:
		aim_controller.launch_height = hand_height

	# 4. 获取三环尺寸
	var r_min: float = aim_controller.call("get_effective_radius_min") if aim_controller.has_method("get_effective_radius_min") else 16.0
	var r0: float = aim_controller.call("get_effective_radius_horizontal") if aim_controller.has_method("get_effective_radius_horizontal") else aim_controller.radius_horizontal
	var r_max: float = aim_controller.call("get_effective_radius_max") if aim_controller.has_method("get_effective_radius_max") else aim_controller.radius_max

	# 5. 绘制【内环】—— 最大俯角环 (像素虚线边界，θ = -max_pitch)
	_draw_dashed_isometric_ellipse(ground_center, r_min, r_min * 0.5, inner_ring_col, 1.0, 4.0, 4.0)

	# 5.1 绘制【中环】—— 2:1 等距基准水平环 (像素实线，θ = 0°)
	_draw_isometric_ellipse(ground_center, r0, r0 * 0.5, ring_col, 1.0)

	# 5.2 绘制【外环】—— 2:1 等距最大仰角外环 (像素虚线边界，θ = +max_pitch)
	_draw_dashed_isometric_ellipse(ground_center, r_max, r_max * 0.5, outer_ring_col, 1.0, 6.0, 5.0)

	# 6. 计算鼠标在等距地面上的投影与动态准心光标
	var mouse_screen: Vector2 = get_global_mouse_position()
	var delta_ground: Vector2 = mouse_screen - ground_center
	var r_iso: float = sqrt(delta_ground.x * delta_ground.x + 4.0 * delta_ground.y * delta_ground.y)
	
	# 光标位置在 [r_min, r_max] 之间随鼠标自由滑移；落入内环以内时光标贴附在内环上并保持 360° 全向朝向
	var r_clamped: float = clampf(r_iso, r_min, r_max)
	var active_cursor_pos: Vector2
	var r0_ref_pos: Vector2
	if r_iso > 0.001:
		active_cursor_pos = ground_center + delta_ground * (r_clamped / r_iso)
		r0_ref_pos = ground_center + delta_ground * (r0 / r_iso)
	else:
		active_cursor_pos = ground_center + Vector2(r_min, 0.0)
		r0_ref_pos = ground_center + Vector2(r0, 0.0)

	# 提前获取 3D 地形自适应重力弹道数据
	var traj_info: Dictionary = {}
	if aim_controller.has_method("get_terrain_adaptive_trajectory"):
		traj_info = aim_controller.call("get_terrain_adaptive_trajectory", player_ground, p_floor, chest_origin)

	var hit_type: int = traj_info.get("hit_type", 0) if traj_info.get("is_valid", false) else 0

	# 绘制从地面中心到活动准心的【地面指引射线】(像素直线，无抗锯齿)
	draw_line(ground_center.round(), active_cursor_pos.round(), Color(ring_col.r, ring_col.g, ring_col.b, 0.35), 1.0, false)

	# 在基准水平环 (r0) 上绘制 0° 像素十字标记
	var ref_c := r0_ref_pos.round()
	draw_rect(Rect2(ref_c.x - 1, ref_c.y, 3, 1), Color(ring_col.r, ring_col.g, ring_col.b, 0.65))
	draw_rect(Rect2(ref_c.x, ref_c.y - 1, 1, 3), Color(ring_col.r, ring_col.g, ring_col.b, 0.65))

	# 当前瞄准准星 (2:1 像素绿色标记):
	# 若命中位置与角色同层 (hit_type == 0)，瞄准原点不显示，直接在落地点显示红色点；
	# 若命中位置为跨层 (高台截断 hit_type == 1 或 低层悬崖 hit_type == -1)，显示 2:1 绿色瞄准原点以明确区分基准瞄准点与实际落点
	var pitch_deg: float = aim_controller.get_pitch_degrees()
	var end_color: Color = Color(1.0, 0.4, 0.4, 0.9) if pitch_deg < -3.0 else (Color(0.2, 1.0, 0.5, 0.9) if pitch_deg > 3.0 else cursor_col)
	if hit_type != 0:
		_draw_2to1_dot(active_cursor_pos, 4.0, 2.0, Color(0.2, 1.0, 0.5, 0.85), Color(0.1, 0.85, 0.35, 0.95), Color(0.85, 1.0, 0.85, 0.95))

	# 7. 角色身旁俯仰角显示 HUD (像素对齐文本)
	var text_str := ("%+d°" % int(round(pitch_deg))) if absf(pitch_deg) >= 0.5 else "0°"
	var default_font: Font = ThemeDB.fallback_font
	var font_size: int = 12
	var str_size := default_font.get_string_size(text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

	# 位于角色身侧 (依据瞄准方位动态放置在面朝方向的身旁侧上方，整像素对齐)
	var text_pos: Vector2
	if delta_ground.x >= 0.0:
		text_pos = (chest_origin + Vector2(16.0, -10.0)).round()
	else:
		text_pos = (chest_origin + Vector2(-16.0 - str_size.x, -10.0)).round()

	# 黑色描边保证在任何地形背景上均清晰可见
	draw_string_outline(default_font, text_pos, text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color(0.0, 0.0, 0.0, 0.85))
	draw_string(default_font, text_pos, text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, end_color)

	# 8. 绘制【3D 地形自适应重力弹道指示线】(高层提前截断 / 同层常规 / 低层虚线延伸 + 2:1 像素红点，遮挡处 50% 透明度)
	if not traj_info.is_empty() and traj_info.get("is_valid", false):
		var primary_pts: PackedVector2Array = traj_info.get("primary_points", PackedVector2Array())
		var primary_z: PackedFloat32Array = traj_info.get("primary_z", PackedFloat32Array())
		var dashed_pts: PackedVector2Array = traj_info.get("dashed_points", PackedVector2Array())
		var dashed_z: PackedFloat32Array = traj_info.get("dashed_z", PackedFloat32Array())
		var hit_screen_pos: Vector2 = traj_info.get("hit_screen_pos", Vector2.ZERO)
		var is_hit_occluded: bool = traj_info.get("is_hit_occluded", false)

		var traj_col: Color = aim_controller.trajectory_color if "trajectory_color" in aim_controller else Color(0.4, 0.8, 1.0, 0.85)

		# 8.1 绘制像素实线段 (被瓷砖遮挡处透明度降低至 50%)
		if primary_pts.size() >= 2:
			_draw_occlusion_aware_trajectory(primary_pts, primary_z, traj_col, false)

		# 8.2 绘制像素虚线延伸段 (低层悬崖下坠，被瓷砖遮挡处透明度降低至 50%)
		if hit_type == -1 and dashed_pts.size() >= 2:
			_draw_occlusion_aware_trajectory(dashed_pts, dashed_z, Color(traj_col.r, traj_col.g, traj_col.b, 0.85), true)

		# 8.3 绘制落点指示：无论同层或跨层，直接在真实着弹地表绘制 2:1 像素红色着弹点 (若被瓷砖遮挡同步降至 50% 透明度)
		var dot_scale := 0.5 if is_hit_occluded else 1.0
		_draw_2to1_dot(hit_screen_pos, 4.0, 2.0,
			Color(1.0, 0.25, 0.25, 0.85 * dot_scale),
			Color(1.0, 0.1, 0.1, 0.95 * dot_scale),
			Color(1.0, 0.85, 0.85, 0.95 * dot_scale))
	elif aim_controller.has_method("get_trajectory_points"):
		var traj_points: PackedVector2Array = aim_controller.call("get_trajectory_points", chest_origin)
		if traj_points.size() >= 2:
			var traj_col: Color = aim_controller.trajectory_color if "trajectory_color" in aim_controller else Color(0.4, 0.8, 1.0, 0.85)
			var snapped_points := PackedVector2Array()
			snapped_points.resize(traj_points.size())
			for i in range(traj_points.size()):
				snapped_points[i] = traj_points[i].round()
			draw_polyline(snapped_points, traj_col, 1.0, false)
			var land_pt: Vector2 = traj_points[-1]
			_draw_2to1_dot(land_pt, 4.0, 2.0, Color(1.0, 0.25, 0.25, 0.85), Color(1.0, 0.1, 0.1, 0.95), Color(1.0, 0.85, 0.85, 0.95))

# 绘制 2:1 像素风格等距圆点/菱形标记 (贴合等距地面的微型像素标记)
func _draw_2to1_dot(center: Vector2, _rx: float, _ry: float, fill_color: Color, outline_color: Color, core_color: Color = Color(1.0, 1.0, 1.0, 0.95)) -> void:
	var c := center.round()
	# 顶层 (y = -2): 2px 宽外边框
	draw_rect(Rect2(c.x - 1, c.y - 2, 2, 1), outline_color)
	# 次顶层 (y = -1): 6px 宽 (外边框各 1px, 内部填充 4px)
	draw_rect(Rect2(c.x - 3, c.y - 1, 1, 1), outline_color)
	draw_rect(Rect2(c.x - 2, c.y - 1, 4, 1), fill_color)
	draw_rect(Rect2(c.x + 2, c.y - 1, 1, 1), outline_color)
	# 中间层 (y = 0): 8px 宽 (外边框各 1px, 填充各 2px, 中心 2px 高亮核)
	draw_rect(Rect2(c.x - 4, c.y, 1, 1), outline_color)
	draw_rect(Rect2(c.x - 3, c.y, 2, 1), fill_color)
	draw_rect(Rect2(c.x - 1, c.y, 2, 1), core_color)
	draw_rect(Rect2(c.x + 1, c.y, 2, 1), fill_color)
	draw_rect(Rect2(c.x + 3, c.y, 1, 1), outline_color)
	# 次底层 (y = +1): 6px 宽
	draw_rect(Rect2(c.x - 3, c.y + 1, 1, 1), outline_color)
	draw_rect(Rect2(c.x - 2, c.y + 1, 4, 1), fill_color)
	draw_rect(Rect2(c.x + 2, c.y + 1, 1, 1), outline_color)
	# 底层 (y = +2): 2px 宽外边框
	draw_rect(Rect2(c.x - 1, c.y + 2, 2, 1), outline_color)

# 沿折线路径绘制像素风格虚线 (用于悬崖下坠延伸弹道)
func _draw_pixel_dashed_polyline(points: PackedVector2Array, color: Color, _width: float = 1.0, dash_len: float = 4.0, gap_len: float = 3.5) -> void:
	if points.size() < 2:
		return
	var is_drawing := true
	var current_remaining := dash_len

	for i in range(points.size() - 1):
		var p0 := points[i].round()
		var p1 := points[i + 1].round()
		var seg_len := p0.distance_to(p1)
		if seg_len < 0.001:
			continue
		var seg_dir := (p1 - p0) / seg_len
		var walked := 0.0

		while walked < seg_len:
			var step := minf(seg_len - walked, current_remaining)
			var start_pt := (p0 + seg_dir * walked).round()
			var end_pt := (p0 + seg_dir * (walked + step)).round()

			if is_drawing and start_pt != end_pt:
				draw_line(start_pt, end_pt, color, 1.0, false)

			walked += step
			current_remaining -= step

			if current_remaining <= 0.0001:
				is_drawing = not is_drawing
				current_remaining = dash_len if is_drawing else gap_len

# 绘制 2:1 像素风格等距椭圆 (实线基准环)
func _draw_isometric_ellipse(center: Vector2, rx: float, ry: float, color: Color, _width: float = 1.0) -> void:
	var c := center.round()
	var steps := maxi(int(TAU * rx), 72)
	var pts := PackedVector2Array()
	var last_p := Vector2(-99999, -99999)
	for i in range(steps + 1):
		var th := (float(i) / float(steps)) * TAU
		var p := Vector2(round(c.x + cos(th) * rx), round(c.y + sin(th) * ry))
		if p != last_p:
			pts.push_back(p)
			last_p = p
	if pts.size() >= 2:
		draw_polyline(pts, color, 1.0, false)

# 绘制 2:1 像素风格等距虚线椭圆 (内环与外环)
func _draw_dashed_isometric_ellipse(center: Vector2, rx: float, ry: float, color: Color, _width: float = 1.0, dash_len: float = 4.0, gap_len: float = 4.0) -> void:
	var c := center.round()
	var steps := maxi(int(TAU * rx), 72)
	var unique_pts := PackedVector2Array()
	var last_p := Vector2(-99999, -99999)
	for i in range(steps + 1):
		var th := (float(i) / float(steps)) * TAU
		var p := Vector2(round(c.x + cos(th) * rx), round(c.y + sin(th) * ry))
		if p != last_p:
			unique_pts.push_back(p)
			last_p = p

	if unique_pts.size() < 2:
		return

	var is_drawing := true
	var curr_budget := int(dash_len)
	var current_dash := PackedVector2Array()

	for i in range(unique_pts.size()):
		var p := unique_pts[i]
		if is_drawing:
			current_dash.push_back(p)
		curr_budget -= 1
		if curr_budget <= 0:
			if is_drawing:
				if current_dash.size() >= 2:
					draw_polyline(current_dash, color, 1.0, false)
				elif current_dash.size() == 1:
					draw_rect(Rect2(current_dash[0], Vector2(1, 1)), color)
				current_dash.clear()
				is_drawing = false
				curr_budget = int(gap_len)
			else:
				is_drawing = true
				curr_budget = int(dash_len)

	if is_drawing and current_dash.size() >= 2:
		draw_polyline(current_dash, color, 1.0, false)

# 兼容旧接口虚线辅助函数 (像素风格，无抗锯齿)
func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, _width: float = 1.0, dash_len: float = 4.0, gap_len: float = 4.0) -> void:
	var f := from.round()
	var t := to.round()
	var total_dist := f.distance_to(t)
	if total_dist <= 0.0:
		return
	var dir := (t - f) / total_dist
	var curr := 0.0
	while curr < total_dist:
		var start := (f + dir * curr).round()
		var end := (f + dir * minf(curr + dash_len, total_dist)).round()
		if start != end:
			draw_line(start, end, color, 1.0, false)
		curr += dash_len + gap_len

# 绘制自适应遮挡弹道线（在被瓷砖遮挡处将透明度降低至 50%）
func _draw_occlusion_aware_trajectory(pts: PackedVector2Array, z_vals: PackedFloat32Array, color: Color, is_dashed: bool = false) -> void:
	if pts.size() < 2:
		return
	if z_vals.size() != pts.size() or aim_controller == null or not aim_controller.has_method("is_point_occluded"):
		var snapped := PackedVector2Array()
		snapped.resize(pts.size())
		for i in range(pts.size()):
			snapped[i] = pts[i].round()
		if is_dashed:
			_draw_pixel_dashed_polyline(snapped, color, 1.0, 4.0, 3.5)
		else:
			draw_polyline(snapped, color, 1.0, false)
		return

	var color_occluded := Color(color.r, color.g, color.b, color.a * 0.2)

	# 1. 预先计算每个顶点的遮挡状态
	var occ_status: Array[bool] = []
	occ_status.resize(pts.size())
	for i in range(pts.size()):
		occ_status[i] = aim_controller.call("is_point_occluded", pts[i], z_vals[i])

	# 2. 逐段遍历并将线段切分为连续的可见段与遮挡段
	# 为保证过渡处 1 像素级精准对齐且无缝连接，对跨越遮挡边界的线段进行 3 轮二分查找
	var current_mode: bool = occ_status[0]
	var current_strip := PackedVector2Array()
	current_strip.push_back(pts[0].round())

	for i in range(pts.size() - 1):
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var z0 := z_vals[i]
		var z1 := z_vals[i + 1]
		var occ0 := occ_status[i]
		var occ1 := occ_status[i + 1]

		if occ0 == occ1:
			var p1_round := p1.round()
			if current_strip.is_empty() or current_strip[-1] != p1_round:
				current_strip.push_back(p1_round)
		else:
			var t0 := 0.0
			var t1 := 1.0
			for iter in range(3):
				var t_mid := (t0 + t1) * 0.5
				var s_mid := p0.lerp(p1, t_mid)
				var z_mid := lerpf(z0, z1, t_mid)
				var occ_mid: bool = aim_controller.call("is_point_occluded", s_mid, z_mid)
				if occ_mid == occ0:
					t0 = t_mid
				else:
					t1 = t_mid

			var split_pt := p0.lerp(p1, (t0 + t1) * 0.5).round()
			if current_strip.is_empty() or current_strip[-1] != split_pt:
				current_strip.push_back(split_pt)

			_flush_trajectory_strip(current_strip, current_mode, color, color_occluded, is_dashed)

			current_mode = occ1
			current_strip.clear()
			current_strip.push_back(split_pt)
			var p1_round := p1.round()
			if split_pt != p1_round:
				current_strip.push_back(p1_round)

	if not current_strip.is_empty():
		_flush_trajectory_strip(current_strip, current_mode, color, color_occluded, is_dashed)

func _flush_trajectory_strip(strip: PackedVector2Array, is_occluded: bool, normal_col: Color, occluded_col: Color, is_dashed: bool) -> void:
	if strip.size() < 2:
		return
	var col := occluded_col if is_occluded else normal_col
	if is_dashed:
		_draw_pixel_dashed_polyline(strip, col, 1.0, 4.0, 3.5)
	else:
		draw_polyline(strip, col, 1.0, false)



