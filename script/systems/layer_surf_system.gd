@tool
# layer_surf_system.gd —— 2.5D 楼层与双网格表面覆盖物系统 (Layer & Surface System)
# 支持楼层高度一键扩展与草皮 (grass)、菌毯 (creep)、积雪 (snow) 等各类地表装饰覆层
class_name LayerSurfSystem
extends Node

## 编辑器一键操作：创建新的最高楼层 (layerX) 及附属表面节点 (surfX)
@export_tool_button("创建新最高楼层及附属Surf") var btn_add_floor = add_new_highest_floor

## 编辑器一键同步：点击该按钮即可自动为 layers 下的所有 layer 创建对应的 surf 子节点
@export_tool_button("一键同步各楼层Surf子节点") var btn_sync_surf = sync_surf_layers_in_editor

## 编辑器一键回写：从运行时快照 (editor_map_dump.json) 全量同步并覆盖当前编辑器场景
@export_tool_button("从运行时快照同步覆盖场景") var btn_import_dump = import_runtime_map_dump

@export_group("兼容复选框触发")
## 勾选后立即创建新的最高楼层及附属表面节点
@export var add_new_floor_action: bool = false:
	set(v):
		if v:
			add_new_highest_floor()

## 勾选后立即同步各楼层 Surf 子节点
@export var sync_floor_surf_nodes: bool = false:
	set(v):
		if v:
			sync_surf_layers_in_editor()

## 勾选后立即从运行时快照同步覆盖场景
@export var import_map_dump_action: bool = false:
	set(v):
		if v:
			import_runtime_map_dump()

static var instance: LayerSurfSystem = null

# 16 种双网格角落组合对应的瓦片坐标映射表 (遵循 4-bit 掩码 0~15，完全匹配 grass_out.png 等标准图集)
# Bit 0: 上角 (Top), Bit 1: 右角 (Right), Bit 2: 左角 (Left), Bit 3: 下角 (Bottom)
const MASK_TO_ATLAS: Array[Vector2i] = [
	Vector2i(0, 3), # 0:  0000 (完全透明/无表面)
	Vector2i(3, 3), # 1:  0001 (仅上角)
	Vector2i(0, 2), # 2:  0010 (仅右角)
	Vector2i(1, 2), # 3:  0011 (上 + 右)
	Vector2i(0, 0), # 4:  0100 (仅左角)
	Vector2i(3, 2), # 5:  0101 (上 + 左)
	Vector2i(2, 3), # 6:  0110 (右 + 左)
	Vector2i(3, 1), # 7:  0111 (上 + 右 + 左)
	Vector2i(1, 3), # 8:  1000 (仅下角)
	Vector2i(0, 1), # 9:  1001 (上 + 下)
	Vector2i(1, 0), # 10: 1010 (右 + 下)
	Vector2i(2, 2), # 11: 1011 (上 + 右 + 下)
	Vector2i(3, 0), # 12: 1100 (左 + 下)
	Vector2i(2, 0), # 13: 1101 (上 + 左 + 下)
	Vector2i(1, 1), # 14: 1110 (右 + 左 + 下)
	Vector2i(2, 1), # 15: 1111 (4角全满，完整表面)
]

# 编辑器中手动绘制表面时的占位图块坐标（第3列第2行，满覆盖图块）
const PLACEHOLDER_TILE: Vector2i = Vector2i(2, 1)

# 默认草皮 TileSet
var default_tileset: TileSet = preload("res://resources/surface/GreenGrass/grass_tileset.tres")
var cell_script: GDScript = preload("res://script/core/row_layer.gd")

# 表面预设表：支持多类型表面（如草皮 grass、菌毯 creep、积雪 snow）
var surface_presets: Dictionary = {
	"grass": preload("res://resources/surface/GreenGrass/grass_tileset.tres"),
}

var sort_world: Node2D = null
var layers_node: Node2D = null
var floor0_surf_layer: TileMapLayer = null

