# aim_reticle.gd —— 2.5D 等距地面基准光环与 3D 弹道指示器总控
class_name AimReticle
extends Node2D

const AimPixelDrawer = preload("res://script/systems/aim_pixel_drawer.gd")

@export var player_path: NodePath
var aim_controller: Node

# 视觉颜色配置 (可由 AimController 动态覆盖)
var ring_color: Color = Color(0.2, 0.9, 1.0, 0.6)        # 基准水平环 (亮青色)
var cursor_color: Color = Color(0.2, 1.0, 0.5, 0.9)       # 准心指示器 (亮绿)
var deadzone_color: Color = Color(1.0, 0.3, 0.3, 0.45)    # 死区环 (淡红)
var laser_color: Color = Color(1.0, 0.95, 0.2, 0.85)      # 激光瞄准线 (亮金黄)

@export_group("性能与更新频率 (Performance & Tick Rate)")
## 准星与瞄准线重绘刷新率 (Hz，默认 60.0 次/秒；若 <= 0 则跟随渲染帧率无限制刷新)
@export var update_rate_hz: float = 60.0

# 惰性持久化节点缓存 (消除每帧多次 find_child 开销)
var _player: Node2D = null
var _hand_node: Node2D = null
var _grid_data: Node = null
var _update_timer: float = 0.0
var _was_aim_active: bool = false

func _ready() -> void:
	z_index = 150
	_ensure_references()

# 惰性获取并缓存关键节点引用 (仅在失效时重新查找，性能开销接近于 0)
func _ensure_references() -> bool:
	if not is_instance_valid(_player):
		_player = get_node_or_null(player_path) as Node2D
		if _player == null and get_tree() and get_tree().root:
			_player = get_tree().root.find_child("CharacterBody2D", true, false) as Node2D

	if is_instance_valid(_player):
		if not is_instance_valid(aim_controller):
			aim_controller = _player.find_child("AimController", true, false)
		if not is_instance_valid(_hand_node):
			_hand_node = _player.find_child("hand", true, false) as Node2D

	if not is_instance_valid(_grid_data) and get_tree() and get_tree().root:
		_grid_data = get_tree().root.get_node_or_null("GridData")
		if _grid_data == null and Engine.has_singleton("GridData"):
			_grid_data = Engine.get_singleton("GridData")

	return is_instance_valid(_player) and is_instance_valid(aim_controller)

func _process(delta: float) -> void:
	if not _ensure_references():
		return

	var is_active: bool = bool(aim_controller.get("is_aim_active")) if aim_controller else false

	# 状态切换检测：若激活状态发生改变，立即重绘一帧以确保准星即时响应，零延迟切换
	if is_active != _was_aim_active:
		_was_aim_active = is_active
		_update_timer = 0.0
		queue_redraw()
		return

	if not is_active:
		return

	# 解耦物理状态同步：将 hand_height 出膛落差同步放在 _process，保证 _draw 纯只读无副作用
	var p_ground := _player.global_position
	var p_cell: Vector2i = _grid_data.world_to_cell(p_ground) if _grid_data else Vector2i.ZERO
	var p_floor: int = _grid_data.get_highest_floor(p_cell) if _grid_data else 0
	var floor_y: float = _grid_data.get_floor_pixel_offset(p_floor) if _grid_data else 0.0
	var ground_c := p_ground + Vector2(0.0, floor_y)
	var chest_o := _hand_node.global_position if is_instance_valid(_hand_node) else (ground_c + Vector2(0.0, -8.0))

	if "launch_height" in aim_controller:
		aim_controller.launch_height = maxf(ground_c.y - chest_o.y, 4.0)

	# 刷新率节流控制
	var target_hz: float = float(aim_controller.update_rate_hz) if ("update_rate_hz" in aim_controller) else update_rate_hz
	if target_hz <= 0.0:
		queue_redraw()
		return

	_update_timer += delta
	var interval := 1.0 / target_hz
	if _update_timer >= interval:
		_update_timer = fmod(_update_timer, interval)
		queue_redraw()

