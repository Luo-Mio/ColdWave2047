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
@onready var step_limit_comp: Node = find_child("HeightStepLimitComponent", true, false)
@onready var health_comp: Node = find_child("HealthComponent", true, false)

# 大脑/输入决策组件 (自动识别 PlayerInputComponent 或各类 AI 组件)
@onready var brain_comp: Node = _find_brain_component()

@export_group("物理立体受击与视线高度 (Physical 3D Height)")
## 生物站立时的身体立体高度/视线高度 (像素，未缩放值)。
## 用于：1. 飞弹 3D 飞行拦截碰撞判定；2. 2.5D 视线投射与跨障碍俯视判断。
## 实际 3D 受击立体高度 = (eye_height * scale.y) + 6.0px。
## 主角站立约为 18.0px；野狼等四足生物建议设为 12.0~14.0px；巨型生物可设为 32.0px 以上。
@export var eye_height: float = 18.0

# 透视遮罩参数 (方便玩家在视野内锁定被物体遮挡的目标)
@export_group("透视遮罩配置 (X-Ray)")
## 是否启用该生物的透视遮罩。勾选后，该生物处于树冠或高墙等遮挡物下方时会自动挖出透视视窗；取消勾选可用于隐形或潜行生物
@export var xray_enabled: bool = true
## 透视椭圆视窗的大小 (X: 水平半宽像素, Y: 垂直半高像素)。数值越大，挖出的透视洞越广
@export var xray_radius: Vector2 = Vector2(85.0, 55.0)
## 透视中心相对于生物脚底的世界坐标偏移量。例如 (0, -16) 代表将透视中心由脚底上移至胸口/面部
@export var xray_offset: Vector2 = Vector2(0.0, -16.0)
## 透视中心的最大镂空透明度 (0.0=完全实心不透, 0.85=85%点阵镂空露出生物, 1.0=中心完全透明)
@export_range(0.0, 1.0, 0.05) var xray_max_transparency: float = 0.85
## 透视边缘透明度渐变曲线弧度 (0.0=45度直线线性渐变, 1.0=1/4圆弧先平缓大范围透光再边缘陡降)
@export_range(0.0, 1.0, 0.05) var xray_curve: float = 0.0

const CREATURE_OUTLINE_MATERIAL = preload("res://resources/materials/creature_outline.tres")

# 瞄准高亮受击状态
var is_aim_highlighted: bool = false
var _sprite_node: CanvasItem = null

func _ready() -> void:
	# 统一 2.5D 生物物理碰撞规则：
	# Layer 3 (数值 4): 活体生物层
	# Mask 6 (Layer 2 障碍物 + Layer 3 其他生物)
	# motion_mode = FLOATING (禁用横版重力，适合 2.5D 等距自由移动)
	collision_layer = 4
	collision_mask = 6
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("creatures")
	_init_outline_material()

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

# 获取生物当前所处楼层 (0=地表, 1=一层台上...)
func get_current_floor() -> int:
	if depth_comp and "current_floor" in depth_comp:
		return depth_comp.current_floor
	return 0

# 自动寻找大脑组件
func _find_brain_component() -> Node:
	var player_input := find_child("PlayerInputComponent", true, false)
	if player_input:
		return player_input
	var wander_ai := find_child("WanderAIComponent", true, false)
	if wander_ai:
		return wander_ai
	return null

# === 生命值与伤害结算接口 ===
func _ensure_health_comp() -> Node:
	if health_comp == null:
		health_comp = find_child("HealthComponent", true, false)
	return health_comp

func take_damage(amount: float, source: Node = null) -> void:
	var hc := _ensure_health_comp()
	if hc and hc.has_method("take_damage"):
		hc.call("take_damage", amount, source)

func heal(amount: float, source: Node = null) -> void:
	var hc := _ensure_health_comp()
	if hc and hc.has_method("heal"):
		hc.call("heal", amount, source)

func is_alive() -> bool:
	var hc := _ensure_health_comp()
	if hc and hc.has_method("is_alive"):
		return hc.call("is_alive")
	return true

func get_health_ratio() -> float:
	var hc := _ensure_health_comp()
	if hc and hc.has_method("get_health_ratio"):
		return hc.call("get_health_ratio")
	return 1.0

# === 瞄准高亮与外轮廓显示接口 ===
func _find_sprite_node() -> CanvasItem:
	if _sprite_node and is_instance_valid(_sprite_node):
		return _sprite_node
	var anim_sprite := find_child("AnimatedSprite2D", true, false) as CanvasItem
	if anim_sprite:
		_sprite_node = anim_sprite
		return _sprite_node
	var sprite := find_child("Sprite2D", true, false) as CanvasItem
	if sprite:
		_sprite_node = sprite
		return _sprite_node
	return null

## 初始化轮廓着色器材质 (零侵入：若未显式配置材质则自动赋予全局共享材质)
func _init_outline_material() -> void:
	var sp := _find_sprite_node()
	if sp == null:
		return
	if sp.material == null:
		sp.material = CREATURE_OUTLINE_MATERIAL
	# 确保初始状态为未被瞄准
	sp.set_instance_shader_parameter("is_targeted", false)

## 设置生物受瞄准高亮状态
func set_aim_highlight(is_highlighted: bool, color: Color = Color(0.2, 1.0, 0.4, 1.0), outline_width: float = 1.0) -> void:
	is_aim_highlighted = is_highlighted
	var sp := _find_sprite_node()
	if sp:
		if sp.material == null:
			_init_outline_material()
		sp.set_instance_shader_parameter("is_targeted", is_highlighted)
		if is_highlighted:
			sp.set_instance_shader_parameter("outline_color", color)
			sp.set_instance_shader_parameter("outline_width", outline_width)


