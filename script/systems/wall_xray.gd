# wall_xray.gd —— 动态高墙与表面/物体透视控制器（支持高墙透视 + 草皮透视 + 柱顶物体透视 + 同层地基截面纯黑效果）
class_name WallXRayManager
extends Node

# 可在右侧检查器中可视化微调的参数
@export_group("高墙透视参数")
@export var rx: float = 60.0:
	set(v):
		rx = v
		if material: material.set_shader_parameter("rx", rx)
@export var ry: float = 120.0:
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

@export_group("地基截面封顶参数")
## 透视时同层地基截面的渲染颜色（默认为纯黑，可在检查器微调）
@export var base_floor_color: Color = Color(0.0, 0.0, 0.0, 1.0)
## 截面封顶的 Z-Index 渲染层级（默认 1，确保高于所有地砖层 z_index=0，避免被南侧/更大 Y 的地砖柱遮挡）
@export var cap_z_index: int = 1

# 轻量截面封顶多边形绘制节点 (排在所有瓷砖之上，渲染 64x32 纯黑截面)
class XRayCap extends Node2D:
	var sort_key: float = 0.0
	var layer_no: int = 999
	var cap_color: Color = Color.BLACK

	func _draw() -> void:
		var pts := PackedVector2Array([
			Vector2(0, -16),
			Vector2(32, 0),
			Vector2(0, 16),
			Vector2(-32, 0)
		])
		draw_colored_polygon(pts, cap_color)

var material: ShaderMaterial
var active_xray_layers: Array[TileMapLayer] = []
var active_xray_objects: Dictionary = {} # CanvasItem -> Material (记录透视前原始材质，用于精准还原)
var active_caps: Array[Node2D] = [] # 记录当前活跃的同层封顶盖板

func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://script/shaders/xray.gdshader")
	material.set_shader_parameter("rx", rx)
	material.set_shader_parameter("ry", ry)
	material.set_shader_parameter("feather", feather)
	material.set_shader_parameter("max_transparency", max_transparency)

