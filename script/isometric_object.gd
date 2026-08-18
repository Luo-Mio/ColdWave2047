# isometric_object.gd —— 等距可排序物件通用脚本
# 用法：挂到任何 Sprite2D / Node2D 上（父节点必须是 charaSort）
# 然后只需在检查器里填 3 个参数，无需改代码
extends Node2D

# [自定义] 物件的平面位置（格子底部中心的世界坐标，不含楼层偏移）
@export var base_position: Vector2 = Vector2.ZERO

# [自定义] 物件所在楼层（0=地面，1=一层平台，2=二层平台...）
@export var floor_level: int = 0

# [自定义] 物件底部到原点的 Y 差（负=精灵原点在中心，需把脚底对齐到站立点）
@export var foot_offset: float = 0.0


func _ready() -> void:
	# global_position.y 就是 charaSort 的排序键 —— 一次性摆好
	global_position = base_position + Vector2(
		0.0,
		GridData.get_floor_pixel_offset(floor_level) + foot_offset
	)
