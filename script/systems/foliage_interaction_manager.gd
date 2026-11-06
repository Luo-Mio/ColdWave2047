# foliage_interaction_manager.gd —— 植被与草地多实体动态交互管理器 (方案 B: SubViewport 2:1 椭圆动态矢量交互图)
class_name FoliageInteractionManager
extends Node2D

@export_group("交互与衰减配置")
## 是否启用多实体交互图
@export var enabled: bool = true:
	set(v):
		enabled = v
		_sync_enabled()

## 踩踏压倒滞留时间 (秒)。草被踩扁后保持完全倒伏、不动的延迟时间 (例如 0.35 秒)
@export_range(0.0, 2.0, 0.05) var trample_hold_time: float = 0.35

## 挺直回弹恢复时间 (秒)。滞留结束后，草从倒伏缓慢挺直、逐渐变亮复原所需的时间 (例如 1.2 秒)
@export_range(0.2, 5.0, 0.1) var trample_recover_time: float = 1.2

## 脚印盖章步长间隔 (像素)。角色走动多少像素盖下一个新的衰减足迹
@export_range(2.0, 20.0, 1.0) var step_stamp_interval: float = 6.0

## 默认 2:1 椭圆推力尺寸 (像素，宽度与高度，2:1 比例)
@export var default_stamp_size: Vector2 = Vector2(48.0, 24.0)

## 默认推挤力量倍率
@export_range(0.1, 5.0, 0.1) var default_strength: float = 1.0

## 交互视口分辨率 (覆盖可见视口，带安全外扩边距)
@export var viewport_size: Vector2i = Vector2i(768, 448)

@export_group("关联材质引用")
## 杂草材质 (若留空，自动从 SurfManager 获取)
@export var weed_material: ShaderMaterial
## 地表材质 (若留空，自动从 SurfManager 获取)
@export var surface_material: ShaderMaterial

@export_group("调试预览")
## 是否在游戏左上角显示交互贴图实时黑白/矢量监视小窗
@export var debug_preview: bool = false:
	set(v):
		debug_preview = v
		if _debug_rect:
			_debug_rect.visible = debug_preview

# 内部脚印结构体
class TrailStamp:
	var pos: Vector2
	var size: Vector2
	var strength: float
	var life: float
	var max_life: float
	var current_strength: float

var _stamps: Array[TrailStamp] = []
var _creature_states: Dictionary = {} # instance_id -> { "last_pos": Vector2 }

var _sub_viewport: SubViewport
var _sub_camera: Camera2D
var _stamp_drawer: Node2D
var _stamp_texture: ImageTexture
var _debug_canvas: CanvasLayer
var _debug_rect: TextureRect

func _ready() -> void:
	_init_stamp_texture()
	_setup_sub_viewport()
	_setup_debug_preview()
	_fetch_materials_if_needed()
	_sync_materials()

func _init_stamp_texture() -> void:
	# 动态生成 64x32 的 2:1 椭圆径向矢量推力贴图
	var w := 64
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rx := 30.0
	var ry := 15.0
	var cx := 31.5
	var cy := 15.5
	
	for y in range(h):
		for x in range(w):
			var dx := float(x) - cx
			var dy := float(y) - cy
			var dist := sqrt((dx / rx) * (dx / rx) + (dy / ry) * (dy / ry))
			if dist >= 1.0:
				# 外部中立区域：R=0.5, G=0.5 (推力向量为 0), B=0 (推力强度为 0), A=0
				img.set_pixel(x, y, Color(0.5, 0.5, 0.0, 0.0))
			else:
				# 内部 S 型余弦平滑衰减
				var s := clampf(1.0 - dist, 0.0, 1.0)
				s = s * s * (3.0 - 2.0 * s)
				# 2:1 等距椭圆梯度法线方向 (朝向椭圆外侧排斥)
				var dir := Vector2(dx, dy * 2.0)
				if dir.length_squared() > 0.001:
					dir = dir.normalized()
				else:
					dir = Vector2.ZERO
				var r := 0.5 + 0.5 * dir.x
				var g := 0.5 + 0.5 * dir.y
				var b := s
				var a := s
				img.set_pixel(x, y, Color(r, g, b, a))
				
	_stamp_texture = ImageTexture.create_from_image(img)

