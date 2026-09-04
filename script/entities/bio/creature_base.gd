# creature_base.gd —— 通用生物基础物理实体 (所有动物、怪物、NPC、主角的基类)
class_name CreatureBase
extends CharacterBody2D

# 2.5D 深度排序所需变量（供 sort_world.gd 比对，由 depth_comp 自动维护）
var layer_no: int = 1000
var sort_key: float = 0.0
var foot_y: float = 0.0

@onready var depth_comp: Node = find_child("IsoDepthComponent", true, false)
@onready var mover_comp: Node = find_child("MoverComponent", true, false)
@onready var anim_comp: Node = find_child("IsoAnimComponent", true, false)
@onready var weapon_comp: Node = find_child("WeaponHolderComponent", true, false)

# 大脑/输入决策组件 (自动识别 PlayerInputComponent 或各类 AI 组件)
@onready var brain_comp: Node = _find_brain_component()

func _ready() -> void:
	# 统一 2.5D 生物物理碰撞规则：
	# Layer 3 (数值 4): 活体生物层
	# Mask 6 (Layer 2 障碍物 + Layer 3 其他生物)
	# motion_mode = FLOATING (禁用横版重力，适合 2.5D 等距自由移动)
	collision_layer = 4
	collision_mask = 6
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("creatures")

func _physics_process(delta: float) -> void:
	# 1. 询问大脑当前的期望移动意图 (无论是按键输入、AI漫步、追击或骑乘接管)
	var desired_dir := Vector2.ZERO
	if brain_comp and brain_comp.has_method("get_movement_direction"):
		desired_dir = brain_comp.call("get_movement_direction", delta)
	elif brain_comp and brain_comp.has_method("update_ai"):
		desired_dir = brain_comp.call("update_ai", delta)

	# 2. 物理运动组件平滑执行
	var current_velocity := Vector2.ZERO
	if mover_comp and mover_comp.has_method("move"):
		current_velocity = mover_comp.call("move", desired_dir, delta)
	else:
		move_and_slide()

	# 3. 2.5D 楼层台阶贴地与动态深度排序
	if depth_comp and depth_comp.has_method("update_depth"):
		depth_comp.call("update_depth", delta)

	# 4. 等距朝向动画驱动 (若大脑开启了始终朝向鼠标，或手持武器瞄准，锁定朝向目标实现平移倒退走；否则随移动方向转向)
	var look_dir := Vector2.ZERO
	if brain_comp and brain_comp.get("always_face_mouse") and brain_comp.has_method("get_aim_direction"):
		look_dir = brain_comp.call("get_aim_direction", global_position)
	elif weapon_comp and weapon_comp.get("is_weapon_active"):
		look_dir = weapon_comp.get("current_aim_dir")

	if anim_comp and anim_comp.has_method("update_animation"):
		anim_comp.call("update_animation", current_velocity, look_dir)

# 获取当前实体的世界朝向向量 (优先鼠标瞄准向量，其次身体动画朝向)
func get_facing_direction() -> Vector2:
	if brain_comp and brain_comp.get("always_face_mouse") and brain_comp.has_method("get_aim_direction"):
		var aim: Vector2 = brain_comp.call("get_aim_direction", global_position)
		if aim.length_squared() > 0.001:
			return aim
	if weapon_comp and weapon_comp.get("is_weapon_active"):
		var aim: Vector2 = weapon_comp.get("current_aim_dir")
		if aim.length_squared() > 0.001:
			return aim
	if anim_comp and anim_comp.has_method("get_facing_direction"):
		return anim_comp.call("get_facing_direction")
	return Vector2.DOWN

# 供全局 Shader（树干与高墙透视）获取角色的视觉身体/脚底世界坐标
func get_visual_foot_position() -> Vector2:
	if depth_comp and depth_comp.has_method("get_visual_foot_position"):
		return depth_comp.call("get_visual_foot_position")
	return global_position

# 动态切换控制大脑 (例如骑马时把大脑切换为玩家输入，下马时恢复 AI)
func set_brain(new_brain: Node) -> void:
	brain_comp = new_brain

# 转发物品栏武器更新
func update_held_item(item_data: Dictionary) -> void:
	if weapon_comp and weapon_comp.has_method("update_held_item"):
		weapon_comp.call("update_held_item", item_data)

# 自动寻找大脑组件
func _find_brain_component() -> Node:
	var player_input := find_child("PlayerInputComponent", true, false)
	if player_input:
		return player_input
	var wander_ai := find_child("WanderAIComponent", true, false)
	if wander_ai:
		return wander_ai
	return null