func _draw() -> void:
	if not _ensure_references() or not aim_controller.get("is_aim_active"):
		return

	# 1. 读取视觉配置与尺寸 (支持道具定制化动态覆盖)
	var ring_col: Color = aim_controller.ring_color if "ring_color" in aim_controller else ring_color
	var inner_ring_col: Color = aim_controller.inner_ring_color if "inner_ring_color" in aim_controller else Color(1.0, 0.45, 0.35, 0.45)
	var outer_ring_col: Color = aim_controller.outer_ring_color if "outer_ring_color" in aim_controller else Color(ring_col.r, ring_col.g, ring_col.b, 0.35)
	var cursor_col: Color = aim_controller.cursor_color if "cursor_color" in aim_controller else cursor_color

	var player_ground: Vector2 = _player.global_position
	var player_cell: Vector2i = _grid_data.world_to_cell(player_ground) if _grid_data else Vector2i.ZERO
	var p_floor: int = _grid_data.get_highest_floor(player_cell) if _grid_data else 0
	var floor_y_lift: float = _grid_data.get_floor_pixel_offset(p_floor) if _grid_data else 0.0
	var ground_center := player_ground + Vector2(0.0, floor_y_lift)
	var chest_origin: Vector2 = _hand_node.global_position if is_instance_valid(_hand_node) else (ground_center + Vector2(0.0, -8.0))

	var r_min: float = aim_controller.call("get_effective_radius_min") if aim_controller.has_method("get_effective_radius_min") else 16.0
	var r0: float = aim_controller.call("get_effective_radius_horizontal") if aim_controller.has_method("get_effective_radius_horizontal") else aim_controller.radius_horizontal
	var r_max: float = aim_controller.call("get_effective_radius_max") if aim_controller.has_method("get_effective_radius_max") else aim_controller.radius_max

	# 2. 绘制地面三环 (享元缓存 + GPU 变换，单帧 0 次三角运算)
	AimPixelDrawer.draw_cached_dashed_ellipse(self, ground_center, r_min, r_min * 0.5, inner_ring_col, 1.0, 4.0, 4.0)
	AimPixelDrawer.draw_cached_solid_ellipse(self, ground_center, r0, r0 * 0.5, ring_col, 1.0)
	AimPixelDrawer.draw_cached_dashed_ellipse(self, ground_center, r_max, r_max * 0.5, outer_ring_col, 1.0, 6.0, 5.0)

	# 3. 鼠标等距投影与基准标记计算
	var mouse_screen: Vector2 = get_global_mouse_position()
	var delta_ground: Vector2 = mouse_screen - ground_center
	var r_iso: float = sqrt(delta_ground.x * delta_ground.x + 4.0 * delta_ground.y * delta_ground.y)
	var r_clamped: float = clampf(r_iso, r_min, r_max)

	var active_cursor_pos: Vector2
	var r0_ref_pos: Vector2
	if r_iso > 0.001:
		active_cursor_pos = ground_center + delta_ground * (r_clamped / r_iso)
		r0_ref_pos = ground_center + delta_ground * (r0 / r_iso)
	else:
		active_cursor_pos = ground_center + Vector2(r_min, 0.0)
		r0_ref_pos = ground_center + Vector2(r0, 0.0)

	# 获取 3D 地形自适应重力弹道数据
	var traj_info: Dictionary = {}
	if aim_controller.has_method("get_terrain_adaptive_trajectory"):
		traj_info = aim_controller.call("get_terrain_adaptive_trajectory", player_ground, p_floor, chest_origin)

	var hit_type: int = traj_info.get("hit_type", 0) if traj_info.get("is_valid", false) else 0

	# 4. 地面引导射线与 0° 参考十字
	draw_line(ground_center.round(), active_cursor_pos.round(), Color(ring_col.r, ring_col.g, ring_col.b, 0.35), 1.0, false)
	AimPixelDrawer.draw_pixel_cross(self, r0_ref_pos, Color(ring_col.r, ring_col.g, ring_col.b, 0.65))

	# 跨层时 (高台截断 hit_type==1 或 悬崖下坠 hit_type==-1) 在基准环显示 2:1 绿色瞄准原点
	if hit_type != 0:
		AimPixelDrawer.draw_pixel_diamond(self, active_cursor_pos, Color(0.2, 1.0, 0.5, 0.85), Color(0.1, 0.85, 0.35, 0.95), Color(0.85, 1.0, 0.85, 0.95))

	# 5. 角色身旁俯仰角 HUD 显示
	var pitch_deg: float = aim_controller.get_pitch_degrees()
	var end_color: Color = Color(1.0, 0.4, 0.4, 0.9) if pitch_deg < -3.0 else (Color(0.2, 1.0, 0.5, 0.9) if pitch_deg > 3.0 else cursor_col)
	var text_str := ("%+d°" % int(round(pitch_deg))) if absf(pitch_deg) >= 0.5 else "0°"
	var default_font: Font = ThemeDB.fallback_font
	var font_size: int = 12
	var str_size := default_font.get_string_size(text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

	var text_pos: Vector2
	if delta_ground.x >= 0.0:
		text_pos = (chest_origin + Vector2(16.0, -10.0)).round()
	else:
		text_pos = (chest_origin + Vector2(-16.0 - str_size.x, -10.0)).round()

	draw_string_outline(default_font, text_pos, text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color(0.0, 0.0, 0.0, 0.85))
	draw_string(default_font, text_pos, text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, end_color)

	# 6. 3D 地形自适应重力弹道指示线 (遮挡处 50% 透明度透视)
	if not traj_info.is_empty() and traj_info.get("is_valid", false):
		var primary_pts: PackedVector2Array = traj_info.get("primary_points", PackedVector2Array())
		var primary_z: PackedFloat32Array = traj_info.get("primary_z", PackedFloat32Array())
		var dashed_pts: PackedVector2Array = traj_info.get("dashed_points", PackedVector2Array())
		var dashed_z: PackedFloat32Array = traj_info.get("dashed_z", PackedFloat32Array())
		var hit_screen_pos: Vector2 = traj_info.get("hit_screen_pos", Vector2.ZERO)
		var is_hit_occluded: bool = traj_info.get("is_hit_occluded", false)
		var traj_col: Color = aim_controller.trajectory_color if "trajectory_color" in aim_controller else Color(0.4, 0.8, 1.0, 0.85)
		var occ_ratio: float = float(aim_controller.trajectory_occluded_alpha_ratio) if "trajectory_occluded_alpha_ratio" in aim_controller else 0.5

		# 6.1 实线主弹道 (遮挡感知切分)
		AimPixelDrawer.draw_occlusion_aware_trajectory(self, primary_pts, primary_z, traj_col, aim_controller, false, occ_ratio)

		# 6.2 悬崖下坠虚线段 (遮挡感知切分)
		if hit_type == -1 and dashed_pts.size() >= 2:
			AimPixelDrawer.draw_occlusion_aware_trajectory(self, dashed_pts, dashed_z, Color(traj_col.r, traj_col.g, traj_col.b, 0.85), aim_controller, true, occ_ratio)

		# 6.3 着弹点 2:1 像素红色宝石 (若被瓷砖遮挡同步以透视比例渲染)
		var dot_scale := occ_ratio if is_hit_occluded else 1.0
		AimPixelDrawer.draw_pixel_diamond(self, hit_screen_pos,
			Color(1.0, 0.25, 0.25, 0.85 * dot_scale),
			Color(1.0, 0.1, 0.1, 0.95 * dot_scale),
			Color(1.0, 0.85, 0.85, 0.95 * dot_scale))
