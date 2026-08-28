# wall_xray.gd —— 动态高墙透视控制器
class_name WallXRayManager
extends Node

# 可在右侧检查器中可视化微调的参数
@export_group("高墙透视参数")
@export var rx: float = 75.0:
	set(v):
		rx = v
		if material: material.set_shader_parameter("rx", rx)
@export var ry: float = 50.0:
	set(v):
		ry = v
		if material: material.set_shader_parameter("ry", ry)
@export var target_alpha: float = 0.2:
	set(v):
		target_alpha = v
		if material: material.set_shader_parameter("target_alpha", target_alpha)
@export var feather: float = 0.8:
	set(v):
		feather = v
		if material: material.set_shader_parameter("feather", feather)

var material: ShaderMaterial
var active_xray_layers: Array[TileMapLayer] = []
var _last_player_cell: Vector2i = Vector2i(-99999, -99999)

# 玩家前方遮挡扇区（南侧）
const FRONT_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1),
	Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)
]

func _ready() -> void:
	# 初始化透视材质并赋参数
	material = ShaderMaterial.new()
	material.shader = load("res://script/shaders/xray.gdshader")
	material.set_shader_parameter("rx", rx)
	material.set_shader_parameter("ry", ry)
	material.set_shader_parameter("target_alpha", target_alpha)
	material.set_shader_parameter("feather", feather)

# 动态刷新高墙透视
func update_wall_xray(player_node: Node2D, sort_world: Node2D) -> void:
	# 1. 还原上一批处于透视状态的高墙
	for layer in active_xray_layers:
		if is_instance_valid(layer):
			layer.material = null
	active_xray_layers.clear()

	if player_node == null or material == null or sort_world == null:
		return

	# 2. 获取玩家当前脚下的格子与楼层高度
	var player_cell := GridData.world_to_cell(player_node.global_position)
	var player_floor := GridData.get_highest_floor(player_cell)

	# 3. 扫描玩家正前方（南面）相邻格子
	for offset in FRONT_OFFSETS:
		var front_cell := player_cell + offset
		var wall_floor := GridData.get_highest_floor(front_cell)

		# 核心条件：高度差 >= 2
		if wall_floor >= player_floor + 2:
			for z in range(player_floor + 1, wall_floor + 1):
				var key := "cell_z%d_%d_%d" % [z, front_cell.x, front_cell.y]
				var cell_layer := sort_world.get_node_or_null(key) as TileMapLayer
				if cell_layer:
					cell_layer.material = material
					active_xray_layers.append(cell_layer)
