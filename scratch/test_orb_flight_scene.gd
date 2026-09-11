extends SceneTree

func _init() -> void:
	var main_scene = load("res://scene/main_scene.tscn").instantiate()
	root.add_child(main_scene)
	
	var player = main_scene.get_node("sortworld/CharacterBody2D")
	var aim_ctrl: AimController = player.find_child("AimController", true, false)
	var sort_world = main_scene.get_node("sortworld")
	
	print("Player pos: ", player.global_position)
	
	var test_cases: Array[Dictionary] = [
		{"dir": "South (+Y)", "vec": Vector2(0, 30)},
		{"dir": "North (-Y)", "vec": Vector2(0, -30)},
		{"dir": "East (+X)",  "vec": Vector2(30, 0)},
		{"dir": "West (-X)",  "vec": Vector2(-30, 0)},
		{"dir": "South (close 12px)", "vec": Vector2(0, 12)},
		{"dir": "North (close 12px)", "vec": Vector2(0, -12)},
	]
	
	for tc in test_cases:
		var offset: Vector2 = tc["vec"]
		var target_mouse: Vector2 = player.global_position + offset
		aim_ctrl.update_aim(player.global_position, target_mouse)
		
		var pitch_deg: float = aim_ctrl.get_pitch_degrees()
		var traj: Dictionary = aim_ctrl.get_terrain_adaptive_trajectory(player.global_position, 0, player.global_position + Vector2(0, -6))
		var calc_hit: Vector2 = traj["hit_screen_pos"]
		
		# Now spawn orb
		var orb: MagicOrb = load("res://scene/particle/magic_orb.tscn").instantiate()
		orb.speed = aim_ctrl.projectile_speed
		orb.gravity = aim_ctrl.drop_value
		sort_world.add_child(orb)
		orb.launch_3d(aim_ctrl.aim_vector_3d, player.global_position, 0)
		
		var last_orb_pos: Vector2 = orb.global_position
		var last_ground_pos: Vector2 = orb.ground_pos
		var last_height: float = orb.height_px
		var frame_count: int = 0
		
		while is_instance_valid(orb):
			last_orb_pos = orb.global_position
			last_ground_pos = orb.ground_pos
			last_height = orb.height_px
			frame_count += 1
			# Manually step physics
			orb._physics_process(1.0 / 60.0)
			if frame_count > 100:
				break
				
		print("\n[%s] TargetMouse=%s, Pitch=%.1f°" % [tc["dir"], target_mouse, pitch_deg])
		print("  Calc Hit Dot = ", calc_hit)
		print("  Last Orb Pos = ", last_orb_pos, " (height_px=%.2f, frames=%d)" % [last_height, frame_count])
		print("  Discrepancy (Orb - Calc) = ", last_orb_pos - calc_hit)
		print("  Discrepancy (Orb - Mouse) = ", last_orb_pos - target_mouse)
		
	quit(0)

