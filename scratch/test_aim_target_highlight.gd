extends SceneTree

func _init():
	var root = Node2D.new()
	get_root().add_child(root)

	# 1. 模拟玩家与 AimController
	var player = CharacterBody2D.new()
	player.name = "Player"
	player.position = Vector2(0, 0)
	player.collision_layer = 4
	root.add_child(player)

	var aim_ctrl_script = load("res://script/components/aim_controller.gd")
	var aim_ctrl = aim_ctrl_script.new()
	aim_ctrl.name = "AimController"
	player.add_child(aim_ctrl)

	# 2. 模拟两只野狼
	var wolf_scene = load("res://scene/bio/wolf/wolf.tscn")
	var wolf1 = wolf_scene.instantiate()
	wolf1.name = "Wolf1"
	wolf1.position = Vector2(100, 0) # 玩家右侧 100px
	root.add_child(wolf1)

	var wolf2 = wolf_scene.instantiate()
	wolf2.name = "Wolf2"
	wolf2.position = Vector2(0, 100) # 玩家下方 100px
	root.add_child(wolf2)

	await create_timer(0.1).timeout

	print("=== 1. 初始状态检测 ===")
	print("Wolf1 highlighted: ", wolf1.is_aim_highlighted)
	print("Wolf2 highlighted: ", wolf2.is_aim_highlighted)
	assert(not wolf1.is_aim_highlighted, "Wolf1 should not be highlighted initially")
	assert(not wolf2.is_aim_highlighted, "Wolf2 should not be highlighted initially")

	aim_ctrl.is_aim_active = true
	aim_ctrl.radius_min = 20.0
	aim_ctrl.radius_horizontal = 200.0
	aim_ctrl.radius_max = 400.0

	print("=== 2. 瞄准 Wolf1 碰撞箱 ===")
	# 瞄准点设定为 Wolf1 位置 (100, 0)
	aim_ctrl.update_aim(player.position, Vector2(100, 0))
	print("Current target: ", aim_ctrl.current_target.name if aim_ctrl.current_target else "null")
	print("Wolf1 is_aim_highlighted: ", wolf1.is_aim_highlighted)
	var sp1: CanvasItem = wolf1._find_sprite_node()
	var targeted1 = sp1.get_instance_shader_parameter("is_targeted") if sp1 else null
	var col1 = sp1.get_instance_shader_parameter("outline_color") if sp1 else null
	print("Wolf1 is_targeted instance uniform: ", targeted1)
	print("Wolf1 outline_color: ", col1)
	assert(aim_ctrl.current_target == wolf1, "Target should be Wolf1")
	assert(wolf1.is_aim_highlighted, "Wolf1 must be highlighted")
	assert(targeted1 == true, "Wolf1 shader is_targeted must be true")

	print("=== 3. 移开瞄准准星到空白处 ===")
	aim_ctrl.update_aim(player.position, Vector2(-150, -150))
	print("Current target after move away: ", aim_ctrl.current_target)
	print("Wolf1 is_aim_highlighted: ", wolf1.is_aim_highlighted)
	var targeted1_off = sp1.get_instance_shader_parameter("is_targeted") if sp1 else null
	print("Wolf1 is_targeted instance uniform after move away: ", targeted1_off)
	assert(aim_ctrl.current_target == null, "Target should be null")
	assert(not wolf1.is_aim_highlighted, "Wolf1 highlight must be disabled")
	assert(targeted1_off == false, "Wolf1 shader is_targeted must be false")

	print("=== 4. 切换目标到 Wolf2 ===")
	aim_ctrl.update_aim(player.position, Vector2(0, 100))
	print("Current target: ", aim_ctrl.current_target.name if aim_ctrl.current_target else "null")
	print("Wolf1 is_aim_highlighted: ", wolf1.is_aim_highlighted)
	print("Wolf2 is_aim_highlighted: ", wolf2.is_aim_highlighted)
	var sp2: CanvasItem = wolf2._find_sprite_node()
	var targeted2 = sp2.get_instance_shader_parameter("is_targeted") if sp2 else null
	assert(aim_ctrl.current_target == wolf2, "Target should be Wolf2")
	assert(not wolf1.is_aim_highlighted, "Wolf1 should not be highlighted")
	assert(wolf2.is_aim_highlighted, "Wolf2 should be highlighted")
	assert(targeted2 == true, "Wolf2 shader is_targeted must be true")

	print("=== 5. 退出瞄准模式 ===")
	aim_ctrl.clear_aim_config()
	print("Current target after clear_aim_config: ", aim_ctrl.current_target)
	print("Wolf2 is_aim_highlighted: ", wolf2.is_aim_highlighted)
	var targeted2_off = sp2.get_instance_shader_parameter("is_targeted") if sp2 else null
	assert(aim_ctrl.current_target == null, "Target should be null")
	assert(not wolf2.is_aim_highlighted, "Wolf2 highlight must be cleared")
	assert(targeted2_off == false, "Wolf2 shader is_targeted must be false")

	print("=== 6. 生物死亡自动脱靶测试 ===")
	aim_ctrl.is_aim_active = true
	aim_ctrl.update_aim(player.position, Vector2(100, 0))
	assert(aim_ctrl.current_target == wolf1, "Should target Wolf1 again")
	# 击杀 Wolf1
	wolf1.take_damage(9999.0)
	aim_ctrl.update_aim(player.position, Vector2(100, 0))
	print("Target after Wolf1 died: ", aim_ctrl.current_target)
	assert(aim_ctrl.current_target == null, "Dead creature should not remain targeted")

	print("\n>>> ALL TESTS PASSED SUCCESSFULLY! <<<")
	wolf1.queue_free()
	wolf2.queue_free()
	player.queue_free()
	root.queue_free()
	quit()

