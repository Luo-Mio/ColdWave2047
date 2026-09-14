@tool
extends SceneTree

func _init() -> void:
	print("=== Running Main Scene Integration Test ===")
	var scene: PackedScene = load("res://scene/main_scene.tscn")
	assert(scene != null, "Failed to load main_scene.tscn!")
	var instance: Node2D = scene.instantiate() as Node2D
	assert(instance != null, "Failed to instantiate main_scene.tscn!")
	root.add_child(instance)

	# Locate wolf in sortworld
	var wolf := instance.find_child("Wolf", true, false)
	assert(wolf != null, "Wolf must exist in main_scene!")
	var hc := wolf.find_child("HealthComponent", true, false)
	assert(hc != null, "Wolf must have HealthComponent in main_scene!")
	assert(hc.get("current_health") == 100.0, "Wolf health must be 100.0")

	print("Main scene loaded and wolf health verified successfully!")
	quit(0)

