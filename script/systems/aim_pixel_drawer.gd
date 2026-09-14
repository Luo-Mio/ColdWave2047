# aim_pixel_drawer.gd —— 2:1 等距像素艺术绘制器与享元几何缓存核心
class_name AimPixelDrawer
extends RefCounted

# 静态几何享元缓存 (跨帧全局共享，零每帧 GC 垃圾分配)
static var _solid_cache: Dictionary = {}
static var _dashed_cache: Dictionary = {}

# 清空几何缓存 (通常在分辨率或全局图集发生大幅变动时调用)
static func clear_cache() -> void:
	_solid_cache.clear()
	_dashed_cache.clear()

# =========================================================================
# 1. 2:1 等距椭圆享元缓存与绘制 (利用 draw_set_transform 直接 GPU 变换)
# =========================================================================

# 绘制 2:1 像素风格等距实线椭圆 (全量命中缓存时单帧 0 次三角运算，0 次数组分配)
static func draw_cached_solid_ellipse(ci: CanvasItem, center: Vector2, rx: float, ry: float, color: Color, _width: float = 1.0) -> void:
	var k := Vector2(round(rx), round(ry))
	var pts: PackedVector2Array
	if _solid_cache.has(k):
		pts = _solid_cache[k]
	else:
		pts = _generate_solid_ellipse(k.x, k.y)
		_solid_cache[k] = pts

	if pts.size() >= 2:
		ci.draw_set_transform(center.round(), 0.0, Vector2.ONE)
		ci.draw_polyline(pts, color, 1.0, false)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 绘制 2:1 等距椭圆在指定方位角两侧带透明渐变的弧段 (用于 45° 最大仰角触顶视觉提示)
static func draw_radial_gradient_ellipse_arc(
	ci: CanvasItem,
	center: Vector2,
	rx: float,
	ry: float,
	center_angle: float,
	half_arc_angle: float,
	base_color: Color,
	segments: int = 16,
	width: float = 1.0,
	activation: float = 1.0
) -> void:
	if ci == null or activation <= 0.001 or base_color.a <= 0.001 or half_arc_angle <= 0.001:
		return

	var num_pts := segments * 2 + 1
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	pts.resize(num_pts)
	cols.resize(num_pts)

	var c_round := center.round()
	var step_inv := 1.0 / float(segments)

	for i in range(-segments, segments + 1):
		var idx := i + segments
		var t := float(i) * step_inv # -1.0 ~ 1.0
		var angle := center_angle + t * half_arc_angle
		var pt := c_round + Vector2(round(cos(angle) * rx), round(sin(angle) * ry))
		pts[idx] = pt

		# 平滑二次衰减透明度：中心 100%，两端平滑渐变归零
		var fade := 1.0 - t * t
		var alpha := fade * base_color.a * activation
		cols[idx] = Color(base_color.r, base_color.g, base_color.b, alpha)

	ci.draw_polyline_colors(pts, cols, width, false)

# 生成局部相对 (0, 0) 的整像素椭圆点序列 (步长自适应，单次生成仅 ~70us)
static func _generate_solid_ellipse(rx: float, ry: float) -> PackedVector2Array:
	var steps := clampi(int(TAU * rx * 0.35), 64, 256)
	var pts := PackedVector2Array()
	pts.resize(steps + 1)
	for i in range(steps + 1):
		var th := (float(i) / float(steps)) * TAU
		pts[i] = Vector2(round(cos(th) * rx), round(sin(th) * ry))
	return pts

# 绘制 2:1 像素风格等距虚线椭圆 (缓存各虚线段，单帧 0 次几何计算)
static func draw_cached_dashed_ellipse(ci: CanvasItem, center: Vector2, rx: float, ry: float, color: Color, _width: float = 1.0, dash_len: float = 4.0, gap_len: float = 4.0) -> void:
	var k := Vector4(round(rx), round(ry), dash_len, gap_len)
	var dashes: Array
	if _dashed_cache.has(k):
		dashes = _dashed_cache[k]
	else:
		dashes = _generate_dashed_ellipse(k.x, k.y, dash_len, gap_len)
		_dashed_cache[k] = dashes

	if dashes.is_empty():
		return

	ci.draw_set_transform(center.round(), 0.0, Vector2.ONE)
	for d in dashes:
		var dash: PackedVector2Array = d
		if dash.size() >= 2:
			ci.draw_polyline(dash, color, 1.0, false)
		elif dash.size() == 1:
			ci.draw_rect(Rect2(dash[0], Vector2(1, 1)), color)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# 生成局部相对 (0, 0) 的虚线分段序列
static func _generate_dashed_ellipse(rx: float, ry: float, dash_len: float, gap_len: float) -> Array:
	var steps := maxi(int(TAU * rx), 72)
	var unique_pts := PackedVector2Array()
	var last_p := Vector2(-99999, -99999)
	for i in range(steps + 1):
		var th := (float(i) / float(steps)) * TAU
		var p := Vector2(round(cos(th) * rx), round(sin(th) * ry))
		if p != last_p:
			unique_pts.push_back(p)
			last_p = p

	var dashes: Array = []
	if unique_pts.size() < 2:
		return dashes

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
				if not current_dash.is_empty():
					dashes.append(current_dash.duplicate())
				current_dash.clear()
				is_drawing = false
				curr_budget = int(gap_len)
			else:
				is_drawing = true
				curr_budget = int(dash_len)

	if is_drawing and not current_dash.is_empty():
		dashes.append(current_dash.duplicate())

	return dashes

