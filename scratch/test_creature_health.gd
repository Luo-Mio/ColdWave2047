@tool
extends SceneTree

const WolfScene: PackedScene = preload("res://scene/bio/wolf/wolf.tscn")

func _init() -> void:
	print("=== Running Creature Health & Damage Verification ===")

	# 1. 实例化野狼
	var wolf: CharacterBody2D = WolfScene.instantiate() as CharacterBody2D
	assert(wolf != null, "Failed to instantiate Wolf scene!")
	root.add_child(wolf)
	wolf.position = Vector2(200, 200)

	# 2. 检查 HealthComponent
	var health_comp: Node = wolf.find_child("HealthComponent", true, false)
	assert(health_comp != null, "Wolf must have a HealthComponent child!")
	assert(health_comp.get("max_health") == 100.0, "Wolf max_health should default to 100.0")
	assert(health_comp.get("current_health") == 100.0, "Wolf current_health should default to 100.0")

	# 3. 检查 HealthBar UI
	var health_bar: Control = wolf.find_child("HealthBar", true, false) as Control
	assert(health_bar != null, "Wolf must have a HealthBar child!")

	# 4. 测试生物基类代理与受击扣血
	var damage_records: Array = []
	health_comp.connect("damaged", func(amount: float, _src: Node):
		damage_records.append(amount)
	)

	print("--- Testing take_damage(35.0) ---")
	wolf.call("take_damage", 35.0, null)
	assert(damage_records.size() == 1, "Damaged signal should be emitted once")
	assert(damage_records[0] == 35.0, "Damage amount should be 35.0")
	assert(is_equal_approx(float(health_comp.get("current_health")), 65.0), "Wolf current_health should be 65.0")
	assert(is_equal_approx(health_bar.current_health, 65.0), "HealthBar current_health should sync to 65.0")
	print("  Health after 35 damage: %.1f / %.1f (OK)" % [health_comp.get("current_health"), health_comp.get("max_health")])

	# 5. 测试治疗恢复
	print("--- Testing heal(15.0) ---")
	wolf.call("heal", 15.0, null)
	assert(is_equal_approx(float(health_comp.get("current_health")), 80.0), "Wolf current_health should be 80.0 after healing")
	assert(is_equal_approx(health_bar.current_health, 80.0), "HealthBar current_health should sync to 80.0")
	print("  Health after 15 heal: %.1f / %.1f (OK)" % [health_comp.get("current_health"), health_comp.get("max_health")])

	# 6. 测试死亡判定
	print("--- Testing lethal damage (100.0) ---")
	var died_records: Array = []
	health_comp.connect("died", func():
		died_records.append(true)
	)
	wolf.call("take_damage", 100.0, null)
	assert(died_records.size() == 1, "Died signal should be emitted upon health reaching 0")
	assert(health_comp.call("is_alive") == false, "Wolf is_alive should return false")
	assert(wolf.call("is_alive") == false, "Wolf CreatureBase is_alive should return false")
	print("  Wolf died signal emitted, is_alive = false (OK)")

	print("\n>>> ALL CREATURE HEALTH & DAMAGE VERIFICATIONS PASSED CLEANLY! <<<")
	quit(0)

