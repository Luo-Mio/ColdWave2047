# map_manager.gd —— 纯数据驱动地图系统管理器 (支持运行时启动自动载入 + 编辑器视口瞬时阅览)
@tool
class_name MapManager
extends Node

signal map_saved(file_path: String)
signal map_loaded(file_path: String)

@export_group("节点依赖")
@export var ground_layer: TileMapLayer
@export var entities_container: Node2D
@export var air_wall_manager: StaticBody2D
@export var vision_shadow_manager: VisionShadowManager
@export var selector: Node2D

@export_group("数据文件")
@export_file("*.json") var map_file_path: String = "res://map_data.json"

@export_group("编辑器视口实时阅览 (只读预览，绝不污染场景树与 .tscn)")
## 是否在 Godot 编辑器 2D 视口中实时阅览地图 (不产生乱码节点，按 Ctrl+S 不会写入场景树)
@export var show_editor_preview: bool = true:
	set(v):
		show_editor_preview = v
		if Engine.is_editor_hint():
			_update_editor_preview()

@export_group("编辑器操作 (在检查器中点击直接执行)")
## 在编辑器中重新刷新视口预览
@export_tool_button("🔄 刷新编辑器视口预览") var btn_refresh = _update_editor_preview
## 在编辑器中将当前地图保存到 JSON 文件
@export_tool_button("💾 保存地图数据到 JSON") var btn_save = _editor_save_map
## 在编辑器中将全图所有地砖随机分配变种贴图
@export_tool_button("🎲 随机化所有地砖变种") var btn_randomize = _editor_randomize_tiles

# 专用瞬时预览容器 (无 owner，绝不序列化进场景文件)
var _preview_container: Node2D = null

func _ready() -> void:
	_auto_find_references()

	if Engine.is_editor_hint():
		# 编辑器环境下：自动呈现视口预览
		if show_editor_preview:
			call_deferred("_update_editor_preview")
	else:
		# 游戏运行时：纯数据驱动，启动时自动从 map_data.json 载入全图并生成实体
		if FileAccess.file_exists(map_file_path):
			call_deferred("load_map", map_file_path)

func _auto_find_references() -> void:
	var root := get_parent()
	if root:
		if ground_layer == null:
			ground_layer = root.find_child("GroundLayer", true, false) as TileMapLayer
		if entities_container == null:
			entities_container = root.find_child("Entities", true, false) as Node2D
		if air_wall_manager == null:
			air_wall_manager = root.find_child("AirWallManager", true, false) as StaticBody2D
		if vision_shadow_manager == null:
			vision_shadow_manager = root.find_child("VisionShadowManager", true, false) as VisionShadowManager
		if selector == null:
			selector = root.find_child("Selector", true, false) as Node2D

