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

func _ready() -> void:
	z_index = 150
	if hotbar_node == null:
		hotbar_node = get_tree().root.find_child("hotbar", true, false)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var player: Node2D = get_node_or_null(player_path)
	if player == null:
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
	var cursor_col: Color = aim_controller.cursor_color if "cursor_color" in aim_controller else cursor_color
	var deadzone_col: Color = aim_controller.deadzone_color if "deadzone_color" in aim_controller else deadzone_color
	var laser_col: Color = aim_controller.laser_color if "laser_color" in aim_controller else laser_color
	var laser_len: float = float(aim_controller.laser_length) if "laser_length" in aim_controller else 180.0

	# 3. 获取角色地面坐标与胸口/手部起点
	var player_ground: Vector2 = player.global_position
	var player_cell := GridData.world_to_cell(player_ground)
	var p_floor := GridData.get_highest_floor(player_cell)
	var floor_y_lift := GridData.get_floor_pixel_offset(p_floor)
	
	# 地面环中心（等距地面基准面）
	var ground_center := player_ground + Vector2(0.0, floor_y_lift)
	# 激光起点：优先使用武器手部挂点位置，保证法杖旋转与瞄准虚线 100% 贴合
	var hand_node: Node2D = player.find_child("hand", true, false) as Node2D
	var chest_origin: Vector2
	if hand_node != null:
		chest_origin = hand_node.global_position
	else:
		chest_origin = player_ground + Vector2(0.0, floor_y_lift - 8.0)

	# 4. 绘制 2:1 等距基准水平环 (θ = 0°)
	var r0: float = aim_controller.radius_horizontal
	_draw_isometric_ellipse(ground_center, r0, r0 * 0.5, ring_col, 1.5)

	# 5. 绘制 2:1 等距内圈死区环
	var r_dead: float = aim_controller.radius_deadzone
	_draw_isometric_ellipse(ground_center, r_dead, r_dead * 0.5, deadzone_col, 1.0)

	# 5.5 绘制 2:1 等距最大仰角外环 (虚线边界，θ = +75°)
	var r_max: float = aim_controller.call("get_effective_radius_max") if aim_controller.has_method("get_effective_radius_max") else aim_controller.radius_max
	var max_ring_col := Color(ring_col.r, ring_col.g, ring_col.b, 0.35)
	_draw_dashed_isometric_ellipse(ground_center, r_max, r_max * 0.5, max_ring_col, 1.0, 5.0, 4.0)

	# 6. 计算鼠标在等距地面上的投影与动态准心光标
	var mouse_screen: Vector2 = get_global_mouse_position()
	var delta_ground: Vector2 = mouse_screen - ground_center
	var r_iso: float = sqrt(delta_ground.x * delta_ground.x + 4.0 * delta_ground.y * delta_ground.y)
	
	var r_clamped: float = clampf(r_iso, r_dead, r_max)
	var active_cursor_pos: Vector2
	var r0_ref_pos: Vector2
	if r_iso > 0.001:
		active_cursor_pos = ground_center + delta_ground * (r_clamped / r_iso)
		r0_ref_pos = ground_center + delta_ground * (r0 / r_iso)
	else:
		active_cursor_pos = ground_center + Vector2(r0, 0.0)
		r0_ref_pos = ground_center + Vector2(r0, 0.0)

	# 绘制从地面中心到活动准心的【地面指引射线】
	draw_line(ground_center, active_cursor_pos, Color(ring_col.r, ring_col.g, ring_col.b, 0.35), 1.0)

	# 在基准水平环 (r0) 上绘制 0° 参考圆点
	draw_circle(r0_ref_pos, 2.5, Color(ring_col.r, ring_col.g, ring_col.b, 0.5))

	# 当前瞄准光标（跟随鼠标距离平滑滑移）
	var pitch_deg: float = aim_controller.get_pitch_degrees()
	var end_color: Color = Color(1.0, 0.4, 0.4, 0.9) if pitch_deg < -3.0 else (Color(0.2, 1.0, 0.5, 0.9) if pitch_deg > 3.0 else cursor_col)
	draw_circle(active_cursor_pos, 3.5, end_color)
	draw_arc(active_cursor_pos, 6.5, 0.0, TAU, 16, end_color, 1.2)

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