func _setup_sub_viewport() -> void:
	_sub_viewport = SubViewport.new()
	_sub_viewport.name = "FoliageInteractionViewport"
	_sub_viewport.size = viewport_size
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_sub_viewport.transparent_bg = false
	add_child(_sub_viewport)

	_sub_camera = Camera2D.new()
	_sub_camera.name = "InteractionCamera"
	_sub_camera.zoom = Vector2(1, 1)
	_sub_camera.position_smoothing_enabled = false
	_sub_viewport.add_child(_sub_camera)

	_stamp_drawer = Node2D.new()
	_stamp_drawer.name = "StampDrawer"
	_sub_viewport.add_child(_stamp_drawer)
	_stamp_drawer.draw.connect(_on_stamp_drawer_draw)

func _setup_debug_preview() -> void:
	_debug_canvas = CanvasLayer.new()
	_debug_canvas.layer = 120
	add_child(_debug_canvas)

	_debug_rect = TextureRect.new()
	_debug_rect.position = Vector2(16, 16)
	_debug_rect.size = Vector2(256, 150)
	_debug_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_debug_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_debug_rect.texture = _sub_viewport.get_texture()
	_debug_rect.visible = debug_preview
	_debug_canvas.add_child(_debug_rect)

func _fetch_materials_if_needed() -> void:
	if weed_material == null or surface_material == null:
		var parent := get_parent()
		var surf_mgr: Node = parent if (parent and "weed_material" in parent) else (get_tree().get_first_node_in_group("surf_manager") if get_tree() else null)
		if surf_mgr:
			if weed_material == null and "weed_material" in surf_mgr:
				weed_material = surf_mgr.weed_material
			if surface_material == null and "surface_material" in surf_mgr:
				surface_material = surf_mgr.surface_material

func _sync_enabled() -> void:
	if weed_material:
		weed_material.set_shader_parameter("enable_interaction_map", enabled)
	if surface_material:
		surface_material.set_shader_parameter("enable_interaction_map", enabled)

func _process(delta: float) -> void:
	if not enabled or not is_inside_tree():
		return

	# 1. 寻找当前主摄像机并同步视口世界坐标
	var main_cam := get_viewport().get_camera_2d()
	var center_pos := Vector2.ZERO
	if main_cam and is_instance_valid(main_cam):
		center_pos = main_cam.global_position
	else:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player and is_instance_valid(player):
			center_pos = player.global_position

	_sub_camera.global_position = center_pos

	var vp_size := Vector2(_sub_viewport.size)
	var top_left := center_pos - vp_size * 0.5
	var bounds := Vector4(top_left.x, top_left.y, vp_size.x, vp_size.y)

	# 2. 收集当前场景中的活跃生物 (包括玩家和所有动物)
	var active_creatures := _collect_active_creatures()

	# 3. 为移动的生物留下衰减脚印
	for c in active_creatures:
		var iid := c.get_instance_id()
		var cur_pos := c.global_position
		if not _creature_states.has(iid):
			_creature_states[iid] = { "last_pos": cur_pos }
			continue

		var state: Dictionary = _creature_states[iid]
		var last_p: Vector2 = state["last_pos"]
		if cur_pos.distance_to(last_p) >= step_stamp_interval:
			# 产生新的衰减足迹
			var st := TrailStamp.new()
			st.pos = last_p
			st.size = c.get("foliage_push_size") if ("foliage_push_size" in c and c.foliage_push_size != Vector2.ZERO) else default_stamp_size
			st.strength = c.get("foliage_push_strength") if ("foliage_push_strength" in c) else default_strength
			var total_time := trample_hold_time + trample_recover_time
			st.life = total_time
			st.max_life = total_time
			st.current_strength = st.strength
			_stamps.append(st)
			state["last_pos"] = cur_pos

	# 4. 更新与清理历史脚印
	var idx := _stamps.size() - 1
	while idx >= 0:
		var st := _stamps[idx]
		st.life -= delta
		if st.life <= 0.0:
			_stamps.remove_at(idx)
		else:
			if st.life >= trample_recover_time:
				# 阶段一：滞留延迟阶段 (Hold Phase) —— 100% 保持完全倒伏与变暗
				st.current_strength = st.strength
			else:
				# 阶段二：挺直回弹阶段 (Recover Phase) —— 从 1.0 缓慢滑落至 0.0，同时逐渐变亮复原
				var t := clampf(st.life / trample_recover_time, 0.0, 1.0)
				st.current_strength = st.strength * (t * t * (3.0 - 2.0 * t))
		idx -= 1

	# 清理已销毁生物的旧状态
	var valid_iids: Dictionary = {}
	for c in active_creatures:
		valid_iids[c.get_instance_id()] = true
	var keys := _creature_states.keys()
	for k in keys:
		if not valid_iids.has(k):
			_creature_states.erase(k)

	# 5. 通知 StampDrawer 重绘
	if _stamp_drawer:
		_stamp_drawer.queue_redraw()

	# 6. 传递视口贴图与世界边界给材质
	_sync_materials_runtime(bounds)

