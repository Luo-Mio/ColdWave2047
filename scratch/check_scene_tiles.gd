extends SceneTree

const GridDataScript = preload("res://script/core/grid_data.gd")

func _init() -> void:
	var gd = GridDataScript.new()
	root.add_child(gd)
	
	# Load main_scene without scripts
	var packed: PackedScene = load("res://scene/main_scene.tscn")
	var state := packed.get_state()
	
	# Find layers and CharacterBody2D
	var chara_pos := Vector2.ZERO
	var tile_layers: Array[TileMapLayer] = []
	
	var scene = packed.instantiate()
	root.add_child(scene)
	
	var player = scene.find_child("CharacterBody2D", true, false)
	if player:
		chara_pos = player.global_position
		print("Found player at: ", chara_pos)
		
	var layers_node = scene.find_child("layers", true, false)
	if layers_node:
		for c in layers_node.get_children():
			if c is TileMapLayer:
				tile_layers.append(c)
				
		tile_layers.sort_custom(func(a: TileMapLayer, b: TileMapLayer) -> bool:
			return a.position.y > b.position.y
		)
		gd.build_from_layers(tile_layers)
		
		var p_cell = gd.world_to_cell(chara_pos)
		var p_fl = gd.get_highest_floor(p_cell)
		print("Player cell = ", p_cell, " floor = ", p_fl)
		
		var p_ground = chara_pos
		var p_floor_offset = gd.get_floor_pixel_offset(p_fl)
		print("Player floor_pixel_offset = ", p_floor_offset)
	
	quit(0)

