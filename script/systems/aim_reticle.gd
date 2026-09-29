# aim_reticle.gd —— 2.5D 等距地面基准光环与 3D 弹道指示器总控 (GPU 着色器加速版)
class_name AimReticle
extends Node2D

const AimPixelDrawer = preload("res://script/systems/aim_pixel_drawer.gd")
const IsoGridDrawer = preload("res://script/systems/iso_grid_drawer.gd")

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

# 每帧基准几何数据缓存 (供各绘制层共享，避免重复计算)
var _frame_ground_pos: Vector2 = Vector2.ZERO
var _frame_cell: Vector2i = Vector2i.ZERO
var _frame_floor: int = 0
var _frame_floor_y: float = 0.0
var _frame_ground_center: Vector2 = Vector2.ZERO
var _frame_chest_origin: Vector2 = Vector2.ZERO
var _frame_active_cursor_pos: Vector2 = Vector2.ZERO
var _frame_r0_ref_pos: Vector2 = Vector2.ZERO
var _frame_r_iso: float = 0.0
var _frame_r_min: float = 16.0
var _frame_r0: float = 32.0
var _frame_r_max: float = 64.0

# ====== GPU 渲染子图层与材质 ======
var _ground_ray_layer: Node2D = null
var _impact_grid_layer: Node2D = null
var _trajectory_layer: Node2D = null
var _overlay_layer: Node2D = null

var _ground_ray_mat: ShaderMaterial = null
var _impact_mat: ShaderMaterial = null
var _traj_mat: ShaderMaterial = null

func _ready() -> void:
	z_index = 150
	_ensure_references()
	_setup_gpu_layers()

## 初始化 GPU 渲染子图层与材质
func _setup_gpu_layers() -> void:
	if _impact_grid_layer != null:
		return

	# 1. 地面引导射线 GPU 层 (显示在自身后方，受高度场遮挡着色器驱动)
	_ground_ray_layer = Node2D.new()
	_ground_ray_layer.name = "GPUGroundRayLayer"
	_ground_ray_layer.show_behind_parent = true
	_ground_ray_mat = ShaderMaterial.new()
	_ground_ray_mat.shader = preload("res://script/shaders/trajectory_occlusion.gdshader")
	_ground_ray_layer.material = _ground_ray_mat
	_ground_ray_layer.draw.connect(_on_ground_ray_draw)
	add_child(_ground_ray_layer)

	# 2. 着弹点 5x5 网格 GPU 层 (由 impact_grid_falloff 着色器驱动椭圆二次衰减)
	_impact_grid_layer = Node2D.new()
	_impact_grid_layer.name = "GPUImpactGridLayer"
	_impact_mat = ShaderMaterial.new()
	_impact_mat.shader = preload("res://script/shaders/impact_grid_falloff.gdshader")
	_impact_grid_layer.material = _impact_mat
	_impact_grid_layer.draw.connect(_on_impact_grid_draw)
	add_child(_impact_grid_layer)

	# 3. 3D 自适应抛物线弹道 GPU 层 (受高度场遮挡着色器驱动，零 CPU 步进)
	_trajectory_layer = Node2D.new()
	_trajectory_layer.name = "GPUTrajectoryLayer"
	_traj_mat = ShaderMaterial.new()
	_traj_mat.shader = preload("res://script/shaders/trajectory_occlusion.gdshader")
	_trajectory_layer.material = _traj_mat
	_trajectory_layer.draw.connect(_on_trajectory_draw)
	add_child(_trajectory_layer)

	# 4. 顶层装饰层 (着弹点红宝石、HUD 文字，置于所有网格和弹道最上方)
	_overlay_layer = Node2D.new()
	_overlay_layer.name = "GPUOverlayLayer"
	_overlay_layer.draw.connect(_on_overlay_draw)
	add_child(_overlay_layer)

# 惰性获取并缓存关键节点引用
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

## 通知所有绘制层同步重绘
func _queue_all_redraw() -> void:
	queue_redraw()
	if is_instance_valid(_ground_ray_layer): _ground_ray_layer.queue_redraw()
	if is_instance_valid(_impact_grid_layer): _impact_grid_layer.queue_redraw()
	if is_instance_valid(_trajectory_layer): _trajectory_layer.queue_redraw()
	if is_instance_valid(_overlay_layer): _overlay_layer.queue_redraw()

## 同步子层显隐状态
func _set_sublayers_visible(vis: bool) -> void:
	if is_instance_valid(_ground_ray_layer): _ground_ray_layer.visible = vis
	if is_instance_valid(_impact_grid_layer): _impact_grid_layer.visible = vis
	if is_instance_valid(_trajectory_layer): _trajectory_layer.visible = vis
	if is_instance_valid(_overlay_layer): _overlay_layer.visible = vis

