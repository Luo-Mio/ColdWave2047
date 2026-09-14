@tool
extends SceneTree

const HealthBarScript = preload("res://script/ui/health_bar.gd")

class MockHealthComp extends Node:
	var max_health: float = 100.0
	var current_health: float = 100.0
	signal health_changed(new_h: float, max_h: float)
	signal damaged(amount: float, source: Node)
	signal healed(amount: float, source: Node)
	signal died()

func _init() -> void:
	print("=== Running HealthBar UI Verification ===")
	var bar_scene: PackedScene = load("res://scene/ui/health_bar.tscn")
	assert(bar_scene != null, "Failed to load health_bar.tscn!")
	
	var bar: Control = bar_scene.instantiate() as Control
	assert(bar != null, "Instantiated node is null!")
	
	root.add_child(bar)
	
	# Test initial state
	assert(bar.bar_width == 28.0, "Default bar_width should be 28.0")
	assert(bar.bar_height == 4.0, "Default bar_height should be 4.0")
	
	# Test manual set_health
	bar.set_health(70.0, 100.0, false)
	assert(bar.current_health == 70.0, "current_health should be 70.0")
	
	# Test setup with HealthComponent mock
	var comp := MockHealthComp.new()
	bar.setup(comp)
	assert(bar.current_health == 100.0, "Should read 100.0 from component")
	
	# Emit damage
	comp.current_health = 60.0
	comp.damaged.emit(40.0, null)
	comp.health_changed.emit(60.0, 100.0)
	assert(bar.current_health == 60.0, "current_health should be 60.0 after damage")
	
	print(">>> ALL HEALTH BAR VERIFICATIONS PASSED CLEANLY! <<<")
	quit(0)

