# hotbar.gd —— 底部物品栏控制器
extends CanvasLayer

enum ItemType { TILE, OBJECT, WEAPON }

var items: Array[Dictionary] = [
	# 1 号位：木棍法杖（武器）
	{ "type": ItemType.WEAPON, "name": "木棍法杖", "icon": "res://resources/object/weapon/stick/stick.png", "weapon_tex": "res://resources/object/weapon/stick/stick.png" },
	# 2 号位：泥土砖（地砖）
	{ "type": ItemType.TILE,   "name": "新泥土砖", "atlas": Vector2i(0, 0) },
	# 3 号位：小麦（农作物 1x1 微格）
	{ "type": ItemType.OBJECT, "name": "小麦",     "scene": "res://scene/object/wheat.tscn", "icon": "res://resources/Plant/wheat/wheat.png", "grid_size": Vector2i(1, 1) },
	# 4 号位：秋季大树（物体 4x4 整格）
	{ "type": ItemType.OBJECT, "name": "秋季树",   "scene": "res://scene/object/tree.tscn", "icon": "res://resources/tree/AutumnTree/AutumnTree.png", "grid_size": Vector2i(4, 4) },
]

# 当前选中的槽位索引（0 ~ 4）
var active_index: int = 0

# 节点引用
@onready var slots_container: HBoxContainer = $MarginContainer/SlotsContainer

# 样式：普通未选中样式 与 选中高亮样式
var normal_style: StyleBoxFlat
var selected_style: StyleBoxFlat

func _ready() -> void:
	# 等一帧，确保全局数据和图集已加载完毕
	await get_tree().process_frame
	_init_styles()
	_load_slot_icons()
	_update_selection()

# 初始化未选中与选中时的边框样式
func _init_styles() -> void:
	var first_slot := slots_container.get_child(0) as PanelContainer
	if first_slot and first_slot.has_theme_stylebox_override("panel"):
		# 复制你在编辑器里调好的样式作为默认样式
		normal_style = first_slot.get_theme_stylebox("panel").duplicate()
	else:
		normal_style = StyleBoxFlat.new()
		normal_style.bg_color = Color(0.1, 0.1, 0.1, 0.7)
		normal_style.set_border_width_all(2)
		normal_style.border_color = Color(0.5, 0.5, 0.5)
		normal_style.set_corner_radius_all(3)

	# 创建一个高亮样式（亮黄色/金色外边框，边框加粗）
	selected_style = normal_style.duplicate()
	selected_style.border_color = Color(1.0, 0.85, 0.2, 1.0) # 金黄色
	selected_style.set_border_width_all(3)                     # 加粗为 3px

# 读取贴图并填入各个槽位
func _load_slot_icons() -> void:
	var tile_source: TileSetAtlasSource = null
	if not GridData.layers.is_empty():
		var ts: TileSet = GridData.layers[0].tile_set
		tile_source = ts.get_source(0) as TileSetAtlasSource

	for i in items.size():
		if i >= slots_container.get_child_count():
			break
		var slot := slots_container.get_child(i)
		var icon_rect := slot.get_node_or_null("TextureRect") as TextureRect
		if icon_rect == null:
			continue

		var item_data := items[i]
		if item_data["type"] == ItemType.TILE:
			# 瓷砖：从 TileSet 图集中裁剪出该格子的贴图
			if tile_source:
				var atlas_tex := AtlasTexture.new()
				atlas_tex.atlas = tile_source.texture
				atlas_tex.region = tile_source.get_tile_texture_region(item_data["atlas"])
				icon_rect.texture = atlas_tex
		elif item_data["type"] == ItemType.OBJECT or item_data["type"] == ItemType.WEAPON:
			# 物体与武器：直接加载指定的图标贴图
			if item_data.has("icon"):
				icon_rect.texture = load(item_data["icon"])

# 监听按键 1~5 和鼠标滚轮
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			_select_slot(0)
		elif event.keycode == KEY_2:
			_select_slot(1)
		elif event.keycode == KEY_3:
			_select_slot(2)
		elif event.keycode == KEY_4:
			_select_slot(3)
		elif event.keycode == KEY_5:
			_select_slot(4)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select_slot((active_index - 1 + items.size()) % items.size())
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select_slot((active_index + 1) % items.size())

# 切换槽位
func _select_slot(index: int) -> void:
	if index < 0 or index >= items.size() or index == active_index:
		return
	active_index = index
	_update_selection()

# 刷新各个槽位的边框外观（选中的槽位变成金色高亮框）
func _update_selection() -> void:
	for i in slots_container.get_child_count():
		var slot := slots_container.get_child(i) as PanelContainer
		if slot:
			if i == active_index:
				slot.add_theme_stylebox_override("panel", selected_style)
			else:
				slot.add_theme_stylebox_override("panel", normal_style)

# 供外部（主场景）获取当前选中的物品数据
func get_active_item() -> Dictionary:
	if active_index >= 0 and active_index < items.size():
		return items[active_index]
	return {}
