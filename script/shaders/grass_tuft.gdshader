shader_type canvas_item;
render_mode blend_mix;

group_uniforms Debug_Preview;
// 调试预览模式：
// 0: 正常游戏渲染 (草皮原色与风吹摆动)
// 1: 第一层风波灰度 (Wave 1: 黑=-1, 白=+1)
// 2: 第二层风波灰度 (Wave 2: 黑=-1, 白=+1)
// 3: 混合阵风黑白波带 (Wave 1 * Wave 2: 黑=无风/反向, 白=强阵风峰值)
// 4: 混合阵风彩色热力带 (蓝=静风区, 绿=微风, 橙红=强阵风带, 最直观查看风带宽度与流向)
uniform int debug_wind_mode : hint_enum("0: 正常游戏渲染", "1: 预览第一层风波 (Wave 1)", "2: 预览第二层风波 (Wave 2)", "3: 预览混合阵风黑白波带", "4: 预览混合阵风彩色热力带") = 0;
// 调试时是否冻结草身摆动 (勾选后小草原地不动作为静止风带探测器，便于像看地图一样精确微调风带宽度)
uniform bool debug_freeze_sway = false;

group_uniforms Animation_FPS;
// 动画抽帧速率：将连续时间离散化，模拟复古像素定格质感 (支持 1/3/5/10/12/15/30 FPS 及 60 FPS 原生平滑)
uniform int animation_fps : hint_enum("1 FPS:1", "3 FPS:3", "5 FPS:5", "10 FPS:10", "12 FPS:12", "15 FPS:15", "30 FPS:30", "Smooth (60 FPS):0") = 3;
// 错峰更新开关：根据世界坐标为每颗草分配专属时间偏移，消除全图同步跳步的剧烈抽搐感
uniform bool enable_staggered_offset = true;

group_uniforms Wind_Settings;
// 是否开启风力摇摆模拟
uniform bool enable_wind = true;
// 风场主速度：控制风波在地图上行进掠过的快慢节奏 (推荐 1.0 ~ 2.5)
uniform float wind_speed : hint_range(0.0, 10.0, 0.1) = 2.0;
// 基础水平摆动幅度 (像素)：强阵风吹过时草尖的最大位移距离
uniform float wind_strength : hint_range(0.0, 10.0, 0.1) = 3.0;
// 梯形透视张缩系数：上下风向时的近大远小形变强度 (向下风顶端变宽，向上风顶端变窄)
uniform float perspective_expand : hint_range(0.0, 1.0, 0.05) = 0.35;
// 高度压缩比率：草被风吹倒下时的纵向透视变矮压扁比例
uniform float height_squash : hint_range(0.0, 1.0, 0.05) = 0.25;
// 主导风向：风在世界坐标系中的流动方向向量
uniform vec2 wind_base_dir = vec2(1.0, 0.3);
// 是否开启风向周期性偏摆 (像麦浪一样左右缓缓摇曳)
uniform bool enable_wind_wander = true;
// 最大偏转角度 (弧度，0.35 约 20 度)
uniform float wind_wander_angle : hint_range(0.0, 1.57, 0.02) = 0.35;
// 偏转摆动频率 (0.3 约 10~15 秒完成一个完整周期)
uniform float wind_wander_speed : hint_range(0.0, 3.0, 0.05) = 0.30;

group_uniforms Single_Noise_Wind;
// 单一风力噪波贴图 (可在 resources/surface/wind/wind_noise.tres 中统一自由编辑)
uniform sampler2D wind_noise : repeat_enable, filter_linear;

// 风力噪波空间尺度 (控制阵风团块大小，数值越小阵风团块越大，推荐 0.001 ~ 0.004)
uniform float wind_noise_scale : hint_range(0.0005, 0.02, 0.0005) = 0.002;
// 双向偏航开角 (弧度，约 23 度，产生相反偏航交叉流动)
uniform float noise_diverge_angle : hint_range(0.0, 1.57, 0.02) = 0.40;
// 阵风平衡阈值 (让平静时居中在 0，阵风波峰重叠时爆发强风)
uniform float wind_noise_threshold : hint_range(-0.5, 0.5, 0.02) = 0.25;

