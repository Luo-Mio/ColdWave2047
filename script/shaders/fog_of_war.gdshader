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

// 4x4 经典 Bayer 像素抖动矩阵
const mat4 bayer = mat4(
    vec4( 0.0/16.0, 12.0/16.0,  3.0/16.0, 15.0/16.0),
    vec4( 8.0/16.0,  4.0/16.0, 11.0/16.0,  7.0/16.0),
    vec4( 2.0/16.0, 14.0/16.0,  1.0/16.0, 13.0/16.0),
    vec4(10.0/16.0,  6.0/16.0,  9.0/16.0,  5.0/16.0)
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
	if (current_vis > 0.001) {
		// 当前视野内与阴影过渡边缘：平滑过渡为 0 遮罩
		darkness = mix(explored_alpha, 0.0, clamp(current_vis, 0.0, 1.0));
	} else if (explored > 0.05) {
		// 历史探索记忆区：半黑留底
		darkness = mix(unexplored_alpha, explored_alpha, clamp(explored, 0.0, 1.0));
	}

	// 5. 像素呈现：纯黑点阵抖动或传统 Alpha 半透明
	if (enable_dither_fog) {
		int px = (int(FRAGCOORD.x) / dither_scale) % 4;
		int py = (int(FRAGCOORD.y) / dither_scale) % 4;
		float threshold = bayer[px][py];

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
