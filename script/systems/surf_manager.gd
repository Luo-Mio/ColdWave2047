# surf_manager.gd —— 2D 等距双网格表层草皮/覆盖物系统 (Dual-Grid Surface System)
# 将逻辑地块网格与 16-Tile 紧凑双网格瓦片完美交错对齐，实现零缝隙自然圆角与平滑地表过渡
@tool
class_name SurfManager
extends Node

static var instance: SurfManager = null

## 16 种双网格角落组合对应的瓦片图集坐标 (遵循 4-bit 掩码 0~15，完全匹配 grass_out.png)
## Bit 0: 上角 (Top), Bit 1: 右角 (Right), Bit 2: 左角 (Left), Bit 3: 下角 (Bottom)
const MASK_TO_ATLAS: Array[Vector2i] = [
	Vector2i(0, 3), # 0:  0000 (完全透明/无草)
	Vector2i(3, 3), # 1:  0001 (仅上角有草)
	Vector2i(0, 2), # 2:  0010 (仅右角有草)
	Vector2i(1, 2), # 3:  0011 (上 + 右)
	Vector2i(0, 0), # 4:  0100 (仅左角有草)
	Vector2i(3, 2), # 5:  0101 (上 + 左)
	Vector2i(2, 3), # 6:  0110 (右 + 左)
	Vector2i(3, 1), # 7:  0111 (上 + 右 + 左)
	Vector2i(1, 3), # 8:  1000 (仅下角有草)
	Vector2i(0, 1), # 9:  1001 (上 + 下)
	Vector2i(1, 0), # 10: 1010 (右 + 下)
	Vector2i(2, 2), # 11: 1011 (上 + 右 + 下)
	Vector2i(3, 0), # 12: 1100 (左 + 下)
	Vector2i(2, 0), # 13: 1101 (上 + 左 + 下)
	Vector2i(1, 1), # 14: 1110 (右 + 左 + 下)
	Vector2i(2, 1), # 15: 1111 (4角全满，完整草皮)
]

@export var surface_layer: TileMapLayer
@export var ground_layer: TileMapLayer
@export var grass_tileset: TileSet = preload("res://resources/surface/GreenGrass/grass_tileset.tres")
@export var surface_material: Material = preload("res://resources/materials/grass_surface.tres")

@export_group("草皮噪波色斑与阅览")
## 噪波阅览模式切换：0:正常渲染 1:纯黑白灰度噪波 2:阈值二值遮罩
@export_enum("正常游戏渲染", "纯噪波黑白灰度图", "阈值二值遮罩") var debug_mode: int = 0:
	set(v):
		debug_mode = v
		_sync_debug_mode()

@export_group("风力热力图与气象阅览 (Wind Debug & Heatmap)")
## 气象与阵风阅览模式：一键将主场景所有草皮与杂草切换为实时彩色热力图！
## 红色/橙红 = 强阵风峰值（推挤小草最大的区域）；深海蓝 = 静风无力区；青/明黄 = 微风过渡
@export_enum(
	"正常游戏渲染 (草皮色斑 + 自然风动)",
	"阵风彩色热力图 (红=强风推挤 / 蓝=静风区)",
	"阵风黑白位移场 (白=强推位移 / 黑=回弹无风)",
	"单噪波流向 A 灰度",
	"单噪波流向 B 灰度 (+PI 偏移)"
) var wind_debug_mode: int = 0:
	set(v):
		wind_debug_mode = v
		_sync_wind_debug_mode()

const DEFAULT_WEED_TEXTURE: Texture2D = preload("res://resources/surface/textre/grass.png")
const DEFAULT_WEED_MATERIAL: Material = preload("res://resources/materials/grass_tuft.tres")
const MASK_TEXTURE_PATH: String = "res://resources/surface/GreenGrass/grass_out.png"

@export_group("杂草点缀 (Weed Foliage)")
@export var enable_weeds: bool = true
@export var weed_texture: Texture2D = DEFAULT_WEED_TEXTURE
@export var weed_material: Material = DEFAULT_WEED_MATERIAL
## 归一化杂草密度 (0.0 为完全无草，1.0 为极致饱满草浪)
@export_range(0.0, 1.0, 0.02) var weed_density: float = 0.5:
	set(v):
		weed_density = v
		rebuild_all_weeds()
## 随机颜色杂草比例 (0.0 为完全遵从地表颜色，0.2 为 20% 杂草从噪波三阶池随机抽选)
@export_range(0.0, 1.0, 0.05) var random_color_ratio: float = 0.2:
	set(v):
		random_color_ratio = v
		_sync_random_color_ratio()

var foliage_container: Node2D = null
var weeds_by_dual_cell: Dictionary = {}
var _player_node: Node2D = null
var _mask_image: Image = null