func _process(delta: float) -> void:
	if not _ensure_references():
		return

	var is_active: bool = bool(aim_controller.get("is_aim_active")) if aim_controller else false

	# 状态切换检测：若激活状态发生改变，立即重绘一帧以确保准星即时响应
	if is_active != _was_aim_active:
		_was_aim_active = is_active
		_update_timer = 0.0
		_set_sublayers_visible(is_active)
		_queue_all_redraw()
		return

	if not is_active:
		return

	# 1. 更新本帧几何基准数据 (单次计算，供所有子层共享)
	_update_frame_geometry()

	# 2. 出膛落差消抖同步
	if "launch_height" in aim_controller:
		var raw_lh: float = maxf(_frame_ground_center.y - _frame_chest_origin.y, 4.0)
		if absf(raw_lh - aim_controller.launch_height) >= 2.0:
			aim_controller.launch_height = roundf(raw_lh)

	# 3. 刷新率节流控制
	var target_hz: float = float(aim_controller.update_rate_hz) if ("update_rate_hz" in aim_controller) else update_rate_hz
	if target_hz <= 0.0:
		_queue_all_redraw()
		return

	_update_timer += delta
	var interval := 1.0 / target_hz
	if _update_timer >= interval:
		_update_timer = fmod(_update_timer, interval)
		_queue_all_redraw()

## 每帧单次计算共享的几何位置
func _update_frame_geometry() -> void:
	_frame_ground_pos = _player.global_position
	_frame_cell = _grid_data.world_to_cell(_frame_ground_pos) if _grid_data else Vector2i.ZERO
	_frame_floor = _grid_data.get_highest_floor(_frame_cell) if _grid_data else 0
	_frame_floor_y = _grid_data.get_floor_pixel_offset(_frame_floor) if _grid_data else 0.0
	_frame_ground_center = _frame_ground_pos + Vector2(0.0, _frame_floor_y)
	_frame_chest_origin = _hand_node.global_position if is_instance_valid(_hand_node) else (_frame_ground_center + Vector2(0.0, -8.0))

	_frame_r_min = snappedf(aim_controller.call("get_effective_radius_min") if aim_controller.has_method("get_effective_radius_min") else 16.0, 2.0)
	_frame_r0 = snappedf(aim_controller.call("get_effective_radius_horizontal") if aim_controller.has_method("get_effective_radius_horizontal") else aim_controller.radius_horizontal, 4.0)
	_frame_r_max = snappedf(aim_controller.call("get_effective_radius_max") if aim_controller.has_method("get_effective_radius_max") else aim_controller.radius_max, 4.0)

	var mouse_screen: Vector2 = get_global_mouse_position()
	var delta_ground: Vector2 = mouse_screen - _frame_ground_center
	_frame_r_iso = sqrt(delta_ground.x * delta_ground.x + 4.0 * delta_ground.y * delta_ground.y)
	var r_clamped: float = clampf(_frame_r_iso, _frame_r_min, _frame_r_max)

	if _frame_r_iso > 0.001:
		_frame_active_cursor_pos = _frame_ground_center + delta_ground * (r_clamped / _frame_r_iso)
		_frame_r0_ref_pos = _frame_ground_center + delta_ground * (_frame_r0 / _frame_r_iso)
	else:
		_frame_active_cursor_pos = _frame_ground_center + Vector2(_frame_r_min, 0.0)
		_frame_r0_ref_pos = _frame_ground_center + Vector2(_frame_r0, 0.0)

func _get_current_trajectory_info() -> Dictionary:
	if not is_instance_valid(aim_controller):
		return {}
	if "current_trajectory_info" in aim_controller and not aim_controller.current_trajectory_info.is_empty():
		return aim_controller.current_trajectory_info
	elif aim_controller.has_method("get_terrain_adaptive_trajectory"):
		return aim_controller.call("get_terrain_adaptive_trajectory", _frame_ground_pos, _frame_floor, _frame_chest_origin)
	return {}