# 兼容旧代码引用
var floor0_turf_layer: TileMapLayer:
	get: return floor0_surf_layer
	set(v): floor0_surf_layer = v

func _init() -> void:
	instance = self

# 注册新的表面材质（供后续扩展菌毯、雪等）
func register_surface_preset(type_name: String, tileset: TileSet) -> void:
	surface_presets[type_name] = tileset

# 获取指定类型的 TileSet
func get_tileset_for_type(type_name: String) -> TileSet:
	if surface_presets.has(type_name):
		return surface_presets[type_name]
	return default_tileset

# 获取当前场景中的 layers 容器节点
func _get_layers_node() -> Node2D:
	if layers_node and is_instance_valid(layers_node):
		return layers_node
	if get_parent():
		var ln = get_parent().get_node_or_null("layers") as Node2D
		if ln: return ln
	if get_tree():
		var root := get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
		if root:
			var ln = root.get_node_or_null("layers") as Node2D
			if ln == null:
				ln = root.find_child("layers", true, false) as Node2D
			if ln: return ln
	return null

# 【功能一】编辑器中一键创建新的最高楼层 (layerX) 及附属表面子节点 (surfX)
func add_new_highest_floor() -> void:
	var l_node := _get_layers_node()
	if l_node == null:
		push_warning("[LayerSurfSystem] 未找到 layers 节点，无法创建新楼层！")
		return

	var scene_root := get_tree().edited_scene_root if Engine.is_editor_hint() else (get_tree().current_scene if get_tree() else null)

	# 1. 扫描当前已有最高楼层数字 (例如已有 layer1~layer9，则最大为 9)
	var max_floor := 0
	var template_layer: TileMapLayer = null
	for child in l_node.get_children():
		var n: String = child.name
		if child is TileMapLayer and n.to_lower().begins_with("layer"):
			if template_layer == null:
				template_layer = child
			var num_str := ""
			for ch in n:
				if ch >= "0" and ch <= "9":
					num_str += ch
			if num_str != "":
				max_floor = maxi(max_floor, num_str.to_int())

	var new_floor := max_floor + 1
	var new_layer_name := "layer%d" % new_floor
	var new_surf_name := "surf%d" % new_floor
	# 每增加一层，Y 坐标向上抬升 16 像素 (0层=0, 1层=-16, 2层=-32...)
	var floor_pos_y := -float(new_floor - 1) * 16.0

	# 2. 创建新的泥土地砖层 (layerX)
	var new_layer := TileMapLayer.new()
	new_layer.name = new_layer_name
	if template_layer:
		new_layer.tile_set = template_layer.tile_set
	new_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	new_layer.y_sort_enabled = true
	new_layer.collision_visibility_mode = 1
	new_layer.position = Vector2(0.0, floor_pos_y)

	# 3. 创建附属表面子节点 (surfX)
	var new_surf := TileMapLayer.new()
	new_surf.name = new_surf_name
	new_surf.tile_set = default_tileset
	new_surf.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	new_surf.y_sort_enabled = true
	new_surf.z_index = 1 # 编辑器下置于泥土之上
	new_surf.position = Vector2.ZERO # 继承父节点的楼层高度

	# 4. 组装父子层级并加入场景
	new_layer.add_child(new_surf)
	l_node.add_child(new_layer)

	# 5. 绑定所有者以确保在编辑器场景树中即时显示并保存进 .tscn
	if scene_root:
		new_layer.owner = scene_root
		new_surf.owner = scene_root

	print("[LayerSurfSystem] 成功创建新最高楼层 %s (高度 y = %.0f) 及附属表面子节点 %s！" % [new_layer_name, floor_pos_y, new_surf_name])

