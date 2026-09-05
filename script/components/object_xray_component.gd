# object_xray_component.gd —— 物体高耸遮挡透视组件 (自动为树冠/屋顶挂载共享 X-Ray Shader)
class_name ObjectXRayComponent
extends Node

@export_group("高耸遮挡透视配置 (X-Ray)")
## 是否启用该物体的树冠/高物透视遮罩。勾选后进入角色视野时树冠将自动呈现 Bayer 点阵透明
@export var enable_xray: bool = true
## 需要挂载透视材质的目标子节点名称 (默认 "Canopy"，也可按需指定为 "Roof" 等)
@export var target_node_name: String = "Canopy"
## 该物体透视遮罩的最大镂空透光度乘率 (0.0=实心不透, 1.0=完全遵照生物透视遮罩)
@export_range(0.0, 1.0, 0.05) var xray_max_transparency: float = 1.0

# 共享材质静态缓存 (享元模式 Flyweight，所有物体共用一份资源，底层自动合批！)
static var _shared_xray_material: ShaderMaterial = null

var parent_object: Node2D
var target_visual_node: CanvasItem

func _ready() -> void:
	var curr := get_parent()
	while curr:
		if curr is Node2D:
			parent_object = curr as Node2D
			break
		curr = curr.get_parent()

	if not enable_xray or parent_object == null:
		return

	# 确保加入全局 xray_objects 分组
	parent_object.add_to_group("xray_objects")

	# 自动寻找目标视觉节点
	target_visual_node = parent_object.find_child(target_node_name, true, false) as CanvasItem
	if target_visual_node == null:
		# 尝试通配寻找以 Canopy 或 Roof 开头的节点
		for child in parent_object.get_children():
			if child is CanvasItem and (child.name.begins_with("Canopy") or child.name.begins_with("Roof")):
				target_visual_node = child as CanvasItem
				break

	if target_visual_node:
		_apply_xray_material(target_visual_node)

func _apply_xray_material(target: CanvasItem) -> void:
	if _shared_xray_material == null:
		# 优先尝试加载已保存的共享材质，否则动态创建一份并复用
		var mat_path := "res://resources/materials/canopy_xray.tres"
		if ResourceLoader.exists(mat_path):
			_shared_xray_material = load(mat_path) as ShaderMaterial
		if _shared_xray_material == null:
			_shared_xray_material = ShaderMaterial.new()
			_shared_xray_material.shader = load("res://script/shaders/xray.gdshader")

	# 若该物体自身有特殊的透明度乘率覆盖，可根据需要设置；若为默认1.0，则直接共享单例
	if xray_max_transparency != 1.0:
		var custom_mat := _shared_xray_material.duplicate() as ShaderMaterial
		custom_mat.set_shader_parameter("max_transparency", xray_max_transparency)
		target.material = custom_mat
	else:
		target.material = _shared_xray_material
