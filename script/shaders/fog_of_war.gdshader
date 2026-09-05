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

// 纯黑点阵抖动配置 (掺杂纯黑像素、边缘少、中心深的像素艺术模式)
uniform bool enable_dither_fog = true;
uniform int dither_scale : hint_range(1, 4) = 1; // 点阵像素缩放 (1=精细屏幕像素, 2=2x2复古像素)
uniform float edge_softness : hint_range(4.0, 80.0) = 28.0; // 边缘到中心渐变过渡宽度 (像素)

// 8x8 经典 Bayer 像素抖动矩阵 (64 级精细灰阶，比 4x4 细腻 4 倍，浓度渐变过渡极度柔和丝滑)
const float bayer8[64] = float[64](
    0.000000, 0.500000, 0.125000, 0.625000, 0.031250, 0.531250, 0.156250, 0.656250,
    0.750000, 0.250000, 0.875000, 0.375000, 0.781250, 0.281250, 0.906250, 0.406250,
    0.187500, 0.687500, 0.062500, 0.562500, 0.218750, 0.718750, 0.093750, 0.593750,
    0.937500, 0.437500, 0.812500, 0.312500, 0.968750, 0.468750, 0.843750, 0.343750,
    0.046875, 0.546875, 0.171875, 0.671875, 0.015625, 0.515625, 0.140625, 0.640625,
    0.796875, 0.296875, 0.921875, 0.421875, 0.765625, 0.265625, 0.890625, 0.390625,
    0.234375, 0.734375, 0.109375, 0.609375, 0.203125, 0.703125, 0.078125, 0.578125,
    0.984375, 0.484375, 0.859375, 0.359375, 0.953125, 0.453125, 0.828125, 0.328125
);

// 13-tap 径向加权平滑采样核 (中心点 + 内圈4点 + 外圈8点)
const vec2 SAMPLE_OFFSETS[13] = {
    vec2(0.0, 0.0),
    // 内圈 (0.5 半径)
    vec2(0.5, 0.0), vec2(-0.5, 0.0), vec2(0.0, 0.5), vec2(0.0, -0.5),
    // 外圈 (1.0 半径)
    vec2(0.707, 0.707), vec2(-0.707, 0.707), vec2(0.707, -0.707), vec2(-0.707, -0.707),
    vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0)
};

const float SAMPLE_WEIGHTS[13] = {
    0.20,
    0.10, 0.10, 0.10, 0.10,
    0.05, 0.05, 0.05, 0.05,
    0.05, 0.05, 0.05, 0.05
};

void fragment() {
	// 1. 摄像机微小位移平滑补偿采样活跃视野 (实现 30FPS 逻辑运算下的 120FPS 丝滑移动)
	vec2 cam_diff = (cam_world_pos - mask_cam_pos) * cam_zoom;
	vec2 base_mask_uv = clamp(SCREEN_UV + cam_diff / screen_size, vec2(0.0), vec2(1.0));

	float current_vis = 0.0;
	if (enable_dither_fog && edge_softness > 1.0) {
		// 多重采样边缘平滑，产生“边缘少、中心深”的平滑灰阶过渡
		vec2 step_uv = (edge_softness / screen_size) * cam_zoom;
		for (int i = 0; i < 13; i++) {
			vec2 tap_uv = clamp(base_mask_uv + SAMPLE_OFFSETS[i] * step_uv, vec2(0.0), vec2(1.0));
			current_vis += texture(fog_mask, tap_uv).r * SAMPLE_WEIGHTS[i];
		}
	} else {
		current_vis = texture(fog_mask, base_mask_uv).r;
	}

	// 2. 根据 SCREEN_UV 换算当前屏幕像素在世界坐标系中的位置
	vec2 screen_pixel = (SCREEN_UV - 0.5) * screen_size;
	vec2 world_pos = cam_world_pos + screen_pixel / cam_zoom;

	// 3. 将世界坐标映射到历史地图 UV [0.0, 1.0]
	vec2 hist_uv = (world_pos + map_bounds * 0.5) / map_bounds;
	float explored = 0.0;
	if (hist_uv.x >= 0.0 && hist_uv.x <= 1.0 && hist_uv.y >= 0.0 && hist_uv.y <= 1.0) {
		explored = texture(history_mask, hist_uv).r;
	}

	// 4. 三态深度计算：当前视野全亮(0.0) -> 历史探索半黑 -> 未知浓雾纯黑(1.0)
	float darkness = unexplored_alpha;
	if (current_vis > 0.0001) {
		// S 型平滑缓动曲线让浓度过渡极度柔和自然
		float vis_factor = smoothstep(0.0, 1.0, clamp(current_vis, 0.0, 1.0));
		darkness = mix(explored_alpha, 0.0, vis_factor);
	} else if (explored > 0.05) {
		// 历史探索记忆区：半黑留底
		darkness = mix(unexplored_alpha, explored_alpha, clamp(explored, 0.0, 1.0));
	}

	// 5. 像素呈现：纯黑 8x8 精细点阵抖动或传统 Alpha 半透明
	if (enable_dither_fog) {
		int px = (int(FRAGCOORD.x) / dither_scale) % 8;
		if (px < 0) px += 8;
		int py = (int(FRAGCOORD.y) / dither_scale) % 8;
		if (py < 0) py += 8;
		float threshold = bayer8[py * 8 + px];

		if (darkness > threshold) {
			// 纯黑像素！
			COLOR = vec4(fog_color.rgb, 1.0);
		} else {
			// 镂空，露出底层世界原色！
			discard;
		}
	} else {
		COLOR = vec4(fog_color.rgb, darkness);
	}
}
