# main_chara.gd —— 主角控制器（支持法杖 360° 瞄准与身体锁定鼠标）
extends CharacterBody2D

const MovementControllerScript := preload("res://script/components/movement_controller.gd")
const IsoDepthComponent := preload("res://script/components/iso_depth_component.gd")
const AnimationControllerScript := preload("res://script/components/animation_controller.gd")

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = get_node_or_null("Camera2D")

@onready var hand_node: Node2D = find_child("hand", true, false)
@onready var weapon_sprite: Sprite2D = find_child("Sprite2D", true, false)

@onready var movement: Node = get_node_or_null("MovementController")
@onready var depth_comp: IsoDepthComponent = get_node_or_null("IsoDepthComponent")
@onready var anim_controller: Node = get_node_or_null("AnimationController")

var layer_no: int = 1000
var sort_key: float = 0.0
var foot_y: float = 0.0

func _ready() -> void:
	if movement == null:
		movement = MovementControllerScript.new()
		add_child(movement)
	if depth_comp == null:
		depth_comp = IsoDepthComponent.new()
		depth_comp.foot_offset_y = -12.0
		depth_comp.enable_camera_follow = true
		add_child(depth_comp)
	if anim_controller == null:
		anim_controller = AnimationControllerScript.new()
		add_child(anim_controller)

func _physics_process(delta: float) -> void:
	# 1. 角色移动
	velocity = movement.call("get_movement_velocity")
	move_and_slide()

	# 2. 楼层高度跟踪与 2.5D 深度动态排序 (由 IsoDepthComponent 统一处理)
	if depth_comp:
		depth_comp.update_depth(delta)

	# 3. 检查当前物品栏是否手持武器
	var hotbar: Node = get_tree().root.find_child("hotbar", true, false)
	var is_weapon_mode: bool = false
	if hotbar and hotbar.has_method("get_active_item"):
		var active_item: Dictionary = hotbar.call("get_active_item")
		is_weapon_mode = (active_item.get("type") == 2) # 2 = WEAPON
		if is_weapon_mode and active_item.has("weapon_tex") and weapon_sprite:
			if weapon_sprite.texture == null or weapon_sprite.texture.resource_path != active_item["weapon_tex"]:
				weapon_sprite.texture = load(active_item["weapon_tex"])

	# 4. 计算鼠标瞄准方向 (直接取 Sprite 的全局世界坐标，免疫节点 Scale 影响)
	var chest_world_pos := animated_sprite.global_position if animated_sprite else global_position
	var mouse_world_pos := get_global_mouse_position()
	var aim_dir := mouse_world_pos - chest_world_pos
	var input_dir: Vector2 = movement.call("get_input_direction")

	# 5. 驱动身体朝向与武器显示
	if is_weapon_mode:
		if hand_node:
			hand_node.visible = true
		anim_controller.call("update_animation", input_dir, aim_dir, animated_sprite)
		_update_weapon_rotation(aim_dir)
	else:
		if hand_node:
			hand_node.visible = false
		anim_controller.call("update_animation", input_dir, input_dir, animated_sprite)

# 驱动法杖跟随鼠标
func _update_weapon_rotation(aim_dir: Vector2) -> void:
	if hand_node and weapon_sprite:
		hand_node.rotation = aim_dir.angle()

		# 向左瞄准时垂直翻转贴图，防止木棍倒立颠倒
		var angle_rad := aim_dir.angle()
		weapon_sprite.flip_v = (absf(angle_rad) > PI * 0.5)

		# 朝上方（北）瞄准时把法杖放到角色背后，朝下方（南）瞄准时放在角色身前！
		hand_node.show_behind_parent = (aim_dir.y < 0.0)

# 供全局 Shader（树干与高墙透视）获取角色的视觉身体/脚底世界坐标
func get_visual_foot_position() -> Vector2:
	if depth_comp:
		return depth_comp.get_visual_foot_position()
	return global_position

# 外部（如物品栏切换）调用此函数更新武器状态
func update_held_item(item_data: Dictionary) -> void:
	if item_data.is_empty() or item_data.get("type") != 2: # 2 = WEAPON
		# 拿着地砖、小麦或空手：收起武器，隐藏手部
		if hand_node:
			hand_node.visible = false
	else:
		# 拿着武器：亮出武器并动态更换贴图！
		if hand_node and weapon_sprite:
			hand_node.visible = true
			if item_data.has("weapon_tex"):
				weapon_sprite.texture = load(item_data["weapon_tex"])