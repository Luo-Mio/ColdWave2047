extends Node

func _ready() -> void:
	var main_scene = load("res://scene/main_scene.tscn").instantiate()
	add_child(main_scene)
	for i in range(5):
		await get_tree().physics_frame
	
	var xray = main_scene.find_child("WallXRayManager", true, false)
	var chara = main_scene.find_child("CharacterBody2D", true, false)
	var sort_world = main_scene.find_child("sortworld", true, false)
	
	print("\n==================================================================")
	print("--- Running Wall X-Ray Plan A Comprehensive Test Suite ---")
	print("==================================================================")
	
	var test_cases = [
		{"name": "正前方 (南侧 160, 视野无遮挡)", "pos": Vector2(320, 160), "expect_xray": false},
		{"name": "正前方 (南侧 144, 刚好在南顶点)", "pos": Vector2(320, 144), "expect_xray": false},
		{"name": "图中位置 (北侧 0, 远处)", "pos": Vector2(320, 0), "expect_xray": true},
		{"name": "北侧 64 (靠近中)", "pos": Vector2(320, 64), "expect_xray": true},
		{"name": "北侧 80 (北边缘)", "pos": Vector2(320, 80), "expect_xray": true},
		{"name": "左侧开阔地 (西侧 250, 125)", "pos": Vector2(250, 125), "expect_xray": true},
		{"name": "右侧开阔地 (东侧 390, 120)", "pos": Vector2(390, 120), "expect_xray": true},
	]
	
	var all_passed := true
	for tc in test_cases:
		var p_pos: Vector2 = tc["pos"]
		chara.global_position = p_pos
		xray.update_wall_xray(chara, sort_world)
		
		var active_layers: Array = xray._source_layers.get(&"player", [])
		var has_pillar_xray := false
		for l in active_layers:
			if l.name.contains("4_5") or l.name.contains("4_6") or l.name.contains("5_6") or l.name.contains("4_7"):
				has_pillar_xray = true
				break
				
		var expect: bool = tc["expect_xray"]
		var passed: bool = (has_pillar_xray == expect)
		if not passed:
			all_passed = false
			
		print("[%s] %s pos=%s -> pillar_xray=%s (expected: %s, total_layers=%d)" % [
			"PASS" if passed else "FAIL",
			tc["name"],
			p_pos,
			has_pillar_xray,
			expect,
			active_layers.size()
		])
		
	print("==================================================================")
	if all_passed:
		print("ALL TEST CASES PASSED SUCCESSFULLY (Plan A verified)!")
		get_tree().quit(0)
	else:
		print("SOME TEST CASES FAILED!")
		get_tree().quit(1)