# =========================================================================
# 2. 经典像素艺术图元 (钻石标记、十字准星与虚线折线)
# =========================================================================

# 绘制严格 8x5 像素 2:1 等距宝石菱形标记 (外边框 + 填充色 + 中心高亮核)
static func draw_pixel_diamond(ci: CanvasItem, center: Vector2, fill_color: Color, outline_color: Color, core_color: Color = Color(1.0, 1.0, 1.0, 0.95)) -> void:
	var c := center.round()
	# 顶层 (y = -2): 2px 宽外边框
	ci.draw_rect(Rect2(c.x - 1, c.y - 2, 2, 1), outline_color)
	# 次顶层 (y = -1): 6px 宽 (外边框各 1px, 内部填充 4px)
	ci.draw_rect(Rect2(c.x - 3, c.y - 1, 1, 1), outline_color)
	ci.draw_rect(Rect2(c.x - 2, c.y - 1, 4, 1), fill_color)
	ci.draw_rect(Rect2(c.x + 2, c.y - 1, 1, 1), outline_color)
	# 中间层 (y = 0): 8px 宽 (外边框各 1px, 填充各 2px, 中心 2px 高亮核)
	ci.draw_rect(Rect2(c.x - 4, c.y, 1, 1), outline_color)
	ci.draw_rect(Rect2(c.x - 3, c.y, 2, 1), fill_color)
	ci.draw_rect(Rect2(c.x - 1, c.y, 2, 1), core_color)
	ci.draw_rect(Rect2(c.x + 1, c.y, 2, 1), fill_color)
	ci.draw_rect(Rect2(c.x + 3, c.y, 1, 1), outline_color)
	# 次底层 (y = +1): 6px 宽
	ci.draw_rect(Rect2(c.x - 3, c.y + 1, 1, 1), outline_color)
	ci.draw_rect(Rect2(c.x - 2, c.y + 1, 4, 1), fill_color)
	ci.draw_rect(Rect2(c.x + 2, c.y + 1, 1, 1), outline_color)
	# 底层 (y = +2): 2px 宽外边框
	ci.draw_rect(Rect2(c.x - 1, c.y + 2, 2, 1), outline_color)

# 绘制 3x3 像素十字标记 (用于基准水平环 0° 参考点)
static func draw_pixel_cross(ci: CanvasItem, center: Vector2, color: Color) -> void:
	var ref_c := center.round()
	ci.draw_rect(Rect2(ref_c.x - 1, ref_c.y, 3, 1), color)
	ci.draw_rect(Rect2(ref_c.x, ref_c.y - 1, 1, 3), color)

# 沿折线路径绘制像素风格虚线 (用于悬崖下坠延伸弹道)
static func draw_pixel_dashed_polyline(ci: CanvasItem, points: PackedVector2Array, color: Color, _width: float = 1.0, dash_len: float = 4.0, gap_len: float = 3.5) -> void:
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
				ci.draw_line(start_pt, end_pt, color, 1.0, false)

			walked += step
			current_remaining -= step

			if current_remaining <= 0.0001:
				is_drawing = not is_drawing
				current_remaining = dash_len if is_drawing else gap_len

# =========================================================================
# 3. 遮挡感知弹道分段绘制 (未遮挡 100% / 瓷砖遮挡 50% 半透明透视)
# =========================================================================

# 绘制自适应遮挡弹道线（在被瓷砖遮挡处将透明度降低至 occluded_ratio，默认 50%）
static func draw_occlusion_aware_trajectory(ci: CanvasItem, pts: PackedVector2Array, z_vals: PackedFloat32Array, color: Color, aim_controller: Node, is_dashed: bool = false, occluded_ratio: float = 0.5) -> void:
	if pts.size() < 2:
		return
	if occluded_ratio >= 0.99 or z_vals.size() != pts.size() or aim_controller == null or not aim_controller.has_method("is_point_occluded"):
		var snapped := PackedVector2Array()
		snapped.resize(pts.size())
		for i in range(pts.size()):
			snapped[i] = pts[i].round()
		if is_dashed:
			draw_pixel_dashed_polyline(ci, snapped, color, 1.0, 4.0, 3.5)
		else:
			ci.draw_polyline(snapped, color, 1.0, false)
		return

	var color_occluded := Color(color.r, color.g, color.b, color.a * occluded_ratio)

	# 1. 预先获取每个顶点的遮挡状态 (直接方法调用，消除动态反射 call 开销)
	var occ_status: Array[bool] = []
	occ_status.resize(pts.size())
	for i in range(pts.size()):
		occ_status[i] = aim_controller.is_point_occluded(pts[i], z_vals[i])

	# 2. 逐段切分并按条带批次绘制（交界处 3 轮二分查找，实现 +-0.5px 精准无缝衔接）
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
				var occ_mid: bool = aim_controller.is_point_occluded(s_mid, z_mid)
				if occ_mid == occ0:
					t0 = t_mid
				else:
					t1 = t_mid

			var split_pt := p0.lerp(p1, (t0 + t1) * 0.5).round()
			if current_strip.is_empty() or current_strip[-1] != split_pt:
				current_strip.push_back(split_pt)

			_flush_trajectory_strip(ci, current_strip, current_mode, color, color_occluded, is_dashed)

			current_mode = occ1
			current_strip.clear()
			current_strip.push_back(split_pt)
			var p1_round := p1.round()
			if split_pt != p1_round:
				current_strip.push_back(p1_round)

	if not current_strip.is_empty():
		_flush_trajectory_strip(ci, current_strip, current_mode, color, color_occluded, is_dashed)

