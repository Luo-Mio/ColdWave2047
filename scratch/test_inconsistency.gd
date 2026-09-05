extends SceneTree

func _init() -> void:
	print("=== Simulating Tile Shadow vs Creature Invisibility ===")
	
	var p_pos := Vector2(255, 103)
	var p_eye_z := 20.0
	
	# Suppose tile is 1 floor high (h = 16.0)
	# Let's test a ray from p_pos through the tile to various distances
	# In isometric grid, let's say tile is at distance D_tile from p_pos
	var d_tile := 64.0
	var tile_pos := p_pos + Vector2(d_tile, 0)
	
	print("\n--- Theoretical 3D Geometry ---")
	print("Player eye Z: %f, Tile height: 16.0" % p_eye_z)
	print("Distance to tile: %f" % d_tile)
	var max_shadow_dist := d_tile * (p_eye_z / (p_eye_z - 16.0))
	print("Geometric shadow cutoff distance from player: %f (shadow length behind tile: %f)" % [max_shadow_dist, max_shadow_dist - d_tile])

	# Now let's test raymarching math with different step counts
	for test_dist in [80.0, 120.0, 160.0, 200.0, 240.0, 280.0, 310.0, 330.0, 400.0, 500.0]:
		var target_pos := p_pos + Vector2(test_dist, 0)
		var target_z := 0.0 # ground
		
		# In terrain_raymarch.gdshader (steps = 32):
		var steps := 32
		var shader_blocked := false
		for i in range(1, steps - 1):
			var s := float(i) / float(steps)
			var cur_pos := p_pos.lerp(target_pos, s)
			var cur_ray_z := lerpf(p_eye_z, target_z, s)
			var dist_to_eye := cur_pos.distance_to(p_pos)
			# If this step hits the tile (around d_tile, width ~32)
			if abs(dist_to_eye - d_tile) < 16.0:
				if cur_ray_z < 16.0 - 0.5:
					shader_blocked = true
					break
		
		# In _is_blocked_by_terrain (steps = clampi(int(total_dist / 24.0), 6, 32)):
		var cpu_steps := clampi(int(test_dist / 24.0), 6, 32)
		var cpu_blocked := false
		for i in range(1, cpu_steps):
			var s := float(i) / float(cpu_steps)
			var cur_pos := p_pos.lerp(target_pos, s)
			var cur_ray_z := lerpf(p_eye_z, target_z, s)
			var dist_to_eye := cur_pos.distance_to(p_pos)
			if abs(dist_to_eye - d_tile) < 16.0:
				if cur_ray_z < 16.0:
					cpu_blocked = true
					break
		
		print("Dist: %3.0f | Behind tile: %3.0f | Shader Blocked: %5s (steps=%2d) | CPU Blocked: %5s (steps=%2d)" % [
			test_dist, test_dist - d_tile, shader_blocked, steps, cpu_blocked, cpu_steps
		])

	quit()

