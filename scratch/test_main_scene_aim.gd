extends SceneTree

func _init():
	var scene = load("res://scene/main_scene.tscn").instantiate()
	get_root().add_child(scene)

	await create_timer(0.2).timeout

	var player = scene.find_child("CharacterBody2D", true, false)
	var aim_ctrl = player.find_child("AimController", true, false)
	var wolf = scene.find_child("Wolf", true, false)

	print("Player pos: ", player.global_position)
	print("Wolf pos: ", wolf.global_position)

	# 激活瞄准
	aim_ctrl.is_aim_active = true

	# 1. 瞄准狼的脚底 (feet)
	aim_ctrl.update_aim(player.global_position, wolf.global_position)
	print("Aiming at wolf feet ", wolf.global_position, " -> target: ", aim_ctrl.current_target.name if aim_ctrl.current_target else "null")
	assert(aim_ctrl.current_target == wolf, "Should target wolf at feet")

	# 2. 瞄准狼的身体 (body, y - 20)
	aim_ctrl.update_aim(player.global_position, wolf.global_position + Vector2(0, -20))
	print("Aiming at wolf body ", wolf.global_position + Vector2(0, -20), " -> target: ", aim_ctrl.current_target.name if aim_ctrl.current_target else "null")
	assert(aim_ctrl.current_target == wolf, "Should target wolf at body")

	# 3. 瞄准狼的头部上方一点 (head, y - 40)
	aim_ctrl.update_aim(player.global_position, wolf.global_position + Vector2(0, -40))
	print("Aiming at wolf head ", wolf.global_position + Vector2(0, -40), " -> target: ", aim_ctrl.current_target.name if aim_ctrl.current_target else "null")
	assert(aim_ctrl.current_target == wolf, "Should target wolf at head")

	# 4. 瞄准远离狼的位置 (far, y - 90)
	aim_ctrl.update_aim(player.global_position, wolf.global_position + Vector2(0, -90))
	print("Aiming far away ", wolf.global_position + Vector2(0, -90), " -> target: ", aim_ctrl.current_target.name if aim_ctrl.current_target else "null")
	assert(aim_ctrl.current_target == null, "Should NOT target wolf far away")

	# 5. 检查狼精灵材质上的 instance uniform 参数
	var wolf_sp = wolf._find_sprite_node()
	aim_ctrl.update_aim(player.global_position, wolf.global_position + Vector2(0, -20))
	var is_targeted = wolf_sp.get_instance_shader_parameter("is_targeted")
	var outline_color = wolf_sp.get_instance_shader_parameter("outline_color")
	print("wolf is_targeted instance uniform: ", is_targeted)
	print("wolf outline_color instance uniform: ", outline_color)
	assert(is_targeted == true, "wolf is_targeted must be true")

	print("\n>>> ALL TESTS IN MAIN SCENE PASSED SUCCESSFULLY! <<<")
	scene.queue_free()
	quit()

