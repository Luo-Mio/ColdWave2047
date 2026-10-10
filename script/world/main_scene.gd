# main_scene.gd —— 主场景总调度
extends Node2D

const BuildManagerScript := preload("res://script/systems/build_manager.gd")
const WallXRayScript := preload("res://script/systems/wall_xray.gd")
const AirWallScript := preload("res://script/systems/air_wall.gd")
const AimControllerScript := preload("res://script/components/aim_controller.gd")
const AimReticleScript := preload("res://script/systems/aim_reticle.gd")
const EdgeIndicateSystemScript := preload("res://script/systems/edge_indicate_system.gd")
const MagicOrbScene := preload("res://scene/particle/magic_orb.tscn")
const LightOrbScene := preload("res://scene/particle/light.tscn")

var tile_layers: Array[TileMapLayer] = []
var _last_player_cell: Vector2i = Vector2i(-99999, -99999)
var build_manager: BuildManager
var wall_xray: WallXRayManager
var air_wall: StaticBody2D
var aim_controller: Node
var aim_reticle: Node2D
var layer_surf_system: LayerSurfSystem
var surf_system: LayerSurfSystem
var turf_system: LayerSurfSystem
var edge_indicate_system: EdgeIndicateSystem

@onready var sort_world: Node2D = $sortworld
@onready var selector: Node2D = $selector
@onready var hotbar_node: Node = find_child("hotbar")

func _ready() -> void:
	# 1. 自动获取或挂载子管理器组件
	build_manager = get_node_or_null("BuildManager") as BuildManager
	if build_manager == null:
		build_manager = BuildManagerScript.new()
		add_child(build_manager)

	wall_xray = get_node_or_null("WallXRayManager") as WallXRayManager
	if wall_xray == null:
		wall_xray = WallXRayScript.new()
		add_child(wall_xray)

	air_wall = get_node_or_null("AirWall") as StaticBody2D
	if air_wall == null:
		air_wall = AirWallScript.new()
		add_child(air_wall)

	var player_node: Node2D = get_node_or_null("sortworld/CharacterBody2D")
	if player_node:
		aim_controller = player_node.find_child("AimController", true, false)
	aim_reticle = get_node_or_null("AimReticle")
	if aim_reticle and aim_controller:
		aim_reticle.aim_controller = aim_controller

	# 2. 收集并按 Y 坐标排序原始层 (过滤掉草皮层，仅收集泥土砖块层)
	# 2. 收集并按 Y 坐标排序原始层 (过滤掉表面层，仅收集泥土砖块层)
	tile_layers = []
	for child in $layers.get_children():
		var n := child.name.to_lower()
		if child is TileMapLayer and not (n.contains("surf") or n.contains("turf") or n.contains("creep") or n.contains("snow")):
			tile_layers.append(child)
	tile_layers.sort_custom(func(a: TileMapLayer, b: TileMapLayer) -> bool:
		return a.position.y > b.position.y
	)

	# 3. 构建全局高度场
	GridData.build_from_layers(tile_layers)

	# 4. 拆分成行级层 (0 层为平坦地表底板；仅将 1 层及以上具有立面高度的障碍层拆入 sort_world 参与前后景深排位)
	_split_layers_into_rows()

	# 5. 隐藏原层 (0 层平坦基底保留为整张底板，1 层及以上立体障碍移入 sort_world 动态排序)
	for i in tile_layers.size():
		if i == 0:
			tile_layers[i].visible = true
			tile_layers[i].material = VisionFogComponent.get_tile_shadow_material()
		else:
			tile_layers[i].visible = false

	# 6. 全量构建并填补地图初始三角半砖
	build_manager.update_all_half_tiles(sort_world, tile_layers)

	# 7. 【正确位置】：必须在 GridData 与半砖构建完之后，再生成空气墙！
	air_wall.rebuild_walls()

	# 8. 初始排序
	sort_world.call("sort_now")

	# 8. 初始化楼层与双网格表面系统 (自动读取场景中的表面占位层并平滑渲染)
	layer_surf_system = get_node_or_null("LayerSurfSystem") as LayerSurfSystem
	if layer_surf_system == null:
		layer_surf_system = get_node_or_null("SurfSystem") as LayerSurfSystem
	if layer_surf_system == null:
		layer_surf_system = get_node_or_null("TurfSystem") as LayerSurfSystem
	if layer_surf_system == null:
		layer_surf_system = LayerSurfSystem.new()
		layer_surf_system.name = "LayerSurfSystem"
		add_child(layer_surf_system)
	layer_surf_system.init_surf_system(self, sort_world, $layers)
	surf_system = layer_surf_system
	turf_system = layer_surf_system

	# 9. 初始化顶层落差白边指示系统
	edge_indicate_system = get_node_or_null("EdgeIndicateSystem") as EdgeIndicateSystem
	if edge_indicate_system == null:
		edge_indicate_system = EdgeIndicateSystemScript.new()
		edge_indicate_system.name = "EdgeIndicateSystem"
		add_child(edge_indicate_system)
	edge_indicate_system.init_system(sort_world, $layers)

	# 10. 连接 HUD 保存快照按钮
	var save_btn := get_node_or_null("HUD/SaveMapBtn") as Button
	if save_btn:
		save_btn.pressed.connect(_on_save_map_btn_pressed)