# 动态刷新高墙透视
func update_wall_xray(player_node: Node2D, sort_world: Node2D) -> void:
	# 1. 还原上一批透视的高墙与泥土切片
	for layer in active_xray_layers:
		if is_instance_valid(layer):
			layer.material = VisionFogComponent.get_tile_shadow_material()
	active_xray_layers.clear()

	# 还原上一批透视的柱顶/高处物体精灵与草皮表面 (树木、小麦、掉落物、surf切片等)
	for item in active_xray_objects.keys():
		if is_instance_valid(item):
			item.material = active_xray_objects[item]
	active_xray_objects.clear()

	# 清理上一批截面封顶
	for cap in active_caps:
		if is_instance_valid(cap):
			if cap.get_parent():
				cap.get_parent().remove_child(cap)
			cap.queue_free()
	active_caps.clear()

	if player_node == null or material == null or sort_world == null:
		return

	var player_visual: Vector2 = player_node.global_position
	if player_node.has_method("get_visual_foot_position"):
		player_visual = player_node.call("get_visual_foot_position")

	var player_cell := GridData.world_to_cell(player_node.global_position)
	var player_floor := GridData.get_highest_floor(player_cell)
	var player_sort_key: float = float(player_node.get("sort_key")) if player_node.get("sort_key") != null else GridData.cell_to_sort_key(player_cell)

	var created_caps := false

	# 2. 向南方扫描可能遮挡玩家的高墙候选格 (在等距 2.5D 视角中，遮挡障碍必须在排序键上处于角色南侧前景)
	for dy in range(-4, 16):
		for dx in range(-4, 16):
			var front_cell := player_cell + Vector2i(dx, dy)
			var wall_floor := GridData.get_highest_floor(front_cell)
			
			if wall_floor <= player_floor:
				continue

			# 【核心深度准则 1】：地形障碍必须在角色南侧 (前景)，其排序键必须严格大于角色！
			# 若 wall_sort_key <= player_sort_key，则该高台/墙面物理处于角色北侧/后景，
			# 角色本身会自然遮盖后方立面，绝不可能被该墙面遮挡，彻底杜绝站在墙脚或斜边被误判为遮挡！
			var wall_sort_key := GridData.cell_to_sort_key(front_cell)
			if wall_sort_key <= player_sort_key:
				continue

			var cell_center := GridData.cell_to_world(front_cell)

			# 【核心几何准则 2】：横向屏幕重叠判定
			# 菱形地砖宽度为 64px (半宽 32px)，角色半宽约为 20px。
			# 若角色与该柱的屏幕 X 轴投影相距超过 52px，两者在屏幕空间上完全不重叠，无遮挡可能！
			if absf(player_visual.x - cell_center.x) > 52.0:
				continue

			# 【核心几何准则 3】：垂直屏幕立面重叠判定
			# 该高墙立面在屏幕上的覆盖范围：
			# 底端 (player_floor 处): cell_center.y + get_floor_pixel_offset(player_floor) + 16.0
			# 顶端 (wall_floor 处): cell_center.y + get_floor_pixel_offset(wall_floor) - 16.0
			# 角色的全身视觉垂直范围：[player_visual.y - 48.0 (头顶), player_visual.y + 4.0 (脚底)]
			var wall_bottom_y := cell_center.y + GridData.get_floor_pixel_offset(player_floor) + 16.0
			var wall_top_y := cell_center.y + GridData.get_floor_pixel_offset(wall_floor) - 16.0
			var player_top_y := player_visual.y - 48.0
			var player_bottom_y := player_visual.y + 4.0

			if wall_top_y > player_bottom_y or wall_bottom_y < player_top_y:
				continue

			var is_cell_occluding := false

			# 3. 逐层检查高出玩家视野的砖块是否进入透视范围
			for z in range(player_floor + 1, wall_floor + 1):
				var block_screen_pos := Vector2(cell_center.x, cell_center.y - float(z) * 16.0) # 适配 64x32
				
				var norm_x := (block_screen_pos.x - player_visual.x) / (rx + 20.0)
				var norm_y := (block_screen_pos.y - player_visual.y) / (ry + 20.0)
				
				if (norm_x * norm_x + norm_y * norm_y) <= 1.0:
					var key := "cell_z%d_%d_%d" % [z, front_cell.x, front_cell.y]
					var cell_layer := sort_world.get_node_or_null(key) as TileMapLayer
					if cell_layer:
						if not active_xray_layers.has(cell_layer):
							cell_layer.material = material
							active_xray_layers.append(cell_layer)
						is_cell_occluding = true

			# 4. 【遮挡处理与封顶】：如果该格有砖块遮挡玩家
			if is_cell_occluding:
				# 4.1 确保整根遮挡柱从 (player_floor + 1) 到 wall_floor 的所有泥土方块均挂载 X-Ray 材质
				for z in range(player_floor + 1, wall_floor + 1):
					var key := "cell_z%d_%d_%d" % [z, front_cell.x, front_cell.y]
					var cell_layer := sort_world.get_node_or_null(key) as TileMapLayer
					if cell_layer and not active_xray_layers.has(cell_layer):
						cell_layer.material = material
						active_xray_layers.append(cell_layer)
					# 4.2 挂载该楼层对应的所有草皮/表面切片 (surf)
					_apply_xray_to_surf(front_cell, z, sort_world)

				# 4.3 挂载该柱顶及高出的所有物体精灵 (树木躯干/树冠、农作物、掉落物等)
				_apply_xray_to_objects_at(front_cell, player_floor)

				# 4.4 【核心截面封顶】：在角色同高度的地基顶部渲染 64x32 纯黑菱形封顶面！
				var diamond_center := cell_center + Vector2(0.0, GridData.get_floor_pixel_offset(player_floor))
				var cap := XRayCap.new()
				cap.name = "xray_cap_%d_%d" % [front_cell.x, front_cell.y]
				cap.position = diamond_center
				cap.sort_key = GridData.cell_to_sort_key(front_cell)
				cap.layer_no = 999
				cap.cap_color = base_floor_color
				cap.z_index = cap_z_index
				sort_world.add_child(cap)
				active_caps.append(cap)
				created_caps = true

	if created_caps:
		sort_world.call("sort_now")

