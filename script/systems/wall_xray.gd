# wall_xray.gd —— 动态高墙透视控制器（支持高墙透视 + 同层地基截面纯黑效果）
class_name WallXRayManager
extends Node

# 可在右侧检查器中可视化微调的参数
@export_group("高墙透视参数")
@export var rx: float = 60.0:
	set(v):
		rx = v
		if material: material.set_shader_parameter("rx", rx)
@export var ry: float = 120:
	set(v):
		ry = v
		if material: material.set_shader_parameter("ry", ry)
@export var feather: float = 1.0:           # 透视边缘羽化 (0.0=硬边, 1.0=极柔)
	set(v):
		feather = v
		if material: material.set_shader_parameter("feather", feather)
@export var max_transparency: float = 0.6: # 透明透视强度 (0.0=不透, 1.0=中心完全透空)
	set(v):
		max_transparency = v
		if material: material.set_shader_parameter("max_transparency", max_transparency)

# 【核心配置】：透视时同层地基的渲染颜色（默认为纯黑，可在检查器微调）
@export var base_floor_color: Color = Color(0.0, 0.0, 0.0, 1.0)

var material: ShaderMaterial
var active_xray_layers: Array[TileMapLayer] = []
var active_black_layers: Array[TileMapLayer] = [] # 记录当前被染黑的同层地基图层

func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://script/shaders/xray.gdshader")
	material.set_shader_parameter("rx", rx)
	material.set_shader_parameter("ry", ry)
	material.set_shader_parameter("feather", feather)
	material.set_shader_parameter("max_transparency", max_transparency)

# 动态刷新高墙透视
func update_wall_xray(player_node: Node2D, sort_world: Node2D) -> void:
	# 1. 还原上一批透视的高墙与被染黑的同层地基
	for layer in active_xray_layers:
		if is_instance_valid(layer):
			layer.material = null
	active_xray_layers.clear()

	for layer in active_black_layers:
		if is_instance_valid(layer):
			layer.modulate = Color(1.0, 1.0, 1.0, 1.0) # 还原为正常原色
	active_black_layers.clear()

	if player_node == null or material == null or sort_world == null:
		return

	var player_visual: Vector2 = player_node.global_position
	if player_node.has_method("get_visual_foot_position"):
		player_visual = player_node.call("get_visual_foot_position")

	var player_cell := GridData.world_to_cell(player_node.global_position)
	var player_floor := GridData.get_highest_floor(player_cell)
	var player_base_y := player_node.global_position.y

	# 2. 向南方大范围扫描
	for dy in range(0, 25):
		for dx in range(-8, 9):
			var front_cell := player_cell + Vector2i(dx, dy)
			var wall_floor := GridData.get_highest_floor(front_cell)
			
			if wall_floor <= player_floor:
				continue

			var cell_center := GridData.cell_to_world(front_cell)
			if cell_center.y <= player_base_y - 2.0:
				continue

			var is_cell_occluding := false

			# 3. 逐层检查高出玩家视野的砖块
			for z in range(player_floor + 1, wall_floor + 1):
				var block_screen_pos := Vector2(cell_center.x, cell_center.y - float(z) * 16.0) # 适配 64x32
				
				var norm_x := (block_screen_pos.x - player_visual.x) / (rx + 20.0)
				var norm_y := (block_screen_pos.y - player_visual.y) / (ry + 20.0)
				
				if (norm_x * norm_x + norm_y * norm_y) <= 1.0:
					var key := "cell_z%d_%d_%d" % [z, front_cell.x, front_cell.y]
					var cell_layer := sort_world.get_node_or_null(key) as TileMapLayer
					if cell_layer:
						cell_layer.material = material
						active_xray_layers.append(cell_layer)
						is_cell_occluding = true

			# 4. 【核心新增】：如果该格有砖块被透视，将该格与角色同层级的地基瓦片渲染为纯黑色！
			if is_cell_occluding:
				var base_key := "cell_z%d_%d_%d" % [player_floor, front_cell.x, front_cell.y]
				var base_layer := sort_world.get_node_or_null(base_key) as TileMapLayer
				if base_layer and not active_black_layers.has(base_layer):
					base_layer.modulate = base_floor_color # 变成纯黑
					active_black_layers.append(base_layer)