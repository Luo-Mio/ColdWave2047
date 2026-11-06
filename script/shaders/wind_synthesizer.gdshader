shader_type canvas_item;

group_uniforms Display;
// 0: 合成阵风黑白 (A * B)
// 1: 合成阵风彩色热力图
// 2: 噪波流向 A (偏航向右 +angle)
// 3: 噪波流向 B (偏航向左 -angle + PI 无理数偏移)
// 4: 基础噪波原图 (静态展示)
uniform int display_mode : hint_enum("0: 合成阵风黑白 (A * B)", "1: 合成阵风彩色热力图", "2: 噪波流向 A (偏向角 +angle)", "3: 噪波流向 B (反向偏航 + PI 偏移)", "4: 基础噪波原图 (静态)") = 0;

group_uniforms Single_Noise_Source;
uniform sampler2D wind_noise : repeat_enable, filter_linear;

group_uniforms Wind_Parameters;
uniform float wind_speed : hint_range(0.0, 10.0, 0.1) = 2.0;
uniform vec2 wind_base_dir = vec2(0.0, -1.0);
uniform float noise_diverge_angle : hint_range(0.0, 1.57, 0.02) = 0.40;
uniform float wind_noise_scale : hint_range(0.1, 5.0, 0.1) = 1.0;
uniform float wind_noise_threshold : hint_range(-0.5, 0.5, 0.02) = 0.25;

group_uniforms Wind_Wander;
uniform bool enable_wind_wander = true;
uniform float wind_wander_angle : hint_range(0.0, 1.57, 0.02) = 0.35; // 最大偏摆角度 (弧度，约 20°)
uniform float wind_wander_speed : hint_range(0.0, 3.0, 0.05) = 0.30; // 偏摆频率速度 (0.3 约 10~15 秒摆动一轮)

// 向量旋转辅助函数 (用于双层噪波分叉流向)
vec2 rotate_vec2(vec2 v, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// 解析积分风力漂移向量 (平滑且永不随时间发散)
vec2 calc_wind_drift(vec2 base_direction, float v_speed, float time_val, float wander_ang, float wander_spd, bool use_wander) {
	vec2 fwd = normalize(base_direction);
	float forward_dist = time_val * v_speed * 0.1;
	float lateral_offset = 0.0;
	if (use_wander && wander_spd > 0.001 && wander_ang > 0.001) {
		float tan_a = tan(wander_ang);
		// 结合主谐波与次级谐波 (2.13x)，打破呆板机械单摆，模拟自然界微风的不规则摆动
		float wave1 = sin(time_val * wander_spd);
		float wave2 = sin(time_val * wander_spd * 2.13) * 0.25;
		lateral_offset = (v_speed * 0.1 * tan_a / wander_spd) * (wave1 + wave2 * 0.5);
	}
	vec2 side = vec2(-fwd.y, fwd.x);
	return fwd * forward_dist + side * lateral_offset;
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

	const float PI_VAL = 3.14159265359;

	// 流向 A：沿 +diverge_angle 前进
	vec2 drift1 = calc_wind_drift(dir1, wind_speed, TIME, wind_wander_angle, wind_wander_speed, enable_wind_wander);
	vec2 uv1 = UV * wind_noise_scale - drift1;

	// 流向 B：相反偏航 (-diverge_angle)，并叠加无理数偏移消解周期重复：
	// 1. 无理数速度比例：PI * 0.25 ≈ 0.785398，两路速度之比为无理数，时间上永远不会出现重复相位
	// 2. 空间无理数相位偏移：vec2(PI, PI * 0.5)，采样同张图的不同区域，消除局部重叠对称
	// 3. 采样尺度微调：1.18 倍
	float speed2 = wind_speed * (PI_VAL * 0.25);
	vec2 drift2 = calc_wind_drift(dir2, speed2, TIME, wind_wander_angle, wind_wander_speed, enable_wind_wander);
	vec2 uv2 = (UV * wind_noise_scale * 1.18 + vec2(PI_VAL, PI_VAL * 0.5)) - drift2;

	float s1 = texture(wind_noise, uv1).r;
	float s2 = texture(wind_noise, uv2).r;

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
	} else if (display_mode == 4) {
		// 静态展示基础噪波原图
		col = vec3(texture(wind_noise, UV * wind_noise_scale).r);
	}

	COLOR = vec4(col, 1.0);
}

