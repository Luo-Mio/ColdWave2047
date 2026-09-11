extends SceneTree

const AimControllerScript = preload("res://script/components/aim_controller.gd")

func _init() -> void:
	var ctrl: AimController = AimControllerScript.new()
	ctrl.radius_min = 8.0
	ctrl.projectile_speed = 520.0
	ctrl.drop_value = 800.0
	ctrl.launch_height = 10.0
	
	var player_ground: Vector2 = Vector2(255.0, 103.0)
	var chest_origin: Vector2 = player_ground + Vector2(0.0, -6.0)
	
	var distances: Array[float] = [200.0, 150.0, 100.0, 82.22, 60.0, 40.0, 20.0, 10.0, 8.0]
	
	for s_name in ["South", "North"]:
		var sign_y := 1.0 if s_name == "South" else -1.0
		print("\n=== %s ===" % s_name)
		for dist in distances:
			var mouse := player_ground + Vector2(0.0, dist * 0.5 * sign_y)
			ctrl.update_aim(player_ground, mouse)
			
			var pitch: float = ctrl.get_pitch_degrees()
			var traj: Dictionary = ctrl.get_terrain_adaptive_trajectory(player_ground, 0, chest_origin)
			var calc_hit: Vector2 = traj["hit_screen_pos"]
			
			var aim_3d: Vector3 = ctrl.aim_vector_3d
			var horiz_length: float = sqrt(aim_3d.x * aim_3d.x + aim_3d.y * aim_3d.y)
			var v_horiz: float = 520.0 * horiz_length
			var vz: float = aim_3d.z * 520.0
			var cos_a: float = (aim_3d.x - aim_3d.y) / (sqrt(2.0) * horiz_length)
			var sin_a: float = (aim_3d.x + aim_3d.y) / (sqrt(2.0) * horiz_length)
			var vel_ground: Vector2 = Vector2(cos_a, sin_a * 0.5) * v_horiz
			
			var g_pos: Vector2 = player_ground
			var h_px: float = 10.0
			var last_pos: Vector2 = g_pos - Vector2(0, h_px)
			var dt: float = 1.0 / 60.0
			
			for step in range(300):
				g_pos += vel_ground * dt
				h_px += vz * dt
				vz -= 800.0 * dt
				last_pos = g_pos - Vector2(0, h_px)
				if h_px <= 0.0:
					break
			
			var diff: Vector2 = last_pos - calc_hit
			print("Dist=%5.1f | Pitch=%5.1f° | MouseY=%5.1f | CalcHitY=%5.1f | OrbHitY=%5.1f | Diff Y = %+5.1f" % [
				dist, pitch, mouse.y, calc_hit.y, last_pos.y, diff.y
			])
			
	ctrl.free()
	quit(0)

