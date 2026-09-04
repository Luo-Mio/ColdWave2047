# wolf.gd —— 狼实体控制器（全模块化架构，各功能组件即插即用）
class_name Wolf
extends CharacterBody2D

const IsoDepthComponent := preload("res://script/components/iso_depth_component.gd")
const MoverComponent := preload("res://script/components/mover_component.gd")
const IsoAnimComponent := preload("res://script/components/iso_anim_component.gd")
const WanderAIComponent := preload("res://script/components/wander_ai_component.gd")

@onready var depth_comp: IsoDepthComponent = get_node_or_null("IsoDepthComponent")
@onready var mover_comp: MoverComponent = get_node_or_null("MoverComponent")
@onready var anim_comp: IsoAnimComponent = get_node_or_null("IsoAnimComponent")
@onready var ai_comp: WanderAIComponent = get_node_or_null("WanderAIComponent")

# 2.5D 深度排序所需变量（供 sort_world.gd 比对，由 depth_comp 自动维护）
var layer_no: int = 1000
var sort_key: float = 0.0
var foot_y: float = 0.0

func _ready() -> void:
	# 统一 2.5D 生物物理碰撞规则：
	# collision_layer = 4 (Layer 3: 活体生物层)
	# collision_mask = 6  (监听 Layer 2 空气墙/树木障碍物 + Layer 3 其他生物)
	# motion_mode = 1     (MOTION_MODE_FLOATING 禁用横版重力，适合 2.5D 自由移动)
	collision_layer = 4
	collision_mask = 6
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	# 容错初始化：如果场景树中未挂载，则自动用标准参数创建
	if depth_comp == null:
		depth_comp = IsoDepthComponent.new()
		depth_comp.name = "IsoDepthComponent"
		depth_comp.foot_offset_y = -16.0
		add_child(depth_comp)
	if mover_comp == null:
		mover_comp = MoverComponent.new()
		mover_comp.name = "MoverComponent"
		mover_comp.move_speed = 100.0
		add_child(mover_comp)
	if anim_comp == null:
		anim_comp = IsoAnimComponent.new()
		anim_comp.name = "IsoAnimComponent"
		anim_comp.anim_mode = IsoAnimComponent.AnimMode.DIAGONAL_4
		anim_comp.idle_prefix = "idel"
		anim_comp.move_prefix = "run"
		add_child(anim_comp)
	if ai_comp == null:
		ai_comp = WanderAIComponent.new()
		ai_comp.name = "WanderAIComponent"
		ai_comp.enable_wander = true
		add_child(ai_comp)

func _physics_process(delta: float) -> void:
	# 1. AI 决策目标移动方向 (通过 WanderAIComponent 检查器可随时开启/关闭闲逛)
	var desired_dir := Vector2.ZERO
	if ai_comp:
		desired_dir = ai_comp.update_ai(delta)

	# 2. 物理运动组件执行平滑加减速与碰撞滑动
	var current_velocity := Vector2.ZERO
	if mover_comp:
		current_velocity = mover_comp.move(desired_dir, delta)
	else:
		move_and_slide()

	# 3. 2.5D 楼层高度贴地与深度动态排序 (由 IsoDepthComponent 统一计算)
	if depth_comp:
		depth_comp.update_depth(delta)

	# 4. 4斜向带记忆动画朝向驱动 (由 IsoAnimComponent 自动解析播放)
	if anim_comp:
		anim_comp.update_animation(current_velocity)
