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
// 横风旋转倾倒强度：横风吹拂时草身绕底部中心基点旋转倾斜的最大强度 (0.0 为纯剪切，1.0 强横风时草尖旋转达 45 度)
uniform float wind_rotation_strength : hint_range(0.0, 1.5, 0.05) = 0.8;
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

group_uniforms Dynamic_Interaction_Map;
// 是否启用多生物动态交互图 (方案 B)
uniform bool enable_interaction_map = true;
// 动态交互图纹理 (由 FoliageInteractionManager 提供)
uniform sampler2D interaction_tex : filter_linear, repeat_disable;
// 动态交互图在世界空间的范围矩形 (xy = 左上角, zw = 宽高)
uniform vec4 interaction_bounds = vec4(0.0, 0.0, 1.0, 1.0);

group_uniforms Creature_Interaction;
// 触碰交互的生物/玩家世界坐标 (当未开启交互图时的后备单点参数)
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
// 随机杂色比例：让部分杂草从噪波三阶颜色池 (浅绿/中绿/深绿) 中随机挑选，增强点缀层次感 (0.2 代表 20%)
uniform float random_color_ratio : hint_range(0.0, 1.0, 0.01) = 0.20;

varying vec3 tuft_color;
varying float var_wave1;
varying float var_wave2;
varying float var_gust;
varying vec2 local_pos;
varying float var_rot_deg;
varying float var_shear;
varying float var_h_scale;
varying float var_w_scale;

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

	// 通过四舍五入吸附到绝对整像素，彻底消除摄像机平滑移动与亚像素光栅化带来的微弱浮点漂移 (±0.17px 抖动)
	vec2 static_root = round(root_world);

	// 采样点严格对应草根脚下的整像素中心 (+0.5, +0.5)
	vec2 base_pos = static_root + vec2(0.5, 0.5);

	// 2:1 等距世界坐标校正，并采样噪波确定当前像素的草皮颜色
	vec2 iso_world = vec2(base_pos.x * 0.8, base_pos.y * 1.8);
	vec2 sample_uv = (iso_world + noise_offset) * noise_scale;
	// 顶点着色器中使用 textureLod 确保跨 GPU 驱动通用稳定性
	float n = textureLod(noise_tex, sample_uv, 0.0).r;

	// 确定小草基础颜色 (完全对应地表噪波三阶色块)
	vec3 c = color_mid.rgb;
	if (n >= threshold_bright) {
		c = color_light.rgb;
	} else if (n <= threshold_dark) {
		c = color_dark.rgb;
	}

	// 局部杂草随机色：允许指定比例的杂草从噪波颜色池 (浅绿/中绿/深绿) 中随机挑选
	if (random_color_ratio > 0.001) {
		vec2 rnd = fract(sin(vec2(
			dot(static_root, vec2(127.1, 311.7)),
			dot(static_root, vec2(269.5, 183.3))
		)) * 43758.5453);

		if (rnd.x < random_color_ratio) {
			if (rnd.y < 0.3333) {
				c = color_light.rgb;
			} else if (rnd.y < 0.6667) {
				c = color_mid.rgb;
			} else {
				c = color_dark.rgb;
			}
		}
	}
	tuft_color = c;

	float rot_deg = 0.0;
	float shear = 0.0;
	float h_scale = 1.0;
	float w_scale = 1.0;

	if (enable_wind) {
		// 时间离散化 (支持 5 / 10 / 12 / 15 / 30 FPS 抽帧，并按每颗草的世界坐标错开跳帧时机)
		float effective_time = TIME;
		if (animation_fps > 0) {
			float target_fps = float(animation_fps);
			float time_offset = 0.0;
			if (enable_staggered_offset) {
				// 利用草根唯一绝对世界坐标生成 [0.0, 1.0) 的空间伪随机相位 (使用 static_root 保证运动时相位永不跳跃)
				float phase = fract(sin(dot(static_root, vec2(12.9898, 78.233))) * 43758.5453);
				time_offset = phase / target_fps;
			}
			effective_time = floor((TIME - time_offset) * target_fps) / target_fps + time_offset;
		}

		// 单噪波反向双流交错采样 (流向 B 引入 PI 无理数速度与相位偏移，基于 static_root 锁定稳定风场)
		vec2 iso_root = vec2(static_root.x * 0.8, static_root.y * 1.8);
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

			// 生物推挤叠加 (使用 static_root 保证推挤受力稳定无颤动)
			if (enable_interaction_map) {
				vec2 inter_uv = (static_root - interaction_bounds.xy) / interaction_bounds.zw;
				if (inter_uv.x >= 0.0 && inter_uv.x <= 1.0 && inter_uv.y >= 0.0 && inter_uv.y <= 1.0) {
					vec4 inter_data = textureLod(interaction_tex, inter_uv, 0.0);
					if (inter_data.b > 0.01) {
						vec2 push_dir = (inter_data.rg - vec2(0.5)) * 2.0;
						float push_fact = inter_data.b;
						cur_wind += push_dir * (push_fact * creature_push_strength);
					}
				}
			} else {
				// 后备单点推挤 (2:1 等距椭圆透视校正)
				vec2 to_creature = static_root - creature_pos;
				float iso_dist = length(vec2(to_creature.x, to_creature.y * 2.0));
				if (iso_dist < creature_push_radius && iso_dist > 0.001) {
					float push_fact = smoothstep(creature_push_radius, 0.0, iso_dist);
					vec2 push_dir = normalize(vec2(to_creature.x, to_creature.y * 2.0));
					cur_wind += push_dir * (push_fact * creature_push_strength);
				}
			}

			// 计算实例级形变参数 (与实验工具 weed_distortion_lab 100% 对齐)
			rot_deg = clamp(cur_wind.x * 6.0 * wind_rotation_strength, -45.0, 45.0);
			shear = cur_wind.x * (1.0 - clamp(wind_rotation_strength * 0.4, 0.0, 0.7));

			float h_loss = abs(cur_wind.y) * (height_squash * 0.12) + max(0.0, cur_wind.y * 0.08);
			h_scale = clamp(1.0 - h_loss, 0.28, 1.2);
			w_scale = clamp(1.0 + cur_wind.y * (perspective_expand * 0.15), 0.4, 2.0);
		}
	}

	var_rot_deg = rot_deg;
	var_shear = shear;
	var_h_scale = h_scale;
	var_w_scale = w_scale;

	// 统一均匀外扩四边形边界，为片元级完整像素反向重采样提供充裕空间，杜绝三角形斜切残像素
	VERTEX.x *= 6.0;
	if (UV.y > 0.5) {
		VERTEX.y += 8.0;
	} else {
		VERTEX.y *= 2.5;
	}
	local_pos = VERTEX;
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
		// 【正常游戏场景渲染】完整像素反向重采样 (Pixel-Perfect Resampling)
		vec2 sample_pos = floor(local_pos) + vec2(0.5, 0.5);

		// 1. 绕根部 (0, 0) 逆旋转采样坐标
		float rot_rad = radians(var_rot_deg);
		float cos_r = cos(rot_rad);
		float sin_r = sin(rot_rad);
		vec2 p = vec2(sample_pos.x * cos_r + sample_pos.y * sin_r, -sample_pos.x * sin_r + sample_pos.y * cos_r);

		// 2. 高度范围检查 (超出当前有效高度直接整像素剔除)
		float y_up = -p.y;
		float cur_total_h = 8.0 * var_h_scale;
		if (y_up < 0.0 || y_up > cur_total_h) {
			discard;
		}

		// 3. 归一化高度与中轴线抛物线弯曲
		float h = clamp(y_up / cur_total_h, 0.0, 1.0);
		float center_x = var_shear * pow(h, 1.8);
		float cur_w = 4.0 * mix(1.0, var_w_scale, h);
		float rel_x = p.x - center_x;
		float u = (rel_x / cur_w) + 0.5;
		float v = 1.0 - h;
		if (u < 0.0 || u > 1.0) {
			discard;
		}

		// 4. 原图 4x8 离散整像素采样
		vec2 tex_size = vec2(4.0, 8.0);
		vec2 orig_pixel = clamp(floor(vec2(u, v) * tex_size), vec2(0.0), tex_size - vec2(1.0));
		vec2 snapped_uv = (orig_pixel + vec2(0.5)) / tex_size;
		vec4 mask = texture(TEXTURE, snapped_uv);
		if (mask.a < 0.5) {
			discard;
		}

		// 5. 确定颜色
		vec3 final_color = tuft_color;
		if (debug_wind_mode == 1) {
			final_color = vec3(var_wave1);
		} else if (debug_wind_mode == 2) {
			final_color = vec3(var_wave2);
		} else if (debug_wind_mode == 3) {
			final_color = vec3(var_gust * 0.5 + 0.5);
		} else if (debug_wind_mode == 4) {
			final_color = heat_map(var_gust * 0.5 + 0.5);
		} else {
			if (tip_brightness > 0.0) {
				final_color += vec3(tip_brightness * (1.0 - v));
			}
		}

		// 6. 输出 100% 完整纯色像素，彻底消除游戏内一切残像素与半像素毛边！
		COLOR = vec4(final_color, 1.0);
	}
}
