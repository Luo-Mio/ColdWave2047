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

func _init() -> void:
	instance = self

func _ready() -> void:
	instance = self
	_setup_surface_layer()

## 配置双网格渲染图层
func _setup_surface_layer() -> void:
	if surface_layer == null:
		var root := get_parent()
		if root:
			surface_layer = root.find_child("SurfaceLayer", true, false) as TileMapLayer

	if surface_layer:
		if grass_tileset:
			surface_layer.tile_set = grass_tileset
		# 双网格在 2:1 等距菱形网格下向上偏移半格 (-16px)，使显示格中心与 4 个地砖交界角精准重合
		surface_layer.position = Vector2(0.0, -16.0)
		surface_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		surface_layer.y_sort_enabled = true

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

## 放置或铲除某格草皮 (同步更新 GridData 并刷新受影响的 4 个双网格交点)
func set_surf(cell: Vector2i, exists: bool, type_name: String = "grass") -> void:
	GridData.set_surf(cell, exists, type_name)
	for d in get_affected_dual_cells(cell):
		_update_dual_cell(d.x, d.y)

## 检查指定地块是否有草皮
func has_surf(cell: Vector2i) -> bool:
	return GridData.has_surf(cell)

## 更新单个双网格交点 (u, v) 的切片贴图
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

	if mask == 0:
		surface_layer.erase_cell(Vector2i(u, v))
	else:
		surface_layer.set_cell(Vector2i(u, v), 0, MASK_TO_ATLAS[mask])

## 根据当前 GridData.surf_grid 全量重新计算并烘焙所有双网格瓦片
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

## 清空所有地表草皮
func clear_all_surf() -> void:
	GridData.clear_all_surfaces()
	if surface_layer:
		surface_layer.clear()