# =========================================================================
# 1. 主层绘制：地面基准环、45° 仰角弧段与绿色同层准星
# =========================================================================
func _draw() -> void:
	if not _ensure_references() or not aim_controller.get("is_aim_active"):
		return

	var ring_col: Color = aim_controller.ring_color if "ring_color" in aim_controller else ring_color
	var inner_ring_col: Color = aim_controller.inner_ring_color if "inner_ring_color" in aim_controller else Color(1.0, 0.45, 0.35, 0.45)
	var outer_ring_col: Color = aim_controller.outer_ring_color if "outer_ring_color" in aim_controller else Color(ring_col.r, ring_col.g, ring_col.b, 0.35)

	var show_deadzone: bool = bool(aim_controller.show_deadzone_ring) if "show_deadzone_ring" in aim_controller else false
	var show_horiz: bool = bool(aim_controller.show_horizontal_ring) if "show_horizontal_ring" in aim_controller else false
	var show_max_arc: bool = bool(aim_controller.show_max_pitch_arc) if "show_max_pitch_arc" in aim_controller else true

	if show_deadzone:
		AimPixelDrawer.draw_cached_solid_ellipse(self, _frame_ground_center, _frame_r_min, _frame_r_min * 0.5, inner_ring_col, 1.0)
	if show_horiz:
		AimPixelDrawer.draw_cached_solid_ellipse(self, _frame_ground_center, _frame_r0, _frame_r0 * 0.5, ring_col, 1.0)

	# 45° 最大仰角限制弧 (仅在达到/逼近 45° 最大仰角时在准星两侧平滑渐变显示)
	if show_max_arc:
		var max_pitch: float = float(aim_controller.max_pitch_deg) if "max_pitch_deg" in aim_controller else 45.0
		var pitch_deg: float = aim_controller.get_pitch_degrees()
		var activation: float = 0.0
		if pitch_deg >= max_pitch - 1.5:
			activation = clampf((pitch_deg - (max_pitch - 1.5)) / 1.5, 0.0, 1.0)
		elif _frame_r_iso >= _frame_r_max - 2.0:
			activation = 1.0

		if activation > 0.001:
			var delta_ground := _frame_active_cursor_pos - _frame_ground_center
			var arc_angle: float = float(aim_controller.max_pitch_arc_angle) if "max_pitch_arc_angle" in aim_controller else 0.35
			var arc_segs: int = int(aim_controller.max_pitch_arc_segments) if "max_pitch_arc_segments" in aim_controller else 16
			var center_angle: float = float(aim_controller.azimuth_rad) if "azimuth_rad" in aim_controller else atan2(2.0 * delta_ground.y, delta_ground.x)
			AimPixelDrawer.draw_radial_gradient_ellipse_arc(
				self, _frame_ground_center, _frame_r_max, _frame_r_max * 0.5,
				center_angle, arc_angle, outer_ring_col,
				arc_segs, 1.5, activation
			)

	# 同层基准点 (绿色菱形标记)
	var show_point: bool = bool(aim_controller.show_ground_cursor_point) if "show_ground_cursor_point" in aim_controller else true
	if show_point:
		var pt_is_occ: bool = false
		if _grid_data and aim_controller != null and aim_controller.has_method("is_point_occluded"):
			pt_is_occ = aim_controller.is_point_occluded(_frame_active_cursor_pos, float(_frame_floor) * 16.0)
		var pt_occ_ratio: float = float(aim_controller.ground_ray_occluded_alpha_ratio) if "ground_ray_occluded_alpha_ratio" in aim_controller else 0.5
		var pt_alpha_scale: float = pt_occ_ratio if pt_is_occ else 1.0
		AimPixelDrawer.draw_pixel_diamond(
			self, _frame_active_cursor_pos,
			Color(0.2, 1.0, 0.5, 0.85 * pt_alpha_scale),
			Color(0.1, 0.85, 0.35, 0.95 * pt_alpha_scale),
			Color(0.85, 1.0, 0.85, 0.95 * pt_alpha_scale)
		)

	# 0° 水平基准十字标记
	var show_cross: bool = bool(aim_controller.show_zero_cross) if "show_zero_cross" in aim_controller else false
	if show_cross and show_horiz:
		AimPixelDrawer.draw_pixel_cross(self, _frame_r0_ref_pos, Color(ring_col.r, ring_col.g, ring_col.b, 0.65))

