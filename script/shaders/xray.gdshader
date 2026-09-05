shader_type canvas_item;

// 全局屏幕空间多实体透视遮罩贴图 (由 vision_fog_component 动态绘制玩家与视野内所有生物)
global uniform sampler2D xray_mask_tex : filter_linear, repeat_disable;

// 保持材质级可选参数兼容性 (供树木或高墙微调透视透光乘率)
uniform float max_transparency : hint_range(0.0, 1.0) = 1.0;
uniform vec2 target_offset = vec2(0.0, 0.0);
uniform float rx : hint_range(4.0, 400.0) = 85.0;
uniform float ry : hint_range(4.0, 400.0) = 55.0;
uniform float feather : hint_range(0.01, 1.0) = 0.8;

// 4x4 经典 Bayer 像素抖动矩阵
const mat4 bayer = mat4(
    vec4( 0.0/16.0, 12.0/16.0,  3.0/16.0, 15.0/16.0),
    vec4( 8.0/16.0,  4.0/16.0, 11.0/16.0,  7.0/16.0),
    vec4( 2.0/16.0, 14.0/16.0,  1.0/16.0, 13.0/16.0),
    vec4(10.0/16.0,  6.0/16.0,  9.0/16.0,  5.0/16.0)
);

void fragment() {
    vec4 col = COLOR;
    if (col.a <= 0.001) { discard; }

    // 1. 单次采样屏幕空间多实体透视蒙版 (Alpha 通道记录透视强度，O(1) 恒定开销)
    float proximity_mask = texture(xray_mask_tex, SCREEN_UV).a * max_transparency;

    // 2. 经典 4x4 Bayer 像素点阵抖动镂空
    if (proximity_mask > 0.0) {
        int x = int(FRAGCOORD.x) % 4;
        int y = int(FRAGCOORD.y) % 4;
        float dither_threshold = bayer[x][y];

        // 越靠近生物中心，被剔除的像素越多
        if (proximity_mask > dither_threshold) {
            discard;
        }
    }

    COLOR = col;
}