group_uniforms Creature_Interaction;
// 触碰交互的生物/玩家世界坐标
uniform vec2 creature_pos = vec2(-9999.0, -9999.0);
// 生物推挤影响半径 (像素)
uniform float creature_push_radius : hint_range(0.0, 100.0, 1.0) = 24.0;
// 生物推挤强力位移 (像素)
uniform float creature_push_strength : hint_range(0.0, 20.0, 0.5) = 5.0;

group_uniforms Ground_Color;
// 世界地表噪波贴图 (与 grass_surface.gdshader 共享，实现精准的颜色融合)
uniform sampler2D noise_tex : repeat_enable, filter_linear;
// 噪波世界采样缩放比
uniform vec2 noise_scale = vec2(0.003, 0.003);
// 噪波世界采样原点偏移
uniform vec2 noise_offset = vec2(0.0, 0.0);
// 浅绿亮色斑块阈值
uniform float threshold_bright : hint_range(0.0, 1.0, 0.005) = 0.485;
// 深绿暗色斑块阈值
uniform float threshold_dark : hint_range(0.0, 1.0, 0.005) = 0.154;
// 浅绿颜色配置 (#5d8515)
uniform vec4 color_light : source_color = vec4(0.396, 0.596, 0.078, 1.0);
// 中绿基准颜色配置 (#4e7c14)
uniform vec4 color_mid : source_color = vec4(0.322, 0.553, 0.075, 1.0);
// 深绿阴影颜色配置 (#417700)
uniform vec4 color_dark : source_color = vec4(0.263, 0.525, 0.000, 1.0);
// 草尖高光微调 (默认 0.0 严格等于地表原色，微量增加凸显立体感)
uniform float tip_brightness : hint_range(0.0, 0.3, 0.01) = 0.0;

varying vec3 tuft_color;
varying float var_wave1;
varying float var_wave2;
varying float var_gust;