# =========================================================================
# 2. 地面引导射线 GPU 层 (片元级高度场截断与遮挡半透明)
# =========================================================================
func _on_ground_ray_draw() -> void:
	if not _ensure_references() or not aim_controller.get("is_aim_active"):
		return
	var show_ray: bool = bool(aim_controller.show_ground_ray) if "show_ground_ray" in aim_controller else true
	if not show_ray or _grid_data == null:
		return

	var ring_col: Color = aim_controller.ring_color if "ring_color" in aim_controller else ring_color
	var ray_col: Color = aim_controller.ground_ray_color if "ground_ray_color" in aim_controller else Color(ring_col.r, ring_col.g, ring_col.b, 0.4)
	var ray_occ_ratio: float = float(aim_controller.ground_ray_occluded_alpha_ratio) if "ground_ray_occluded_alpha_ratio" in aim_controller else 0.5
	var req_same_fl: bool = false
	if "ground_ray_require_same_floor" in aim_controller and aim_controller.ground_ray_require_same_floor:
		req_same_fl = true
	elif "ground_ray_truncate_only_on_high" in aim_controller and not aim_controller.ground_ray_truncate_only_on_high:
		req_same_fl = true

	# 注入 GPU Shader 参数
	_ground_ray_mat.set_shader_parameter("height_map_tex", _grid_data.get_height_map_texture())
	_ground_ray_mat.set_shader_parameter("visual_color", ray_col)
	_ground_ray_mat.set_shader_parameter("occluded_alpha_ratio", ray_occ_ratio)
	_ground_ray_mat.set_shader_parameter("is_ground_ray", true)
	_ground_ray_mat.set_shader_parameter("player_floor", float(_frame_floor))
	_ground_ray_mat.set_shader_parameter("require_same_floor", req_same_fl)

	# 提交几何线段 (顶点 R 通道编码物理 Z 高度，Shader 片元级自动测试截断与半透明)
	var delta := _frame_active_cursor_pos - _frame_ground_center
	var dist := delta.length()
	if dist < 1.0:
		return

	var steps := clampi(int(ceil(dist / 4.0)), 2, 48)
	var pts := PackedVector2Array()
	pts.resize(steps + 1)
	var cols := PackedColorArray()
	cols.resize(steps + 1)
	var norm_z := (float(_frame_floor) * 16.0) / 256.0
	var col_z := Color(norm_z, 0.0, 0.0, 1.0)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		pts[i] = (_frame_ground_center.lerp(_frame_active_cursor_pos, t)).round()
		cols[i] = col_z

	_ground_ray_layer.draw_polyline_colors(pts, cols, 1.0)

# =========================================================================
# 3. 着弹点网格 GPU 层 (5x5 地砖几何单次提交，Shader 片元级椭圆衰减)
# =========================================================================
func _on_impact_grid_draw() -> void:
	if not _ensure_references() or not aim_controller.get("is_aim_active"):
		return
	var show_grid: bool = bool(aim_controller.show_impact_grid) if "show_impact_grid" in aim_controller else true
	if not show_grid or _grid_data == null:
		return

	var traj_info: Dictionary = _get_current_trajectory_info()
	if traj_info.is_empty() or not traj_info.get("is_valid", false):
		return

	var hit_cell: Vector2i = traj_info.get("hit_cell", Vector2i.ZERO)
	var hit_floor: int = traj_info.get("hit_floor", 0)
	var hit_screen_pos: Vector2 = traj_info.get("hit_screen_pos", Vector2.ZERO)
	var is_hit_occluded: bool = traj_info.get("is_hit_occluded", false)
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

	# 注入 GPU 衰减 Shader 参数
	_impact_mat.set_shader_parameter("hit_world_pos", hit_screen_pos)
	_impact_mat.set_shader_parameter("radius_x", rx)
	_impact_mat.set_shader_parameter("radius_y", ry)

	# 提交几何多边形与边框线，GPU 片元级自动进行二次椭圆衰减
	IsoGridDrawer.draw_gpu_radial_falloff_grid(
		_impact_grid_layer, hit_cell, grid_rng, hit_floor, _grid_data,
		grid_col, 1.0, show_cap, cap_col, cap_tgt
	)

