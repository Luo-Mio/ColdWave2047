# object_destructible_component.gd —— 物体可破坏、连带瓦解与掉落物产出组件
class_name ObjectDestructibleComponent
extends Node

@export_group("破坏与掉落物配置")
## 是否随下层地基被挖除而连带瓦解 (小麦/花草 = true，大树/巨石等坚固结构 = false)
@export var break_with_tile: bool = true
## 自身被破坏/采摘时掉落的物品 ID (如 "wood", "wheat"，为空代表无掉落)
@export var drop_item_id: String = ""
## 每次破坏产出的掉落物数量
@export var drop_count: int = 1