func _init() -> void:
	instance = self

func _ready() -> void:
	instance = self
	_setup_surface_layer()
	_setup_foliage_container()
	_sync_debug_mode()
	_sync_wind_debug_mode()
	_sync_random_color_ratio()
	rebuild_all_weeds()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if weed_material is ShaderMaterial:
		if _player_node == null or not is_instance_valid(_player_node):
			var root := get_parent()
			if root:
				_player_node = root.find_child("main_chara", true, false) as Node2D
		if _player_node and is_instance_valid(_player_node):
			(weed_material as ShaderMaterial).set_shader_parameter("creature_pos", _player_node.global_position)

func _sync_debug_mode() -> void:
	if wind_debug_mode == 0:
		if surface_material is ShaderMaterial:
			(surface_material as ShaderMaterial).set_shader_parameter("debug_mode", debug_mode)
		if surface_layer and surface_layer.material is ShaderMaterial:
			(surface_layer.material as ShaderMaterial).set_shader_parameter("debug_mode", debug_mode)

func _sync_wind_debug_mode() -> void:
	# 映射到 grass_surface.gdshader 的 debug_mode
	var surf_debug := 0
	match wind_debug_mode:
		1: surf_debug = 6 # 6: 预览混合阵风彩色热力带
		2: surf_debug = 5 # 5: 预览混合阵风黑白波块
		3: surf_debug = 3 # 3: 预览第一层风波 (Wave 1)
		4: surf_debug = 4 # 4: 预览第二层风波 (Wave 2)
		_: surf_debug = debug_mode

	if surface_material is ShaderMaterial:
		(surface_material as ShaderMaterial).set_shader_parameter("debug_mode", surf_debug)
	if surface_layer and surface_layer.material is ShaderMaterial:
		(surface_layer.material as ShaderMaterial).set_shader_parameter("debug_mode", surf_debug)

	# 映射到 grass_tuft.gdshader 的 debug_wind_mode
	var tuft_debug := 0
	match wind_debug_mode:
		1: tuft_debug = 4 # 4: 合成阵风彩色热力图
		2: tuft_debug = 3 # 3: 合成阵风黑白位移场
		3: tuft_debug = 1 # 1: 噪波流向 A
		4: tuft_debug = 2 # 2: 噪波流向 B
		_: tuft_debug = 0

	if weed_material is ShaderMaterial:
		(weed_material as ShaderMaterial).set_shader_parameter("debug_wind_mode", tuft_debug)

func _sync_random_color_ratio() -> void:
	if weed_material is ShaderMaterial:
		(weed_material as ShaderMaterial).set_shader_parameter("random_color_ratio", random_color_ratio)

## 配置双网格渲染图层
func _setup_surface_layer() -> void:
	if surface_layer == null:
		var root := get_parent()
		if root:
			surface_layer = root.find_child("SurfaceLayer", true, false) as TileMapLayer

	if surface_layer:
		surface_layer.enabled = true
		if grass_tileset:
			surface_layer.tile_set = grass_tileset
		# 双网格在 2:1 等距菱形网格下向上偏移半格 (-16px)，使显示格中心与 4 个地砖交界角精准重合
		surface_layer.position = Vector2(0.0, -16.0)
		surface_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		surface_layer.y_sort_enabled = true
		if surface_material and surface_layer.material == null:
			surface_layer.material = surface_material

## 获取逻辑地砖 (x, y) 触碰到的 4 个双网格交点坐标 (适配交错等距网格 TILE_LAYOUT_STACKED)
static func get_affected_dual_cells(cell: Vector2i) -> Array[Vector2i]:
	var is_odd := (absi(cell.y) % 2 == 1)
	if is_odd:
		return [
			Vector2i(cell.x, cell.y),         # cell 是该双格的下角 (B)
			Vector2i(cell.x, cell.y + 2),     # cell 是该双格的上角 (T)
			Vector2i(cell.x, cell.y + 1),     # cell 是该双格的右角 (R)
			Vector2i(cell.x + 1, cell.y + 1), # cell 是该双格的左角 (L)
		]
	else:
		return [
			Vector2i(cell.x, cell.y),         # cell 是该双格的下角 (B)
			Vector2i(cell.x, cell.y + 2),     # cell 是该双格的上角 (T)
			Vector2i(cell.x - 1, cell.y + 1), # cell 是该双格的右角 (R)
			Vector2i(cell.x, cell.y + 1),     # cell 是该双格的左角 (L)
		]

## 放置或铲除某格草皮 (同步更新 GridData 并刷新受影响的 4 个双网格交点及杂草)
func set_surf(cell: Vector2i, exists: bool, type_name: String = "grass") -> void:
	GridData.set_surf(cell, exists, type_name)
	for d in get_affected_dual_cells(cell):
		_update_dual_cell(d.x, d.y)

