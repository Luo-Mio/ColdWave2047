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

	# 4. 获取三环尺寸
	var r_min: float = aim_controller.call("get_effective_radius_min") if aim_controller.has_method("get_effective_radius_min") else 8.0
	var r0: float = aim_controller.call("get_effective_radius_horizontal") if aim_controller.has_method("get_effective_radius_horizontal") else aim_controller.radius_horizontal
	var r_max: float = aim_controller.call("get_effective_radius_max") if aim_controller.has_method("get_effective_radius_max") else aim_controller.radius_max

	# 5. 绘制【内环】—— 最大俯角环 (虚线边界，θ = -max_pitch，暂定 140px)
	_draw_dashed_isometric_ellipse(ground_center, r_min, r_min * 0.5, inner_ring_col, 1.0, 4.0, 3.5)

	# 5.1 绘制【中环】—— 2:1 等距基准水平环 (实线，θ = 0°)
	_draw_isometric_ellipse(ground_center, r0, r0 * 0.5, ring_col, 1.5)

	# 5.2 绘制【外环】—— 2:1 等距最大仰角外环 (虚线边界，θ = +max_pitch)
	_draw_dashed_isometric_ellipse(ground_center, r_max, r_max * 0.5, outer_ring_col, 1.0, 5.0, 4.0)

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

	# 绘制从地面中心到活动准心的【地面指引射线】
	draw_line(ground_center, active_cursor_pos, Color(ring_col.r, ring_col.g, ring_col.b, 0.35), 1.0)

	# 在基准水平环 (r0) 上绘制 0° 参考圆点
	draw_circle(r0_ref_pos, 2.5, Color(ring_col.r, ring_col.g, ring_col.b, 0.5))

	# 当前瞄准准星 (2:1 绿色圆点):
	# 若命中位置与角色同层 (hit_type == 0)，瞄准原点不显示，直接在落地点显示红色点；
	# 若命中位置为跨层 (高台截断 hit_type == 1 或 低层悬崖 hit_type == -1)，显示 2:1 绿色瞄准原点以明确区分基准瞄准点与实际落点
	var pitch_deg: float = aim_controller.get_pitch_degrees()
	var end_color: Color = Color(1.0, 0.4, 0.4, 0.9) if pitch_deg < -3.0 else (Color(0.2, 1.0, 0.5, 0.9) if pitch_deg > 3.0 else cursor_col)
	if hit_type != 0:
		_draw_2to1_dot(active_cursor_pos, 5.0, 2.5, Color(0.2, 1.0, 0.5, 0.85), Color(0.1, 0.85, 0.35, 0.95), Color(0.85, 1.0, 0.85, 0.95))

	# 7. 计算方向：无俯仰角基准方向 vs 3D 修正瞄准方向
	var base_screen_dir: Vector2 = (r0_ref_pos - ground_center).normalized()
	var aim_screen_dir: Vector2 = aim_controller.get_screen_aim_direction()
	
	# 绘制从手部射出的【水平基准瞄准线】(半透明青白虚线，θ = 0°)
	var base_end: Vector2 = chest_origin + base_screen_dir * (laser_len * 0.85)
	_draw_dashed_line(chest_origin, base_end, Color(0.3, 0.8, 1.0, 0.3), 1.0, 4.0, 4.0)

	# 绘制从手部射出的【3D 修正激光瞄准线】
	var laser_end: Vector2 = chest_origin + aim_screen_dir * laser_len
	_draw_dashed_line(chest_origin, laser_end, laser_col, 1.8, 6.0, 3.5)

	# 8. 夹角弧线与俯仰角数字 HUD 显示
	draw_circle(laser_end, 3.0, end_color)

	# 在两线夹角处绘制角度扇形弧与度数文字
	var arc_radius: float = 52.0
	var angle_base := base_screen_dir.angle()
	var angle_laser := aim_screen_dir.angle()
	
	if absf(pitch_deg) >= 1.0:
		var diff := wrapf(angle_laser - angle_base, -PI, PI)
		var start_a := angle_base
		var end_a := angle_base + diff
		var min_a := minf(start_a, end_a)
		var max_a := maxf(start_a, end_a)
		
		# 绘制夹角弧线
		draw_arc(chest_origin, arc_radius, min_a, max_a, 16, end_color, 1.5)
		
		# 在夹角正中间绘制角度文字（例如 +24° 或 -18°）
		var mid_a := (min_a + max_a) * 0.5
		var text_pos := chest_origin + Vector2(cos(mid_a), sin(mid_a)) * (arc_radius + 16.0) + Vector2(-10.0, 4.0)
		var text_str := "%+d°" % int(round(pitch_deg))
		var default_font: Font = ThemeDB.fallback_font
		draw_string(default_font, text_pos, text_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, end_color)

	# 9. 绘制【3D 地形自适应重力弹道指示线】(高层提前截断 / 同层常规 / 低层虚线延伸 + 2:1 红点)
	if not traj_info.is_empty() and traj_info.get("is_valid", false):
		var primary_pts: PackedVector2Array = traj_info.get("primary_points", PackedVector2Array())
		var dashed_pts: PackedVector2Array = traj_info.get("dashed_points", PackedVector2Array())
		var hit_screen_pos: Vector2 = traj_info.get("hit_screen_pos", Vector2.ZERO)

		var traj_col: Color = aim_controller.trajectory_color if "trajectory_color" in aim_controller else Color(0.4, 0.8, 1.0, 0.85)
		var traj_w: float = aim_controller.trajectory_width if "trajectory_width" in aim_controller else 1.5

		# 9.1 绘制实线段 (高层阻挡时提前在障碍物截断)
		if primary_pts.size() >= 2:
			draw_polyline(primary_pts, traj_col, traj_w, true)

		# 9.2 绘制虚线延伸段 (低层悬崖下坠)
		if hit_type == -1 and dashed_pts.size() >= 2:
			_draw_dashed_polyline(dashed_pts, Color(traj_col.r, traj_col.g, traj_col.b, 0.8), traj_w, 4.0, 3.5)

		# 9.3 绘制落点指示：无论同层或跨层，直接在真实着弹地表绘制 2:1 椭圆红色着弹点
		_draw_2to1_dot(hit_screen_pos, 5.0, 2.5, Color(1.0, 0.25, 0.25, 0.85), Color(1.0, 0.1, 0.1, 0.95), Color(1.0, 0.85, 0.85, 0.95))
	elif aim_controller.has_method("get_trajectory_points"):
		var traj_points: PackedVector2Array = aim_controller.call("get_trajectory_points", chest_origin)
		if traj_points.size() >= 2:
			var traj_col: Color = aim_controller.trajectory_color if "trajectory_color" in aim_controller else Color(0.4, 0.8, 1.0, 0.85)
			var traj_w: float = aim_controller.trajectory_width if "trajectory_width" in aim_controller else 1.5
			# 绘制浅蓝色弹道细线 (启用抗锯齿抗抖动)
			draw_polyline(traj_points, traj_col, traj_w, true)
			# 在落地点直接显示 2:1 红色圆点
			var land_pt: Vector2 = traj_points[-1]
			_draw_2to1_dot(land_pt, 5.0, 2.5, Color(1.0, 0.25, 0.25, 0.85), Color(1.0, 0.1, 0.1, 0.95), Color(1.0, 0.85, 0.85, 0.95))

