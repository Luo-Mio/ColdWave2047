# iso_grid_drawer.gd —— 通用 2:1 等轴测几何网格收集器与合批渲染器
class_name IsoGridDrawer
extends RefCounted

## 收集指定中心格、指定半径、指定楼层高度上的所有有效瓷砖 64x32 菱形外边框线段 (点对格式，用于单次 draw_multiline GPU 合批)
static func collect_floor_grid_lines(center_cell: Vector2i, range_radius: int, floor_level: int, grid_data) -> PackedVector2Array:
	var lines := PackedVector2Array()
	if grid_data == null:
		return lines

	var floor_y: float = grid_data.get_floor_pixel_offset(floor_level)
	var center_ground_pos: Vector2 = grid_data.cell_to_world(center_cell) + Vector2(0.0, floor_y)

	# 2:1 等距网格中，Y 轴每行像素为 16px (对应菱形高32的一半)，扫描步进需要对应比例
	var scan_rx := range_radius + 1
	var scan_ry := range_radius * 2 + 1

	for dy in range(-scan_ry, scan_ry + 1):
		for dx in range(-scan_rx, scan_rx + 1):
			var cell := center_cell + Vector2i(dx, dy)
			if not grid_data.has_any_tile(cell):
				continue

			var fl: int = grid_data.get_highest_floor(cell)
			if fl != floor_level:
				continue

			var cell_top: Vector2 = grid_data.cell_to_world(cell) + Vector2(0.0, floor_y)
			var delta := cell_top - center_ground_pos
			var iso_dist: float = (absf(delta.x) / 64.0) + (absf(delta.y) / 32.0)
			if iso_dist > float(range_radius) + 0.15:
				continue

			# 64x32 菱形边框 4 条独立线段 (8 个顶点)
			var p_top := cell_top + Vector2(0, -16)
			var p_right := cell_top + Vector2(32, 0)
			var p_bot := cell_top + Vector2(0, 16)
			var p_left := cell_top + Vector2(-32, 0)

			lines.push_back(p_top); lines.push_back(p_right)
			lines.push_back(p_right); lines.push_back(p_bot)
			lines.push_back(p_bot); lines.push_back(p_left)
			lines.push_back(p_left); lines.push_back(p_top)

	return lines

## 绘制指定中心、指定半径、指定楼层的高性能等轴测地砖网格 (单次 GPU Draw Call)
static func draw_tile_grid(ci: CanvasItem, center_cell: Vector2i, range_radius: int, floor_level: int, color: Color, grid_data, width: float = 1.0) -> void:
	if color.a <= 0.001 or ci == null:
		return
	var lines := collect_floor_grid_lines(center_cell, range_radius, floor_level, grid_data)
	if not lines.is_empty():
		ci.draw_multiline(lines, color, width)

## 依据已有的地块顶部坐标列表批量绘制 64x32 菱形外边框
static func draw_tiles_borders(ci: CanvasItem, tile_tops: Array, color: Color, width: float = 1.0) -> void:
	if color.a <= 0.001 or ci == null or tile_tops.is_empty():
		return
	var lines := PackedVector2Array()
	lines.resize(tile_tops.size() * 8)
	var idx := 0
	for top in tile_tops:
		var cell_top: Vector2 = top
		var p_top := cell_top + Vector2(0, -16)
		var p_right := cell_top + Vector2(32, 0)
		var p_bot := cell_top + Vector2(0, 16)
		var p_left := cell_top + Vector2(-32, 0)
		lines[idx] = p_top; lines[idx + 1] = p_right
		lines[idx + 2] = p_right; lines[idx + 3] = p_bot
		lines[idx + 4] = p_bot; lines[idx + 5] = p_left
		lines[idx + 6] = p_left; lines[idx + 7] = p_top
		idx += 8
	ci.draw_multiline(lines, color, width)

## 绘制任意规格的 2:1 等轴测菱形区域 (支持填充色 + 边框轮廓)
static func draw_diamond(ci: CanvasItem, center: Vector2, half_w: float, half_h: float, fill_color: Color, border_color: Color = Color.TRANSPARENT, border_width: float = 1.0) -> void:
	if ci == null:
		return
	var c := center.round()
	var pts := PackedVector2Array([
		c + Vector2(0, -half_h),
		c + Vector2(half_w, 0),
		c + Vector2(0, half_h),
		c + Vector2(-half_w, 0)
	])
	if fill_color.a > 0.001:
		ci.draw_polygon(pts, PackedColorArray([fill_color]))
	if border_color.a > 0.001:
		var border := PackedVector2Array([
			pts[0], pts[1], pts[2], pts[3], pts[0]
		])
		ci.draw_polyline(border, border_color, border_width)