## 检查指定地块是否有草皮
func has_surf(cell: Vector2i) -> bool:
	return GridData.has_surf(cell)

## 更新单个双网格交点 (u, v) 的切片贴图与真实遮罩杂草
func _update_dual_cell(u: int, v: int) -> void:
	if surface_layer == null:
		return

	var is_odd := (absi(v) % 2 == 1)
	var top_cell := Vector2i(u, v - 2)
	var bottom_cell := Vector2i(u, v)
	var right_cell: Vector2i
	var left_cell: Vector2i
	if is_odd:
		right_cell = Vector2i(u + 1, v - 1)
		left_cell = Vector2i(u, v - 1)
	else:
		right_cell = Vector2i(u, v - 1)
		left_cell = Vector2i(u - 1, v - 1)

	# 计算该交点四周 4 个逻辑角的草皮存在情况 (4-bit 掩码)
	var mask := 0
	if GridData.has_surf(top_cell):    mask |= 1 # Top (上)
	if GridData.has_surf(right_cell):  mask |= 2 # Right (右)
	if GridData.has_surf(left_cell):   mask |= 4 # Left (左)
	if GridData.has_surf(bottom_cell): mask |= 8 # Bottom (下)

	var dual_cell := Vector2i(u, v)
	if mask == 0:
		surface_layer.erase_cell(dual_cell)
		clear_weeds_for_dual_cell(dual_cell)
	else:
		surface_layer.set_cell(dual_cell, 0, MASK_TO_ATLAS[mask])
		update_weeds_for_dual_cell(dual_cell)

## 根据当前 GridData.surf_grid 全量重新计算并烘焙所有双网格瓦片及杂草
func rebuild_all_surf() -> void:
	_setup_surface_layer()
	if surface_layer:
		surface_layer.clear()

	var affected_dual_cells: Dictionary = {}
	for cell in GridData.surf_grid.keys():
		for d in get_affected_dual_cells(cell):
			affected_dual_cells[d] = true

	for d in affected_dual_cells.keys():
		_update_dual_cell(d.x, d.y)

	rebuild_all_weeds()

## 清空所有地表草皮及杂草
func clear_all_surf() -> void:
	GridData.clear_all_surfaces()
	if surface_layer:
		surface_layer.clear()
	clear_all_weeds()

# ==============================================================================
# 杂草点缀与生成逻辑 (Weed Tufts & Foliage System)
# 基于草皮真实 Alpha 遮罩拒绝采样 (Mask-Based Rejection Sampling)
# ==============================================================================

## 缓存的草皮图集 Alpha 掩码 Image
func _get_mask_image() -> Image:
	if _mask_image == null:
		var tex := preload(MASK_TEXTURE_PATH) as Texture2D
		if tex:
			_mask_image = tex.get_image()
	return _mask_image

## 初始化杂草挂载容器
func _setup_foliage_container() -> void:
	if foliage_container != null and is_instance_valid(foliage_container):
		return
	var root := get_parent()
	if root:
		var entities := root.find_child("Entities", true, false) as Node2D
		if entities:
			foliage_container = entities.find_child("FoliageContainer", false, false) as Node2D
			if foliage_container == null:
				foliage_container = Node2D.new()
				foliage_container.name = "FoliageContainer"
				foliage_container.add_to_group("foliage")
				foliage_container.y_sort_enabled = true
				entities.add_child(foliage_container)