# 绘制 2:1 等距圆点辅助函数 (贴合等距地面的微型椭圆标记)
func _draw_2to1_dot(center: Vector2, rx: float, ry: float, fill_color: Color, outline_color: Color, core_color: Color = Color(1.0, 1.0, 1.0, 0.95)) -> void:
	var segments := 24
	var poly_pts := PackedVector2Array()
	poly_pts.resize(segments)
	for i in range(segments):
		var th := (float(i) / float(segments)) * TAU
		poly_pts[i] = center + Vector2(cos(th) * rx, sin(th) * ry)
	# 绘制内部 2:1 半透明红色填充
	draw_colored_polygon(poly_pts, fill_color)
	# 绘制外边框高亮红环
	poly_pts.push_back(poly_pts[0])
	draw_polyline(poly_pts, outline_color, 1.2, true)
	# 中心高亮小核 (形成立体激光聚光点质感)
	draw_circle(center, 1.0, core_color)

# 沿折线路径绘制平滑虚线 (用于悬崖下坠延伸弹道)
func _draw_dashed_polyline(points: PackedVector2Array, color: Color, width: float, dash_len: float = 4.0, gap_len: float = 3.5) -> void:
	if points.size() < 2:
		return
	var is_drawing := true
	var current_remaining := dash_len

	for i in range(points.size() - 1):
		var p0 := points[i]
		var p1 := points[i + 1]
		var seg_len := p0.distance_to(p1)
		if seg_len < 0.001:
			continue
		var seg_dir := (p1 - p0) / seg_len
		var walked := 0.0

		while walked < seg_len:
			var step := minf(seg_len - walked, current_remaining)
			var start_pt := p0 + seg_dir * walked
			var end_pt := p0 + seg_dir * (walked + step)

			if is_drawing:
				draw_line(start_pt, end_pt, color, width, true)

			walked += step
			current_remaining -= step

			if current_remaining <= 0.0001:
				is_drawing = not is_drawing
				current_remaining = dash_len if is_drawing else gap_len

# 绘制 2:1 等距椭圆辅助函数
func _draw_isometric_ellipse(center: Vector2, rx: float, ry: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	var segments: int = 48
	for i in range(segments + 1):
		var theta := (float(i) / float(segments)) * TAU
		points.push_back(center + Vector2(cos(theta) * rx, sin(theta) * ry))
	draw_polyline(points, color, width)

# 绘制 2:1 等距虚线椭圆辅助函数
func _draw_dashed_isometric_ellipse(center: Vector2, rx: float, ry: float, color: Color, width: float, dash_len: float = 5.0, gap_len: float = 4.0) -> void:
	var segments: int = 40
	var prev_pt := center + Vector2(rx, 0.0)
	for i in range(1, segments + 1):
		var theta := (float(i) / float(segments)) * TAU
		var next_pt := center + Vector2(cos(theta) * rx, sin(theta) * ry)
		_draw_dashed_line(prev_pt, next_pt, color, width, dash_len, gap_len)
		prev_pt = next_pt

# 绘制虚线辅助函数
func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float, dash_len: float, gap_len: float) -> void:
	var total_dist := from.distance_to(to)
	if total_dist <= 0.0:
		return
	var dir := (to - from).normalized()
	var curr := 0.0
	while curr < total_dist:
		var start := from + dir * curr
		var end := from + dir * minf(curr + dash_len, total_dist)
		draw_line(start, end, color, width)
		curr += dash_len + gap_len


