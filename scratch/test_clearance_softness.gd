extends SceneTree

func _init() -> void:
	print("=== Testing Terrain Shadow Clearance Math ===")
	
	var p_eye_z: float = 20.0
	var tile_h: float = 16.0
	var target_z: float = 0.0
	var d_tile: float = 64.0 # tile is 64px from player
	
	print("Player eye Z: %f, Tile H: %f" % [p_eye_z, tile_h])
	print("Tile distance: %f px" % d_tile)
	var cutoff: float = d_tile * (p_eye_z / (p_eye_z - tile_h))
	print("Geometric cutoff: %f px (shadow length: %f px)\n" % [cutoff, cutoff - d_tile])
	
	var distances: Array[float] = [100.0, 200.0, 300.0, 319.0, 321.0, 350.0, 400.0, 600.0]
	for test_dist in distances:
		var s: float = d_tile / test_dist
		var cur_ray_z: float = lerpf(p_eye_z, target_z, s)
		var clearance: float = cur_ray_z - tile_h
		
		# Old shader math with shadow_softness = 16.0:
		var t_old: float = clampf((clearance + 0.5) / 16.0, 0.0, 1.0)
		var vis_old: float = smoothstep(0.0, 1.0, t_old)
		
		# New shader math with z_softness = 1.5:
		# Penumbra centered at clearance = 0 (-1.5 to +1.5)
		var z_softness: float = 1.5
		var t_new: float = clampf((clearance + z_softness) / (2.0 * z_softness), 0.0, 1.0)
		var vis_new: float = smoothstep(0.0, 1.0, t_new)
		
		# CPU is_blocked:
		var cpu_blocked: bool = (cur_ray_z < tile_h)
		
		print("Dist: %3.0f | Ray Z: %4.1f | Clearance: %+4.1f | Old Vis: %4.2f | New Vis: %4.2f | CPU Blocked: %5s" % [
			test_dist, cur_ray_z, clearance, vis_old, vis_new, cpu_blocked
		])
		
	quit()