# =========================================================================
# 4. 抛物线弹道 GPU 层 (Shader 片元级高度场遮挡与渐变)
# =========================================================================
func _on_trajectory_draw() -> void:
	if not _ensure_references() or not aim_controller.get("is_aim_active"):
		return

	var traj_info: Dictionary = _get_current_trajectory_info()
	if traj_info.is_empty() or not traj_info.get("is_valid", false):
		return

	var primary_pts: PackedVector2Array = traj_info.get("primary_points", PackedVector2Array())
	var primary_z: PackedFloat32Array = traj_info.get("primary_z", PackedFloat32Array())
	var dashed_pts: PackedVector2Array = traj_info.get("dashed_points", PackedVector2Array())
	var dashed_z: PackedFloat32Array = traj_info.get("dashed_z", PackedFloat32Array())
	var hit_type: int = traj_info.get("hit_type", 0)

	var traj_col: Color = aim_controller.trajectory_color if "trajectory_color" in aim_controller else Color(0.4, 0.8, 1.0, 0.85)
	var occ_ratio: float = float(aim_controller.trajectory_occluded_alpha_ratio) if "trajectory_occluded_alpha_ratio" in aim_controller else 0.5

	# 注入 GPU 遮挡 Shader 参数
	_traj_mat.set_shader_parameter("height_map_tex", _grid_data.get_height_map_texture())
	_traj_mat.set_shader_parameter("visual_color", traj_col)
	_traj_mat.set_shader_parameter("occluded_alpha_ratio", occ_ratio)
	_traj_mat.set_shader_parameter("is_ground_ray", false)

	# 4.1 主弹道折线：一次性提交，R 通道传递 3D 物理 Z，片元级全自动半透明透视
	var n := primary_pts.size()
	if n >= 2 and primary_z.size() == n:
		var pts := PackedVector2Array()
		pts.resize(n)
		var cols := PackedColorArray()
		cols.resize(n)
		for i in range(n):
			pts[i] = primary_pts[i].round()
			cols[i] = Color(primary_z[i] / 256.0, 0.0, 0.0, 1.0)
		_trajectory_layer.draw_polyline_colors(pts, cols, 1.0)

	# 4.2 悬崖下坠延长段：金黄到警示鲜红渐变 + 片元级全自动遮挡
	if hit_type == -1 and dashed_pts.size() >= 2 and dashed_z.size() == dashed_pts.size():
		var m := dashed_pts.size()
		var pts_cliff := PackedVector2Array()
		pts_cliff.resize(m)
		var cols_cliff := PackedColorArray()
		cols_cliff.resize(m)
		_traj_mat.set_shader_parameter("gradient_start_color", Color(1.0, 0.88, 0.25, 0.9))
		_traj_mat.set_shader_parameter("gradient_end_color", Color(1.0, 0.22, 0.22, 0.95))
		for i in range(m):
			pts_cliff[i] = dashed_pts[i].round()
			var t := float(i) / float(m - 1)
			cols_cliff[i] = Color(dashed_z[i] / 256.0, maxf(t, 0.001), 0.0, 1.0)
		_trajectory_layer.draw_polyline_colors(pts_cliff, cols_cliff, 1.0)

# =========================================================================
# 5. 顶层装饰层 (着弹点红宝石、HUD 文字，绘制于最顶层)
# =========================================================================
func _on_overlay_draw() -> void:
	if not _ensure_references() or not aim_controller.get("is_aim_active"):
		return

	var traj_info: Dictionary = _get_current_trajectory_info()
	var occ_ratio: float = float(aim_controller.trajectory_occluded_alpha_ratio) if "trajectory_occluded_alpha_ratio" in aim_controller else 0.5
	var cursor_col: Color = aim_controller.cursor_color if "cursor_color" in aim_controller else cursor_color

	# 5.1 角色身旁俯仰角 HUD 显示
	var pitch_deg: float = aim_controller.get_pitch_degrees()
	var end_color: Color = Color(1.0, 0.4, 0.4, 0.9) if pitch_deg < -3.0 else (Color(0.2, 1.0, 0.5, 0.9) if pitch_deg > 3.0 else cursor_col)
	var text_str := ("%+d°" % int(round(pitch_deg))) if absf(pitch_deg) >= 0.5 else "0°"
	var default_font: Font = ThemeDB.fallback_font
	var font_size: int = 12
	var str_size := default_font.get_string_size(text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

	var text_pos: Vector2
	var delta_ground := _frame_active_cursor_pos - _frame_ground_center
	if delta_ground.x >= 0.0:
		text_pos = (_frame_chest_origin + Vector2(16.0, -10.0)).round()
	else:
		text_pos = (_frame_chest_origin + Vector2(-16.0 - str_size.x, -10.0)).round()

	_overlay_layer.draw_string_outline(default_font, text_pos, text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color(0.0, 0.0, 0.0, 0.85))
	_overlay_layer.draw_string(default_font, text_pos, text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, end_color)

	# 5.2 着弹点 2:1 像素红色宝石
	if not traj_info.is_empty() and traj_info.get("is_valid", false):
		var hit_screen_pos: Vector2 = traj_info.get("hit_screen_pos", Vector2.ZERO)
		var is_hit_occluded: bool = traj_info.get("is_hit_occluded", false)
		var dot_scale := occ_ratio if is_hit_occluded else 1.0
		AimPixelDrawer.draw_pixel_diamond(
			_overlay_layer, hit_screen_pos,
			Color(1.0, 0.25, 0.25, 0.85 * dot_scale),
			Color(1.0, 0.1, 0.1, 0.95 * dot_scale),
			Color(1.0, 0.85, 0.85, 0.95 * dot_scale)
		)
