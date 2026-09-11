extends SceneTree

func _init() -> void:
	var ctrl := AimController.new()
	ctrl.projectile_speed = 520.0
	ctrl.drop_value = 800.0
	ctrl.launch_height = 10.0
	
	var angles_deg := [0, 45, 90, 135, 180, 225, 270, 315]
	var test_target_r := 30.0 # Well inside r0 (82px), so pitch < 0
	
	print("Testing target_r = 30.0 across 8 directions...")
	var player_pos := Vector2(200, 200)
	var chest_origin := player_pos + Vector2(0, -6)
	
	for a_deg in angles_deg:
		var a_rad := deg_to_rad(a_deg)
		var mouse_pos := player_pos + Vector2(test_target_r * cos(a_rad), test_target_r * sin(a_rad) * 0.5)
		
		ctrl.update_aim(player_pos, mouse_pos)
		var pitch_deg := ctrl.get_pitch_degrees()
		
		# Get calculated trajectory from get_terrain_adaptive_trajectory
		var traj := ctrl.get_terrain_adaptive_trajectory(player_pos, 0, chest_origin)
		var calc_hit: Vector2 = traj["hit_screen_pos"]
		
		# Simulate MagicOrb
		var aim_3d: Vector3 = ctrl.aim_vector_3d
		var horiz_length := sqrt(aim_3d.x * aim_3d.x + aim_3d.y * aim_3d.y)
		var v_horiz := 520.0 * horiz_length
		var vz := aim_3d.z * 520.0
		
		var gx := aim_3d.x / horiz_length
		var gy := aim_3d.y / horiz_length
		var cos_a := (gx - gy) / sqrt(2.0)
		var sin_a := (gx + gy) / sqrt(2.0)
		var vel_ground := Vector2(cos_a, sin_a * 0.5) * v_horiz
		
		var g_pos := player_pos
		var h_px := 10.0
		var dt := 1.0 / 60.0
		var orb_final_screen := Vector2.ZERO
		
		for step in range(200):
			g_pos += vel_ground * dt
			h_px += vz * dt
			vz -= 800.0 * dt
			if h_px <= 0.0:
				orb_final_screen = g_pos - Vector2(0, h_px)
				break
				
		var diff := orb_final_screen - calc_hit
		print("Angle %3d° (pitch %5.1f°): Mouse=(%6.1f, %6.1f) | CalcHit=(%6.1f, %6.1f) | OrbHit=(%6.1f, %6.1f) | Diff=(%5.1f, %5.1f)" % [
			a_deg, pitch_deg, mouse_pos.x, mouse_pos.y, calc_hit.x, calc_hit.y, orb_final_screen.x, orb_final_screen.y, diff.x, diff.y
		])
	
	quit(0)

