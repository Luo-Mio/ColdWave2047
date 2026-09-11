extends SceneTree

func _init() -> void:
	var ctrl := AimController.new()
	ctrl.projectile_speed = 520.0
	ctrl.drop_value = 800.0
	ctrl.launch_height = 10.0
	
	# Check horizontal radius (where pitch = 0)
	var r0 := ctrl.get_effective_radius_horizontal()
	print("r0 (pitch = 0 radius): ", r0)
	
	# Let's test a range of distances:
	# r0 is horizontal, so r < r0 means pitch < 0 (down-pitch / 俯角)
	var test_rs := [r0 * 0.9, r0 * 0.7, r0 * 0.5, r0 * 0.3, r0 * 0.1, 10.0]
	
	for r in test_rs:
		var p := ctrl.solve_pitch_for_distance(r)
		var p_deg := rad_to_deg(p)
		print("\n--- Test target_r = %.2f (pitch = %.2f deg) ---" % [r, p_deg])
		
		# Now simulate MagicOrb physics
		var cos_p := cos(p)
		var sin_p := sin(p)
		var vx := 520.0 * cos_p
		var vy := 520.0 * sin_p # initial velocity_z
		
		var x_ground := 0.0
		var z := 10.0 # launch height
		var vz := vy
		var dt := 1.0 / 60.0
		var t := 0.0
		
		# Theoretical t_impact from formula:
		# 0.5 * g * t^2 - vy * t - h = 0
		var disc := vy * vy + 2.0 * 800.0 * 10.0
		var t_theory := (vy + sqrt(disc)) / 800.0
		var x_theory := vx * t_theory
		
		print("Theoretical: t_land = %.4f s, x_land = %.2f px (target_r = %.2f)" % [t_theory, x_theory, r])
		
		while z > 0.0 and t < 5.0:
			x_ground += vx * dt
			z += vz * dt
			vz -= 800.0 * dt
			t += dt
			
		print("Simulation (dt=1/60): t_land = %.4f s, x_land = %.2f px, final z = %.2f" % [t, x_ground, z])

	quit(0)

