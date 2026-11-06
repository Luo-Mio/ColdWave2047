@tool
extends Control

## 单噪波风场合成监视台控制器 (Single-Noise Wind Synthesizer Controller)
## 只需配置单个标准噪波源 (wind_noise.tres)，系统自动反向双偏航流动并叠加 PI 无理数偏移消解周期重复！

@export_group("单一风噪波源 (Single Noise Source)")
## 唯一的风力噪波纹理 (点击展开即可使用 FastNoiseLite 标准面板调节频度、分形、扭曲等)
@export var wind_noise: Texture2D = preload("res://resources/surface/wind/wind_noise.tres"):
	set(v):
		wind_noise = v
		_update_cards()

@export_group("风向与偏航 (Wind Direction & Yaw)")
## 基础风向向量 (如朝上 Vector2(0, -1)，朝右上 Vector2(1, -1)，朝右偏下 Vector2(1, 0.3))
@export var wind_base_dir: Vector2 = Vector2(0.0, -1.0):
	set(v):
		wind_base_dir = v
		_update_cards()

## 双向偏航开角 (度数，推荐 20° ~ 45°)
## 流向 A 偏航 +angle，流向 B 反向偏航 -angle，两者合成的主推进航向严格指向 wind_base_dir！
@export_range(0.0, 90.0, 1.0) var diverge_angle_deg: float = 23.0:
	set(v):
		diverge_angle_deg = v
		_update_cards()

@export_group("风速与空间尺度 (Speed & Scale)")
## 风速 (控制风浪掠过地表的快慢)
@export_range(0.0, 10.0, 0.1) var wind_speed: float = 2.0:
	set(v):
		wind_speed = v
		_update_cards()

## 噪波空间尺度 (数值越小风斑团块越大)
@export_range(0.1, 5.0, 0.1) var wind_noise_scale: float = 1.0:
	set(v):
		wind_noise_scale = v
		_update_cards()

## 阵风平衡阈值 (微调强风区与静风区的明暗对比)
@export_range(-0.5, 0.5, 0.02) var wind_noise_threshold: float = 0.25:
	set(v):
		wind_noise_threshold = v
		_update_cards()

@export_group("周期性风向摇曳 (Periodic Wander)")
## 是否启用风向左右周期性摆动 (麦浪晃荡感)
@export var enable_wind_wander: bool = true:
	set(v):
		enable_wind_wander = v
		_update_cards()

## 最大偏摆角度 (度数，如 20° 即在主风向左右 ±20° 范围内来回徘徊)
@export_range(0.0, 60.0, 1.0) var wander_angle_deg: float = 20.0:
	set(v):
		wander_angle_deg = v
		_update_cards()

## 偏摆频率速度 (0.3 约每 10~15 秒完成一轮优雅摆动)
@export_range(0.05, 2.0, 0.05) var wander_speed: float = 0.30:
	set(v):
		wander_speed = v
		_update_cards()

@export_group("游戏材质一键同步 (Sync to Game)")
## 勾选后，将当前调试出的这套风力参数与噪波一键同步写入游戏草皮与杂草材质中！
@export var sync_to_game_materials: bool = false:
	set(v):
		if v:
			_sync_to_game()

@onready var status_label: Label = get_node_or_null("StatusIndicator")

func _ready() -> void:
	_update_cards()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	
	if status_label:
		var cur_time = Time.get_ticks_msec() / 1000.0
		var base_deg = rad_to_deg(atan2(wind_base_dir.y, wind_base_dir.x))
		var wan_deg = 0.0
		if enable_wind_wander and wander_speed > 0.001:
			var w = wander_speed
			var tan_a = tan(deg_to_rad(wander_angle_deg))
			var side_vel = tan_a * (cos(cur_time * w) + 0.266 * cos(cur_time * w * 2.13))
			wan_deg = rad_to_deg(atan(side_vel))
		var live_deg = base_deg + wan_deg
		status_label.text = "【单噪波风力气象监视】基础航向: %.1f° | 偏摆角: %+.1f° | 瞬时合流: %.1f° | 反向偏航角: ±%.1f° (叠加 PI 无理数偏移)" % [base_deg, wan_deg, live_deg, diverge_angle_deg]

func _update_cards() -> void:
	var card_nodes = [
		get_node_or_null("CardsContainer/Card1/ViewportRect"),
		get_node_or_null("CardsContainer/Card2/ViewportRect"),
		get_node_or_null("CardsContainer/Card3/ViewportRect"),
		get_node_or_null("CardsContainer/Card4/ViewportRect"),
	]
	
	var div_rad = deg_to_rad(diverge_angle_deg)
	var wan_rad = deg_to_rad(wander_angle_deg)
	
	for rect in card_nodes:
		if rect and rect.material is ShaderMaterial:
			var mat = rect.material as ShaderMaterial
			mat.set_shader_parameter("wind_noise", wind_noise)
			mat.set_shader_parameter("wind_base_dir", wind_base_dir)
			mat.set_shader_parameter("wind_speed", wind_speed)
			mat.set_shader_parameter("noise_diverge_angle", div_rad)
			mat.set_shader_parameter("wind_noise_scale", wind_noise_scale)
			mat.set_shader_parameter("wind_noise_threshold", wind_noise_threshold)
			mat.set_shader_parameter("enable_wind_wander", enable_wind_wander)
			mat.set_shader_parameter("wind_wander_angle", wan_rad)
			mat.set_shader_parameter("wind_wander_speed", wander_speed)

func _sync_to_game() -> void:
	var div_rad = deg_to_rad(diverge_angle_deg)
	var wan_rad = deg_to_rad(wander_angle_deg)
	
	var tuft_mat = load("res://resources/materials/grass_tuft.tres") as ShaderMaterial
	if tuft_mat:
		tuft_mat.set_shader_parameter("wind_noise", wind_noise)
		tuft_mat.set_shader_parameter("wind_base_dir", wind_base_dir)
		tuft_mat.set_shader_parameter("wind_speed", wind_speed)
		tuft_mat.set_shader_parameter("noise_diverge_angle", div_rad)
		tuft_mat.set_shader_parameter("wind_noise_threshold", wind_noise_threshold)
		tuft_mat.set_shader_parameter("enable_wind_wander", enable_wind_wander)
		tuft_mat.set_shader_parameter("wind_wander_angle", wan_rad)
		tuft_mat.set_shader_parameter("wind_wander_speed", wander_speed)
		ResourceSaver.save(tuft_mat, "res://resources/materials/grass_tuft.tres")
		print("[Wind Studio] 已同步单噪波与风力参数至草花材质 grass_tuft.tres")
		
	var surf_mat = load("res://resources/materials/grass_surface.tres") as ShaderMaterial
	if surf_mat:
		surf_mat.set_shader_parameter("wind_noise", wind_noise)
		surf_mat.set_shader_parameter("wind_base_dir", wind_base_dir)
		surf_mat.set_shader_parameter("wind_speed", wind_speed)
		surf_mat.set_shader_parameter("noise_diverge_angle", div_rad)
		surf_mat.set_shader_parameter("wind_noise_threshold", wind_noise_threshold)
		surf_mat.set_shader_parameter("enable_wind_wander", enable_wind_wander)
		surf_mat.set_shader_parameter("wind_wander_angle", wan_rad)
		surf_mat.set_shader_parameter("wind_wander_speed", wander_speed)
		ResourceSaver.save(surf_mat, "res://resources/materials/grass_surface.tres")
		print("[Wind Studio] 已同步单噪波与风力参数至地表材质 grass_surface.tres")
