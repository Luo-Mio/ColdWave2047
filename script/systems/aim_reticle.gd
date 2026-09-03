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
	if hotbar_node == null:
		hotbar_node = get_tree().root.find_child("hotbar", true, false)

	if player == null or aim_controller == null:
		return

	# 1. 检查当前是否手持武器（只有手持武器时才显示瞄准光环与激光）
	var active_item: Dictionary = {}
	if hotbar_node and hotbar_node.has_method("get_active_item"):
		active_item = hotbar_node.call("get_active_item")
	if active_item.get("type", -1) != 2: # 2 = WEAPON
		return

	# 2. 获取角色地面坐标与胸口起点
	var player_ground: Vector2 = player.global_position
	var player_cell := GridData.world_to_cell(player_ground)
	var p_floor := GridData.get_highest_floor(player_cell)
	var floor_y_lift := GridData.get_floor_pixel_offset(p_floor)
	
	# 地面环中心（等距地面基准面）
	var ground_center := player_ground + Vector2(0.0, floor_y_lift)
	# 激光起点（胸口/法杖位置）
	var chest_origin := player_ground + Vector2(0.0, floor_y_lift - 8.0)

	# 3. 绘制 2:1 等距基准水平环 (R0 = 120)
	var r0: float = aim_controller.radius_horizontal
	_draw_isometric_ellipse(ground_center, r0, r0 * 0.5, ring_color, 1.5)

	# 4. 绘制 2:1 等距内圈死区环 (R_dead = 25)
	var r_dead: float = aim_controller.radius_deadzone
	_draw_isometric_ellipse(ground_center, r_dead, r_dead * 0.5, deadzone_color, 1.0)

	# 5. 在基准水平环上绘制方位角准心光标（严格与鼠标射线 100% 共线对齐）
	var mouse_screen: Vector2 = get_global_mouse_position()
	var delta_ground: Vector2 = mouse_screen - ground_center
	var r_iso: float = sqrt(delta_ground.x * delta_ground.x + 4.0 * delta_ground.y * delta_ground.y)
	
	var ring_cursor_pos: Vector2
	if r_iso > 0.001:
		ring_cursor_pos = ground_center + delta_ground * (r0 / r_iso)
	else:
		ring_cursor_pos = ground_center + Vector2(r0, 0.0)

	# 绘制从地面中心到基准环准心的【地面基准射线】
	draw_line(ground_center, ring_cursor_pos, Color(0.2, 0.9, 1.0, 0.35), 1.0)
	draw_circle(ring_cursor_pos, 3.5, cursor_color)
	draw_arc(ring_cursor_pos, 6.0, 0.0, TAU, 16, cursor_color, 1.0)

	# 6. 计算方向：无俯仰角基准方向 vs 3D 修正瞄准方向
	var base_screen_dir: Vector2 = (ring_cursor_pos - ground_center).normalized()
	var aim_screen_dir: Vector2 = aim_controller.get_screen_aim_direction()
	var laser_len: float = 180.0
	
	# 绘制从胸口射出的【水平基准瞄准线】(半透明青白虚线，θ = 0°)
	var base_end: Vector2 = chest_origin + base_screen_dir * (laser_len * 0.85)
	_draw_dashed_line(chest_origin, base_end, Color(0.3, 0.8, 1.0, 0.3), 1.0, 4.0, 4.0)

	# 绘制从胸口射出的【3D 修正激光瞄准线】(亮金黄虚线)
	var laser_end: Vector2 = chest_origin + aim_screen_dir * laser_len
	_draw_dashed_line(chest_origin, laser_end, laser_color, 1.8, 6.0, 3.5)

	# 7. 夹角弧线与俯仰角数字 HUD 显示
	var pitch_deg: float = aim_controller.get_pitch_degrees()
	var end_color: Color = Color(1.0, 0.4, 0.4, 0.9) if pitch_deg < -3.0 else (Color(0.2, 1.0, 0.5, 0.9) if pitch_deg > 3.0 else cursor_color)
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

