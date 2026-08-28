# main_scene.gd —— 主场景总调度
extends Node2D

const BuildManagerScript := preload("res://script/systems/build_manager.gd")
const WallXRayScript := preload("res://script/systems/wall_xray.gd")

var tile_layers: Array[TileMapLayer] = []
var _last_player_cell: Vector2i = Vector2i(-99999, -99999)

var build_manager: BuildManager
var wall_xray: WallXRayManager

@onready var sort_world: Node2D = $sortworld
@onready var selector: Node2D = $selector
@onready var hotbar_node: Node = find_child("hotbar")

func _ready() -> void:
	# 1. 自动实例化并挂载子管理器组件（无需在场景面板手动添加）
	build_manager = BuildManagerScript.new()
	add_child(build_manager)

	wall_xray = WallXRayScript.new()
	add_child(wall_xray)

	# 2. 收集并按 Y 坐标排序原始层
	tile_layers = []
	for child in $layers.get_children():
		if child is TileMapLayer:
			tile_layers.append(child)
	tile_layers.sort_custom(func(a: TileMapLayer, b: TileMapLayer) -> bool:
		return a.position.y > b.position.y
	)

	# 3. 构建全局高度场
	GridData.build_from_layers(tile_layers)

	# 4. 拆分成行级层
	_split_layers_into_rows()

	# 5. 隐藏原层
	for layer in tile_layers:
		layer.visible = false

	# 6. 初始排序
	sort_world.call("sort_now")

# 拆分图层
func _split_layers_into_rows() -> void:
	for z in tile_layers.size():
		var layer: TileMapLayer = tile_layers[z]
		for cell in layer.get_used_cells():
			var cell_layer := build_manager.get_or_create_cell_layer(z, cell, sort_world, tile_layers)
			cell_layer.set_cell(
				cell,
				layer.get_cell_source_id(cell),
				layer.get_cell_atlas_coords(cell),
				layer.get_cell_alternative_tile(cell)
			)

# 鼠标输入交由 BuildManager 处理
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var cell: Vector2i = selector.get("target_cell")
		if cell == Vector2i(-99999, -99999):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			build_manager.place_active_item(cell, hotbar_node, sort_world, selector, tile_layers)
			_refresh_xray()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			build_manager.destroy_top_at(cell, sort_world, selector)
			_refresh_xray()

func _process(_delta: float) -> void:
	var player: Node2D = get_node_or_null("sortworld/CharacterBody2D")
	if player == null:
		return

	# 1. 传递角色世界坐标给全局 Shader
	var player_visual: Vector2 = player.global_position
	if player.has_method("get_visual_foot_position"):
		player_visual = player.call("get_visual_foot_position")
	RenderingServer.global_shader_parameter_set("player_world_pos", player_visual)

	# 2. 玩家跨格子移动时刷新高墙透视
	var current_cell := GridData.world_to_cell(player.global_position)
	if current_cell != _last_player_cell:
		_last_player_cell = current_cell
		_refresh_xray()

func _refresh_xray() -> void:
	var player: Node2D = get_node_or_null("sortworld/CharacterBody2D")
	if wall_xray and player:
		wall_xray.update_wall_xray(player, sort_world)