static func _flush_trajectory_strip(ci: CanvasItem, strip: PackedVector2Array, is_occluded: bool, normal_col: Color, occluded_col: Color, is_dashed: bool) -> void:
	if strip.size() < 2:
		return
	if is_occluded and occluded_col.a <= 0.001:
		return
	var col := occluded_col if is_occluded else normal_col
	if is_dashed:
		draw_pixel_dashed_polyline(ci, strip, col, 1.0, 4.0, 3.5)
	else:
		ci.draw_polyline(strip, col, 1.0, false)

# 绘制自适应遮挡渐变实线弹道（用于悬崖延长段等，从起点到终点平滑颜色渐变，遮挡处自动半透明透视）
static func draw_occlusion_aware_gradient_trajectory(ci: CanvasItem, pts: PackedVector2Array, z_vals: PackedFloat32Array, start_color: Color, end_color: Color, aim_controller: Node, occluded_ratio: float = 0.5) -> void:
	var n := pts.size()
	if n < 2:
		return
	if occluded_ratio >= 0.99 or z_vals.size() != n or aim_controller == null or not aim_controller.has_method("is_point_occluded"):
		var snapped := PackedVector2Array()
		snapped.resize(n)
		var cols := PackedColorArray()
		cols.resize(n)
		for i in range(n):
			snapped[i] = pts[i].round()
			var t := float(i) / float(n - 1)
			cols[i] = start_color.lerp(end_color, t)
		ci.draw_polyline_colors(snapped, cols, 1.0)
		return

	var occ_status: Array[bool] = []
	occ_status.resize(n)
	for i in range(n):
		occ_status[i] = aim_controller.is_point_occluded(pts[i], z_vals[i])

	var current_mode: bool = occ_status[0]
	var current_strip := PackedVector2Array()
	var current_cols := PackedColorArray()

	var col0 := start_color
	if current_mode:
		col0.a *= occluded_ratio
	current_strip.push_back(pts[0].round())
	current_cols.push_back(col0)

	for i in range(n - 1):
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var z0 := z_vals[i]
		var z1 := z_vals[i + 1]
		var occ0 := occ_status[i]
		var occ1 := occ_status[i + 1]
		var t1 := float(i + 1) / float(n - 1)
		var col1 := start_color.lerp(end_color, t1)

		if occ0 == occ1:
			var p1_round := p1.round()
			if occ1:
				col1.a *= occluded_ratio
			if current_strip.is_empty() or current_strip[-1] != p1_round:
				current_strip.push_back(p1_round)
				current_cols.push_back(col1)
		else:
			var s0 := 0.0
			var s1 := 1.0
			for iter in range(3):
				var s_mid := (s0 + s1) * 0.5
				var pt_mid := p0.lerp(p1, s_mid)
				var zm := lerpf(z0, z1, s_mid)
				var om: bool = aim_controller.is_point_occluded(pt_mid, zm)
				if om == occ0:
					s0 = s_mid
				else:
					s1 = s_mid

			var split_s := (s0 + s1) * 0.5
			var split_pt := p0.lerp(p1, split_s).round()
			var split_t := (float(i) + split_s) / float(n - 1)
			var split_col := start_color.lerp(end_color, split_t)

			var split_col_curr := split_col
			if current_mode:
				split_col_curr.a *= occluded_ratio
			if current_strip.is_empty() or current_strip[-1] != split_pt:
				current_strip.push_back(split_pt)
				current_cols.push_back(split_col_curr)

			if current_strip.size() >= 2:
				ci.draw_polyline_colors(current_strip, current_cols, 1.0)

			current_mode = occ1
			current_strip.clear()
			current_cols.clear()

			var split_col_next := split_col
			if current_mode:
				split_col_next.a *= occluded_ratio
			current_strip.push_back(split_pt)
			current_cols.push_back(split_col_next)

			var p1_round := p1.round()
			if split_pt != p1_round:
				if occ1:
					col1.a *= occluded_ratio
				current_strip.push_back(p1_round)
				current_cols.push_back(col1)

	if current_strip.size() >= 2:
		ci.draw_polyline_colors(current_strip, current_cols, 1.0)