## 保存地图数据到 JSON 文件 (记录所有地砖位置与随机编号，以及全部实体对象)
func save_map(path: String = "") -> bool:
	_auto_find_references()
	if path.is_empty():
		path = map_file_path

	if ground_layer == null:
		push_error("[MapManager] 保存失败: GroundLayer 未找到！")
		return false

	# 1. 序列化地砖层 (记录每个坐标与具体随机选中的 atlas 编号)
	var tiles_data: Array[Dictionary] = []
	var used_cells := ground_layer.get_used_cells()
	for cell in used_cells:
		var source_id := ground_layer.get_cell_source_id(cell)
		var atlas_coords := ground_layer.get_cell_atlas_coords(cell)
		var alt_tile := ground_layer.get_cell_alternative_tile(cell)
		tiles_data.append({
			"x": cell.x,
			"y": cell.y,
			"s": source_id,
			"ax": atlas_coords.x,
			"ay": atlas_coords.y,
			"alt": alt_tile
		})

	# 2. 序列化已放置的实体 (树木、小麦、建筑等)
	var objects_data: Array[Dictionary] = []
	var placed_objs: Array[Dictionary] = []
	var grid_data_node = get_node_or_null("/root/GridData")
	if not Engine.is_editor_hint() and grid_data_node and grid_data_node.has_method("get_all_placed_objects"):
		placed_objs = grid_data_node.call("get_all_placed_objects")

	# 兼容编辑器模式或备用直接扫描实体容器
	if placed_objs.is_empty():
		var source_nodes: Array = []
		if entities_container:
			source_nodes.append_array(entities_container.get_children())
		if _preview_container:
			source_nodes.append_array(_preview_container.get_children())

		for child in source_nodes:
			if child.is_in_group("player") or child == _preview_container:
				continue
			if child.has_meta("item_id"):
				var c: Vector2i = child.get_meta("cell", Vector2i.ZERO)
				var sc: Vector2i = child.get_meta("sub_cell", Vector2i.ZERO)
				var sz: Vector2i = child.get_meta("grid_size", Vector2i(4, 4))
				var var_idx: int = child.call("get_variant") if child.has_method("get_variant") else int(child.get_meta("variant", 0))
				objects_data.append({
					"id": child.get_meta("item_id"),
					"cell": [c.x, c.y],
					"sub_cell": [sc.x, sc.y],
					"grid_size": [sz.x, sz.y],
					"variant": var_idx
				})
	else:
		for obj_info in placed_objs:
			var c: Vector2i = obj_info["cell"]
			var sc: Vector2i = obj_info["sub_cell"]
			var sz: Vector2i = obj_info["grid_size"]
			var var_idx: int = int(obj_info.get("variant", 0))
			objects_data.append({
				"id": obj_info["id"],
				"cell": [c.x, c.y],
				"sub_cell": [sc.x, sc.y],
				"grid_size": [sz.x, sz.y],
				"variant": var_idx
			})

	# 3. 组装整张地图结构并写入 JSON
	var map_dict: Dictionary = {
		"version": 1,
		"tile_count": tiles_data.size(),
		"object_count": objects_data.size(),
		"tiles": tiles_data,
		"objects": objects_data
	}

	var json_str := JSON.stringify(map_dict, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		push_error("[MapManager] 打开文件失败: %s (错误代码: %d)" % [path, err])
		return false

	file.store_string(json_str)
	file.close()

	print("[MapManager] 地图成功保存至: %s (地块: %d, 物体: %d)" % [path, tiles_data.size(), objects_data.size()])
	map_saved.emit(path)
	return true

## 从 JSON 文件载入地图数据并在场景中完全还原 (运行时生成真实实体与网格数据)
func load_map(path: String = "") -> bool:
	_auto_find_references()
	if path.is_empty():
		path = map_file_path

	if not FileAccess.file_exists(path):
		push_warning("[MapManager] 地图文件不存在: %s" % path)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[MapManager] 读取文件失败: %s" % path)
		return false

	var json_text := file.get_as_text()
	file.close()

	var parse_res = JSON.parse_string(json_text)
	if not (parse_res is Dictionary):
		push_error("[MapManager] JSON 解析失败，格式不正确！")
		return false

	var map_dict: Dictionary = parse_res

	# 1. 重建地砖层
	if ground_layer:
		ground_layer.clear()
		var tiles_arr: Array = map_dict.get("tiles", [])
		for t in tiles_arr:
			var cell := Vector2i(int(t["x"]), int(t["y"]))
			var source_id := int(t.get("s", 0))
			var atlas := Vector2i(int(t.get("ax", 0)), int(t.get("ay", 0)))
			var alt := int(t.get("alt", 0))
			ground_layer.set_cell(cell, source_id, atlas, alt)

	# 2. 清除并重建实体层
	var grid_data_node = get_node_or_null("/root/GridData")
	if not Engine.is_editor_hint() and grid_data_node and grid_data_node.has_method("clear_all_objects"):
		grid_data_node.call("clear_all_objects")

	if entities_container:
		var children := entities_container.get_children()
		for child in children:
			if child.is_in_group("player"):
				continue
			if child == _preview_container:
				continue
			child.queue_free()

		# 实例化所有已记录物体
		var objects_arr: Array = map_dict.get("objects", [])
		for o in objects_arr:
			var item_id: String = o.get("id", "")
			var cell := Vector2i(int(o["cell"][0]), int(o["cell"][1]))
			var sub_cell := Vector2i(int(o["sub_cell"][0]), int(o["sub_cell"][1]))
			var grid_size := Vector2i(int(o["grid_size"][0]), int(o["grid_size"][1]))

			var scene_path := _resolve_scene_path(item_id)
			if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
				var packed := load(scene_path) as PackedScene
				if packed:
					var obj := packed.instantiate() as Node2D
					var cell_center := _get_cell_world_center(cell)
					var sub_offset := _get_sub_offset(sub_cell, grid_size)
					obj.position = cell_center + sub_offset
					obj.name = "%s_%d_%d" % [item_id, cell.x, cell.y]

					# 恢复保存的变体 (若无记录则自动随机)
					var var_idx: int = int(o.get("variant", -1))
					if var_idx >= 0:
						obj.set_meta("variant", var_idx)
					entities_container.add_child(obj)
					if var_idx >= 0 and obj.has_method("set_variant"):
						obj.call("set_variant", var_idx)
					elif var_idx < 0 and obj.has_method("randomize_variant"):
						obj.call("randomize_variant")

					if not Engine.is_editor_hint() and grid_data_node and grid_data_node.has_method("register_object"):
						grid_data_node.call("register_object", cell, obj, sub_cell, grid_size, item_id, var_idx)
					else:
						obj.set_meta("item_id", item_id)
						obj.set_meta("cell", cell)
						obj.set_meta("sub_cell", sub_cell)
						obj.set_meta("grid_size", grid_size)

	# 3. 刷新系统
	_refresh_systems()

	print("[MapManager] 地图成功载入: %s (还原地块: %d, 物体: %d)" % [path, map_dict.get("tile_count", 0), map_dict.get("object_count", 0)])
	map_loaded.emit(path)
	return true

## === 编辑器视口瞬时阅览核心实现 (绝不设置 owner，保证场景树永远干净) ===
func _update_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_auto_find_references()
	_clear_editor_preview()

	if not show_editor_preview:
		return

	if not FileAccess.file_exists(map_file_path):
		return

	var file := FileAccess.open(map_file_path, FileAccess.READ)
	if file == null:
		return
	var json_text := file.get_as_text()
	file.close()

	var parse_res = JSON.parse_string(json_text)
	if not (parse_res is Dictionary):
		return
	var map_dict: Dictionary = parse_res

	# 1. 刷新地砖视口呈现
	if ground_layer:
		ground_layer.clear()
		for t in map_dict.get("tiles", []):
			var cell := Vector2i(int(t["x"]), int(t["y"]))
			var source_id := int(t.get("s", 0))
			var atlas := Vector2i(int(t.get("ax", 0)), int(t.get("ay", 0)))
			var alt := int(t.get("alt", 0))
			ground_layer.set_cell(cell, source_id, atlas, alt)

	# 2. 创建视口预览容器 (挂在 Entities 下，但不设 owner，绝不写进 .tscn)
	if entities_container:
		_preview_container = Node2D.new()
		_preview_container.name = "EditorPreview"
		_preview_container.y_sort_enabled = true
		_preview_container.process_mode = Node.PROCESS_MODE_DISABLED # 禁用物理与脚本交互
		entities_container.add_child(_preview_container)
		# 重点: 绝对不要设置 _preview_container.owner = edited_root！

		for o in map_dict.get("objects", []):
			var item_id: String = o.get("id", "")
			var cell := Vector2i(int(o["cell"][0]), int(o["cell"][1]))
			var sub_cell := Vector2i(int(o["sub_cell"][0]), int(o["sub_cell"][1]))
			var grid_size := Vector2i(int(o["grid_size"][0]), int(o["grid_size"][1]))

			var scene_path := _resolve_scene_path(item_id)
			if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
				var packed := load(scene_path) as PackedScene
				if packed:
					var obj := packed.instantiate() as Node2D
					var cell_center := _get_cell_world_center(cell)
					var sub_offset := _get_sub_offset(sub_cell, grid_size)
					obj.position = cell_center + sub_offset
					obj.name = "%s_%d_%d" % [item_id, cell.x, cell.y]
					obj.set_meta("item_id", item_id)
					obj.set_meta("cell", cell)
					obj.set_meta("sub_cell", sub_cell)
					obj.set_meta("grid_size", grid_size)
					var var_idx: int = int(o.get("variant", -1))
					if var_idx >= 0:
						obj.set_meta("variant", var_idx)
					_preview_container.add_child(obj)
					if var_idx >= 0 and obj.has_method("set_variant"):
						obj.call("set_variant", var_idx)
					# 重点: 同样不设置 obj.owner！

	print("[MapManager] 编辑器视口预览已刷新 (显示 %d 块地砖与 %d 个物体，场景树保持 0 污染)" % [map_dict.get("tile_count", 0), map_dict.get("object_count", 0)])

func _clear_editor_preview() -> void:
	if _preview_container and is_instance_valid(_preview_container):
		_preview_container.free()
		_preview_container = null
	if entities_container:
		var old = entities_container.get_node_or_null("EditorPreview")
		if old:
			old.free()

## 随机化全部地砖变种 (遍历当前图集内所有定义的变种编号并均匀分配)
func randomize_all_ground_tiles(source_id: int = 0) -> void:
	_auto_find_references()
	if ground_layer == null or ground_layer.tile_set == null:
		return

	var source := ground_layer.tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null or source.get_tiles_count() <= 0:
		return

	var tile_count := source.get_tiles_count()
	var variants: Array[Vector2i] = []
	for i in tile_count:
		variants.append(source.get_tile_id(i))

	var used_cells := ground_layer.get_used_cells()
	for cell in used_cells:
		var alt := ground_layer.get_cell_alternative_tile(cell)
		var rand_atlas: Vector2i = variants[randi() % variants.size()]
		ground_layer.set_cell(cell, source_id, rand_atlas, alt)

	_refresh_systems()
	print("[MapManager] 已为 %d 块地砖随机分配了 %d 种贴图变种！" % [used_cells.size(), variants.size()])

## 解析物体场景路径
func _resolve_scene_path(item_id: String) -> String:
	if has_node("/root/ItemDatabase"):
		var db = get_node("/root/ItemDatabase")
		if db and db.has_method("get_item"):
			var data: Dictionary = db.call("get_item", item_id)
			var p: String = data.get("scene", "")
			if not p.is_empty():
				return p

	# 内置备用映射 (确保编辑器环境下即便无 Autoload 也能 100% 正确还原)
	match item_id:
		"birch_tree":
			return "res://scene/Object/Tree/BritchTree/britch_tree.tscn"
		"oak_tree", "autumn_tree":
			return "res://scene/Object/Tree/OakTree/oak_tree.tscn"
		"wheat":
			return "res://scene/Object/Plant/wheat.tscn"
	return ""

func _get_cell_world_center(cell: Vector2i) -> Vector2:
	var grid_data_node = get_node_or_null("/root/GridData")
	if not Engine.is_editor_hint() and grid_data_node and grid_data_node.has_method("cell_to_world"):
		return grid_data_node.call("cell_to_world", cell)
	if ground_layer:
		return ground_layer.map_to_local(cell) + ground_layer.position
	return Vector2((cell.x - cell.y) * 32.0, (cell.x + cell.y) * 16.0 + 16.0)

func _get_sub_offset(sub_cell: Vector2i, size: Vector2i) -> Vector2:
	var grid_data_node = get_node_or_null("/root/GridData")
	if not Engine.is_editor_hint() and grid_data_node and grid_data_node.has_method("sub_cell_to_local_offset"):
		return grid_data_node.call("sub_cell_to_local_offset", sub_cell, size)
	var center_u := float(sub_cell.x) + float(size.x) * 0.5 - 2.0
	var center_v := float(sub_cell.y) + float(size.y) * 0.5 - 2.0
	var offset_x := (center_u - center_v) * 8.0
	var offset_y := (center_u + center_v) * 4.0
	return Vector2(offset_x, offset_y).round()

func _refresh_systems() -> void:
	if Engine.is_editor_hint():
		return
	if air_wall_manager and air_wall_manager.has_method("rebuild_walls"):
		air_wall_manager.call("rebuild_walls")
	if vision_shadow_manager and vision_shadow_manager.has_method("force_update"):
		vision_shadow_manager.call("force_update")
	if selector and selector.has_method("force_update"):
		selector.call("force_update")

func _editor_save_map() -> void:
	save_map(map_file_path)

func _editor_randomize_tiles() -> void:
	randomize_all_ground_tiles(0)
