shader_type canvas_item;

// 全局屏幕空间多实体透视遮罩贴图 (由 vision_fog_component 动态绘制玩家与视野内所有生物)
global uniform sampler2D xray_mask_tex : filter_linear, repeat_disable;

// 保持材质级可选参数兼容性 (供树木或高墙微调透视透光乘率)
uniform float max_transparency : hint_range(0.0, 1.0) = 1.0;
uniform vec2 target_offset = vec2(0.0, 0.0);
uniform float rx : hint_range(4.0, 400.0) = 85.0;
uniform float ry : hint_range(4.0, 400.0) = 55.0;
uniform float feather : hint_range(0.01, 1.0) = 0.8;

// 动态阴影配置 (与地表瓷砖阴影保持完全一致的 Bayer 8x8 像素质感)
uniform float shadow_darkness : hint_range(0.0, 1.0) = 0.35;
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform bool enable_dither_fog = true;
uniform int dither_scale : hint_range(1, 4) = 1;

// 每个物体独立控制是否处于阴影中 (支持 instance uniform 零冗余动态控制)
instance uniform bool is_in_shadow = false;
// 是否开启 X-Ray 透视 (仅树冠 Canopy/屋顶启用，树干 Trunk 等实体立柱关闭)
instance uniform bool enable_xray = true;

// 4x4 经典 Bayer 像素抖动矩阵 (用于 X-Ray 透视)
const mat4 bayer4 = mat4(
    vec4( 0.0/16.0, 12.0/16.0,  3.0/16.0, 15.0/16.0),
    vec4( 8.0/16.0,  4.0/16.0, 11.0/16.0,  7.0/16.0),
    vec4( 2.0/16.0, 14.0/16.0,  1.0/16.0, 13.0/16.0),
    vec4(10.0/16.0,  6.0/16.0,  9.0/16.0,  5.0/16.0)
);

// 8x8 经典 Bayer 像素抖动矩阵 (用于阴影投影叠加)
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

void fragment() {
    vec4 col = COLOR;
    if (col.a <= 0.001) { discard; }

    // 1. 单次采样屏幕空间多实体透视蒙版 (Alpha 通道记录透视强度，O(1) 恒定开销)
    float proximity_mask = texture(xray_mask_tex, SCREEN_UV).a * max_transparency;

    // 2. 经典 4x4 Bayer 像素点阵抖动镂空 (仅在启用 X-Ray 透视的部件如树冠上生效)
    if (enable_xray && proximity_mask > 0.0) {
        int x = int(FRAGCOORD.x) % 4;
        int y = int(FRAGCOORD.y) % 4;
        float dither_threshold = bayer4[x][y];

        // 越靠近生物中心，被剔除的像素越多
        if (proximity_mask > dither_threshold) {
            discard;
        }
    }

    // 3. 动态阴影叠加：仅当物体处于阴影内时叠加阴影，不在阴影内时保持 100% 原色 (地表阴影在物体之下)
    if (is_in_shadow) {
        if (enable_dither_fog) {
            int px = (int(FRAGCOORD.x) / dither_scale) % 8;
            if (px < 0) px += 8;
            int py = (int(FRAGCOORD.y) / dither_scale) % 8;
            if (py < 0) py += 8;
            float threshold = bayer8[py * 8 + px];

            if (shadow_darkness > threshold) {
                col = vec4(shadow_color.rgb, col.a);
            }
        } else {
            col = vec4(mix(col.rgb, shadow_color.rgb, shadow_darkness), col.a);
        }
    }

    COLOR = col;
}