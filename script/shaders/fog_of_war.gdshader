shader_type canvas_item;

// 战争迷雾全屏遮罩 Shader
// fog_mask: 当前活跃视锥 SubViewport 渲染图 (R=1 代表视野内)
// history_mask: 历史探索足迹 ImageTexture (R=1 代表已探索)
uniform sampler2D fog_mask : filter_linear, repeat_disable;
uniform sampler2D history_mask : filter_linear, repeat_disable;

uniform vec2 cam_world_pos;
uniform vec2 mask_cam_pos;
uniform vec2 cam_zoom = vec2(1.0, 1.0);
uniform vec2 screen_size = vec2(1152.0, 648.0);
uniform vec2 map_bounds = vec2(4096.0, 4096.0);

// 历史探索区域的半黑遮罩透明度 (0.0=全亮, 0.65=半黑留底, 1.0=纯黑)
uniform float explored_alpha : hint_range(0.0, 1.0) = 0.65;
// 未探索区域的浓雾透明度 (1.0 = 纯黑)
uniform float unexplored_alpha : hint_range(0.0, 1.0) = 1.0;
// 迷雾主色调 (默认深黑)
uniform vec4 fog_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	// 1. 摄像机微小位移平滑补偿采样活跃视野 (实现 30FPS 逻辑运算下的 120FPS 丝滑移动)
	vec2 cam_diff = (cam_world_pos - mask_cam_pos) * cam_zoom;
	vec2 mask_uv = clamp(SCREEN_UV + cam_diff / screen_size, vec2(0.0), vec2(1.0));
	vec4 curr = texture(fog_mask, mask_uv);
	float current_vis = curr.r;

	// 2. 根据 SCREEN_UV 换算当前屏幕像素在世界坐标系中的位置
	vec2 screen_pixel = (SCREEN_UV - 0.5) * screen_size;
	vec2 world_pos = cam_world_pos + screen_pixel / cam_zoom;

	// 3. 将世界坐标映射到历史地图 UV [0.0, 1.0]
	vec2 hist_uv = (world_pos + map_bounds * 0.5) / map_bounds;
	float explored = 0.0;
	if (hist_uv.x >= 0.0 && hist_uv.x <= 1.0 && hist_uv.y >= 0.0 && hist_uv.y <= 1.0) {
		explored = texture(history_mask, hist_uv).r;
	}

	// 4. 三态计算：当前视野全亮 -> 历史探索半黑 -> 未知浓雾纯黑
	float darkness = unexplored_alpha;
	if (current_vis > 0.05) {
		// 当前视野内：平滑过渡为 0 遮罩 (100% 全亮)
		darkness = mix(explored_alpha, 0.0, clamp(current_vis, 0.0, 1.0));
	} else if (explored > 0.05) {
		// 历史探索记忆区：半黑留底
		darkness = mix(unexplored_alpha, explored_alpha, clamp(explored, 0.0, 1.0));
	}

	COLOR = vec4(fog_color.rgb, darkness);
}
