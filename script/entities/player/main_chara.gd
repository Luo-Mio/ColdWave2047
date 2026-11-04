# main_chara.gd —— 玩家主角实体控制器 (组件调度中枢，支持 @tool 编辑器实时预览透视)
@tool
class_name MainChara
extends CharacterBody2D

# 缓存已注册的全局 Shader 参数，防止编辑器或运行中重复查询或未注册报错
static var _registered_shader_globals: Dictionary = {}

static func _set_global_param_safe(param_name: StringName, value: Variant, param_type: int) -> void:
	if _registered_shader_globals.is_empty():
		for p in RenderingServer.global_shader_parameter_get_list():
			_registered_shader_globals[p] = true
	
	if not _registered_shader_globals.has(param_name):
		# 如果运行中的引擎/编辑器尚未从 project.godot 载入该变量，自动向 RenderingServer 动态注册
		RenderingServer.global_shader_parameter_add(param_name, param_type, value)
		_registered_shader_globals[param_name] = true
	
	RenderingServer.global_shader_parameter_set(param_name, value)

@export_group("X-Ray 物体遮挡透视")
## 是否启用 Y-Sort 遮挡深度过滤 (仅对物体根部 Y > 玩家地面 Y 的前景物体透视，物体在玩家后方时不透视)
@export var xray_y_sort_filter: bool = true:
	set(v):
		xray_y_sort_filter = v
		_set_global_param_safe(&"xray_y_sort_filter", xray_y_sort_filter, RenderingServer.GLOBAL_VAR_TYPE_BOOL)

## 透视圆心相对角色脚底原点的世界偏移量 (默认为 Vector2.ZERO 正中心)
@export var xray_offset: Vector2 = Vector2.ZERO

## 触发整株透视的判定半径 (X: 水平感应半宽建议 50~60px, Y: 离开树冠顶部/底部的垂直羽化缓冲区建议 20~30px)
@export var xray_radius: Vector2 = Vector2(55.0, 25.0):
	set(v):
		xray_radius = v
		_set_global_param_safe(&"xray_radius", xray_radius, RenderingServer.GLOBAL_VAR_TYPE_VEC2)

## 最大透光度 (0.70 = 透视时整株剩余 30% 不透明度，0.80 = 剩余 20% 不透明度)
@export_range(0.0, 1.0, 0.05) var xray_max_transparency: float = 0.70:
	set(v):
		xray_max_transparency = v
		_set_global_param_safe(&"xray_max_transparency", xray_max_transparency, RenderingServer.GLOBAL_VAR_TYPE_FLOAT)

## 边缘平滑进入羽化度 (0.1 = 接近硬切, 0.45 = 柔和淡入淡出过渡)
@export_range(0.01, 1.0, 0.05) var xray_feather: float = 0.45:
	set(v):
		xray_feather = v
		_set_global_param_safe(&"xray_feather", xray_feather, RenderingServer.GLOBAL_VAR_TYPE_FLOAT)

@onready var input_comp: PlayerInputComponent = $PlayerInputComponent
@onready var mover_comp: MoverComponent = $MoverComponent
@onready var anim_comp: FourDirAnimComponent = $FourDirAnimComponent
@onready var inventory_comp: InventoryComponent = $InventoryComponent

func _ready() -> void:
	sync_xray_parameters()

## 同步全套透视配置给全局 Shader
func sync_xray_parameters() -> void:
	_set_global_param_safe(&"player_world_pos", global_position + xray_offset, RenderingServer.GLOBAL_VAR_TYPE_VEC2)
	_set_global_param_safe(&"xray_y_sort_filter", xray_y_sort_filter, RenderingServer.GLOBAL_VAR_TYPE_BOOL)
	_set_global_param_safe(&"xray_radius", xray_radius, RenderingServer.GLOBAL_VAR_TYPE_VEC2)
	_set_global_param_safe(&"xray_max_transparency", xray_max_transparency, RenderingServer.GLOBAL_VAR_TYPE_FLOAT)
	_set_global_param_safe(&"xray_feather", xray_feather, RenderingServer.GLOBAL_VAR_TYPE_FLOAT)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		# 编辑器模式下实时同步角色坐标给 Shader (支持在编辑器 2D 视口中拖拽角色实时预览透视挖孔)
		_set_global_param_safe(&"player_world_pos", global_position + xray_offset, RenderingServer.GLOBAL_VAR_TYPE_VEC2)
		return

	# 1. 从输入大脑获取 8 向输入向量
	var move_dir := input_comp.get_movement_direction() if input_comp else Vector2.ZERO
	
	# 2. 交给移动驱动组件执行 2:1 等距物理滑动
	var current_velocity := mover_comp.move(move_dir, delta) if mover_comp else Vector2.ZERO
	
	# 3. 交给动画组件更新四向帧动画
	if anim_comp:
		anim_comp.update_animation(current_velocity)

	# 4. 同步玩家世界中心坐标给全局 Shader (用于树木等遮挡物 X-Ray 透视)
	_set_global_param_safe(&"player_world_pos", global_position + xray_offset, RenderingServer.GLOBAL_VAR_TYPE_VEC2)
