@tool
extends Control

# ==============================================================================
# 杂草 Photoshop 自由变换与重采样实验室 (Weed Distortion Lab Studio)
# 核心控制器：所有滑块均暴露在 Godot 检查器 (Inspector) 面板中，随调随看！
# ==============================================================================

@export_group("📐 物理投影光学换算 (30° 等距相机视角)")
## 垂直风导致草身在深度方向的倾倒角度 θ (-45° ~ +45°)
## +45° = 顺风吹向镜头/玩家； 0° = 无风直立； -45° = 逆风背离镜头
@export_range(-45.0, 45.0, 1.0) var wind_tilt_angle_deg: float = 0.0:
	set(v):
		wind_tilt_angle_deg = v
		_apply_physical_tilt_angle(v)

## 相机俯角 α (默认 2:1 等距视角为 30.0°)
@export_range(15.0, 60.0, 1.0) var camera_pitch_deg: float = 30.0:
	set(v):
		camera_pitch_deg = v
		_apply_physical_tilt_angle(wind_tilt_angle_deg)

@export_group("🎨 Photoshop 自由变换与重采样 (Photoshop Warp & Resample)")
## 顶边拉长/缩短比例 (Top Width Scale)：1.0 为原始 4px 顶宽，2.0 为拉宽至 8px，0.5 为收窄至 2px，0.2 为极度收尖
@export_range(0.1, 3.5, 0.05) var top_width_scale: float = 1.0:
	set(v):
		top_width_scale = v
		_sync_parameters()

## 高度压缩/拉伸比例 (Height Scale)：1.0 为原始 8px 高度，0.5 为狂风贴地压扁至 4px，1.2 为拉伸
@export_range(0.15, 1.8, 0.05) var height_scale: float = 1.0:
	set(v):
		height_scale = v
		_sync_parameters()

## 水平侧倾偏倒量 (Horizontal Shear)：草尖横向偏倒像素位移 (正值向右偏，负值向左偏)
@export_range(-12.0, 12.0, 0.2) var horizontal_shear: float = 0.0:
	set(v):
		horizontal_shear = v
		_sync_parameters()

## 基底旋转角度 (Base Rotation Angle)：绕底部中心 (0, 0) 旋转整个贴图 (-60° ~ +60°，正值向右倾倒，负值向左倾倒)
@export_range(-60.0, 60.0, 1.0) var base_rotation_deg: float = 0.0:
	set(v):
		base_rotation_deg = v
		_sync_parameters()

## 弯曲柔韧指数 (Bend Exponent)：1.0 为纯直斜切，1.8 为自然抛物线弯曲，3.0 为尖端剧烈折曲
@export_range(0.8, 3.5, 0.05) var bend_exponent: float = 1.8:
	set(v):
		bend_exponent = v
		_sync_parameters()

## 重采样平滑模式：开启为双线性抗锯齿重采样 (像 PS 缩放插值)，关闭为邻近硬像素重采样 (经典像素画风格)
@export var resample_bilinear: bool = true:
	set(v):
		resample_bilinear = v
		_sync_parameters()

## 是否显示 4x8 原图半透明基准草
@export var show_ghost: bool = true:
	set(v):
		show_ghost = v
		if ghost_sprite:
			ghost_sprite.visible = v

## 是否显示 1:1 像素网格
@export var show_grid: bool = true:
	set(v):
		show_grid = v
		if pixel_grid:
			pixel_grid.visible = v

@export_group("🌪️ 狂风动态起伏模拟 (Live Wind Simulation)")
## 是否开启动态狂风起伏摆动测试
@export var live_wind_mode: bool = false:
	set(v):
		live_wind_mode = v
		_sync_parameters()

## 模拟风力强度 (最大侧向推倒位移)
@export_range(1.0, 15.0, 0.2) var sim_wind_strength: float = 6.0:
	set(v):
		sim_wind_strength = v
		_sync_parameters()

## 模拟纵向迎面/背向风比重 (-1.0 顶风收细顶边，+1.0 顺风拉宽顶边)
@export_range(-1.0, 1.0, 0.05) var sim_wind_dir_y: float = 0.3:
	set(v):
		sim_wind_dir_y = v
		_sync_parameters()