## 绘制指定中心、指定半径、以指定屏幕坐标为圆心在椭圆 (默认 128x64) 范围内平滑不透明渐变显示的等轴测地砖网格与高墙底部截面
static func draw_radial_falloff_grid(
	ci: CanvasItem,
	center_cell: Vector2i,
	range_radius: int,
	floor_level: int,
	falloff_center: Vector2,
	radius_x: float,
	radius_y: float,
	base_color: Color,
	grid_data,
	width: float = 1.0,
	show_cap: bool = false,
	cap_color: Color = Color(0.0, 0.0, 0.0, 1.0),
	cap_target: int = 0
) -> void:
	if ci == null or grid_data == null:
		return
	if base_color.a <= 0.001 and (not show_cap or cap_color.a <= 0.001):
		return

	var floor_y: float = grid_data.get_floor_pixel_offset(floor_level)
	var center_ground_pos: Vector2 = grid_data.cell_to_world(center_cell) + Vector2(0.0, floor_y)

	var scan_rx := range_radius + 1
	var scan_ry := range_radius * 2 + 1

	var processed_edges: Dictionary = {}
	var pts := PackedVector2Array()
	var cols := PackedColorArray()

	var rx_inv: float = 1.0 / maxf(radius_x, 1.0)
	var ry_inv: float = 1.0 / maxf(radius_y, 1.0)

	# 1. 优先绘制高墙/地基底部截面封顶多边形 (纯黑菱形面，在网格线条下方渲染)
	if show_cap and cap_color.a > 0.001:
		for dy in range(-scan_ry, scan_ry + 1):
			for dx in range(-scan_rx, scan_rx + 1):
				var cell := center_cell + Vector2i(dx, dy)
				if not grid_data.has_any_tile(cell):
					continue

				var fl: int = grid_data.get_highest_floor(cell)
				if fl < floor_level:
					continue

				var is_cap_target := false
				if cap_target == 0:
					is_cap_target = (fl > floor_level) # 仅高墙底部截面
				elif cap_target == 1:
					is_cap_target = (fl >= floor_level) # 高墙底与同层地表
				elif cap_target == 2:
					is_cap_target = (fl == floor_level) # 仅同层地表

				if not is_cap_target:
					continue

				var cell_top: Vector2 = grid_data.cell_to_world(cell) + Vector2(0.0, floor_y)
				var delta := cell_top - center_ground_pos
				var iso_dist: float = (absf(delta.x) / 64.0) + (absf(delta.y) / 32.0)
				if iso_dist > float(range_radius) + 0.35:
					continue

				var c_top := (cell_top + Vector2(0, -16)).round()
				var c_right := (cell_top + Vector2(32, 0)).round()
				var c_bot := (cell_top + Vector2(0, 16)).round()
				var c_left := (cell_top + Vector2(-32, 0)).round()
				var corners := PackedVector2Array([c_top, c_right, c_bot, c_left])

				# 计算菱形 4 个顶点的独立衰减颜色 (GPU 双线性插值平滑渐变)
				var poly_cols := PackedColorArray()
				var has_visible_vertex := false
				for pt in corners:
					var u := (pt.x - falloff_center.x) * rx_inv
					var v := (pt.y - falloff_center.y) * ry_inv
					var d_sq := u * u + v * v
					var alpha := 0.0
					if d_sq < 1.0:
						alpha = (1.0 - d_sq) * cap_color.a
						if alpha > 0.005:
							has_visible_vertex = true
					poly_cols.push_back(Color(cap_color.r, cap_color.g, cap_color.b, alpha))

				if has_visible_vertex:
					ci.draw_polygon(corners, poly_cols)

	# 2. 绘制等轴测地砖网格线条 (在封顶多边形之上渲染)
	if base_color.a > 0.001:
		for dy in range(-scan_ry, scan_ry + 1):
			for dx in range(-scan_rx, scan_rx + 1):
				var cell := center_cell + Vector2i(dx, dy)
				if not grid_data.has_any_tile(cell):
					continue

				var fl: int = grid_data.get_highest_floor(cell)
				# 绘制线条的条件：同层地表，或开启了截面封顶的高墙底部
				var should_draw_lines := false
				if fl == floor_level:
					should_draw_lines = true
				elif fl > floor_level and show_cap and (cap_target == 0 or cap_target == 1):
					should_draw_lines = true

				if not should_draw_lines:
					continue

				var cell_top: Vector2 = grid_data.cell_to_world(cell) + Vector2(0.0, floor_y)
				var delta := cell_top - center_ground_pos
				var iso_dist: float = (absf(delta.x) / 64.0) + (absf(delta.y) / 32.0)
				if iso_dist > float(range_radius) + 0.35:
					continue

				var corners := [
					(cell_top + Vector2(0, -16)).round(),
					(cell_top + Vector2(32, 0)).round(),
					(cell_top + Vector2(0, 16)).round(),
					(cell_top + Vector2(-32, 0)).round()
				]

				for i in 4:
					var p0: Vector2 = corners[i]
					var p1: Vector2 = corners[(i + 1) % 4]

					# 边去重处理，消除相邻瓦片公共边的重复绘制
					var edge_key: Vector4
					if p0.x < p1.x or (p0.x == p1.x and p0.y < p1.y):
						edge_key = Vector4(p0.x, p0.y, p1.x, p1.y)
					else:
						edge_key = Vector4(p1.x, p1.y, p0.x, p0.y)

					if processed_edges.has(edge_key):
						continue
					processed_edges[edge_key] = true

					# 每条 36px 的边折半为 2 条小线段，保证 GPU 渐变极致细腻
					var pm: Vector2 = ((p0 + p1) * 0.5).round()
					for seg in [[p0, pm], [pm, p1]]:
						var a: Vector2 = seg[0]
						var b: Vector2 = seg[1]
						var mid: Vector2 = (a + b) * 0.5

						var u := (mid.x - falloff_center.x) * rx_inv
						var v := (mid.y - falloff_center.y) * ry_inv
						var d_sq := u * u + v * v
						if d_sq >= 1.0:
							continue

						# 平滑二次衰减曲线：中心 100% 强度，边缘 0% 平滑隐形
						var falloff: float = 1.0 - d_sq
						var alpha: float = falloff * base_color.a
						if alpha <= 0.005:
							continue

						pts.push_back(a)
						pts.push_back(b)
						cols.push_back(Color(base_color.r, base_color.g, base_color.b, alpha))

		if not pts.is_empty():
			ci.draw_multiline_colors(pts, cols, width)

