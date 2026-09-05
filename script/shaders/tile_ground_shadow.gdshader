shader_type canvas_item;

// 地表瓷砖动态阴影 Shader (CanvasItem)
// 运行于各 cell_layer (TileMapLayer)，将 3D 地形视线遮挡与障碍物阴影直接渲染在地表
// 使得前景树木、建筑与实体能够自然覆盖阴影，实现“阴影在物体之下”的 2.5D 深度视觉

global uniform sampler2D vision_mask_tex : filter_linear, repeat_disable;
global uniform vec2 vision_cam_pos;
global uniform vec2 vision_cam_zoom;
global uniform vec2 vision_screen_size;

uniform bool active = true;
uniform float shadow_darkness : hint_range(0.0, 1.0) = 0.35;
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform bool enable_dither_fog = true;
uniform int dither_scale : hint_range(1, 4) = 1;
uniform float edge_softness : hint_range(4.0, 80.0) = 28.0;

// 8x8 经典 Bayer 像素抖动矩阵 (64 级精细灰阶，梯度过渡柔和丝滑)
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
    vec4 col = COLOR; // Godot 的 COLOR 在片元阶段已预乘贴图与 modulate，直接使用避免二次乘算导致变黑
    if (col.a <= 0.001) {
        discard;
    }

    COLOR = col;

    if (active) {
        vec2 base_mask_uv = SCREEN_UV;

        float current_vis = 0.0;
        if (enable_dither_fog && edge_softness > 1.0) {
            vec2 step_uv = (edge_softness / vision_screen_size) * vision_cam_zoom;
            for (int i = 0; i < 13; i++) {
                vec2 tap_uv = clamp(base_mask_uv + SAMPLE_OFFSETS[i] * step_uv, vec2(0.0), vec2(1.0));
                current_vis += texture(vision_mask_tex, tap_uv).r * SAMPLE_WEIGHTS[i];
            }
        } else {
            current_vis = texture(vision_mask_tex, base_mask_uv).r;
        }

        // 2. 计算阴影浓度：当处于视野内(current_vis=1.0)为 0.0，在阴影盲区(current_vis=0.0)为 shadow_darkness
        float vis_factor = smoothstep(0.0, 1.0, clamp(current_vis, 0.0, 1.0));
        float darkness = mix(shadow_darkness, 0.0, vis_factor);

        // 3. 像素呈现：纯黑 8x8 精细点阵抖动或平滑半透明深色混合
        if (darkness > 0.001) {
            if (enable_dither_fog) {
                int px = (int(FRAGCOORD.x) / dither_scale) % 8;
                if (px < 0) px += 8;
                int py = (int(FRAGCOORD.y) / dither_scale) % 8;
                if (py < 0) py += 8;
                float threshold = bayer8[py * 8 + px];

                if (darkness > threshold) {
                    // 点阵命中黑点：将瓷砖当前像素着色为纯黑阴影点，完美呈现复古像素艺术质感
                    COLOR = vec4(shadow_color.rgb, col.a);
                }
            } else {
                COLOR = vec4(mix(col.rgb, shadow_color.rgb, darkness), col.a);
            }
        }
    }
}