@export_group("⚡ 典型风力级别快速预设 (Presets)")
## 选择常用风力形变预设快速查看
@export_enum("保持当前自定义", "微风拂动 (Breeze)", "中度阵风 (Gust)", "狂风暴雨 (Storm)", "极限飓风 (Extreme)", "📐 物理极限顺风迎面 (+45°)", "📐 物理极限逆风背离 (-45°)", "🌪️ 极限横风侧倾 (45° 旋转 + 弧度侧弯)") var preset_selector: int = 0:
	set(v):
		preset_selector = v
		if v > 0:
			_apply_preset_by_index(v)

@export_group("💾 一键写入主游戏材质 (Export to Game)")
## 勾选此项立即将当前形变换算出的风力与透视参数写入 res://resources/materials/grass_tuft.tres
@export var apply_to_game_material: bool = false:
	set(v):
		if v:
			apply_to_game_material = false
			save_to_game_material()

## 重置为默认初始零形变
@export var reset_to_default: bool = false:
	set(v):
		if v:
			reset_to_default = false
			reset_defaults()

# 内部节点引用
@onready var stage_area: Control = $HBox/LeftPanel/VBoxPreview/CardCloseup/Margin/VBox/StageArea
@onready var stage_node: Node2D = $HBox/LeftPanel/VBoxPreview/CardCloseup/Margin/VBox/StageArea/Stage
@onready var ghost_sprite: Sprite2D = $HBox/LeftPanel/VBoxPreview/CardCloseup/Margin/VBox/StageArea/Stage/GhostSprite
@onready var deformed_sprite: Sprite2D = $HBox/LeftPanel/VBoxPreview/CardCloseup/Margin/VBox/StageArea/Stage/DeformedSprite
@onready var pixel_grid: Node2D = $HBox/LeftPanel/VBoxPreview/CardCloseup/Margin/VBox/StageArea/Stage/PixelGrid

# 监视面板 UI 控件
@onready var lbl_stat_physics: Label = $HBox/RightPanel/Margin/VBox/SecStats/CardStats/Margin/VBox/StatPhysics
@onready var lbl_stat_top: Label = $HBox/RightPanel/Margin/VBox/SecStats/CardStats/Margin/VBox/StatTop
@onready var lbl_stat_h: Label = $HBox/RightPanel/Margin/VBox/SecStats/CardStats/Margin/VBox/StatHeight
@onready var lbl_stat_health: Label = $HBox/RightPanel/Margin/VBox/SecStats/CardStats/Margin/VBox/StatHealth

@onready var lbl_eq_strength: Label = $HBox/RightPanel/Margin/VBox/SecExport/VBoxCard/Margin/VBox/RowStrength/Val
@onready var lbl_eq_expand: Label = $HBox/RightPanel/Margin/VBox/SecExport/VBoxCard/Margin/VBox/RowExpand/Val
@onready var lbl_eq_squash: Label = $HBox/RightPanel/Margin/VBox/SecExport/VBoxCard/Margin/VBox/RowSquash/Val
@onready var lbl_status_msg: Label = $HBox/RightPanel/Margin/VBox/SecExport/LblStatus

@onready var btn_apply: Button = $HBox/RightPanel/Margin/VBox/SecExport/BtnApplyToGame
@onready var btn_reset: Button = $HBox/RightPanel/Margin/VBox/SecExport/BtnResetDefault

var lab_material: ShaderMaterial = null
var ghost_material: ShaderMaterial = null
var field_material: ShaderMaterial = null

func _ready() -> void:
	_init_materials()
	if stage_area:
		stage_area.resized.connect(_reposition_stage)
		_reposition_stage()
	if btn_apply:
		btn_apply.pressed.connect(save_to_game_material)
	if btn_reset:
		btn_reset.pressed.connect(reset_defaults)
	_sync_parameters()

func _reposition_stage() -> void:
	if stage_area and stage_node:
		stage_node.position = Vector2(stage_area.size.x * 0.5, stage_area.size.y * 0.65)

func _init_materials() -> void:
	if deformed_sprite and deformed_sprite.material is ShaderMaterial:
		lab_material = deformed_sprite.material as ShaderMaterial

	if ghost_sprite and ghost_sprite.material is ShaderMaterial:
		ghost_material = ghost_sprite.material as ShaderMaterial

	var field_spr = $HBox/LeftPanel/VBoxPreview/CardField/Margin/VBox/FieldContainer/Tuft1 as Sprite2D
	if field_spr and field_spr.material is ShaderMaterial:
		field_material = field_spr.material as ShaderMaterial

