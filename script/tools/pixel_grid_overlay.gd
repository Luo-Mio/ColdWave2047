@tool
extends Node2D

@export var grid_color: Color = Color(1.0, 1.0, 1.0, 0.09)
@export var axis_color: Color = Color(0.2, 0.8, 1.0, 0.28)
@export var ground_color: Color = Color(0.3, 0.9, 0.4, 0.55)
@export var bound_color: Color = Color(1.0, 0.8, 0.2, 0.45)

func _draw() -> void:
	# 绘制 1:1 本地像素网格 (单位为草皮纹素像素)
	for x in range(-14, 15):
		var col = axis_color if x == 0 else grid_color
		var w = 0.06 if x == 0 else 0.025
		draw_line(Vector2(x, -14), Vector2(x, 4), col, w)
	for y in range(-14, 5):
		var col = ground_color if y == 0 else grid_color
		var w = 0.08 if y == 0 else 0.025
		draw_line(Vector2(-14, y), Vector2(14, y), col, w)

	# 4x8 原图黄色基准包围盒 (左: -2, 右: 2, 上: -8, 下: 0)
	draw_rect(Rect2(-2.0, -8.0, 4.0, 8.0), bound_color, false, 0.06)
