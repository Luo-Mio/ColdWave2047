extends SceneTree

func _initialize() -> void:
	var main_scene_path: String = ProjectSettings.get_setting("application/run/main_scene")
	print("[性能诊断] 正在加载主场景: ", main_scene_path)
	
	var scene: PackedScene = load(main_scene_path)
	if scene == null:
		print("[错误] 无法加载主场景: ", main_scene_path)
		quit(1)
		return
	
	var inst: Node = scene.instantiate()
	root.add_child(inst)
	
	# 等待 15 帧热身让所有系统就绪
	for i in range(15):
		await process_frame
	
	print("[性能诊断] 开始采集 60 帧的性能监控数据...")
	
	var samples_process_ms: Array[float] = []
	var samples_physics_ms: Array[float] = []
	var samples_fps: Array[float] = []
	var samples_draw_calls: Array[int] = []
	var samples_nodes: Array[int] = []
	
	for i in range(60):
		await process_frame
		samples_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		samples_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		samples_fps.append(Performance.get_monitor(Performance.TIME_FPS))
		samples_draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		samples_nodes.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	
	# 计算平均值
	var avg_process := _avg(samples_process_ms)
	var max_process := _max(samples_process_ms)
	var avg_physics := _avg(samples_physics_ms)
	var max_physics := _max(samples_physics_ms)
	var avg_fps := _avg(samples_fps)
	var min_fps := _min(samples_fps)
	var avg_draw_calls := _avg_int(samples_draw_calls)
	var avg_nodes := _avg_int(samples_nodes)
	
	# 检查 sortworld 节点数量
	var sort_world: Node = inst.find_child("sortworld", true, false)
	var sort_world_children := sort_world.get_child_count() if sort_world else 0
	
	# 检查 layers 下的格子数
	var total_layer_cells := 0
	var layers_node: Node = inst.find_child("layers", true, false)
	if layers_node:
		for child in layers_node.get_children():
			if child is TileMapLayer:
				total_layer_cells += child.get_used_cells().size()
	
	var report := """
==================================================
           🎮 GODOT 性能诊断分析报告
==================================================
【帧率与时间开销】
  - 平均 FPS: %.1f (最低 FPS: %.1f)
  - 主线程 CPU 帧循环时间 (Process Time):
      * 平均: %.2f ms / 帧
      * 峰值: %.2f ms / 帧
  - 物理线程 CPU 帧时间 (Physics Time):
      * 平均: %.2f ms / 帧
      * 峰值: %.2f ms / 帧
  - 120 FPS 预算上限: 8.33 ms / 帧
  - 60 FPS 预算上限:  16.67 ms / 帧

【场景节点与渲染开销】
  - 活动节点总数 (Object Node Count): %d 个
  - sortworld (景深排序容器) 下的子节点数: %d 个
  - 原始地貌 Tile 瓦片总数: %d 个
  - 单帧渲染 Draw Calls: %d 次

【瓶颈诊断结论】
%s
==================================================
"""
	
	var diagnosis := ""
	if sort_world_children > 200:
		diagnosis += "  [严重瓶颈 1] sortworld 容器内挂载了高达 %d 个独立子节点！\n" % sort_world_children
		diagnosis += "    原因: _split_layers_into_rows 将每一块高层瓦片都拆成了一个独立的 TileMapLayer 节点。\n"
		diagnosis += "    影响: 破坏了 2D 渲染批处理 (Batching)，导致每次生物移动时的 insert_sort 遍历开销巨大。\n"
	
	if avg_process > 12.0 or max_process > 16.0:
		diagnosis += "  [严重瓶颈 2] 主线程 Process 耗时过高 (平均 %.2f ms, 峰值 %.2f ms)！\n" % [avg_process, max_process]
		diagnosis += "    原因: 大量组件在 _process 中执行全局参数广播、视口重绘、高墙遮挡判定。\n"
		
	if avg_physics > 10.0 or max_physics > 16.0:
		diagnosis += "  [严重瓶颈 3] 物理线程 Physics 耗时过高 (平均 %.2f ms, 峰值 %.2f ms)！\n" % [avg_physics, max_physics]
		diagnosis += "    原因: 各实体 IsoDepthComponent 每物理帧都查询 GridData 楼层并触发排序。\n"
		
	if diagnosis == "":
		diagnosis = "  未检测到极端瓶颈，当前测试场景在基准测试下运行平稳。\n"
		
	var final_text = report % [
		avg_fps, min_fps,
		avg_process, max_process,
		avg_physics, max_physics,
		avg_nodes, sort_world_children, total_layer_cells, avg_draw_calls,
		diagnosis
	]
	
	print(final_text)
	
	var f := FileAccess.open("res://scratch/perf_report.txt", FileAccess.WRITE)
	if f:
		f.store_string(final_text)
		f.close()
		
	inst.queue_free()
	quit()

func _avg(arr: Array[float]) -> float:
	if arr.is_empty(): return 0.0
	var s := 0.0
	for v in arr: s += v
	return s / arr.size()

func _max(arr: Array[float]) -> float:
	if arr.is_empty(): return 0.0
	var m := arr[0]
	for v in arr: if v > m: m = v
	return m

func _min(arr: Array[float]) -> float:
	if arr.is_empty(): return 0.0
	var m := arr[0]
	for v in arr: if v < m: m = v
	return m

func _avg_int(arr: Array[int]) -> int:
	if arr.is_empty(): return 0
	var s := 0
	for v in arr: s += v
	return s / arr.size()

