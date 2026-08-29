# wall_xray.gd —— 动态高墙透视控制器
class_name WallXRayManager
extends Node

# 可在右侧检查器中可视化微调的参数
@export_group("高墙透视参数")
@export var rx: float = 45.0:
	set(v):
		rx = v
		if material: material.set_shader_parameter("rx", rx)
@export var ry: float = 50.0:
	set(v):
		ry = v
		if material: material.set_shader_parameter("ry", ry)
@export var target_alpha: float = 0.35:
	set(v):
		target_alpha = v
		if material: material.set_shader_parameter("target_alpha", target_alpha)
@export var feather: float = 1.0: # 透视边缘羽化 (0.0=硬边, 0.5=柔边, 1.0=极柔)
	set(v):
		feather = v
		if material: material.set_shader_parameter("feather", feather)
@export var max_transparency: float = 0.2: # 透明透视强度 (0.0=不透, 0.5=半透, 1.0=完全透空)
	set(v):
		max_transparency = v
		if material: material.set_shader_parameter("max_transparency", max_transparency)
@export var min_height_diff: int = 3   # 最小触发高度差（3层）

var material: ShaderMaterial
var active_xray_layers: Array[TileMapLayer] = []

# 扫描角色周围的相邻格子候选区
func _get_scan_offsets() -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			offsets.append(Vector2i(dx, dy))
	return offsets

func _ready() -> void:
	# 初始化透视材质并赋参数
	material = ShaderMaterial.new()
	material.shader = load("res://script/shaders/xray.gdshader")
	material.set_shader_parameter("rx", rx)
	material.set_shader_parameter("ry", ry)
	material.set_shader_parameter("feather", feather)
	material.set_shader_parameter("max_transparency", max_transparency)

# 动态刷新高墙透视
func update_wall_xray(player_node: Node2D, sort_world: Node2D) -> void:
	# 1. 还原上一批处于透视状态的高墙
	for layer in active_xray_layers:
		if is_instance_valid(layer):
			layer.material = null
	active_xray_layers.clear()

	if player_node == null or material == null or sort_world == null:
		return

	var player_cell := GridData.world_to_cell(player_node.global_position)
	var player_floor := GridData.get_highest_floor(player_cell)
	var player_base_y := player_node.global_position.y  # 角色在地面网格上的连续真实 Y 坐标

	# 2. 扫描候选格子
	for offset in _get_scan_offsets():
		var front_cell := player_cell + offset
		var wall_floor := GridData.get_highest_floor(front_cell)

		# 条件 1：高度差必须达到门槛 (>= 3 层)
		if wall_floor < player_floor + min_height_diff:
			continue

		# 条件 2【双保险核心】：墙体的世界基底 Y 必须严格在角色脚底的南侧（下方）
		# 左右平排（Y 相同）或角色身前（Y 较小）100% 排除，彻底消除菱形量化误差！
		var wall_base_pos := GridData.cell_to_world(front_cell)
		if wall_base_pos.y <= player_base_y + 4.0:
			continue

		# 3. 满足所有条件：仅将高于玩家视线部分的砖层赋予透视 Shader
		for z in range(player_floor + 1, wall_floor + 1):
			var key := "cell_z%d_%d_%d" % [z, front_cell.x, front_cell.y]
			var cell_layer := sort_world.get_node_or_null(key) as TileMapLayer
			if cell_layer:
				cell_layer.material = material
				active_xray_layers.append(cell_layer)