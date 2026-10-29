# main_chara.gd —— 玩家主角实体控制器 (组件调度中枢)
class_name MainChara
extends CharacterBody2D

@export_group("X-Ray 物体遮挡透视")
## 透视圆心相对角色脚底原点的世界偏移量 (默认为 Vector2.ZERO 正中心)
@export var xray_offset: Vector2 = Vector2.ZERO

## 透视椭圆半径 (X: 水平半宽, Y: 垂直半高，建议保持 2:1 或 4:3 比例)
@export var xray_radius: Vector2 = Vector2(52.0, 38.0):
	set(v):
		xray_radius = v
		RenderingServer.global_shader_parameter_set("xray_radius", xray_radius)

## 最大透光度 (0.85 = 中心保留 15% 像素微弱轮廓质感, 1.0 = 中心完全镂空透明)
@export_range(0.0, 1.0, 0.05) var xray_max_transparency: float = 0.85:
	set(v):
		xray_max_transparency = v
		RenderingServer.global_shader_parameter_set("xray_max_transparency", xray_max_transparency)

## 边缘过渡羽化度 (0.01 = 硬边缘圆孔, 0.6 = 柔和扩散渐变)
@export_range(0.01, 1.0, 0.05) var xray_feather: float = 0.6:
	set(v):
		xray_feather = v
		RenderingServer.global_shader_parameter_set("xray_feather", xray_feather)

## 像素点阵抖动颗粒缩放 (1 = 原生单像素点阵, 2 = 2x2 复古粗颗粒)
@export_range(1, 4, 1) var xray_dither_scale: int = 1:
	set(v):
		xray_dither_scale = v
		RenderingServer.global_shader_parameter_set("xray_dither_scale", xray_dither_scale)

## 像素抖动排列算法模式 (0=Bayer 8x8 64阶平滑消除分层, 1=Interleaved 噪波极致柔和, 2=Bayer 4x4 16阶经典)
@export_enum("Bayer 8x8 (64阶平滑复古)", "Interleaved 噪波 (极致柔和)", "Bayer 4x4 (16阶经典粗糙)") var xray_dither_mode: int = 0:
	set(v):
		xray_dither_mode = v
		RenderingServer.global_shader_parameter_set("xray_dither_mode", xray_dither_mode)

@onready var input_comp: PlayerInputComponent = $PlayerInputComponent
@onready var mover_comp: MoverComponent = $MoverComponent
@onready var anim_comp: FourDirAnimComponent = $FourDirAnimComponent
@onready var inventory_comp: InventoryComponent = $InventoryComponent

func _ready() -> void:
	sync_xray_parameters()

## 同步全套透视配置给全局 Shader
func sync_xray_parameters() -> void:
	RenderingServer.global_shader_parameter_set("xray_radius", xray_radius)
	RenderingServer.global_shader_parameter_set("xray_max_transparency", xray_max_transparency)
	RenderingServer.global_shader_parameter_set("xray_feather", xray_feather)
	RenderingServer.global_shader_parameter_set("xray_dither_scale", xray_dither_scale)
	RenderingServer.global_shader_parameter_set("xray_dither_mode", xray_dither_mode)

func _physics_process(delta: float) -> void:
	# 1. 从输入大脑获取 8 向输入向量
	var move_dir := input_comp.get_movement_direction() if input_comp else Vector2.ZERO
	
	# 2. 交给移动驱动组件执行 2:1 等距物理滑动
	var current_velocity := mover_comp.move(move_dir, delta) if mover_comp else Vector2.ZERO
	
	# 3. 交给动画组件更新四向帧动画
	if anim_comp:
		anim_comp.update_animation(current_velocity)

	# 4. 同步玩家世界中心坐标给全局 Shader (用于树木等遮挡物 X-Ray 透视)
	RenderingServer.global_shader_parameter_set("player_world_pos", global_position + xray_offset)

