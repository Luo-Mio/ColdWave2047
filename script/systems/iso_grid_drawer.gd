# iso_grid_drawer.gd —— 2:1 等距几何网格极速绘制工具类
class_name IsoGridDrawer
extends RefCounted

## 绘制任意规格的 2:1 等轴测菱形 (支持填充色 + 边框轮廓)
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

## 批量绘制多个 64x32 菱形外边框线 (单次 draw_multiline GPU 极速合批)
static func draw_tiles_borders(ci: CanvasItem, tile_centers: Array[Vector2], color: Color, width: float = 1.0) -> void:
	if color.a <= 0.001 or ci == null or tile_centers.is_empty():
		return
	var lines := PackedVector2Array()
	lines.resize(tile_centers.size() * 8)
	var idx := 0
	for c in tile_centers:
		var top := c + Vector2(0, -16)
		var right := c + Vector2(32, 0)
		var bot := c + Vector2(0, 16)
		var left := c + Vector2(-32, 0)
		lines[idx] = top; lines[idx + 1] = right
		lines[idx + 2] = right; lines[idx + 3] = bot
		lines[idx + 4] = bot; lines[idx + 5] = left
		lines[idx + 6] = left; lines[idx + 7] = top
		idx += 8
	ci.draw_multiline(lines, color, width)