# 为某格子在第 z 层涉及的所有双网格表面切片挂载 X-Ray 材质
func _apply_xray_to_surf(cell: Vector2i, z: int, sort_world: Node2D) -> void:
	if sort_world == null:
		return
	var dual_cells := LayerSurfSystem.get_affected_dual_cells(cell)
	for d in dual_cells:
		var key := "surf_z%d_%d_%d" % [z, d.x, d.y]
		var surf_node := sort_world.get_node_or_null(key) as CanvasItem
		if surf_node == null:
			# 兼容旧命名规范
			surf_node = sort_world.get_node_or_null("turf_z%d_%d_%d" % [z, d.x, d.y]) as CanvasItem
		
		if surf_node and not active_xray_objects.has(surf_node):
			active_xray_objects[surf_node] = surf_node.material
			surf_node.material = material

# 为某格子上高于 min_floor 的所有物体 (树木、小麦、掉落物等) 挂载 X-Ray 材质
func _apply_xray_to_objects_at(cell: Vector2i, min_floor: int) -> void:
	# 1. 查找 GridData 中注册在该格子的所有实体 (大树、微格小麦等)
	var objs := GridData.get_all_objects_at(cell)
	for obj in objs:
		if not is_instance_valid(obj):
			continue
		var obj_fl: int = obj.get("floor_level") if obj.get("floor_level") != null else GridData.get_highest_floor(cell)
		if obj_fl > min_floor:
			_apply_xray_to_node_sprites(obj)

	# 2. 检查全局 world_objects (防止有场景预置但未在 GridData 中的物体)
	if objs.is_empty():
		for obj in get_tree().get_nodes_in_group("world_objects"):
			if not is_instance_valid(obj):
				continue
			var obj_base_pos: Vector2 = obj.get("base_position") if obj.get("base_position") != null and obj.get("base_position") != Vector2.ZERO else obj.global_position
			var obj_cell := GridData.world_to_cell(obj_base_pos)
			if obj_cell == cell:
				var obj_fl: int = obj.get("floor_level") if obj.get("floor_level") != null else GridData.get_highest_floor(cell)
				if obj_fl > min_floor:
					_apply_xray_to_node_sprites(obj)

	# 3. 检查掉落物 drop_items (掉落在该柱顶上的物品)
	for drop in get_tree().get_nodes_in_group("drop_items"):
		if not is_instance_valid(drop):
			continue
		var drop_pos: Vector2 = drop.get("base_position") if drop.get("base_position") != null and drop.get("base_position") != Vector2.ZERO else drop.global_position
		var drop_cell := GridData.world_to_cell(drop_pos)
		if drop_cell == cell:
			var drop_fl: int = drop.get("floor_level") if drop.get("floor_level") != null else 0
			if drop_fl > min_floor:
				_apply_xray_to_node_sprites(drop)

func _apply_xray_to_node_sprites(obj: Node) -> void:
	for sprite in _get_all_visual_sprites(obj):
		if not active_xray_objects.has(sprite):
			active_xray_objects[sprite] = sprite.material
		sprite.material = material

func _get_all_visual_sprites(obj: Node) -> Array[CanvasItem]:
	var result: Array[CanvasItem] = []
	if obj == null:
		return result
	var stack: Array[Node] = [obj]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Sprite2D or n is AnimatedSprite2D or n is Polygon2D:
			result.append(n as CanvasItem)
		for c in n.get_children():
			stack.push_back(c)
	return result