# 【功能二】在编辑器中一键同步各楼层的 Surf 节点（创建或归整为 layerX 的子节点）
func sync_surf_layers_in_editor() -> void:
	var l_node := _get_layers_node()
	if l_node == null:
		push_warning("[LayerSurfSystem] 未找到 layers 节点！")
		return

	var scene_root := get_tree().edited_scene_root if Engine.is_editor_hint() else (get_tree().current_scene if get_tree() else null)
	var synced_count := 0

	for child in l_node.get_children():
		var n: String = child.name
		if not n.to_lower().begins_with("layer"):
			continue

		var num_str := ""
		for ch in n:
			if ch >= "0" and ch <= "9":
				num_str += ch
		if num_str == "":
			continue
		var floor_num := num_str.to_int()
		var surf_name := "surf%d" % floor_num

		var existing := child.get_node_or_null(surf_name) as TileMapLayer
		if existing == null:
			var sibling_surf := l_node.get_node_or_null(surf_name) as TileMapLayer
			if sibling_surf:
				sibling_surf.reparent(child)
				sibling_surf.position = Vector2.ZERO
				if scene_root:
					sibling_surf.owner = scene_root
				synced_count += 1
				print("[LayerSurfSystem] 已将 %s 移入 %s 作为子节点" % [surf_name, n])
			else:
				var new_surf := TileMapLayer.new()
				new_surf.name = surf_name
				new_surf.tile_set = default_tileset
				new_surf.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				new_surf.y_sort_enabled = true
				new_surf.z_index = 1
				new_surf.position = Vector2.ZERO
				child.add_child(new_surf)
				if scene_root:
					new_surf.owner = scene_root
				synced_count += 1
				print("[LayerSurfSystem] 为 %s 新建表面子节点 %s" % [n, surf_name])
		else:
			existing.position = Vector2.ZERO
			existing.tile_set = default_tileset
			existing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			existing.y_sort_enabled = true
			existing.z_index = 1

	print("[LayerSurfSystem] 楼层表面子节点同步完成！共处理 %d 个节点" % synced_count)

# 【功能三】运行时将当前地图数据全量导出至 JSON 快照
func dump_map_to_file(path: String = "res://data/editor_map_dump.json") -> bool:
	var global_dir := ProjectSettings.globalize_path("res://data")
	if not DirAccess.dir_exists_absolute(global_dir):
		DirAccess.make_dir_recursive_absolute(global_dir)

	var dump := {
		"tiles": [],
		"surfs": [],
		"objects": []
	}

	# 1. 收集瓷砖 (Tiles)
	var l_node := _get_layers_node()
	for k in GridData.grid.keys():
		var z: int = k.z
		var cell := Vector2i(k.x, k.y)
		var atlas := Vector2i(0, 0)
		if z == 0 and l_node:
			var l1 := l_node.get_node_or_null("layer1") as TileMapLayer
			if l1 and l1.get_cell_source_id(cell) != -1:
				atlas = l1.get_cell_atlas_coords(cell)
		elif sort_world:
			var cell_layer := sort_world.get_node_or_null("cell_z%d_%d_%d" % [z, cell.x, cell.y]) as TileMapLayer
			if cell_layer and cell_layer.get_cell_source_id(cell) != -1:
				atlas = cell_layer.get_cell_atlas_coords(cell)

		dump["tiles"].append({
			"x": cell.x, "y": cell.y, "z": z,
			"ax": atlas.x, "ay": atlas.y
		})

	# 2. 收集草皮 / 表面覆盖物 (Surfs)
	for k in GridData.surf_grid.keys():
		dump["surfs"].append({
			"x": k.x, "y": k.y, "z": k.z,
			"type": GridData.surf_grid[k]
		})

	# 3. 收集世界静态物体 (World Objects)
	if get_tree():
		for obj in get_tree().get_nodes_in_group("world_objects"):
			if not is_instance_valid(obj) or obj.is_queued_for_deletion():
				continue
			var sc_path: String = obj.scene_file_path
			if sc_path.is_empty():
				continue

			var bp: Vector2 = obj.get("base_position") if ("base_position" in obj and obj.base_position != Vector2.ZERO) else obj.position
			var fl: int = obj.get("floor_level") if "floor_level" in obj else 0
			var gs: Vector2i = obj.get("grid_size") if "grid_size" in obj else Vector2i(4, 4)
			var sc: Vector2i = obj.get("sub_cell") if "sub_cell" in obj else Vector2i.ZERO

			dump["objects"].append({
				"scene": sc_path,
				"base_pos": [bp.x, bp.y],
				"floor": fl,
				"grid_size": [gs.x, gs.y],
				"sub_cell": [sc.x, sc.y]
			})

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[LayerSurfSystem] 无法写入地图快照文件: " + path)
		return false

	file.store_string(JSON.stringify(dump, "\t"))
	file.close()
	print("[LayerSurfSystem] 地图快照已成功导出到: %s (瓷砖: %d, 草皮: %d, 物体: %d)" % [path, dump["tiles"].size(), dump["surfs"].size(), dump["objects"].size()])
	return true

