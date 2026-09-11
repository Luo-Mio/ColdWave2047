extends SceneTree

var frame := 0

func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		change_scene_to_file("res://scene/main_scene.tscn")
		return false
	elif frame == 3:
		run_test()
		quit(0)
		return true
	return false

func run_test() -> void:
	var scene = current_scene
	var gd = root.get_node("GridData")
	var player = scene.get_node("sortworld/CharacterBody2D")
	var aim_ctrl: AimController = player.find_child("AimController", true, false)
	var sort_world = scene.get_node("sortworld")
	var hand_node: Node2D = player.find_child("hand", true, false)
	
	var player_ground: Vector2 = player.global_position
	var p_cell: Vector2i = gd.world_to_cell(player_ground)
	var p_floor: int = gd.get_highest_floor(p_cell)
	var floor_y_lift: float = gd.get_floor_pixel_offset(p_floor)
	var ground_center := player_ground + Vector2(0.0, floor_y_lift)
	var chest_origin: Vector2 = hand_node.global_position if hand_node else player_ground + Vector2(0.0, floor_y_lift - 8.0)
	
	# Determine actual launch height from hand to ground center
	var hand_height: float = ground_center.y - chest_origin.y
	print("Player ground = ", player_ground)
	print("Ground center = ", ground_center)
	print("Chest origin  = ", chest_origin)
	print("Hand height   = ", hand_height)
	
	aim_ctrl.launch_height = hand_height
	aim_ctrl.radius_min = 8.0
	
	var r0 = aim_ctrl.get_effective_radius_horizontal()
	print("r0 (pitch 0 distance) = ", r0)
	
	var test_cases = [
		{"name": "South Pitch 0 (r=r0)",    "offset": Vector2(0, r0 * 0.5)},
		{"name": "South Pitch -4.4 (r=60)", "offset": Vector2(0, 60 * 0.5)},
		{"name": "South Pitch -10.7 (r=40)", "offset": Vector2(0, 40 * 0.5)},
		{"name": "South Pitch -24.9 (r=20)", "offset": Vector2(0, 20 * 0.5)},
		{"name": "South Pitch -44.2 (r=8)",  "offset": Vector2(0, 8 * 0.5)},
		{"name": "North Pitch 0 (r=r0)",    "offset": Vector2(0, -r0 * 0.5)},
		{"name": "North Pitch -10.7 (r=40)", "offset": Vector2(0, -40 * 0.5)},
		{"name": "North Pitch -24.9 (r=20)", "offset": Vector2(0, -20 * 0.5)},
		{"name": "East Pitch -10.7 (r=40)",  "offset": Vector2(40, 0)},
		{"name": "West Pitch -10.7 (r=40)",  "offset": Vector2(-40, 0)},
		{"name": "SE Pitch -10.7 (r=40)",    "offset": Vector2(40, 40 * 0.5) / sqrt(2.0)},
	]
	
	for tc in test_cases:
		var target_mouse = ground_center + tc["offset"]
		aim_ctrl.update_aim(ground_center, target_mouse)
		var pitch = aim_ctrl.get_pitch_degrees()
		
		# --- NEW TRAJECTORY FORMULA ---
		var cos_p := cos(aim_ctrl.pitch_rad)
		var sin_p := sin(aim_ctrl.pitch_rad)
		var cos_a := cos(aim_ctrl.azimuth_rad)
		var sin_a := sin(aim_ctrl.azimuth_rad)
		var vx := aim_ctrl.projectile_speed * cos_p
		var vy := aim_ctrl.projectile_speed * sin_p
		var h_player := float(p_floor) * 16.0
		var z_start := h_player + hand_height
		
		var disc_base := vy * vy + 2.0 * aim_ctrl.drop_value * hand_height
		var t_base := (vy + sqrt(maxf(disc_base, 0.0))) / aim_ctrl.drop_value
		
		# Analytical screen landing pos:
		var g_land := player_ground + Vector2(cos_a, 0.5 * sin_a) * (vx * t_base)
		var screen_land := g_land - Vector2(0.0, h_player) # since surface is h_player
		
		# --- SIMULATE ORB WITH CLAMPED IMPACT ---
		var v_horiz := vx
		var vz := vy
		var orb_ground := player_ground
		var orb_h := z_start
		var dt := 1.0 / 60.0
		var orb_vel_g := Vector2(cos_a, 0.5 * sin_a) * v_horiz
		
		var orb_impact_pos := Vector2.ZERO
		
		for step in range(300):
			var next_ground := orb_ground + orb_vel_g * dt
			var next_h := orb_h + (vz - 0.5 * aim_ctrl.drop_value * dt) * dt
			var next_vz := vz - aim_ctrl.drop_value * dt
			
			var c: Vector2i = gd.world_to_cell(next_ground)
			var fl: int = gd.get_highest_floor(c) if gd.has_any_tile(c) else 0
			var surf_h := float(fl) * 16.0
			
			if next_h <= surf_h:
				# Interpolate exact contact fraction
				var denom := (orb_h - next_h)
				var frac := clampf((orb_h - surf_h) / denom, 0.0, 1.0) if absf(denom) > 0.0001 else 0.5
				var contact_ground := orb_ground.lerp(next_ground, frac)
				orb_impact_pos = contact_ground - Vector2(0.0, surf_h)
				break
				
			orb_ground = next_ground
			orb_h = next_h
			vz = next_vz
			
		var diff := orb_impact_pos - screen_land
		print("[%s] Pitch=%5.1f° | TargetMouse=(%5.1f,%5.1f) | TrajLand=(%5.1f,%5.1f) | OrbImpact=(%5.1f,%5.1f) | Diff Y=%+5.2f, X=%+5.2f" % [
			tc["name"], pitch, target_mouse.x, target_mouse.y, screen_land.x, screen_land.y, orb_impact_pos.x, orb_impact_pos.y, diff.y, diff.x
		])