func _collect_active_creatures() -> Array[Node2D]:
	var list: Array[Node2D] = []
	var seen: Dictionary = {}

	# A. 抓取 player 组
	for n in get_tree().get_nodes_in_group("player"):
		if n is Node2D and n.is_inside_tree() and n.visible:
			var iid := n.get_instance_id()
			if not seen.has(iid):
				seen[iid] = true
				list.append(n as Node2D)

	# B. 抓取 creature 组 (动物、野生生物、NPC)
	for n in get_tree().get_nodes_in_group("creature"):
		if n is Node2D and n.is_inside_tree() and n.visible:
			var iid := n.get_instance_id()
			if not seen.has(iid):
				seen[iid] = true
				list.append(n as Node2D)

	# C. 自动扫描 Entities 容器下的所有 CharacterBody2D
	var entities := get_tree().get_first_node_in_group("entities")
	if entities == null:
		var root := get_tree().current_scene
		if root:
			entities = root.find_child("Entities", true, false)
	if entities:
		for child in entities.get_children():
			if child is CharacterBody2D and child.is_inside_tree() and child.visible:
				var iid := child.get_instance_id()
				if not seen.has(iid):
					seen[iid] = true
					list.append(child as Node2D)

	return list

func _on_stamp_drawer_draw() -> void:
	if _stamp_drawer == null or _stamp_texture == null or _sub_camera == null:
		return

	var cam_pos := _sub_camera.global_position
	var vp_size := Vector2(_sub_viewport.size)

	# 1. 铺设中立中灰色背景 (R=0.5, G=0.5, B=0, A=1 代表全域推力为 0)
	var bg_rect := Rect2(cam_pos - vp_size * 0.5, vp_size)
	_stamp_drawer.draw_rect(bg_rect, Color(0.5, 0.5, 0.0, 1.0))

	# 2. 绘制所有正在缓慢回弹的衰减足迹
	for st in _stamps:
		var rect := Rect2(st.pos - st.size * 0.5, st.size)
		_stamp_drawer.draw_texture_rect(_stamp_texture, rect, false, Color(1.0, 1.0, 1.0, st.current_strength))

	# 3. 绘制所有当前活跃生物脚底的实时强推力印章 (强度 100%)
	var creatures := _collect_active_creatures()
	for c in creatures:
		var sz: Vector2 = c.get("foliage_push_size") if ("foliage_push_size" in c and c.foliage_push_size != Vector2.ZERO) else default_stamp_size
		var strn: float = c.get("foliage_push_strength") if ("foliage_push_strength" in c) else default_strength
		var rect := Rect2(c.global_position - sz * 0.5, sz)
		_stamp_drawer.draw_texture_rect(_stamp_texture, rect, false, Color(1.0, 1.0, 1.0, strn))

func _sync_materials() -> void:
	_fetch_materials_if_needed()
	if _sub_viewport == null:
		return
	var tex := _sub_viewport.get_texture()
	if weed_material:
		weed_material.set_shader_parameter("enable_interaction_map", enabled)
		weed_material.set_shader_parameter("interaction_tex", tex)
	if surface_material:
		surface_material.set_shader_parameter("enable_interaction_map", enabled)
		surface_material.set_shader_parameter("interaction_tex", tex)

func _sync_materials_runtime(bounds: Vector4) -> void:
	_fetch_materials_if_needed()
	if weed_material:
		weed_material.set_shader_parameter("interaction_bounds", bounds)
	if surface_material:
		surface_material.set_shader_parameter("interaction_bounds", bounds)
