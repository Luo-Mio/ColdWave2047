shader_type canvas_item;

// 全局角色世界坐标 (由 main_scene.gd 动态更新)
global uniform vec2 player_world_pos;

// 截面基础颜色 (默认为纯黑，可在检查器微调)
uniform vec4 cap_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// GPU 椭圆淡出参数 (适配 2:1 等距视角水平长半轴与垂直短半轴)
uniform float rx : hint_range(4.0, 400.0) = 80.0;
uniform float ry : hint_range(4.0, 400.0) = 48.0;
uniform float feather : hint_range(0.01, 1.0) = 0.5;
uniform float max_alpha : hint_range(0.0, 1.0) = 1.0;

// 是否启用复古点阵像素抖动 (默认 false 为平滑 alpha 渐变，true 为 Bayer 4x4 点阵)
uniform bool enable_dither = false;

// 4x4 经典 Bayer 像素抖动矩阵
const mat4 bayer4 = mat4(
    vec4( 0.0/16.0, 12.0/16.0,  3.0/16.0, 15.0/16.0),
    vec4( 8.0/16.0,  4.0/16.0, 11.0/16.0,  7.0/16.0),
    vec4( 2.0/16.0, 14.0/16.0,  1.0/16.0, 13.0/16.0),
    vec4(10.0/16.0,  6.0/16.0,  9.0/16.0,  5.0/16.0)
);

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 diff = world_pos - player_world_pos;
	float dist = (diff.x * diff.x) / (rx * rx) + (diff.y * diff.y) / (ry * ry);

	// GPU 硬件级椭圆平滑淡出：
	// 距离中心越近，遮罩越明显；靠近边缘平滑渐隐至 0
	float alpha = smoothstep(1.0, 1.0 - feather, dist) * max_alpha;

	if (alpha <= 0.001) {
		discard;
	}

	if (enable_dither) {
		int px = int(FRAGCOORD.x) % 4;
		int py = int(FRAGCOORD.y) % 4;
		float dither_threshold = bayer4[px][py];
		if (alpha < dither_threshold) {
			discard;
		}
		COLOR = vec4(cap_color.rgb, cap_color.a);
	} else {
		COLOR = vec4(cap_color.rgb, cap_color.a * alpha);
	}
}

