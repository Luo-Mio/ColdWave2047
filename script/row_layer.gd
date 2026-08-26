# row_layer.gd —— 行级地形层脚本
extends TileMapLayer

# 排序主键:该行格子的基底屏幕 y(由 GridData.cell_to_sort_key 算)
var sort_key: float = 0.0

# 排序次键:楼层号(同格叠砖时低层先画、高层后画)
var layer_no: int = 0