# 【功能四】在编辑器中从运行时快照全量回写并覆盖当前场景
func import_runtime_map_dump(path: String = "res://data/editor_map_dump.json") -> void:
	if not FileAccess.file_exists(path):
		printerr("[LayerSurfSystem] 未找到导出的地图快照文件: ", path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("[LayerSurfSystem] 无法打开地图文件: ", path)
		return
	var json_str := file.get_as_text()
	file.close()

	var dump = JSON.parse_string(json_str)
	if typeof(dump) != TYPE_DICTIONARY:
		printerr("[LayerSurfSystem] 地图快照 JSON 格式错误！")
		return

	var scene_root: Node = null
	if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		scene_root = get_tree().edited_scene_root
	elif get_parent():
		scene_root = get_parent()
	elif get_tree():
		scene_root = get_tree().current_scene

	var l_node := _get_layers_node()
	if l_node == null:
		printerr("[LayerSurfSystem] 未找到 layers 容器节点！")
		return

	var sort_world_node: Node2D = null
	if scene_root:
		sort_world_node = scene_root.find_child("sortworld", true, false) as Node2D
	if sort_world_node == null and get_parent():
		sort_world_node = get_parent().find_child("sortworld", true, false) as Node2D

	# 1. 计算需要支持的最大楼层数并自动创建缺少的 layerX / surfX
	var max_z := 0
	for t in dump.get("tiles", []):
		max_z = maxi(max_z, int(t.get("z", 0)))
	for s in dump.get("surfs", []):
		max_z = maxi(max_z, int(s.get("z", 0)))

	var required_layers := max_z + 1
	var current_max_floor := 0
	for child in l_node.get_children():
		var n: String = child.name
		if child is TileMapLayer and n.to_lower().begins_with("layer"):
			var num_str := ""
			for ch in n:
				if ch >= "0" and ch <= "9":
					num_str += ch
			if num_str != "":
				current_max_floor = maxi(current_max_floor, num_str.to_int())

	while current_max_floor < required_layers:
		add_new_highest_floor()
		current_max_floor += 1

	# 2. 收集各楼层 layerX 与 surfX 节点，并清空所有已有瓦片
	var floor_layers: Dictionary = {} # z -> TileMapLayer
	var floor_surfs: Dictionary = {}  # z -> TileMapLayer
	for child in l_node.get_children():
		var n: String = child.name
		if child is TileMapLayer and n.to_lower().begins_with("layer"):
			var num_str := ""
			for ch in n:
				if ch >= "0" and ch <= "9":
					num_str += ch
			if num_str != "":
				var z := num_str.to_int() - 1
				floor_layers[z] = child
				child.clear()

				# 收集附属 surf 子节点
				for sub in child.get_children():
					if sub is TileMapLayer and sub.name.to_lower().begins_with("surf"):
						floor_surfs[z] = sub
						sub.clear()

				# 兜底：如果 layers 下直接挂有 surfX
				if not floor_surfs.has(z):
					var direct_surf := l_node.get_node_or_null("surf%d" % (z + 1)) as TileMapLayer
					if direct_surf:
						floor_surfs[z] = direct_surf
						direct_surf.clear()

	# 3. 回填瓷砖 (Tiles)
	var tile_count := 0
	for t in dump.get("tiles", []):
		var z: int = int(t.get("z", 0))
		var cell := Vector2i(int(t.get("x", 0)), int(t.get("y", 0)))
		var atlas := Vector2i(int(t.get("ax", 0)), int(t.get("ay", 0)))
		if floor_layers.has(z):
			var l: TileMapLayer = floor_layers[z]
			l.set_cell(cell, 0, atlas, 0)
			tile_count += 1

	# 4. 回填草皮/表面覆层 (Surfs)
	var surf_count := 0
	for s in dump.get("surfs", []):
		var z: int = int(s.get("z", 0))
		var cell := Vector2i(int(s.get("x", 0)), int(s.get("y", 0)))
		# 若该层没有 surf 节点，自动创建
		if not floor_surfs.has(z) and floor_layers.has(z):
			var new_surf := TileMapLayer.new()
			new_surf.name = "surf%d" % (z + 1)
			new_surf.tile_set = default_tileset
			new_surf.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			new_surf.y_sort_enabled = true
			new_surf.z_index = 1
			new_surf.position = Vector2.ZERO
			floor_layers[z].add_child(new_surf)
			if scene_root:
				new_surf.owner = scene_root
			floor_surfs[z] = new_surf

		if floor_surfs.has(z):
			var sf: TileMapLayer = floor_surfs[z]
			sf.set_cell(cell, 0, PLACEHOLDER_TILE, 0)
			surf_count += 1

	# 5. 回填世界物体 (World Objects)
	var obj_count := 0
	if sort_world_node:
		# 清理旧有的世界物体 (仅清理 world_objects 组或 WorldObjectBase，绝不误删玩家和怪物)
		var to_remove: Array[Node] = []
		for child in sort_world_node.get_children():
			if child.is_in_group("world_objects") or child is WorldObjectBase:
				to_remove.append(child)
		for obj in to_remove:
			obj.free()

		# 实例化回填
		for o in dump.get("objects", []):
			var scene_path: String = o.get("scene", "")
			if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
				continue
			var packed := load(scene_path) as PackedScene
			if packed == null:
				continue
			var obj := packed.instantiate() as Node2D
			if obj == null:
				continue

			var bp_arr = o.get("base_pos", [0.0, 0.0])
			var bp := Vector2(float(bp_arr[0]), float(bp_arr[1]))
			var fl: int = int(o.get("floor", 0))
			var gs_arr = o.get("grid_size", [4, 4])
			var gs := Vector2i(int(gs_arr[0]), int(gs_arr[1]))
			var sc_arr = o.get("sub_cell", [0, 0])
			var sc := Vector2i(int(sc_arr[0]), int(sc_arr[1]))

			obj.set("base_position", bp)
			obj.set("floor_level", fl)
			obj.set("grid_size", gs)
			obj.set("sub_cell", sc)
			obj.position = bp + Vector2(0.0, -float(fl) * 16.0)

			sort_world_node.add_child(obj)
			if scene_root:
				obj.owner = scene_root
			obj_count += 1

	print("[LayerSurfSystem] 地图快照同步完成！共恢复 %d 块瓷砖、%d 块草皮、%d 个物体。请在编辑器中按 Ctrl+S 存盘。" % [tile_count, surf_count, obj_count])

# 初始化双网格表面系统（在 main_scene._ready() 中调用）
func init_surf_system(main_scene: Node2D, sort_world_ref: Node2D, layers_ref: Node2D) -> void:
	instance = self
	sort_world = sort_world_ref
	layers_node = layers_ref

	# 1. 扫描场景中由关卡设计师在编辑器里手动绘制的表面占位层 (surf1~surf9, turf1 等)
	_scan_editor_surf_layers(main_scene)

	# 2. 准备第 0 层平坦地表的双网格专用渲染层（作为底板并入 layers）
	_setup_floor0_surf_layer()

	# 3. 初始全量烘焙：把所有占位图转换为带圆角与平滑边缘的双网格切片
	rebuild_all_surf()

# 兼容旧方法名
func init_turf_system(main_scene: Node2D, sort_world_ref: Node2D, layers_ref: Node2D) -> void:
	init_surf_system(main_scene, sort_world_ref, layers_ref)

# 扫描并解析编辑器中绘制的表面图层（提取占位图块数据存入 GridData）
func _scan_editor_surf_layers(main_scene: Node2D) -> void:
	var scanned_layers: Array[TileMapLayer] = []
	for node in main_scene.find_children("*", "TileMapLayer", true, false):
		if node is TileMapLayer:
			var n := node.name.to_lower()
			if n.contains("surf") or n.contains("turf") or n.contains("creep") or n.contains("snow"):
				scanned_layers.append(node)

	for tl in scanned_layers:
		# 1. 识别表面类型 (默认为 grass 草皮，未来支持 creep 菌毯、snow 积雪)
		var s_type := "grass"
		var n_lower := tl.name.to_lower()
		if n_lower.contains("creep"):
			s_type = "creep"
		elif n_lower.contains("snow"):
			s_type = "snow"

		# 2. 推导楼层高度 z
		# 优先从图层名提取数字 (例如 surf1 对应 z=0, surf2 对应 z=1)
		var num_str := ""
		for ch in str(tl.name):
			if ch >= "0" and ch <= "9":
				num_str += ch
		
		# 如果图层名没有数字，尝试从父节点名提取 (例如 parent 是 layer2)
		if num_str == "" and tl.get_parent():
			for ch in str(tl.get_parent().name):
				if ch >= "0" and ch <= "9":
					num_str += ch

		var z := 0
		if num_str != "":
			var num := num_str.to_int()
			z = num - 1 if num > 0 else 0
		else:
			# 兜底：根据世界 Y 偏移估算
			z = maxi(0, int(round(-tl.global_position.y / 16.0)))

		# 3. 将画了任意瓦片（占位图）的格子提取到 GridData.surf_grid 中
		for cell in tl.get_used_cells():
			GridData.set_surf(cell, z, true, s_type)

		# 4. 提取完毕后清空占位图并隐藏原编辑层（后续由双网格系统统一平滑渲染）
		tl.clear()
		if z > 0:
			tl.visible = false

# 准备第 0 层平坦地面的专用双网格渲染层
func _setup_floor0_surf_layer() -> void:
	if layers_node == null:
		return

	# 检查是否已有现成的 surf1 或 turf1
	var existing = layers_node.get_node_or_null("surf1") as TileMapLayer
	if existing == null:
		existing = layers_node.get_node_or_null("turf1") as TileMapLayer
	if existing == null:
		existing = layers_node.get_node_or_null("surf_layer1") as TileMapLayer
	if existing == null:
		existing = layers_node.find_child("surf1", true, false) as TileMapLayer
	if existing == null:
		existing = layers_node.find_child("turf1", true, false) as TileMapLayer

	if existing:
		floor0_surf_layer = existing
	else:
		floor0_surf_layer = TileMapLayer.new()
		floor0_surf_layer.name = "surf1"
		layers_node.add_child(floor0_surf_layer)

	# 核心修复：运行时将 floor0_surf_layer 调整为 layers_node 的直接子节点且紧跟在 layer1 之后
	# 避免作为 layer1 的子节点时，被开启了 y_sort 的 layer1 当作 Y=-16 的单点物体排序，
	# 导致 layer1 中 Y > -16 的所有泥土地砖都覆盖在草皮之上造成严重拼接与遮挡错误！
	if floor0_surf_layer.get_parent() != layers_node:
		floor0_surf_layer.reparent(layers_node)

	var layer1 = layers_node.get_node_or_null("layer1")
	if layer1:
		var idx := layer1.get_index() + 1
		layers_node.move_child(floor0_surf_layer, idx)

	floor0_surf_layer.tile_set = default_tileset
	# 双网格在第 0 层向上偏移半格 (-16px)，使显示格中心对齐 4 个地砖交汇点
	floor0_surf_layer.position = Vector2(0.0, -16.0)
	floor0_surf_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floor0_surf_layer.material = VisionFogComponent.get_tile_shadow_material()
	floor0_surf_layer.y_sort_enabled = true
	floor0_surf_layer.z_index = 0
	floor0_surf_layer.visible = true

# 全量根据当前 GridData.surf_grid 重新计算并刷新双网格贴图
func rebuild_all_surf() -> void:
	if floor0_surf_layer:
		floor0_surf_layer.clear()

	var affected_by_floor: Dictionary = {} # z -> Dictionary of dual_cell -> true
	for k in GridData.surf_grid.keys():
		var cell := Vector2i(k.x, k.y)
		var z: int = k.z
		if not affected_by_floor.has(z):
			affected_by_floor[z] = {}
		for d in _get_affected_dual_cells(cell):
			affected_by_floor[z][d] = true

	for z in affected_by_floor.keys():
		for d in affected_by_floor[z].keys():
			_update_dual_cell(d.x, d.y, z)

func rebuild_all_turf() -> void:
	rebuild_all_surf()

# 放置或铲除某格表面覆盖物（运行时调用）
func set_surf(cell: Vector2i, z: int, exists: bool, type: String = "grass") -> void:
	GridData.set_surf(cell, z, exists, type)
	# 刷新触碰到该格子的 4 个双网格交点
	for d in _get_affected_dual_cells(cell):
		_update_dual_cell(d.x, d.y, z)

func set_turf(cell: Vector2i, z: int, exists: bool) -> void:
	set_surf(cell, z, exists, "grass")

# 某格泥土发生增删时，联动更新其四周涉及的双网格表面切片排序深度与贴图
func update_surf_around_tile(cell: Vector2i, z: int) -> void:
	if z <= 0:
		return
	for d in _get_affected_dual_cells(cell):
		_update_dual_cell(d.x, d.y, z)

# 某格是否有表面覆盖物
func has_surf(cell: Vector2i, z: int) -> bool:
	return GridData.has_surf(cell, z)

func has_turf(cell: Vector2i, z: int) -> bool:
	return has_surf(cell, z)

# 获取某格的表面类型
func get_surf(cell: Vector2i, z: int) -> String:
	return GridData.get_surf(cell, z)

# 获取逻辑网格 (x, y) 触碰到的 4 个双网格交点坐标 (适配交错等距网格 TILE_LAYOUT_STACKED)
static func get_affected_dual_cells(cell: Vector2i) -> Array[Vector2i]:
	var is_odd := (absi(cell.y) % 2 == 1)
	if is_odd:
		return [
			Vector2i(cell.x, cell.y),         # cell 是该双格的下角 (B)
			Vector2i(cell.x, cell.y + 2),     # cell 是该双格的上角 (T)
			Vector2i(cell.x, cell.y + 1),     # cell 是该双格的右角 (R)
			Vector2i(cell.x + 1, cell.y + 1), # cell 是该双格的左角 (L)
		]
	else:
		return [
			Vector2i(cell.x, cell.y),         # cell 是该双格的下角 (B)
			Vector2i(cell.x, cell.y + 2),     # cell 是该双格的上角 (T)
			Vector2i(cell.x - 1, cell.y + 1), # cell 是该双格的右角 (R)
			Vector2i(cell.x, cell.y + 1),     # cell 是该双格的左角 (L)
		]

func _get_affected_dual_cells(cell: Vector2i) -> Array[Vector2i]:
	return get_affected_dual_cells(cell)

# 更新单个双网格交点 (u, v) 在第 z 层的贴图
func _update_dual_cell(u: int, v: int, z: int) -> void:
	var is_odd := (absi(v) % 2 == 1)
	var top_cell := Vector2i(u, v - 2)
	var bottom_cell := Vector2i(u, v)
	var right_cell: Vector2i
	var left_cell: Vector2i
	if is_odd:
		right_cell = Vector2i(u + 1, v - 1)
		left_cell = Vector2i(u, v - 1)
	else:
		right_cell = Vector2i(u, v - 1)
		left_cell = Vector2i(u - 1, v - 1)

	# 计算该交点四周 4 个逻辑角的表面存在情况 (4-bit 掩码)
	var mask := 0
	var active_cells: Array[Vector2i] = []
	var dominant_type := "grass"

	if GridData.has_surf(top_cell, z):
		mask |= 1 # Top (上)
		active_cells.append(top_cell)
		dominant_type = GridData.get_surf(top_cell, z)
	if GridData.has_surf(right_cell, z):
		mask |= 2 # Right (右)
		active_cells.append(right_cell)
		dominant_type = GridData.get_surf(right_cell, z)
	if GridData.has_surf(left_cell, z):
		mask |= 4 # Left (左)
		active_cells.append(left_cell)
		dominant_type = GridData.get_surf(left_cell, z)
	if GridData.has_surf(bottom_cell, z):
		mask |= 8 # Bottom (下)
		active_cells.append(bottom_cell)
		dominant_type = GridData.get_surf(bottom_cell, z)

	var current_tileset := get_tileset_for_type(dominant_type)

	if z == 0:
		# 0 层平坦地面：直接画在底板 floor0_surf_layer 上
		if floor0_surf_layer:
			if mask == 0:
				floor0_surf_layer.erase_cell(Vector2i(u, v))
			else:
				floor0_surf_layer.tile_set = current_tileset
				floor0_surf_layer.set_cell(Vector2i(u, v), 0, MASK_TO_ATLAS[mask])
	else:
		# 1 层及以上立体高台：进入 sort_world 参与精细深度排序
		if sort_world == null:
			return
		var key := "surf_z%d_%d_%d" % [z, u, v]
		var d_layer := sort_world.get_node_or_null(key) as TileMapLayer
		if d_layer == null:
			# 兼容旧命名节点
			d_layer = sort_world.get_node_or_null("turf_z%d_%d_%d" % [z, u, v]) as TileMapLayer

		if mask == 0:
			if d_layer:
				d_layer.queue_free()
		else:
			# 找到向该双网格切片贡献表面、或与该交点相邻且同处于楼层 z 的泥土地砖格中最靠南（sort_key 最大）的深度
			# 确保表面切片不仅在自身格泥土之上，也绝不会被同楼层相邻西南/东南侧泥土地砖的顶面边角反噬遮挡，
			# 从而完美保留内凹圆弧与自然过渡边缘！
			var max_sk := -999999.0
			for c in [top_cell, right_cell, left_cell, bottom_cell]:
				if GridData.has_surf(c, z) or GridData.has_tile(c, z):
					var sk := GridData.cell_to_sort_key(c)
					if sk > max_sk:
						max_sk = sk

			if d_layer == null:
				d_layer = cell_script.new()
				d_layer.name = key
				d_layer.tile_set = current_tileset
				d_layer.position = Vector2(0.0, -float(z) * 16.0 - 16.0)
				d_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				d_layer.material = VisionFogComponent.get_tile_shadow_material()
				d_layer.y_sort_enabled = true
				d_layer.collision_enabled = false
				d_layer.set("sort_key", max_sk)
				d_layer.set("layer_no", float(z) + 0.1)
				sort_world.add_child(d_layer)
				if sort_world.has_method("insert_sort"):
					sort_world.call("insert_sort", d_layer)
			else:
				d_layer.name = key
				d_layer.tile_set = current_tileset
				d_layer.set("sort_key", max_sk)
				if sort_world.has_method("insert_sort"):
					sort_world.call("insert_sort", d_layer)

			d_layer.set_cell(Vector2i(u, v), 0, MASK_TO_ATLAS[mask])