func _sync_parameters() -> void:
	_init_materials()

	var mats = [lab_material, field_material]
	for mat in mats:
		if mat is ShaderMaterial:
			mat.set_shader_parameter("top_width_scale", top_width_scale)
			mat.set_shader_parameter("height_scale", height_scale)
			mat.set_shader_parameter("horizontal_shear", horizontal_shear)
			mat.set_shader_parameter("base_rotation_deg", base_rotation_deg)
			mat.set_shader_parameter("bend_exponent", bend_exponent)
			mat.set_shader_parameter("resample_bilinear", resample_bilinear)

			mat.set_shader_parameter("live_wind_mode", live_wind_mode)
			mat.set_shader_parameter("sim_wind_strength", sim_wind_strength)
			mat.set_shader_parameter("sim_wind_dir_y", sim_wind_dir_y)

	if ghost_sprite:
		ghost_sprite.visible = show_ghost
	if pixel_grid:
		pixel_grid.visible = show_grid

	_update_stats_display()

func _apply_physical_tilt_angle(deg: float) -> void:
	var theta := deg_to_rad(deg)
	var alpha := deg_to_rad(camera_pitch_deg)
	
	# 1. 精确 2:1 等距相机投影高度公式:
	# 草直立立于地面时屏幕高 H0 = 8.0, 3D真实长度 L = H0 / cos(alpha)
	# 倾斜 theta 后的屏幕投影高度 H(theta) = H0 * cos(theta + alpha) / cos(alpha)
	var h_ratio: float = cos(theta + alpha) / cos(alpha)
	h_ratio = clampf(h_ratio, 0.15, 1.8)
	height_scale = h_ratio
	
	# 2. 顶视图透视展开与收窄公式:
	# 草被向前吹迎向镜头时展开成扇形(俯瞰草丛叶片), 向后吹时收尖
	# W(theta) = W0 * (1.0 + 0.85 * sin(theta))
	var w_ratio: float = 1.0 + 0.85 * sin(theta)
	w_ratio = clampf(w_ratio, 0.1, 3.5)
	top_width_scale = w_ratio
	
	# 垂直风只沿 Y/深度 吹，横向侧倾剪切为 0
	horizontal_shear = 0.0
	
	_sync_parameters()

func _update_stats_display() -> void:
	var eff_top_w: float = 4.0 * top_width_scale
	var eff_height: float = 8.0 * height_scale

	if lbl_stat_physics:
		lbl_stat_physics.text = "📐 物理等距换算: 倾角 θ = %+0.1f° (30°俯角) | 理论屏幕高: %0.2f px | 顶宽: %0.2f px" % [wind_tilt_angle_deg, eff_height, eff_top_w]
	if lbl_stat_top:
		lbl_stat_top.text = "顶边宽度: %0.1f px (原宽 4px | 缩放: %0.0f%% | %+0.1f px)" % [eff_top_w, top_width_scale * 100.0, eff_top_w - 4.0]
	if lbl_stat_h:
		lbl_stat_h.text = "草身高度: %0.1f px (原高 8px | 缩放: %0.0f%% | 下压: -%0.1f px)" % [eff_height, height_scale * 100.0, 8.0 - eff_height]

	if lbl_stat_health:
		if top_width_scale < 0.2:
			lbl_stat_health.text = "⚠️ 极度收窄：顶边接近 0.5px 针尖状，仅保留单列亚像素采样。"
			lbl_stat_health.modulate = Color(1.0, 0.75, 0.15)
		elif height_scale < 0.3:
			lbl_stat_health.text = "⚠️ 极限贴地：高度压缩超过 70%，草身已完全紧贴地表。"
			lbl_stat_health.modulate = Color(1.0, 0.75, 0.15)
		elif top_width_scale > 2.5:
			lbl_stat_health.text = "⚠️ 扇形膨胀：顶边宽度已拉伸至原图 2.5 倍以上，单像素被横向展开。"
			lbl_stat_health.modulate = Color(1.0, 0.75, 0.15)
		else:
			lbl_stat_health.text = "✅ 自由重采样良好：连续曲率平滑，像素纹素无断裂，完美重采样！"
			lbl_stat_health.modulate = Color(0.4, 0.95, 0.4)

	# 换算逻辑：
	var base_force_y: float = maxf(1.0, sim_wind_strength * 0.35)
	var top_delta_abs: float = absf(eff_top_w - 4.0)
	var height_loss: float = maxf(0.0, 8.0 - eff_height)

	var rec_expand: float = clampf(top_delta_abs / base_force_y, 0.0, 1.2)
	var rec_squash: float = clampf(height_loss / base_force_y, 0.0, 1.2)
	var rec_str: float = maxf(absf(horizontal_shear), sim_wind_strength)

	if lbl_eq_strength: lbl_eq_strength.text = "%0.1f 像素" % rec_str
	if lbl_eq_expand: lbl_eq_expand.text = "%0.2f" % rec_expand
	if lbl_eq_squash: lbl_eq_squash.text = "%0.2f" % rec_squash