## 更新单个双网格切片的杂草 (基于 grass_out.png 真实 Alpha 遮罩拒绝采样 + 归一化空间概率哈希)
func update_weeds_for_dual_cell(dual_cell: Vector2i) -> void:
	clear_weeds_for_dual_cell(dual_cell)

	var eff_density: float = weed_density if weed_density != null else 0.5
	if not enable_weeds or eff_density <= 0.001 or surface_layer == null:
		return

	var atlas_coord := surface_layer.get_cell_atlas_coords(dual_cell)
	if atlas_coord == Vector2i(-1, -1):
		return

	var img := _get_mask_image()
	if img == null:
		return

	if foliage_container == null or not is_instance_valid(foliage_container):
		_setup_foliage_container()
	if foliage_container == null:
		return

	# 双网格切片的全局中心坐标
	var dual_center := surface_layer.to_global(surface_layer.map_to_local(dual_cell))

	var eff_texture := weed_texture if weed_texture != null else DEFAULT_WEED_TEXTURE
	var eff_material := weed_material if weed_material != null else DEFAULT_WEED_MATERIAL
	var tex_h: float = float(eff_texture.get_height()) if eff_texture != null else 8.0
	var weed_bottom_offset := Vector2(0.0, -tex_h * 0.5)

	# 微网格抖动步长 (X 方向 3 像素，Y 方向 2 像素，匹配 2:1 等距透视比例)
	# 保证每一个像素都有平等概率成为候选点，同时维持最佳的像素间距与视觉层次
	const STEP_X: int = 3
	const STEP_Y: int = 2

	var list: Array[Sprite2D] = []

	for y_base in range(-16, 16, STEP_Y):
		for x_base in range(-32, 32, STEP_X):
			# 1. 局部抖动：让每个微格里的任意像素都有平等机会成为候选点
			var h1 := _hash_point(int(dual_center.x) + x_base, int(dual_center.y) + y_base, 42)
			var jx := int(h1 % STEP_X)
			var jy := int((h1 >> 8) % STEP_Y)
			var dx := x_base + jx
			var dy := y_base + jy

			# 2. 本地瓦片边界约束：严格限制在当前瓦片 64x32 范围内，严防跨越到图集中相邻切片
			var local_x := dx + 32
			var local_y := dy + 16
			if local_x < 0 or local_x >= 64 or local_y < 0 or local_y >= 32:
				continue

			var px := atlas_coord.x * 64 + local_x
			var py := atlas_coord.y * 32 + local_y

			# 3. 查询草皮遮罩真值与连通扎根检查 (拒绝透明区域与孤立单像素噪点)
			if not _is_solid_grass_pixel(img, px, py, atlas_coord.x, atlas_coord.y):
				continue # 【拒绝式采样】：透明区域（圆角外/泥地）或孤立单像素点绝对不长草！

			# 4. 全局唯一世界像素坐标
			var raw_world_x: float = floor(dual_center.x + float(dx))
			var raw_world_y: float = floor(dual_center.y + float(dy))

			# 5. 全局空间哈希概率判定 (严格按照 eff_density 归一化比例生成)
			var h_prob: int = _hash_point(int(raw_world_x), int(raw_world_y), 999)
			if (float(h_prob % 1000) / 1000.0) >= eff_density:
				continue

			# 6. 严格对齐整像素网格 (使用纯整数坐标，彻底消除引擎对齐在 0.5 临界点处的亚像素翻转)
			var snapped_pos := Vector2(raw_world_x, raw_world_y)

			var sp := Sprite2D.new()
			sp.texture = eff_texture
			sp.material = eff_material
			sp.centered = true
			sp.offset = weed_bottom_offset
			sp.position = snapped_pos
			foliage_container.add_child(sp)
			list.append(sp)

	if not list.is_empty():
		weeds_by_dual_cell[dual_cell] = list

## 清除单个双网格切片上的杂草
func clear_weeds_for_dual_cell(dual_cell: Vector2i) -> void:
	if weeds_by_dual_cell.has(dual_cell):
		var list: Variant = weeds_by_dual_cell[dual_cell]
		if list is Array:
			for sp in list:
				if is_instance_valid(sp):
					sp.queue_free()
		weeds_by_dual_cell.erase(dual_cell)

## 清空所有杂草
func clear_all_weeds() -> void:
	for dc in weeds_by_dual_cell.keys():
		var list: Variant = weeds_by_dual_cell[dc]
		if list is Array:
			for sp in list:
				if is_instance_valid(sp):
					sp.queue_free()
	weeds_by_dual_cell.clear()

## 全量根据当前 SurfaceLayer 上的所有真实切片重建杂草
func rebuild_all_weeds() -> void:
	clear_all_weeds()
	if not enable_weeds or weed_density <= 0.001 or surface_layer == null:
		return
	for dual_cell in surface_layer.get_used_cells():
		update_weeds_for_dual_cell(dual_cell)

## 辅助通用哈希函数
static func _hash_point(x: int, y: int, seed_val: int) -> int:
	var n := (x * 374761393 + y * 668265263 + seed_val * 982451653) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return n

## 检查指定瓦片内的像素是否属于实心草皮扎根点（拒绝透明区域与美术图中的孤立单像素瑕疵/噪点）
static func _is_solid_grass_pixel(img: Image, px: int, py: int, ax: int, ay: int) -> bool:
	if img.get_pixel(px, py).a <= 0.5:
		return false
	var min_x := ax * 64
	var max_x := (ax + 1) * 64
	var min_y := ay * 32
	var max_y := (ay + 1) * 32
	var neighbors := 0
	for ny in range(py - 1, py + 2):
		for nx in range(px - 1, px + 2):
			if nx == px and ny == py:
				continue
			if nx >= min_x and nx < max_x and ny >= min_y and ny < max_y:
				if img.get_pixel(nx, ny).a > 0.5:
					neighbors += 1
	# 至少有 3 个非透明相邻像素才认定为有效草皮实体，过滤孤立的 1~2 像素笔刷杂点
	return neighbors >= 3
