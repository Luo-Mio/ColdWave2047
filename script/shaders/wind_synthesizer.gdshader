shader_type canvas_item;

group_uniforms Display;
// 0: 合成阵风黑白 (N1 * N2)
// 1: 合成阵风彩色热力图
// 2: 独立展示噪声 1 (流动预览)
// 3: 独立展示噪声 2 (流动预览)
uniform int display_mode : hint_enum("0: 合成阵风黑白 (N1 * N2)", "1: 合成阵风彩色热力图", "2: 独立展示噪声 1 (流向 A)", "3: 独立展示噪声 2 (流向 B)") = 0;

group_uniforms Noise_Textures;
uniform sampler2D noise_1 : repeat_enable, filter_linear;
uniform sampler2D noise_2 : repeat_enable, filter_linear;

group_uniforms Wind_Parameters;
uniform float wind_speed : hint_range(0.0, 10.0, 0.1) = 2.0;
uniform vec2 wind_base_dir = vec2(1.0, 0.3);
uniform float noise_diverge_angle : hint_range(0.0, 1.57, 0.02) = 0.40;
uniform float wind_noise_scale : hint_range(0.1, 5.0, 0.1) = 1.0;
uniform float wind_noise_threshold : hint_range(-0.5, 0.5, 0.02) = 0.25;

// 向量旋转辅助函数 (用于双层噪波分叉流向)
vec2 rotate_vec2(vec2 v, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// 彩色气象热力图映射
vec3 heat_map(float v) {
	vec3 c1 = vec3(0.05, 0.10, 0.35); // 静风无力 (深海蓝)
	vec3 c2 = vec3(0.10, 0.75, 0.85); // 微风拂动 (青蓝)
	vec3 c3 = vec3(0.90, 0.85, 0.15); // 中度风力 (明黄)
	vec3 c4 = vec3(1.00, 0.20, 0.05); // 强阵风峰值 (炽红)
	if (v < 0.33) {
		return mix(c1, c2, v / 0.33);
	} else if (v < 0.66) {
		return mix(c2, c3, (v - 0.33) / 0.33);
	} else {
		return mix(c3, c4, (v - 0.66) / 0.34);
	}
}

void fragment() {
	vec2 dir_norm = normalize(wind_base_dir);
	vec2 dir1 = rotate_vec2(dir_norm, noise_diverge_angle);
	vec2 dir2 = rotate_vec2(dir_norm, -noise_diverge_angle);

	vec2 drift1 = dir1 * (TIME * wind_speed * 0.1);
	vec2 drift2 = dir2 * (TIME * (wind_speed * 0.89) * 0.1);

	vec2 uv1 = UV * wind_noise_scale - drift1;
	vec2 uv2 = (UV * wind_noise_scale * 0.85) - drift2;

	float s1 = texture(noise_1, uv1).r;
	float s2 = texture(noise_2, uv2).r;

	float gust = s1 * s2;
	gust = clamp(gust + wind_noise_threshold, 0.0, 1.0);
	gust = (gust - 0.5) * 2.0;

	vec3 col = vec3(0.0);
	if (display_mode == 0) {
		col = vec3(gust * 0.5 + 0.5);
	} else if (display_mode == 1) {
		col = heat_map(gust * 0.5 + 0.5);
	} else if (display_mode == 2) {
		col = vec3(s1);
	} else if (display_mode == 3) {
		col = vec3(s2);
	}

	COLOR = vec4(col, 1.0);
}