func _apply_preset_by_index(idx: int) -> void:
	match idx:
		1: # 微风
			top_width_scale = 1.25
			height_scale = 0.90
			horizontal_shear = 2.5
			bend_exponent = 1.8
			sim_wind_strength = 3.5
		2: # 中度阵风
			top_width_scale = 1.60
			height_scale = 0.75
			horizontal_shear = 5.5
			bend_exponent = 1.8
			sim_wind_strength = 6.0
		3: # 狂风暴雨
			top_width_scale = 2.10
			height_scale = 0.55
			horizontal_shear = 8.5
			bend_exponent = 1.9
			sim_wind_strength = 9.0
		4: # 极限飓风
			top_width_scale = 2.60
			height_scale = 0.40
			horizontal_shear = 11.0
			bend_exponent = 2.2
			sim_wind_strength = 13.0
		5: # 物理极限顺风迎面 (+45°)
			base_rotation_deg = 0.0
			wind_tilt_angle_deg = 45.0
			_apply_physical_tilt_angle(45.0)
		6: # 物理极限逆风背离 (-45°)
			base_rotation_deg = 0.0
			wind_tilt_angle_deg = -45.0
			_apply_physical_tilt_angle(-45.0)
		7: # 极限横风侧倾 (45° 旋转 + 弧度侧弯)
			base_rotation_deg = 45.0
			horizontal_shear = 2.0
			height_scale = 0.85
			top_width_scale = 1.15
			wind_tilt_angle_deg = 0.0

	_sync_parameters()
	if lbl_status_msg:
		lbl_status_msg.text = "已切换至预设！"
		lbl_status_msg.modulate = Color(0.4, 0.85, 1.0)

func save_to_game_material() -> void:
	var base_force_y: float = maxf(1.0, sim_wind_strength * 0.35)
	var eff_top_w: float = 4.0 * top_width_scale
	var eff_height: float = 8.0 * height_scale
	var top_delta_abs: float = absf(eff_top_w - 4.0)
	var height_loss: float = maxf(0.0, 8.0 - eff_height)

	var rec_expand: float = clampf(top_delta_abs / base_force_y, 0.0, 1.2)
	var rec_squash: float = clampf(height_loss / base_force_y, 0.0, 1.2)
	var final_strength: float = maxf(absf(horizontal_shear), sim_wind_strength)

	var mat_path := "res://resources/materials/grass_tuft.tres"
	var mat = load(mat_path) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("wind_strength", final_strength)
		mat.set_shader_parameter("perspective_expand", rec_expand)
		mat.set_shader_parameter("height_squash", rec_squash)
		ResourceSaver.save(mat, mat_path)
		print("[Weed Lab] 成功保存材质: %s (Strength: %0.1f, Expand: %0.2f, Squash: %0.2f)" % [mat_path, final_strength, rec_expand, rec_squash])

	if lbl_status_msg:
		lbl_status_msg.text = "✅ 成功保存至 grass_tuft.tres！主游戏已实时同步。"
		lbl_status_msg.modulate = Color(0.3, 1.0, 0.4)

func reset_defaults() -> void:
	base_rotation_deg = 0.0
	wind_tilt_angle_deg = 0.0
	top_width_scale = 1.0
	height_scale = 1.0
	horizontal_shear = 0.0
	bend_exponent = 1.8
	resample_bilinear = true
	sim_wind_strength = 6.0
	preset_selector = 0
	_sync_parameters()
	if lbl_status_msg:
		lbl_status_msg.text = "已重置为默认零形变初始状态。"
		lbl_status_msg.modulate = Color(0.8, 0.8, 0.8)