var _toast_tween: Tween = null

func _on_save_map_btn_pressed() -> void:
	if layer_surf_system:
		var ok := layer_surf_system.dump_map_to_file()
		if ok:
			_show_toast("💾 地图快照已成功导出至 res://data/editor_map_dump.json\n可在编辑器中选中 LayerSurfSystem 点击【从运行时快照同步覆盖场景】！")

func _show_toast(msg: String) -> void:
	var toast := get_node_or_null("HUD/ToastLabel") as Label
	if toast == null:
		return
	toast.text = msg
	toast.modulate.a = 1.0
	toast.visible = true
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(3.5)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.6)
	_toast_tween.tween_callback(func(): toast.visible = false)

# 拆分图层 (0 层为平坦地表底板；仅将 1 层及以上具有立面高度的障碍层拆入 sort_world 参与前后景深排位)
func _split_layers_into_rows() -> void:
	for z in range(1, tile_layers.size()):
		var layer: TileMapLayer = tile_layers[z]
		for cell in layer.get_used_cells():
			var cell_layer := build_manager.get_or_create_cell_layer(z, cell, sort_world, tile_layers)
			cell_layer.set_cell(
				cell,
				layer.get_cell_source_id(cell),
				layer.get_cell_atlas_coords(cell),
				layer.get_cell_alternative_tile(cell)
			)

# 鼠标输入处理
func _unhandled_input(event: InputEvent) -> void:
	var inventory_node: CanvasLayer = get_node_or_null("Inventory")
	if inventory_node and inventory_node.visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F10:
			_on_save_map_btn_pressed()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed:
		var active_item: Dictionary = {}
		if hotbar_node and hotbar_node.has_method("get_active_item"):
			active_item = hotbar_node.call("get_active_item")

		# 【武器模式】：手持法杖时，左键发射 MagicOrb，右键发射 Light！
		if active_item.get("type") == 2: # 2 = WEAPON
			if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
				var player: Node2D = get_node_or_null("sortworld/CharacterBody2D")
				if player and aim_controller:
					var player_ground: Vector2 = player.global_position # 角色在地面平面的真实基底坐标
					var player_cell := GridData.world_to_cell(player_ground)
					var p_floor := GridData.get_highest_floor(player_cell)
					
					var aim_3d: Vector3 = aim_controller.aim_vector_3d
					if aim_3d.length_squared() > 0.01:
						var scene_to_spawn: PackedScene = MagicOrbScene if event.button_index == MOUSE_BUTTON_LEFT else LightOrbScene
						var orb := scene_to_spawn.instantiate() as Node2D
						if "speed" in orb and "projectile_speed" in aim_controller:
							orb.speed = aim_controller.projectile_speed
						if "gravity" in orb and "drop_value" in aim_controller:
							orb.gravity = aim_controller.drop_value
						if "launch_height" in orb and "launch_height" in aim_controller:
							orb.launch_height = aim_controller.launch_height
						if "shooter" in orb:
							orb.shooter = player
						sort_world.add_child(orb)
						orb.call("launch_3d", aim_3d, player_ground, p_floor)
			return # 武器模式下不触发地砖建造

		# 【建造模式】：手持地砖或农作物时，左键放置，右键破坏！
		var cell: Vector2i = selector.get("target_cell")
		if cell == Vector2i(-99999, -99999):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			build_manager.place_active_item(cell, hotbar_node, sort_world, selector, tile_layers)
			_refresh_xray()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			build_manager.destroy_top_at(cell, sort_world, selector, tile_layers)
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
