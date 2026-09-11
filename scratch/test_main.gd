extends SceneTree

var frame := 0

func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		change_scene_to_file("res://scene/main_scene.tscn")
		return false
	elif frame == 3:
		run_floor_test()
		quit(0)
		return true
	return false

func run_floor_test() -> void:
	var scene = current_scene
	var gd = root.get_node("GridData")
	var player = scene.get_node("sortworld/CharacterBody2D")
	var aim_ctrl: AimController = player.find_child("AimController", true, false)
	var sort_world = scene.get_node("sortworld")
	
	# Let's test on floor 1 (height = 16px)
	var p_floor := 1
	var floor_offset = gd.get_floor_pixel_offset(p_floor) # -16.0
	var player_ground = player.global_position
	var ground_center = player_ground + Vector2(0, floor_offset)
	var hand_node: Node2D = player.find_child("hand", true, false)
	var chest_origin = hand_node.global_position if hand_node else player_ground + Vector2(0, floor_offset - 6)
	
	print("--- FLOOR 1 TEST ---")
	print("Player ground = ", player_ground)
	print("Ground center = ", ground_center)
	print("Chest origin  = ", chest_origin)
	
	# Aim South pitch < 0
	var target_mouse = ground_center + Vector2(0, 20)
	aim_ctrl.update_aim(ground_center, target_mouse)
	var pitch = aim_ctrl.get_pitch_degrees()
	
	# Let's see how aim_reticle calls get_terrain_adaptive_trajectory:
	# IN AIM_RETICLE.GD LINE 138:
	# traj_info = aim_controller.call("get_terrain_adaptive_trajectory", player_ground, p_floor, chest_origin)
	var traj_reticle = aim_ctrl.get_terrain_adaptive_trajectory(player_ground, p_floor, chest_origin)
	var calc_hit_reticle: Vector2 = traj_reticle["hit_screen_pos"]
	
	# What if passed ground_center?
	var traj_correct = aim_ctrl.get_terrain_adaptive_trajectory(ground_center, p_floor, chest_origin)
	var calc_hit_correct: Vector2 = traj_correct["hit_screen_pos"]
	
	print("Pitch = %.1f°" % pitch)
	print("Mouse = ", target_mouse)
	print("Calc Hit (from aim_reticle with player_ground) = ", calc_hit_reticle)
	print("Calc Hit (if passed ground_center)             = ", calc_hit_correct)
	
	# Now what does MagicOrb do when launched on floor 1?
	# In main_scene.gd:
	# orb.call("launch_3d", aim_3d, player_ground, p_floor)
	var orb_scene = load("res://scene/particle/magic_orb.tscn")
	var orb: Node2D = orb_scene.instantiate()
	orb.set("speed", aim_ctrl.projectile_speed)
	orb.set("gravity", aim_ctrl.drop_value)
	sort_world.add_child(orb)
	orb.call("launch_3d", aim_ctrl.aim_vector_3d, player_ground, p_floor)
	
	print("Orb init: ground_pos=%s, height_px=%.2f, screen_pos=%s" % [orb.get("ground_pos"), orb.get("height_px"), orb.global_position])
	
	while not orb.is_queued_for_deletion():
		orb._physics_process(1.0 / 60.0)
		if orb.is_queued_for_deletion():
			print("Orb death: screen_pos=%s, ground_pos=%s, height_px=%.2f" % [orb.global_position, orb.get("ground_pos"), orb.get("height_px")])
			break

