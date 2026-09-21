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
		var raw_lh: float = maxf(ground_c.y - chest_o.y, 4.0)
		# 滞后消抖滤波：角色微幅呼吸/跑动动画不改变出膛高，防止高频击穿椭圆几何缓存
		if absf(raw_lh - aim_controller.launch_height) >= 2.0:
			aim_controller.launch_height = roundf(raw_lh)

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

	var r_min: float = snappedf(aim_controller.call("get_effective_radius_min") if aim_controller.has_method("get_effective_radius_min") else 16.0, 2.0)
	var r0: float = snappedf(aim_controller.call("get_effective_radius_horizontal") if aim_controller.has_method("get_effective_radius_horizontal") else aim_controller.radius_horizontal, 4.0)
	var r_max: float = snappedf(aim_controller.call("get_effective_radius_max") if aim_controller.has_method("get_effective_radius_max") else aim_controller.radius_max, 4.0)

	# 2. 地面基准环绘制 (死区环与 0° 水平环已默认禁用；45° 环改为仅在达到最大仰角时在准星两侧渐变显示)
	var show_deadzone: bool = bool(aim_controller.show_deadzone_ring) if "show_deadzone_ring" in aim_controller else false
	var show_horiz: bool = bool(aim_controller.show_horizontal_ring) if "show_horizontal_ring" in aim_controller else false
	var show_max_arc: bool = bool(aim_controller.show_max_pitch_arc) if "show_max_pitch_arc" in aim_controller else true

	if show_deadzone:
		AimPixelDrawer.draw_cached_solid_ellipse(self, ground_center, r_min, r_min * 0.5, inner_ring_col, 1.0)
	if show_horiz:
		AimPixelDrawer.draw_cached_solid_ellipse(self, ground_center, r0, r0 * 0.5, ring_col, 1.0)

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

	# 45° 最大仰角限制弧 (仅在达到/逼近 45° 最大仰角时在准星两侧平滑透明渐变显示)
	if show_max_arc:
		var max_pitch: float = float(aim_controller.max_pitch_deg) if "max_pitch_deg" in aim_controller else 45.0
		var pitch_deg: float = aim_controller.get_pitch_degrees()
		var activation: float = 0.0
		if pitch_deg >= max_pitch - 1.5:
			activation = clampf((pitch_deg - (max_pitch - 1.5)) / 1.5, 0.0, 1.0)
		elif r_iso >= r_max - 2.0:
			activation = 1.0

		if activation > 0.001:
			var arc_angle: float = float(aim_controller.max_pitch_arc_angle) if "max_pitch_arc_angle" in aim_controller else 0.35
			var arc_segs: int = int(aim_controller.max_pitch_arc_segments) if "max_pitch_arc_segments" in aim_controller else 16
			var center_angle: float = float(aim_controller.azimuth_rad) if "azimuth_rad" in aim_controller else atan2(2.0 * delta_ground.y, delta_ground.x)
			AimPixelDrawer.draw_radial_gradient_ellipse_arc(
				self, ground_center, r_max, r_max * 0.5,
				center_angle, arc_angle, outer_ring_col,
				arc_segs, 1.5, activation
			)

	# 获取 3D 地形自适应重力弹道数据 (优先复用控制器已解算好的轨迹缓存)
	var traj_info: Dictionary = {}
	if "current_trajectory_info" in aim_controller and not aim_controller.current_trajectory_info.is_empty():
		traj_info = aim_controller.current_trajectory_info
	elif aim_controller.has_method("get_terrain_adaptive_trajectory"):
		traj_info = aim_controller.call("get_terrain_adaptive_trajectory", player_ground, p_floor, chest_origin)

	var hit_type: int = traj_info.get("hit_type", 0) if traj_info.get("is_valid", false) else 0

	# 4. 地面引导射线与同层绿色准星点 (角色原点到准星点连线，强化 2.5D 空间感；遇到高层截断并在同层恢复，墙后半透明)
	var show_ray: bool = bool(aim_controller.show_ground_ray) if "show_ground_ray" in aim_controller else true
	var show_point: bool = bool(aim_controller.show_ground_cursor_point) if "show_ground_cursor_point" in aim_controller else true
	var show_cross: bool = bool(aim_controller.show_zero_cross) if "show_zero_cross" in aim_controller else false

	if show_ray:
		var ray_col: Color = aim_controller.ground_ray_color if "ground_ray_color" in aim_controller else Color(ring_col.r, ring_col.g, ring_col.b, 0.4)
		var ray_occ_ratio: float = float(aim_controller.ground_ray_occluded_alpha_ratio) if "ground_ray_occluded_alpha_ratio" in aim_controller else 0.5
		var req_same_fl: bool = false
		if "ground_ray_require_same_floor" in aim_controller and aim_controller.ground_ray_require_same_floor:
			req_same_fl = true
		elif "ground_ray_truncate_only_on_high" in aim_controller and not aim_controller.ground_ray_truncate_only_on_high:
			req_same_fl = true
		AimPixelDrawer.draw_terrain_adaptive_ground_ray(
			self, ground_center, active_cursor_pos, p_floor,
			ray_col, aim_controller, _grid_data,
			ray_occ_ratio, req_same_fl, 1.0, player_ground
		)
	if show_cross and show_horiz:
		AimPixelDrawer.draw_pixel_cross(self, r0_ref_pos, Color(ring_col.r, ring_col.g, ring_col.b, 0.65))

	# 同层绿色准星点 (基准平面投影参考点，空间感核心；若被高墙遮挡同样降低不透明度)
	if show_point:
		var pt_is_occ: bool = false
		if _grid_data and aim_controller != null and aim_controller.has_method("is_point_occluded"):
			pt_is_occ = aim_controller.is_point_occluded(active_cursor_pos, float(p_floor) * 16.0)
		var pt_occ_ratio: float = float(aim_controller.ground_ray_occluded_alpha_ratio) if "ground_ray_occluded_alpha_ratio" in aim_controller else 0.5
		var pt_alpha_scale: float = pt_occ_ratio if pt_is_occ else 1.0
		AimPixelDrawer.draw_pixel_diamond(
			self, active_cursor_pos,
			Color(0.2, 1.0, 0.5, 0.85 * pt_alpha_scale),
			Color(0.1, 0.85, 0.35, 0.95 * pt_alpha_scale),
			Color(0.85, 1.0, 0.85, 0.95 * pt_alpha_scale)
		)

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

		# 6.2 悬崖下坠延长实线段 (黄到红渐变 + 遮挡感知切分)
		if hit_type == -1 and dashed_pts.size() >= 2:
			var cliff_start_col := Color(1.0, 0.88, 0.25, 0.9)  # 醒目金黄色
			var cliff_end_col := Color(1.0, 0.22, 0.22, 0.95)   # 警示鲜红色
			AimPixelDrawer.draw_occlusion_aware_gradient_trajectory(self, dashed_pts, dashed_z, cliff_start_col, cliff_end_col, aim_controller, occ_ratio)

		# 6.3 着弹点 5x5 瓷砖网格在 128x64 椭圆内平滑不透明渐变显示 (消除 2.5D 高低差光学连续假象，包含高墙/地基底部截面)
		var show_grid: bool = bool(aim_controller.show_impact_grid) if "show_impact_grid" in aim_controller else true
		if show_grid and _grid_data:
			var hit_cell: Vector2i = traj_info.get("hit_cell", Vector2i.ZERO)
			var hit_floor: int = traj_info.get("hit_floor", 0)
			var grid_rng: int = int(aim_controller.impact_grid_range) if "impact_grid_range" in aim_controller else 2
			var rx: float = float(aim_controller.impact_grid_radius_x) if "impact_grid_radius_x" in aim_controller else 128.0
			var ry: float = float(aim_controller.impact_grid_radius_y) if "impact_grid_radius_y" in aim_controller else 64.0
			var grid_col: Color = aim_controller.impact_grid_color if "impact_grid_color" in aim_controller else Color(0.45, 0.85, 1.0, 0.6)
			var show_cap: bool = bool(aim_controller.show_impact_cap) if "show_impact_cap" in aim_controller else true
			var cap_col: Color = aim_controller.impact_cap_color if "impact_cap_color" in aim_controller else Color(0.0, 0.0, 0.0, 1.0)
			var cap_tgt: int = int(aim_controller.impact_cap_target) if "impact_cap_target" in aim_controller else 0
			if is_hit_occluded:
				var grid_occ_ratio: float = float(aim_controller.impact_grid_occluded_alpha_ratio) if "impact_grid_occluded_alpha_ratio" in aim_controller else 1.0
				grid_col.a *= grid_occ_ratio
				cap_col.a *= grid_occ_ratio
			IsoGridDrawer.draw_radial_falloff_grid(self, hit_cell, grid_rng, hit_floor, hit_screen_pos, rx, ry, grid_col, _grid_data, 1.0, show_cap, cap_col, cap_tgt)

		# 6.4 着弹点 2:1 像素红色宝石 (若被瓷砖遮挡同步以透视比例渲染)
		var dot_scale := occ_ratio if is_hit_occluded else 1.0
		AimPixelDrawer.draw_pixel_diamond(self, hit_screen_pos,
			Color(1.0, 0.25, 0.25, 0.85 * dot_scale),
			Color(1.0, 0.1, 0.1, 0.95 * dot_scale),
			Color(1.0, 0.85, 0.85, 0.95 * dot_scale))