// 向量旋转辅助函数 (用于双层噪波分叉流向)
vec2 rotate_vec2(vec2 v, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// 解析积分风力漂移向量 (平滑且永不随时间发散)
vec2 calc_wind_drift(vec2 base_direction, float v_speed, float time_val, float wander_ang, float wander_spd, bool use_wander) {
	vec2 fwd = normalize(base_direction);
	float forward_dist = time_val * v_speed * 0.05;
	float lateral_offset = 0.0;
	if (use_wander && wander_spd > 0.001 && wander_ang > 0.001) {
		float tan_a = tan(wander_ang);
		// 结合主谐波与次级谐波 (2.13x)，打破呆板机械单摆，模拟自然界微风的不规则摆动
		float wave1 = sin(time_val * wander_spd);
		float wave2 = sin(time_val * wander_spd * 2.13) * 0.25;
		lateral_offset = (v_speed * 0.05 * tan_a / wander_spd) * (wave1 + wave2 * 0.5);
	}
	vec2 side = vec2(-fwd.y, fwd.x);
	return fwd * forward_dist + side * lateral_offset;
}

// 彩色热力图渐变映射 (从无风深海蓝到微风青绿，再到中风明黄与强风炽红)
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

void vertex() {
	// 获取小草根部的全局世界坐标 (假设精灵锚点位于底部中心 (0, 0))
	vec2 root_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;

	// 吸附到整像素网格中心
	vec2 base_pos = floor(root_world) + vec2(0.5, 0.5);

	// 2:1 等距世界坐标校正，并采样噪波确定当前像素的草皮颜色
	vec2 iso_world = vec2(base_pos.x * 0.8, base_pos.y * 1.8);
	vec2 sample_uv = (iso_world + noise_offset) * noise_scale;
	// 顶点着色器中使用 textureLod 确保跨 GPU 驱动通用稳定性
	float n = textureLod(noise_tex, sample_uv, 0.0).r;

	// 确定小草颜色 (完全对应地表噪波三阶色块)
	vec3 c = color_mid.rgb;
	if (n >= threshold_bright) {
		c = color_light.rgb;
	} else if (n <= threshold_dark) {
		c = color_dark.rgb;
	}
	tuft_color = c;

	// 弯曲权重：草根 (UV.y = 1.0) 不变形，草尖 (UV.y = 0.0) 形变最大
	float t = pow(clamp(1.0 - UV.y, 0.0, 1.0), 1.4);

	if (enable_wind && t > 0.001) {
		// 时间离散化 (支持 5 / 10 / 12 / 15 / 30 FPS 抽帧，并按每颗草的世界坐标错开跳帧时机)
		float effective_time = TIME;
		if (animation_fps > 0) {
			float target_fps = float(animation_fps);
			float time_offset = 0.0;
			if (enable_staggered_offset) {
				// 利用草根唯一世界坐标生成 [0.0, 1.0) 的空间伪随机相位
				float phase = fract(sin(dot(root_world, vec2(12.9898, 78.233))) * 43758.5453);
				time_offset = phase / target_fps;
			}
			effective_time = floor((TIME - time_offset) * target_fps) / target_fps + time_offset;
		}

		// 单噪波反向双流交错采样 (流向 B 引入 PI 无理数速度与相位偏移)
		vec2 iso_root = vec2(root_world.x * 0.8, root_world.y * 1.8);
		vec2 dir_norm = normalize(wind_base_dir);
		vec2 dir1 = rotate_vec2(dir_norm, noise_diverge_angle);
		vec2 dir2 = rotate_vec2(dir_norm, -noise_diverge_angle);

		const float PI_VAL = 3.14159265359;
		float speed2 = wind_speed * (PI_VAL * 0.25);

		vec2 drift1 = calc_wind_drift(dir1, wind_speed, effective_time, wind_wander_angle, wind_wander_speed, enable_wind_wander);
		vec2 drift2 = calc_wind_drift(dir2, speed2, effective_time, wind_wander_angle, wind_wander_speed, enable_wind_wander);

		vec2 uv1 = (iso_root + noise_offset) * wind_noise_scale - drift1;
		vec2 uv2 = ((iso_root + noise_offset) * (wind_noise_scale * 1.18) + vec2(PI_VAL, PI_VAL * 0.5)) - drift2;

		float s1 = textureLod(wind_noise, uv1, 0.0).r;
		float s2 = textureLod(wind_noise, uv2, 0.0).r;

		float gust = s1 * s2;
		gust = clamp(gust + wind_noise_threshold, 0.0, 1.0);
		gust = (gust - 0.5) * 2.0; // 映射到 [-1.0, 1.0]

		var_wave1 = s1;
		var_wave2 = s2;
		var_gust = gust;

		if (!debug_freeze_sway || debug_wind_mode == 0) {
			// 瞬时受力方向 (与解析积分漂移的瞬时导数严格吻合)
			vec2 inst_dir = dir_norm;
			if (enable_wind_wander && wind_wander_speed > 0.001 && wind_wander_angle > 0.001) {
				vec2 side = vec2(-dir_norm.y, dir_norm.x);
				float tan_a = tan(wind_wander_angle);
				float vel_side = tan_a * (cos(effective_time * wind_wander_speed) + 0.266 * cos(effective_time * wind_wander_speed * 2.13));
				inst_dir = normalize(dir_norm + side * vel_side);
			}

			vec2 cur_wind = inst_dir * (gust * wind_strength);

			// 生物推挤叠加
			vec2 to_creature = root_world - creature_pos;
			float dist = length(to_creature);
			if (dist < creature_push_radius && dist > 0.001) {
				float push_fact = (1.0 - dist / creature_push_radius);
				vec2 push_dir = normalize(to_creature);
				cur_wind += push_dir * (push_fact * creature_push_strength);
			}

			vec2 force = cur_wind * t;

			// 现象 1：水平剪切 (平行四边形)
			VERTEX.x += force.x;

			// 现象 2：上下风 —— 近大远小梯形形变 (以精灵水平中心 UV.x = 0.5 为对称轴)
			// force.y > 0 (风向下/靠近镜头) -> 顶端向两侧扩张 (倒梯形)
			// force.y < 0 (风向上/远离镜头) -> 顶端向内收缩 (正梯形)
			VERTEX.x += (UV.x - 0.5) * (force.y * perspective_expand);

			// 现象 3：上下风 —— 透视压缩变矮 (Foreshortening)
			VERTEX.y += abs(force.y) * height_squash;

			// 现象 4：纵向位移
			VERTEX.y += force.y * 0.4;

			// 像素艺术整数吸附：锁定顶点至整像素，彻底杜绝摄像机平滑移动时的亚像素光栅化高频抖动 (Subpixel Shimmer)
			VERTEX = round(VERTEX);
		}
	}
}

void fragment() {
	// 【检查器缩略图预览窗口适配】
	// 当在 Godot 检查器材质面板顶部预览 (贴图非 4x8 小草精灵图) 时，直接在整个四边形上展开 2D 噪波与热力图，方便直观预览
	if (TEXTURE_PIXEL_SIZE.x < 0.20) {
		vec2 dir_norm = normalize(wind_base_dir);
		vec2 dir1 = rotate_vec2(dir_norm, noise_diverge_angle);
		vec2 dir2 = rotate_vec2(dir_norm, -noise_diverge_angle);

		const float PI_VAL = 3.14159265359;
		float speed2 = wind_speed * (PI_VAL * 0.25);

		vec2 drift1 = calc_wind_drift(dir1, wind_speed, TIME, wind_wander_angle, wind_wander_speed, enable_wind_wander);
		vec2 drift2 = calc_wind_drift(dir2, speed2, TIME, wind_wander_angle, wind_wander_speed, enable_wind_wander);

		vec2 p_uv1 = UV * 2.0 - drift1;
		vec2 p_uv2 = (UV * 2.0 * 1.18 + vec2(PI_VAL, PI_VAL * 0.5)) - drift2;

		float p_s1 = texture(wind_noise, p_uv1).r;
		float p_s2 = texture(wind_noise, p_uv2).r;

		float p_gust = clamp(p_s1 * p_s2 + wind_noise_threshold, 0.0, 1.0);
		p_gust = (p_gust - 0.5) * 2.0;

		vec3 p_col = tuft_color;
		if (debug_wind_mode == 1) {
			p_col = vec3(p_s1);
		} else if (debug_wind_mode == 2) {
			p_col = vec3(p_s2);
		} else if (debug_wind_mode == 3) {
			p_col = vec3(p_gust * 0.5 + 0.5);
		} else if (debug_wind_mode == 4) {
			p_col = heat_map(p_gust * 0.5 + 0.5);
		}
		COLOR = vec4(p_col, 1.0);
	} else {
		// 【正常游戏场景渲染】针对 4x8 像素真实小草精灵：
		vec4 mask = texture(TEXTURE, UV);
		if (mask.a < 0.1) {
			discard;
		}
		vec3 final_color = tuft_color;

		if (debug_wind_mode == 1) {
			// 预览第一层风噪波灰度 (直接显示与草皮色斑同源的有机团块噪波)
			final_color = vec3(var_wave1);
		} else if (debug_wind_mode == 2) {
			// 预览第二层风噪波灰度 (显示第二层斜向漂移的有机团块噪波)
			final_color = vec3(var_wave2);
		} else if (debug_wind_mode == 3) {
			// 预览混合阵风黑白波块 (Wave 1 * Wave 2: 独立阵风气流团)
			final_color = vec3(var_gust * 0.5 + 0.5);
		} else if (debug_wind_mode == 4) {
			// 预览混合阵风彩色热力带 (蓝=静风区, 绿/黄=微风, 橙红=强阵风团块)
			final_color = heat_map(var_gust * 0.5 + 0.5);
		} else {
			if (tip_brightness > 0.0) {
				final_color += vec3(tip_brightness * (1.0 - UV.y));
			}
		}

		// 遮罩纯白部分上色为对应颜色
		COLOR = vec4(final_color, mask.a * COLOR.a);
	}
}
